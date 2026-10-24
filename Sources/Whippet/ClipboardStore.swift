import CryptoKit
import Foundation
import GRDB

enum ClipboardKind: String, Codable, CaseIterable, Identifiable {
    case text
    case link
    case number
    case image

    var id: Self { self }

    var title: String {
        switch self {
        case .text: String(localized: "Text")
        case .link: String(localized: "Link")
        case .number: String(localized: "Number")
        case .image: String(localized: "Image")
        }
    }

    var pluralTitle: String {
        switch self {
        case .text: String(localized: "Text")
        case .link: String(localized: "Links")
        case .number: String(localized: "Numbers")
        case .image: String(localized: "Images")
        }
    }

    var symbolName: String {
        switch self {
        case .text: "doc"
        case .link: "link"
        case .number: "number"
        case .image: "photo"
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

struct ClipboardItem: Identifiable, Hashable, Codable, FetchableRecord, TableRecord {
    static let databaseTableName = "clipboard"

    let id: Int64
    let contentHash: String
    let kind: ClipboardKind
    let text: String?
    let imageFile: String?
    let imageWidth: Int?
    let imageHeight: Int?
    let imageBytes: Int?
    /// Nil until text recognition has run; empty when the image contains no text.
    let ocrText: String?
    let copiedAt: Date
    let sourceBundleID: String?
    let timesCopied: Int
    let pinnedAt: Date?

    var title: String {
        if kind == .image {
            return String(localized: "Image (\(imageWidth ?? 0)×\(imageHeight ?? 0))")
        }
        // Only the first line is read, since splitting a long copy on every render is slow.
        let firstLine = (text ?? "").drop(while: \.isWhitespace).prefix(while: { !$0.isNewline }).prefix(500)
        return String(firstLine).trimmingCharacters(in: .whitespaces)
    }
}

/// How long unpinned clipboard history is kept.
enum ClipboardRetention: String, CaseIterable, Identifiable {
    case day
    case week
    case month
    case threeMonths
    case year
    case forever

    var id: Self { self }

    var title: String {
        switch self {
        case .day: String(localized: "One Day")
        case .week: String(localized: "One Week")
        case .month: String(localized: "One Month")
        case .threeMonths: String(localized: "Three Months")
        case .year: String(localized: "One Year")
        case .forever: String(localized: "Forever")
        }
    }

    /// Items copied before this date are removed, or none when nil.
    func cutoff(from now: Date) -> Date? {
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

struct CalculationRecord: Identifiable, Hashable, Codable, FetchableRecord, TableRecord {
    static let databaseTableName = "calculation"

    let id: Int64
    let expression: String
    let answer: String
    let mode: String
    let calculatedAt: Date
}

struct ClipboardUsage {
    let directory: URL
    let databaseBytes: Int
    let imageBytes: Int
    let imageFiles: Int
    let counts: [ClipboardKind: Int]
    let imagesAwaitingRecognition: Int
    let calculations: Int
}

/// Clipboard history in a SQLite database in Application Support, with an FTS5 index over copied and recognized text.
/// Images live beside it as PNG files named by their content hash.
final class ClipboardStore: Sendable {
    /// Development builds keep their own history, sync state and key, which belong to CloudKit's Development environment.
    #if DEBUG
    static let defaultDirectory = URL.applicationSupportDirectory.appending(path: "Whippet Dev")
    #else
    static let defaultDirectory = URL.applicationSupportDirectory.appending(path: "Whippet")
    #endif

    let directory: URL
    let imagesDirectory: URL
    private let databaseURL: URL
    private let database: DatabaseQueue

    init(directory: URL = defaultDirectory) throws {
        self.directory = directory
        imagesDirectory = directory.appending(path: "Images")
        try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        databaseURL = directory.appending(path: "clipboard.sqlite")
        database = try DatabaseQueue(path: databaseURL.path)
        try Self.migrator.migrate(database)
    }

    /// Records a copy, moving content that is already in history to the top, and returns it for syncing.
    @discardableResult
    func recordText(_ text: String, sourceBundleID: String?) throws -> SyncItem {
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

    @discardableResult
    func recordImage(png: Data, width: Int, height: Int, sourceBundleID: String?) throws -> SyncItem {
        let hash = Self.hash(png)
        let file = imagesDirectory.appending(path: "\(hash).png")
        if !FileManager.default.fileExists(atPath: file.path) {
            try png.write(to: file)
        }
        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO clipboard (contentHash, kind, imageFile, imageWidth, imageHeight, imageBytes, copiedAt, sourceBundleID, updatedAt)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(contentHash) DO UPDATE SET
                        copiedAt = excluded.copiedAt,
                        sourceBundleID = excluded.sourceBundleID,
                        timesCopied = timesCopied + 1,
                        updatedAt = excluded.updatedAt
                    """,
                arguments: [
                    hash, ClipboardKind.image.rawValue, file.lastPathComponent, width, height, png.count, Date.now,
                    sourceBundleID, Date.now,
                ]
            )
        }
        return .clipboard(contentHash: hash)
    }

    func nextImageAwaitingRecognition() throws -> (hash: String, file: URL)? {
        try database.read { db in
            let row = try Row.fetchOne(
                db,
                sql: "SELECT contentHash, imageFile FROM clipboard WHERE kind = ? AND ocrText IS NULL ORDER BY copiedAt DESC",
                arguments: [ClipboardKind.image.rawValue]
            )
            guard let row else { return nil }
            let file: String = row["imageFile"]
            return (row["contentHash"], imagesDirectory.appending(path: file))
        }
    }

    @discardableResult
    func setRecognizedText(_ text: String, hash: String) throws -> SyncItem {
        try database.write { db in
            try db.execute(
                sql: "UPDATE clipboard SET ocrText = ?, updatedAt = ? WHERE contentHash = ?",
                arguments: [text, Date.now, hash]
            )
        }
        return .clipboard(contentHash: hash)
    }

    /// Records a calculation, moving an expression already in history to the top with its latest answer,
    /// and returns it for syncing.
    @discardableResult
    func recordCalculation(expression: String, answer: String, mode: String) throws -> SyncItem {
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

    func recentCalculations(limit: Int) throws -> [CalculationRecord] {
        try database.read { db in
            try CalculationRecord.order(Column("calculatedAt").desc).limit(limit).fetchAll(db)
        }
    }

    func imageURL(for item: ClipboardItem) -> URL? {
        item.imageFile.map { imagesDirectory.appending(path: $0) }
    }

    /// Returns the item for syncing, or nil when it no longer exists.
    func setPinned(_ pinned: Bool, id: Int64) throws -> SyncItem? {
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
    func search(_ query: String, kind: ClipboardKind?, limit: Int) throws -> [ClipboardItem] {
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

    func usage() throws -> ClipboardUsage {
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
                sql: "SELECT contentHash FROM clipboard WHERE (syncedAt IS NULL OR updatedAt > syncedAt) AND (? OR kind != ?)",
                arguments: [includeImages, ClipboardKind.image.rawValue]
            )
            let keys = try String.fetchAll(
                db,
                sql: "SELECT syncKey FROM calculation WHERE syncedAt IS NULL OR updatedAt > syncedAt"
            )
            return hashes.map { .clipboard(contentHash: $0) } + keys.map { .calculation(key: $0) }
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
            try db.execute(sql: "DELETE FROM deletedRecord")
        }
    }

    /// Record names of items deleted on this Mac whose deletion hasn't reached iCloud yet.
    func pendingDeletions() throws -> [String] {
        try database.read { db in
            try String.fetchAll(db, sql: "SELECT recordName FROM deletedRecord")
        }
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
    func delete(contentHash: String) throws -> String? {
        try delete(SyncTarget(.clipboard(contentHash: contentHash)), remembersDeletion: true)
    }

    /// Deletes items copied before `cutoff`, or all of them when it's nil, keeping pinned items unless `includingPinned`.
    /// Returns the iCloud record names of the deleted items that had synced, which are kept until the deletions reach
    /// iCloud, like single deletions.
    func deleteItems(copiedBefore cutoff: Date?, includingPinned: Bool = false) throws -> [String] {
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
            let rows = try Row.fetchAll(db, sql: "SELECT recordName, imageFile FROM clipboard \(filter)", arguments: arguments)
            try db.execute(sql: "DELETE FROM clipboard \(filter)", arguments: arguments)
            for case let recordName? in rows.map({ $0["recordName"] as String? }) {
                try db.execute(sql: "INSERT OR IGNORE INTO deletedRecord (recordName) VALUES (?)", arguments: [recordName])
            }
            return rows
        }
        for case let imageFile? in rows.map({ $0["imageFile"] as String? }) {
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
        if let imageFile = row?["imageFile"] as String? {
            try? FileManager.default.removeItem(at: imagesDirectory.appending(path: imageFile))
        }
        return row?["recordName"]
    }

    /// Merges an item from another Mac: the latest copy time and highest copy count win, and the most recently
    /// changed side decides the pin and source app. Returns true when this Mac's copy is ahead and should be uploaded.
    func mergeRemote(_ item: RemoteClipboardItem) throws -> Bool {
        try database.write { db in
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

    private static var migrator: DatabaseMigrator {
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
        return migrator
    }
}

/// A clipboard item as it arrived from another Mac, ready to merge.
struct RemoteClipboardItem {
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
struct RemoteCalculation {
    let key: String
    let expression: String
    let answer: String
    let mode: String
    let calculatedAt: Date
    let updatedAt: Date
    let recordName: String
    let systemFields: Data
}

/// A row that syncs to iCloud, identified by its content on this Mac. Its iCloud record name is a keyed hash of this,
/// so the name doesn't reveal the content.
enum SyncItem: Hashable, Sendable {
    case clipboard(contentHash: String)
    case calculation(key: String)

    static let clipboardPrefix = "clip-"
    static let calculationPrefix = "calc-"
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
        }
    }

    init?(recordName: String) {
        if recordName.hasPrefix(SyncItem.clipboardPrefix) {
            self.init(table: "clipboard", keyColumn: "recordName", key: recordName)
            return
        }
        guard recordName.hasPrefix(SyncItem.calculationPrefix) else { return nil }
        self.init(table: "calculation", keyColumn: "recordName", key: recordName)
    }

    private init(table: String, keyColumn: String, key: String) {
        self.table = table
        self.keyColumn = keyColumn
        self.key = key
    }
}
