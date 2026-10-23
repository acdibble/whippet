import AppKit
import CloudKit

/// Feedback sent from the app, stored in the iCloud container's public database so no server is needed.
/// The Feedback record type's security roles let signed-in users create records, and only the Admin role read,
/// change and delete them, so reading is enforced by CloudKit rather than by this code.
@MainActor
final class FeedbackStore {
    struct Entry: Identifiable, Hashable {
        let record: CKRecord
        var id: CKRecord.ID { record.recordID }
        var message: String { record["message"] as? String ?? "" }
        var email: String? { (record["email"] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        var details: String { record["details"] as? String ?? "" }
        var sentAt: Date { record.creationDate ?? .distantPast }
        var isHandled: Bool { (record["handled"] as? Int64 ?? 0) != 0 }
    }

    private static let recordType = "Feedback"
    private let database = CKContainer(identifier: "iCloud.codes.dibble.whippet").publicCloudDatabase

    var canSend: Bool {
        get async { (try? await CKContainer(identifier: "iCloud.codes.dibble.whippet").accountStatus()) == .available }
    }

    func send(message: String, email: String) async throws {
        let record = CKRecord(recordType: Self.recordType)
        record["message"] = message
        record["email"] = email.trimmingCharacters(in: .whitespacesAndNewlines)
        record["details"] = SystemDetails.summary
        record["handled"] = Int64(0)
        _ = try await database.save(record)
    }

    // MARK: - Admin

    /// Newest first. Throws a permission error for anyone without the Admin role, which is how the admin pane hides itself.
    func fetchAll() async throws -> [Entry] {
        let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let (results, _) = try await database.records(matching: query, resultsLimit: 200)
        return results.compactMap { try? $0.1.get() }.map(Entry.init)
    }

    var isAdmin: Bool {
        get async { (try? await fetchAll()) != nil }
    }

    func delete(_ entry: Entry) async throws {
        try await database.deleteRecord(withID: entry.id)
    }

    func markHandled(_ entry: Entry) async throws {
        entry.record["handled"] = Int64(1)
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

/// Opens a prefilled new-issue page in the browser, so the app never needs a GitHub token.
enum GitHubIssue {
    static func open(title: String, body: String) {
        var components = URLComponents(string: "https://github.com/acdibble/whippet/issues/new")
        components?.queryItems = [URLQueryItem(name: "title", value: title), URLQueryItem(name: "body", value: body)]
        guard let url = components?.url else { return }
        NSWorkspace.shared.open(url)
    }
}
