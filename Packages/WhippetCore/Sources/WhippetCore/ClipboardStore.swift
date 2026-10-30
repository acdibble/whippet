import CryptoKit
import Foundation
import GRDB
import UniformTypeIdentifiers

public enum ClipboardKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case text
    case link
    case number
    case image
    /// Files copied in Finder and other apps, kept on this Mac only since their paths mean nothing on another.
    case file

    public var id: Self { self }

    public var title: String {
        switch self {
        case .text: String(localized: "Text", bundle: .module)
        case .link: String(localized: "Link", bundle: .module)
        case .number: String(localized: "Number", bundle: .module)
        case .image: String(localized: "Image", bundle: .module)
        case .file: String(localized: "File", bundle: .module)
        }
    }

    public var pluralTitle: String {
        switch self {
        case .text: String(localized: "Text", bundle: .module)
        case .link: String(localized: "Links", bundle: .module)
        case .number: String(localized: "Numbers", bundle: .module)
        case .image: String(localized: "Images", bundle: .module)
        case .file: String(localized: "Files", bundle: .module)
        }
    }

    public var symbolName: String {
        switch self {
        case .text: "doc"
        case .link: "link"
        case .number: "number"
        case .image: "photo"
        case .file: "paperclip"
        }
    }

    static func classify(_ text: String) -> ClipboardKind {
        if Calculator.parseNumber(text) != nil { return .number }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !trimmed.contains(where: \.isWhitespace),
            let url = URL(string: trimmed),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            url.host() != nil
        else { return .text }
        return .link
    }
}

public struct ClipboardItem: Identifiable, Hashable, Codable, FetchableRecord, TableRecord, Sendable {
    public static let databaseTableName = "clipboard"

    public let id: Int64
    public let contentHash: String
    public let kind: ClipboardKind
    public let text: String?
    let imageFile: String?
    public let imageWidth: Int?
    public let imageHeight: Int?
    public let imageBytes: Int?
    /// Nil until text recognition has run; empty when the image contains no text.
    let ocrText: String?
    public let copiedAt: Date
    public let sourceBundleID: String?
    public let timesCopied: Int
    public let pinnedAt: Date?
    /// A link's page title: nil until its preview has been fetched, empty when the page has none.
    let linkTitle: String?
    /// A link's preview image, in the images folder.
    let linkImageFile: String?
    /// Text recognized in a link's preview image: nil until recognition has run.
    let linkOcrText: String?
    /// The type identifier of an image as it was copied, such as `public.jpeg`; it is stored as PNG. Nil for images
    /// copied before 0.11.2 and those from another Mac.
    public let imageType: String?

    /// A file's path is kept in `text`: one per line for files, and for an image copied as a file in Finder, its path.
    public var fileURLs: [URL] {
        guard kind == .file || kind == .image, let text, !text.isEmpty else { return [] }
        return text.split(separator: "\n").map { URL(filePath: String($0)) }
    }

    public var title: String {
        if kind == .file {
            let names = fileURLs.map(\.lastPathComponent)
            guard let first = names.first else { return "" }
            return names.count == 1 ? first : String(localized: "\(first) and \(names.count - 1) More", bundle: .module)
        }
        if kind == .image {
            if let name = fileURLs.first?.lastPathComponent {
                return name
            }
            if let format = imageType.flatMap({ UTType($0) })?.localizedDescription {
                return String(localized: "\(format) (\(imageWidth ?? 0)×\(imageHeight ?? 0))", bundle: .module)
            }
            return String(localized: "Image (\(imageWidth ?? 0)×\(imageHeight ?? 0))", bundle: .module)
        }
        if let linkTitle, !linkTitle.isEmpty {
            return linkTitle
        }
        // Only the first line is read, since splitting a long copy on every render is slow.
        let firstLine = (text ?? "").drop(while: \.isWhitespace).prefix(while: { !$0.isNewline }).prefix(500)
        return String(firstLine).trimmingCharacters(in: .whitespaces)
    }

    /// A link's site, shown beside its page title.
    public var linkHost: String? {
        guard kind == .link, let text else { return nil }
        let host = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines))?.host()
        return host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 }
    }

    /// True once a link has a page title to show.
    public var hasLinkTitle: Bool {
        linkTitle.map { !$0.isEmpty } ?? false
    }
}

/// How long unpinned clipboard history is kept.
public enum ClipboardRetention: String, CaseIterable, Identifiable, Sendable {
    case day
    case week
    case month
    case threeMonths
    case year
    case forever

    public var id: Self { self }

    public var title: String {
        switch self {
        case .day: String(localized: "One Day", bundle: .module)
        case .week: String(localized: "One Week", bundle: .module)
        case .month: String(localized: "One Month", bundle: .module)
        case .threeMonths: String(localized: "Three Months", bundle: .module)
        case .year: String(localized: "One Year", bundle: .module)
        case .forever: String(localized: "Forever", bundle: .module)
        }
    }

    /// Items copied before this date are removed, or none when nil.
    public func cutoff(from now: Date) -> Date? {
        let calendar = Calendar.current
        switch self {
        case .day: return calendar.date(byAdding: .day, value: -1, to: now)
        case .week: return calendar.date(byAdding: .day, value: -7, to: now)
        case .month: return calendar.date(byAdding: .month, value: -1, to: now)
        case .threeMonths: return calendar.date(byAdding: .month, value: -3, to: now)
        case .year: return calendar.date(byAdding: .year, value: -1, to: now)
        case .forever: return nil
        }
    }
}

public struct CalculationRecord: Identifiable, Hashable, Codable, FetchableRecord, TableRecord, Sendable {
    public static let databaseTableName = "calculation"

    public let id: Int64
    public let expression: String
    public let answer: String
    let mode: String
    public let calculatedAt: Date
}

public struct ClipboardUsage: Sendable {
    public let directory: URL
    public let databaseBytes: Int
    public let imageBytes: Int
    public let imageFiles: Int
    public let counts: [ClipboardKind: Int]
    public let imagesAwaitingRecognition: Int
    public let calculations: Int
}

/// Clipboard history in a SQLite database in Application Support, with an FTS5 index over copied and recognized text
/// and link titles. Images live beside it as PNG files named by their content hash, and links' preview images as
/// `link-` followed by the link's hash.
public final class ClipboardStore: Sendable {
    let directory: URL
    let imagesDirectory: URL
    private let databaseURL: URL
    private let database: DatabaseQueue

    /// Opens or creates the store in `directory`, which the app chooses, such as its Application Support folder.
    public init(directory: URL) throws {
        self.directory = directory
        imagesDirectory = directory.appending(path: "Images")
        try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        databaseURL = directory.appending(path: "clipboard.sqlite")
        database = try DatabaseQueue(path: databaseURL.path)
        try Self.migrator.migrate(database)
    }

    /// Records a copy, moving content that is already in history to the top, and returns it for syncing.
    @discardableResult
    public func recordText(_ text: String, sourceBundleID: String?) throws -> SyncItem {
        let hash = Self.hash(Data(text.utf8))
        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO clipboard (contentHash, kind, text, copiedAt, sourceBundleID, updatedAt) VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(contentHash) DO UPDATE SET
                        copiedAt = excluded.copiedAt,
                        sourceBundleID = excluded.sourceBundleID,
                        timesCopied = timesCopied + 1,
                        updatedAt = excluded.updatedAt
                    """,
                arguments: [hash, ClipboardKind.classify(text).rawValue, text, Date.now, sourceBundleID, Date.now]
            )
        }
        return .clipboard(contentHash: hash)
    }

    /// `type` is the image's type identifier as copied, and `path` the file it was copied from in Finder, if any. Copying
    /// the same picture again keeps the name and type it had unless the new copy has its own.
    @discardableResult
    public func recordImage(
        png: Data, width: Int, height: Int, type: String? = nil, path: String? = nil, sourceBundleID: String?
    ) throws -> SyncItem {
        let hash = Self.hash(png)
        let file = imagesDirectory.appending(path: "\(hash).png")
        if !FileManager.default.fileExists(atPath: file.path) {
            try png.write(to: file)
        }
        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO clipboard (
                        contentHash, kind, text, imageFile, imageWidth, imageHeight, imageBytes, imageType, copiedAt,
                        sourceBundleID, updatedAt
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(contentHash) DO UPDATE SET
                        text = COALESCE(excluded.text, text),
                        imageType = COALESCE(excluded.imageType, imageType),
                        copiedAt = excluded.copiedAt,
                        sourceBundleID = excluded.sourceBundleID,
                        timesCopied = timesCopied + 1,
                        updatedAt = excluded.updatedAt
                    """,
                arguments: [
                    hash, ClipboardKind.image.rawValue, path, file.lastPathComponent, width, height, png.count, type,
                    Date.now, sourceBundleID, Date.now,
                ]
            )
        }
        return .clipboard(contentHash: hash)
    }

    /// Records files copied together as one item, by their paths.
    @discardableResult
    public func recordFiles(_ paths: [String], sourceBundleID: String?) throws -> SyncItem {
        let text = paths.joined(separator: "\n")
        // Prefixed, so the same paths copied as text are a separate item.
        let hash = Self.hash(Data("file\n\(text)".utf8))
        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO clipboard (contentHash, kind, text, copiedAt, sourceBundleID, updatedAt) VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(contentHash) DO UPDATE SET
                        copiedAt = excluded.copiedAt,
                        sourceBundleID = excluded.sourceBundleID,
                        timesCopied = timesCopied + 1,
                        updatedAt = excluded.updatedAt
                    """,
                arguments: [hash, ClipboardKind.file.rawValue, text, Date.now, sourceBundleID, Date.now]
            )
        }
        return .clipboard(contentHash: hash)
    }

    /// Moves an item copied again from history to the top and counts the copy, without recording its content again.
    /// Returns nil when the item no longer exists.
    @discardableResult
    public func recordCopy(contentHash: String) throws -> SyncItem? {
        let changed = try database.write { db in
            try db.execute(
                sql: "UPDATE clipboard SET copiedAt = ?, timesCopied = timesCopied + 1, updatedAt = ? WHERE contentHash = ?",
                arguments: [Date.now, Date.now, contentHash]
            )
            return db.changesCount > 0
        }
        return changed ? .clipboard(contentHash: contentHash) : nil
    }

    /// The newest copied image or link preview image whose text hasn't been recognized yet.
    public func nextImageAwaitingRecognition() throws -> (hash: String, file: URL, isLinkPreview: Bool)? {
        try database.read { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT contentHash, imageFile AS file, 0 AS isLinkPreview, copiedAt FROM clipboard
                        WHERE kind = ? AND ocrText IS NULL
                    UNION ALL
                    SELECT contentHash, linkImageFile AS file, 1 AS isLinkPreview, copiedAt FROM clipboard
                        WHERE linkImageFile IS NOT NULL AND linkOcrText IS NULL
                    ORDER BY copiedAt DESC LIMIT 1
                    """,
                arguments: [ClipboardKind.image.rawValue]
            )
            guard let row else { return nil }
            let file: String = row["file"]
            return (row["contentHash"], imagesDirectory.appending(path: file), row["isLinkPreview"])
        }
    }

    /// Returns nil when the item was deleted while its text was being recognized, so nothing syncs it back.
    @discardableResult
    public func setRecognizedText(_ text: String, hash: String) throws -> SyncItem? {
        let changed = try database.write { db in
            try db.execute(
                sql: "UPDATE clipboard SET ocrText = ?, updatedAt = ? WHERE contentHash = ?",
                arguments: [text, Date.now, hash]
            )
            return db.changesCount > 0
        }
        return changed ? .clipboard(contentHash: hash) : nil
    }

    /// Link previews stay on this Mac, so this doesn't change `updatedAt` and nothing syncs.
    public func setLinkPreviewRecognizedText(_ text: String, hash: String) throws {
        try database.write { db in
            try db.execute(sql: "UPDATE clipboard SET linkOcrText = ? WHERE contentHash = ?", arguments: [text, hash])
        }
    }

    // MARK: - Link previews

    /// The newest link whose preview hasn't been fetched yet, leaving out sites that asked for a pause.
    public func nextLinkAwaitingPreview(skippingHosts: Set<String> = []) throws -> (hash: String, url: URL)? {
        try database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT contentHash, text FROM clipboard WHERE kind = ? AND linkTitle IS NULL ORDER BY copiedAt DESC",
                arguments: [ClipboardKind.link.rawValue]
            )
            for row in rows {
                let text: String? = row["text"]
                if let url = text.flatMap({ URL(string: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }),
                   !skippingHosts.contains(url.host()?.lowercased() ?? "") {
                    return (row["contentHash"], url)
                }
            }
            return nil
        }
    }

    /// Saves a fetched preview. An empty title marks a link whose page had none, or couldn't be fetched, so it isn't
    /// fetched again. Local only, like recognized text in previews.
    public func setLinkPreview(title: String, imagePNG: Data?, hash: String) throws {
        // Each image gets a new name, as thumbnails are cached by file, so one fetched again isn't shown stale.
        var imageFile: String?
        if let imagePNG {
            let name = "link-\(hash)-\(UUID().uuidString.prefix(8)).png"
            try imagePNG.write(to: imagesDirectory.appending(path: name))
            imageFile = name
        }
        let oldFile = try database.write { db in
            let oldFile = try String.fetchOne(db, sql: "SELECT linkImageFile FROM clipboard WHERE contentHash = ?", arguments: [hash])
            try db.execute(
                sql: "UPDATE clipboard SET linkTitle = ?, linkImageFile = ?, linkOcrText = NULL WHERE contentHash = ?",
                arguments: [title, imageFile, hash]
            )
            return oldFile
        }
        if let oldFile, oldFile != imageFile {
            try? FileManager.default.removeItem(at: imagesDirectory.appending(path: oldFile))
        }
    }

    /// Forgets a link's preview, so it's fetched again.
    public func clearLinkPreview(hash: String) throws {
        let file = try database.write { db in
            let file = try String.fetchOne(db, sql: "SELECT linkImageFile FROM clipboard WHERE contentHash = ?", arguments: [hash])
            try db.execute(
                sql: "UPDATE clipboard SET linkTitle = NULL, linkImageFile = NULL, linkOcrText = NULL WHERE contentHash = ?",
                arguments: [hash]
            )
            return file
        }
        if let file {
            try? FileManager.default.removeItem(at: imagesDirectory.appending(path: file))
        }
    }

    /// Records a calculation, moving an expression already in history to the top with its latest answer,
    /// and returns it for syncing.
    @discardableResult
    public func recordCalculation(expression: String, answer: String, mode: String) throws -> SyncItem {
        let key = Self.calculationKey(expression: expression, mode: mode)
        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO calculation (expression, answer, mode, calculatedAt, syncKey, updatedAt) VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(expression, mode) DO UPDATE SET
                        answer = excluded.answer,
                        calculatedAt = excluded.calculatedAt,
                        updatedAt = excluded.updatedAt
                    """,
                arguments: [expression, answer, mode, Date.now, key, Date.now]
            )
        }
        return .calculation(key: key)
    }

    public func recentCalculations(limit: Int) throws -> [CalculationRecord] {
        try database.read { db in
            try CalculationRecord.order(Column("calculatedAt").desc).limit(limit).fetchAll(db)
        }
    }

    /// A copied image's file, or a link's preview image.
    public func imageURL(for item: ClipboardItem) -> URL? {
        (item.imageFile ?? item.linkImageFile).map { imagesDirectory.appending(path: $0) }
    }

    /// Returns the item for syncing, or nil when it no longer exists.
    public func setPinned(_ pinned: Bool, id: Int64) throws -> SyncItem? {
        let hash = try database.write { db in
            try String.fetchOne(
                db,
                sql: "UPDATE clipboard SET pinnedAt = ?, updatedAt = ? WHERE id = ? RETURNING contentHash",
                arguments: [pinned ? Date.now : nil, Date.now, id]
            )
        }
        return hash.map { .clipboard(contentHash: $0) }
    }

    /// Pinned items first in the order they were pinned, then newest first; an empty query returns everything.
    public func search(_ query: String, kind: ClipboardKind?, limit: Int) throws -> [ClipboardItem] {
        try database.read { db in
            var request = ClipboardItem.order(sql: "pinnedAt IS NULL, pinnedAt, copiedAt DESC").limit(limit)
            if let kind {
                request = request.filter(Column("kind") == kind.rawValue)
            }
            if let pattern = FTS5Pattern(matchingAllPrefixesIn: query) {
                request = request.filter(
                    sql: "id IN (SELECT rowid FROM clipboardFts WHERE clipboardFts MATCH ?)",
                    arguments: [pattern]
                )
            }
            return try request.fetchAll(db)
        }
    }

    public func usage() throws -> ClipboardUsage {
        let (counts, awaiting, calculations) = try database.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT kind, COUNT(*) AS count FROM clipboard GROUP BY kind")
            let counts: [ClipboardKind: Int] = Dictionary(
                uniqueKeysWithValues: rows.compactMap { row in
                    let kind: String = row["kind"]
                    let count: Int = row["count"]
                    return ClipboardKind(rawValue: kind).map { ($0, count) }
                }
            )
            let awaiting = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM clipboard WHERE kind = ? AND ocrText IS NULL",
                arguments: [ClipboardKind.image.rawValue]
            )
            let calculations = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM calculation")
            return (counts, awaiting ?? 0, calculations ?? 0)
        }

        let databaseFiles = ["", "-wal", "-shm"].map { URL(filePath: databaseURL.path + $0) }
        let imageFiles = (try? FileManager.default.contentsOfDirectory(
            at: imagesDirectory,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey]
        )) ?? []

        return ClipboardUsage(
            directory: directory,
            databaseBytes: Self.allocatedSize(of: databaseFiles),
            imageBytes: Self.allocatedSize(of: imageFiles),
            imageFiles: imageFiles.count,
            counts: counts,
            imagesAwaitingRecognition: awaiting,
            calculations: calculations
        )
    }

    // MARK: - Sync

    static func calculationKey(expression: String, mode: String) -> String {
        hash(Data("\(mode)\n\(expression)".utf8))
    }

    /// Stores the iCloud record names given to items, so records from iCloud can be matched back to their rows.
    func assignRecordNames(_ names: [SyncItem: String]) throws {
        try database.write { db in
            for (item, name) in names {
                let target = SyncTarget(item)
                try db.execute(
                    sql: "UPDATE \(target.table) SET recordName = ? WHERE \(target.keyColumn) = ?",
                    arguments: [name, target.key]
                )
                // Copied again after being deleted, so the deletion no longer applies.
                try db.execute(sql: "DELETE FROM deletedRecord WHERE recordName = ?", arguments: [name])
            }
        }
    }

    func syncRow(recordName: String) throws -> Row? {
        guard let target = SyncTarget(recordName: recordName) else { return nil }
        return try database.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM \(target.table) WHERE recordName = ?", arguments: [recordName])
        }
    }

    /// Items changed on this Mac since they last synced, which covers changes made while sync was off.
    func unsyncedItems(includeImages: Bool) throws -> [SyncItem] {
        try database.read { db in
            let hashes = try String.fetchAll(
                db,
                sql: """
                    SELECT contentHash FROM clipboard
                    WHERE (syncedAt IS NULL OR updatedAt > syncedAt) AND (? OR kind != ?) AND kind != ?
                    """,
                arguments: [includeImages, ClipboardKind.image.rawValue, ClipboardKind.file.rawValue]
            )
            let keys = try String.fetchAll(
                db,
                sql: "SELECT syncKey FROM calculation WHERE syncedAt IS NULL OR updatedAt > syncedAt"
            )
            let quicklinks = try String.fetchAll(
                db,
                sql: "SELECT uuid FROM quicklink WHERE syncedAt IS NULL OR updatedAt > syncedAt"
            )
            return hashes.map { .clipboard(contentHash: $0) } + keys.map { .calculation(key: $0) }
                + quicklinks.map { .quicklink(uuid: $0) }
        }
    }

    func markSynced(recordName: String, systemFields: Data) throws {
        guard let target = SyncTarget(recordName: recordName) else { return }
        try database.write { db in
            try db.execute(
                sql: "UPDATE \(target.table) SET syncedAt = ?, cloudSystemFields = ? WHERE \(target.keyColumn) = ?",
                arguments: [Date.now, systemFields, target.key]
            )
        }
    }

    /// Forgets the server's copy of a record, so the next upload creates it afresh.
    func forgetSyncState(recordName: String) throws {
        guard let target = SyncTarget(recordName: recordName) else { return }
        try database.write { db in
            try db.execute(
                sql: "UPDATE \(target.table) SET syncedAt = NULL, cloudSystemFields = NULL WHERE \(target.keyColumn) = ?",
                arguments: [target.key]
            )
        }
    }

    /// Forgets everything about iCloud, including record names, which depend on the key in the account's zone.
    func forgetAllSyncState() throws {
        try database.write { db in
            try db.execute(sql: "UPDATE clipboard SET recordName = NULL, syncedAt = NULL, cloudSystemFields = NULL")
            try db.execute(sql: "UPDATE calculation SET recordName = NULL, syncedAt = NULL, cloudSystemFields = NULL")
            try db.execute(sql: "UPDATE quicklink SET recordName = NULL, syncedAt = NULL, cloudSystemFields = NULL")
            try db.execute(sql: "DELETE FROM deletedRecord")
        }
    }

    /// Record names of items deleted on this Mac whose deletion hasn't reached iCloud yet.
    func pendingDeletions() throws -> [String] {
        try database.read { db in
            try String.fetchAll(db, sql: "SELECT recordName FROM deletedRecord")
        }
    }

    /// A record deleted on this Mac stays deleted until the deletion reaches iCloud, even when a fetch brings it back
    /// first, as it does for a record this Mac uploaded just before deleting it.
    private static func isPendingDeletion(_ recordName: String, in db: Database) throws -> Bool {
        try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM deletedRecord WHERE recordName = ?)", arguments: [recordName]) ?? false
    }

    func forgetDeletions(_ recordNames: [String]) throws {
        guard !recordNames.isEmpty else { return }
        try database.write { db in
            for recordName in recordNames {
                try db.execute(sql: "DELETE FROM deletedRecord WHERE recordName = ?", arguments: [recordName])
            }
        }
    }

    /// Deletes an item and returns its iCloud record name, or nil when it was never synced. The name is kept until the
    /// deletion reaches iCloud, since sync may be off or still starting.
    public func delete(contentHash: String) throws -> String? {
        try delete(SyncTarget(.clipboard(contentHash: contentHash)), remembersDeletion: true)
    }

    // MARK: - Quicklinks

    public func quicklinks() throws -> [Quicklink] {
        try database.read { db in
            try Quicklink.order(sql: "name COLLATE NOCASE").fetchAll(db)
        }
    }

    /// Adds a quicklink, or updates the one with the same UUID, and returns it for syncing.
    @discardableResult
    public func saveQuicklink(_ quicklink: Quicklink) throws -> SyncItem {
        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO quicklink (uuid, name, keyword, template, appBundleID, createdAt, updatedAt)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(uuid) DO UPDATE SET
                        name = excluded.name,
                        keyword = excluded.keyword,
                        template = excluded.template,
                        appBundleID = excluded.appBundleID,
                        updatedAt = excluded.updatedAt
                    """,
                arguments: [
                    quicklink.uuid, quicklink.name, quicklink.keyword, quicklink.template, quicklink.appBundleID,
                    Date.now, Date.now,
                ]
            )
        }
        return .quicklink(uuid: quicklink.uuid)
    }

    /// Adds a quicklink unless one with its UUID already exists, such as a starter that synced from another Mac.
    /// Returns it for syncing when it was added.
    public func addQuicklinkIfMissing(_ quicklink: Quicklink) throws -> SyncItem? {
        let added = try database.write { db in
            try db.execute(
                sql: """
                    INSERT OR IGNORE INTO quicklink (uuid, name, keyword, template, appBundleID, createdAt, updatedAt)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    quicklink.uuid, quicklink.name, quicklink.keyword, quicklink.template, quicklink.appBundleID,
                    Date.now, Date.now,
                ]
            )
            return db.changesCount > 0
        }
        return added ? .quicklink(uuid: quicklink.uuid) : nil
    }

    /// Deletes a quicklink and returns its iCloud record name, or nil when it never synced.
    public func deleteQuicklink(uuid: String) throws -> String? {
        try delete(SyncTarget(.quicklink(uuid: uuid)), remembersDeletion: true)
    }

    /// Merges a quicklink from another Mac; the most recently changed side wins. Returns true when this Mac's copy is
    /// newer and should be uploaded.
    func mergeRemote(_ quicklink: RemoteQuicklink) throws -> Bool {
        try database.write { db in
            if try Self.isPendingDeletion(quicklink.recordName, in: db) { return false }
            let localUpdatedAt = try Date.fetchOne(
                db,
                sql: "SELECT updatedAt FROM quicklink WHERE uuid = ?",
                arguments: [quicklink.uuid]
            )
            try db.execute(
                sql: """
                    INSERT INTO quicklink (
                        uuid, name, keyword, template, appBundleID, createdAt, updatedAt, recordName, syncedAt,
                        cloudSystemFields
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(uuid) DO UPDATE SET
                        name = CASE WHEN excluded.updatedAt > updatedAt THEN excluded.name ELSE name END,
                        keyword = CASE WHEN excluded.updatedAt > updatedAt THEN excluded.keyword ELSE keyword END,
                        template = CASE WHEN excluded.updatedAt > updatedAt THEN excluded.template ELSE template END,
                        appBundleID = CASE WHEN excluded.updatedAt > updatedAt THEN excluded.appBundleID ELSE appBundleID END,
                        updatedAt = MAX(updatedAt, excluded.updatedAt),
                        recordName = excluded.recordName,
                        syncedAt = excluded.syncedAt,
                        cloudSystemFields = excluded.cloudSystemFields
                    """,
                arguments: [
                    quicklink.uuid, quicklink.name, quicklink.keyword, quicklink.template, quicklink.appBundleID,
                    quicklink.createdAt, quicklink.updatedAt, quicklink.recordName, Date.now, quicklink.systemFields,
                ]
            )
            guard let localUpdatedAt else { return false }
            return localUpdatedAt > quicklink.updatedAt
        }
    }

    /// Deletes items copied before `cutoff`, or all of them when it's nil, keeping pinned items unless `includingPinned`.
    /// Returns the iCloud record names of the deleted items that had synced, which are kept until the deletions reach
    /// iCloud, like single deletions.
    public func deleteItems(copiedBefore cutoff: Date?, includingPinned: Bool = false) throws -> [String] {
        var conditions: [String] = []
        var arguments: StatementArguments = []
        if let cutoff {
            conditions.append("copiedAt < ?")
            arguments += [cutoff]
        }
        if !includingPinned {
            conditions.append("pinnedAt IS NULL")
        }
        let filter = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        let rows = try database.write { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT recordName, imageFile, linkImageFile FROM clipboard \(filter)",
                arguments: arguments
            )
            try db.execute(sql: "DELETE FROM clipboard \(filter)", arguments: arguments)
            for case let recordName? in rows.map({ $0["recordName"] as String? }) {
                try db.execute(sql: "INSERT OR IGNORE INTO deletedRecord (recordName) VALUES (?)", arguments: [recordName])
            }
            return rows
        }
        for case let imageFile? in rows.flatMap({ [$0["imageFile"] as String?, $0["linkImageFile"] as String?] }) {
            try? FileManager.default.removeItem(at: imagesDirectory.appending(path: imageFile))
        }
        return rows.compactMap { $0["recordName"] }
    }

    /// Deletes the item behind a record that was deleted on another Mac.
    func deleteRecord(named recordName: String) throws {
        guard let target = SyncTarget(recordName: recordName) else { return }
        _ = try delete(target, remembersDeletion: false)
        try forgetDeletions([recordName])
    }

    private func delete(_ target: SyncTarget, remembersDeletion: Bool) throws -> String? {
        let row = try database.write { db in
            let row = try Row.fetchOne(db, sql: "SELECT * FROM \(target.table) WHERE \(target.keyColumn) = ?", arguments: [target.key])
            try db.execute(sql: "DELETE FROM \(target.table) WHERE \(target.keyColumn) = ?", arguments: [target.key])
            if remembersDeletion, let recordName = row?["recordName"] as String? {
                try db.execute(sql: "INSERT OR IGNORE INTO deletedRecord (recordName) VALUES (?)", arguments: [recordName])
            }
            return row
        }
        // Quicklink rows have neither column, which reads as nil.
        for case let imageFile? in [row?["imageFile"] as String?, row?["linkImageFile"] as String?] {
            try? FileManager.default.removeItem(at: imagesDirectory.appending(path: imageFile))
        }
        return row?["recordName"]
    }

    /// Merges an item from another Mac: the latest copy time and highest copy count win, and the most recently
    /// changed side decides the pin and source app. Returns true when this Mac's copy is ahead and should be uploaded.
    func mergeRemote(_ item: RemoteClipboardItem) throws -> Bool {
        try database.write { db in
            if try Self.isPendingDeletion(item.recordName, in: db) { return false }
            let local = try Row.fetchOne(
                db,
                sql: "SELECT copiedAt, timesCopied, updatedAt FROM clipboard WHERE contentHash = ?",
                arguments: [item.hash]
            )
            try db.execute(
                sql: """
                    INSERT INTO clipboard (
                        contentHash, kind, text, imageFile, imageWidth, imageHeight, imageBytes, ocrText, copiedAt,
                        sourceBundleID, timesCopied, pinnedAt, updatedAt, recordName, syncedAt, cloudSystemFields
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(contentHash) DO UPDATE SET
                        imageFile = COALESCE(imageFile, excluded.imageFile),
                        ocrText = COALESCE(ocrText, excluded.ocrText),
                        pinnedAt = CASE WHEN excluded.updatedAt > updatedAt THEN excluded.pinnedAt ELSE pinnedAt END,
                        sourceBundleID = CASE WHEN excluded.updatedAt > updatedAt THEN excluded.sourceBundleID ELSE sourceBundleID END,
                        copiedAt = MAX(copiedAt, excluded.copiedAt),
                        timesCopied = MAX(timesCopied, excluded.timesCopied),
                        updatedAt = MAX(updatedAt, excluded.updatedAt),
                        recordName = excluded.recordName,
                        syncedAt = excluded.syncedAt,
                        cloudSystemFields = excluded.cloudSystemFields
                    """,
                arguments: [
                    item.hash, item.kind.rawValue, item.text, item.imageFile, item.imageWidth, item.imageHeight,
                    item.imageBytes, item.ocrText, item.copiedAt, item.sourceBundleID, item.timesCopied, item.pinnedAt,
                    item.updatedAt, item.recordName, Date.now, item.systemFields,
                ]
            )
            guard let local else { return false }
            let copiedAt: Date = local["copiedAt"]
            let timesCopied: Int = local["timesCopied"]
            let updatedAt: Date = local["updatedAt"]
            return copiedAt > item.copiedAt || timesCopied > item.timesCopied || updatedAt > item.updatedAt
        }
    }

    /// Merges a calculation from another Mac, keeping the most recent answer. Returns true when this Mac's copy is newer.
    func mergeRemote(_ calculation: RemoteCalculation) throws -> Bool {
        try database.write { db in
            if try Self.isPendingDeletion(calculation.recordName, in: db) { return false }
            let localCalculatedAt = try Date.fetchOne(
                db,
                sql: "SELECT calculatedAt FROM calculation WHERE syncKey = ?",
                arguments: [calculation.key]
            )
            try db.execute(
                sql: """
                    INSERT INTO calculation (
                        expression, answer, mode, calculatedAt, syncKey, updatedAt, recordName, syncedAt, cloudSystemFields
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(expression, mode) DO UPDATE SET
                        answer = CASE WHEN excluded.calculatedAt > calculatedAt THEN excluded.answer ELSE answer END,
                        calculatedAt = MAX(calculatedAt, excluded.calculatedAt),
                        updatedAt = MAX(updatedAt, excluded.updatedAt),
                        recordName = excluded.recordName,
                        syncedAt = excluded.syncedAt,
                        cloudSystemFields = excluded.cloudSystemFields
                    """,
                arguments: [
                    calculation.expression, calculation.answer, calculation.mode, calculation.calculatedAt,
                    calculation.key, calculation.updatedAt, calculation.recordName, Date.now, calculation.systemFields,
                ]
            )
            guard let localCalculatedAt else { return false }
            return localCalculatedAt > calculation.calculatedAt
        }
    }

    private static func allocatedSize(of files: [URL]) -> Int {
        files.reduce(0) { total, file in
            let size = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize
            return total + (size ?? 0)
        }
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Migrations that shipped in a release must never change; add new ones after them.
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("createSchema") { db in
            try db.create(table: "clipboard") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("contentHash", .text).notNull().unique()
                table.column("kind", .text).notNull()
                table.column("text", .text)
                table.column("imageFile", .text)
                table.column("imageWidth", .integer)
                table.column("imageHeight", .integer)
                table.column("imageBytes", .integer)
                table.column("ocrText", .text)
                table.column("copiedAt", .datetime).notNull().indexed()
                table.column("sourceBundleID", .text)
                table.column("timesCopied", .integer).notNull().defaults(to: 1)
                table.column("pinnedAt", .datetime)
                table.column("updatedAt", .datetime).notNull()
                table.column("recordName", .text).unique()
                table.column("syncedAt", .datetime)
                table.column("cloudSystemFields", .blob)
                // Text recognition and copying read an image's file, so an image without one can't be stored.
                table.check(Column("kind") != ClipboardKind.image.rawValue || Column("imageFile") != nil)
            }
            try db.create(virtualTable: "clipboardFts", using: FTS5()) { table in
                table.synchronize(withTable: "clipboard")
                table.tokenizer = .unicode61()
                table.column("text")
                table.column("ocrText")
            }
            try db.create(table: "calculation") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("expression", .text).notNull()
                table.column("answer", .text).notNull()
                table.column("mode", .text).notNull()
                table.column("calculatedAt", .datetime).notNull().indexed()
                table.column("syncKey", .text)
                table.column("updatedAt", .datetime)
                table.column("recordName", .text).unique()
                table.column("syncedAt", .datetime)
                table.column("cloudSystemFields", .blob)
                table.uniqueKey(["expression", "mode"])
            }
            try db.create(indexOn: "calculation", columns: ["syncKey"], options: .unique)
            try db.create(table: "deletedRecord") { table in
                table.primaryKey("recordName", .text)
            }
        }
        // Added after 0.7.0.
        migrator.registerMigration("addQuicklinks") { db in
            try db.create(table: "quicklink") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("uuid", .text).notNull().unique()
                table.column("name", .text).notNull()
                table.column("keyword", .text)
                table.column("template", .text).notNull()
                table.column("appBundleID", .text)
                table.column("createdAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
                table.column("recordName", .text).unique()
                table.column("syncedAt", .datetime)
                table.column("cloudSystemFields", .blob)
            }
        }
        // Added after 0.9.0. Link previews are fetched on each Mac and never synced.
        migrator.registerMigration("addLinkPreviews") { db in
            try db.alter(table: "clipboard") { table in
                table.add(column: "linkTitle", .text)
                table.add(column: "linkImageFile", .text)
                table.add(column: "linkOcrText", .text)
            }
            // FTS5 tables can't gain columns, so the index is made again with the link's title and its preview's
            // text, and filled from the existing rows.
            try db.dropFTS5SynchronizationTriggers(forTable: "clipboardFts")
            try db.drop(table: "clipboardFts")
            try db.create(virtualTable: "clipboardFts", using: FTS5()) { table in
                table.synchronize(withTable: "clipboard")
                table.tokenizer = .unicode61()
                table.column("text")
                table.column("ocrText")
                table.column("linkTitle")
                table.column("linkOcrText")
            }
        }
        // Previews fetched before 0.10.6 often have only the site's icon, as LinkPresentation finds no share image on
        // some sites, so every link's preview is fetched again. The old image stays until the new one replaces it.
        migrator.registerMigration("refetchLinkPreviews") { db in
            try db.execute(sql: "UPDATE clipboard SET linkTitle = NULL WHERE kind = 'link'")
        }
        // Added after 0.11.1. Kept on each Mac and never synced.
        migrator.registerMigration("addImageTypes") { db in
            try db.alter(table: "clipboard") { table in
                table.add(column: "imageType", .text)
            }
        }
        // 0.11.2 kept the path of a photo copied from Photos, which names a file inside the Photos library by an internal
        // ID, so those images showed that ID as their name.
        migrator.registerMigration("forgetPhotosLibraryPaths") { db in
            try db.execute(sql: "UPDATE clipboard SET text = NULL WHERE kind = 'image' AND text LIKE '%.photoslibrary/%'")
        }
        return migrator
    }
}

/// A clipboard item as it arrived from another Mac, ready to merge.
public struct RemoteClipboardItem: Sendable {
    let hash: String
    let kind: ClipboardKind
    let text: String?
    let ocrText: String?
    let imageFile: String?
    let imageWidth: Int?
    let imageHeight: Int?
    let imageBytes: Int?
    let copiedAt: Date
    let sourceBundleID: String?
    let timesCopied: Int
    let pinnedAt: Date?
    let updatedAt: Date
    let recordName: String
    let systemFields: Data
}

/// A calculation as it arrived from another Mac, ready to merge.
public struct RemoteCalculation: Sendable {
    let key: String
    let expression: String
    let answer: String
    let mode: String
    let calculatedAt: Date
    let updatedAt: Date
    let recordName: String
    let systemFields: Data
}

/// A quicklink as it arrived from another Mac, ready to merge.
public struct RemoteQuicklink: Sendable {
    let uuid: String
    let name: String
    let keyword: String?
    let template: String
    let appBundleID: String?
    let createdAt: Date
    let updatedAt: Date
    let recordName: String
    let systemFields: Data
}

/// A row that syncs to iCloud, identified by its content on this Mac. Its iCloud record name is a keyed hash of this,
/// so the name doesn't reveal the content.
public enum SyncItem: Hashable, Sendable {
    case clipboard(contentHash: String)
    case calculation(key: String)
    case quicklink(uuid: String)

    static let clipboardPrefix = "clip-"
    static let calculationPrefix = "calc-"
    static let quicklinkPrefix = "link-"
}

/// The table and row a sync item or iCloud record name refers to.
private struct SyncTarget {
    let table: String
    let keyColumn: String
    let key: String

    init(_ item: SyncItem) {
        switch item {
        case .clipboard(let contentHash): self.init(table: "clipboard", keyColumn: "contentHash", key: contentHash)
        case .calculation(let key): self.init(table: "calculation", keyColumn: "syncKey", key: key)
        case .quicklink(let uuid): self.init(table: "quicklink", keyColumn: "uuid", key: uuid)
        }
    }

    init?(recordName: String) {
        let tables = [
            SyncItem.clipboardPrefix: "clipboard",
            SyncItem.calculationPrefix: "calculation",
            SyncItem.quicklinkPrefix: "quicklink",
        ]
        guard let table = tables.first(where: { recordName.hasPrefix($0.key) })?.value else { return nil }
        self.init(table: table, keyColumn: "recordName", key: recordName)
    }

    private init(table: String, keyColumn: String, key: String) {
        self.table = table
        self.keyColumn = keyColumn
        self.key = key
    }
}
