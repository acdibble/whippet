import AppKit
import CloudKit
import CryptoKit

/// Feedback sent from the app, stored in the iCloud container's public database so no server is needed.
/// The Feedback record type's security roles let signed-in users create records and only the Admin role read, change
/// and delete them (see docs/cloudkit.md). The message, email and details are also sealed to the admin's key, so they
/// stay unreadable even if those roles are ever wrong.
@MainActor
final class FeedbackStore {
    struct Entry: Identifiable, Hashable {
        let record: CKRecord
        /// Nil when the feedback is sealed and this Mac doesn't have the admin key.
        let content: FeedbackContent?
        var id: CKRecord.ID { record.recordID }
        var message: String { content?.message ?? String(localized: "This feedback is encrypted, and this Mac doesn't have the feedback key.") }
        var email: String? { content.flatMap { $0.email.isEmpty ? nil : $0.email } }
        var details: String { content?.details ?? "" }
        var sentAt: Date { record.creationDate ?? .distantPast }
        var isHandled: Bool { (record["handled"] as? Int64 ?? 0) != 0 }

        /// Reads sealed feedback with the admin key, or the plain fields that versions before 0.6 sent.
        init(record: CKRecord, privateKey: Curve25519.KeyAgreement.PrivateKey?) {
            self.record = record
            if let encapsulatedKey = record["sealedKey"] as? Data, let ciphertext = record["sealed"] as? Data {
                content = privateKey.flatMap {
                    try? SealedFeedback.open(encapsulatedKey: encapsulatedKey, ciphertext: ciphertext, with: $0)
                }
            } else {
                content = FeedbackContent(
                    message: record["message"] as? String ?? "",
                    email: record["email"] as? String ?? "",
                    details: record["details"] as? String ?? ""
                )
            }
        }
    }

    struct Page {
        let entries: [Entry]
        /// Where the next page starts, or nil after the last one.
        let cursor: CKQueryOperation.Cursor?
    }

    private static let recordType = "Feedback"
    private static let pageSize = 50
    private let database = CKContainer(identifier: "iCloud.codes.dibble.whippet").publicCloudDatabase

    var canSend: Bool {
        get async { (try? await CKContainer(identifier: "iCloud.codes.dibble.whippet").accountStatus()) == .available }
    }

    func send(message: String, email: String) async throws {
        let content = FeedbackContent(
            message: message,
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            details: SystemDetails.summary
        )
        let record = CKRecord(recordType: Self.recordType)
        if let publicKey = FeedbackKey.publicKey {
            let sealed = try SealedFeedback.seal(content, to: publicKey)
            record["sealedKey"] = sealed.encapsulatedKey
            record["sealed"] = sealed.ciphertext
        } else {
            // Only builds without a feedback key, such as other people's, send plain fields.
            record["message"] = content.message
            record["email"] = content.email
            record["details"] = content.details
        }
        record["handled"] = Int64(0)
        _ = try await database.save(record)
    }

    // MARK: - Admin

    /// True when CloudKit lets this account read feedback, which only the Admin role can. Fetches at most one record,
    /// with no fields.
    var hasAdminRole: Bool {
        get async {
            let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(value: true))
            return (try? await database.records(matching: query, desiredKeys: [], resultsLimit: 1)) != nil
        }
    }

    /// The Admin role and, on this Mac, the key that opens feedback. Needing both keeps feedback hidden from everyone
    /// else even if the roles were ever wrong.
    var isAdmin: Bool {
        get async {
            guard FeedbackKey.matchingPrivateKey != nil else { return false }
            return await hasAdminRole
        }
    }

    /// Newest first, a page at a time.
    func fetchPage(after cursor: CKQueryOperation.Cursor? = nil) async throws -> Page {
        let privateKey = FeedbackKey.matchingPrivateKey
        let (results, nextCursor): ([(CKRecord.ID, Result<CKRecord, Error>)], CKQueryOperation.Cursor?)
        if let cursor {
            (results, nextCursor) = try await database.records(continuingMatchFrom: cursor, resultsLimit: Self.pageSize)
        } else {
            let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(value: true))
            query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            (results, nextCursor) = try await database.records(matching: query, resultsLimit: Self.pageSize)
        }
        let entries = results.compactMap { try? $0.1.get() }.map { Entry(record: $0, privateKey: privateKey) }
        return Page(entries: entries, cursor: nextCursor)
    }

    func delete(_ entry: Entry) async throws {
        try await database.deleteRecord(withID: entry.id)
    }

    func setHandled(_ isHandled: Bool, for entry: Entry) async throws {
        entry.record["handled"] = Int64(isHandled ? 1 : 0)
        _ = try await database.modifyRecords(saving: [entry.record], deleting: [], savePolicy: .changedKeys)
    }
}

/// The app version and the Mac it runs on, attached to feedback and GitHub issues.
enum SystemDetails {
    static var summary: String {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return """
            Whippet \(version) (\(build))
            macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
            \(machineModel), \(architecture)
            """
    }

    private static var machineModel: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(decoding: model.prefix { $0 != 0 }.map(UInt8.init), as: UTF8.self)
    }

    private static var architecture: String {
        #if arch(arm64)
        "Apple silicon"
        #else
        "Intel"
        #endif
    }
}

/// A link for sharing Whippet: the newest release's page, with the DMG to download, so it never goes stale.
enum ShareLink {
    static let downloadURL = "https://github.com/acdibble/whippet/releases/latest"

    /// Copies the link and confirms it, from the launcher or Settings › About.
    @MainActor
    static func copy(using clipboard: ClipboardHistory) {
        clipboard.copy(text: downloadURL)
        Toast.shared.show(String(localized: "Download link copied"), symbol: "square.and.arrow.up")
    }
}

/// Opens a prefilled new-issue page in the browser, so the app never needs a GitHub token.
enum GitHubIssue {
    static func open(title: String, body: String) {
        var components = URLComponents(string: "https://github.com/acdibble/whippet/issues/new")
        components?.queryItems = [URLQueryItem(name: "title", value: title), URLQueryItem(name: "body", value: body)]
        guard let url = components?.url else { return }
        NSWorkspace.shared.open(url)
    }
}
