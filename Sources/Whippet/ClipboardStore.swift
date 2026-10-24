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
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.split(whereSeparator: \.isNewline).first.map(String.init) ?? trimmed
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
    static let defaultDirectory = URL.applicationSupportDirectory.appending(path: "Whippet")

    let directory: URL
    let imagesDirectory: URL
    private let databaseURL: URL
    private let database: DatabaseQueue

    init() throws {
        directory = Self.defaultDirectory
        imagesDirectory = directory.appending(path: "Images")
        try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        databaseURL = directory.appending(path: "clipboard.sqlite")
        database = try DatabaseQueue(path: databaseURL.path)
        try Self.migrator.migrate(database)
    }

    /// Records a copy, moving content that is already in history to the top, and returns its sync record name.
    @discardableResult
    func recordText(_ text: String, sourceBundleID: String?) throws -> String {
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
        return Self.clipboardRecordName(hash)
    }

    @discardableResult
    func recordImage(png: Data, width: Int, height: Int, sourceBundleID: String?) throws -> String {
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
        return Self.clipboardRecordName(hash)
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
    func setRecognizedText(_ text: String, hash: String) throws -> String {
        try database.write { db in
            try db.execute(
                sql: "UPDATE clipboard SET ocrText = ?, updatedAt = ? WHERE contentHash = ?",
                arguments: [text, Date.now, hash]
            )
        }
        return Self.clipboardRecordName(hash)
    }

    /// Records a calculation, moving an expression already in history to the top with its latest answer,
    /// and returns its sync record name.
    @discardableResult
    func recordCalculation(expression: String, answer: String, mode: String) throws -> String {
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
        return Self.calculationRecordName(key)
    }

    func recentCalculations(limit: Int) throws -> [CalculationRecord] {
        try database.read { db in
            try CalculationRecord.order(Column("calculatedAt").desc).limit(limit).fetchAll(db)
        }
    }

    func imageURL(for item: ClipboardItem) -> URL? {
        item.imageFile.map { imagesDirectory.appending(path: $0) }
    }

    /// Returns the sync record name of the item, or nil when it no longer exists.
    func setPinned(_ pinned: Bool, id: Int64) throws -> String? {
        let hash = try database.write { db in
            try String.fetchOne(
                db,
                sql: "UPDATE clipboard SET pinnedAt = ?, updatedAt = ? WHERE id = ? RETURNING contentHash",
                arguments: [pinned ? Date.now : nil, Date.now, id]
            )
        }
        return hash.map(Self.clipboardRecordName)
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

    static func clipboardRecordName(_ hash: String) -> String {
        "clip-\(hash)"
    }

    static func calculationRecordName(_ key: String) -> String {
        "calc-\(key)"
    }

    static func calculationKey(expression: String, mode: String) -> String {
        hash(Data("\(mode)\n\(expression)".utf8))
    }

    func clipboardSyncRow(hash: String) throws -> Row? {
        try database.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM clipboard WHERE contentHash = ?", arguments: [hash])
        }
    }

    func calculationSyncRow(key: String) throws -> Row? {
        try database.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM calculation WHERE syncKey = ?", arguments: [key])
        }
    }

    /// Record names changed on this Mac since they last synced, which covers changes made while sync was off.
    func unsyncedRecordNames(includeImages: Bool) throws -> [String] {
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
            return hashes.map(Self.clipboardRecordName) + keys.map(Self.calculationRecordName)
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

    func forgetAllSyncState() throws {
        try database.write { db in
            try db.execute(sql: "UPDATE clipboard SET syncedAt = NULL, cloudSystemFields = NULL")
            try db.execute(sql: "UPDATE calculation SET syncedAt = NULL, cloudSystemFields = NULL")
        }
    }

    func deleteRecord(named recordName: String) throws {
        guard let target = SyncTarget(recordName: recordName) else { return }
        let imageFile = try database.write { db in
            let imageFile = target.table == "clipboard"
                ? try String.fetchOne(db, sql: "SELECT imageFile FROM clipboard WHERE contentHash = ?", arguments: [target.key])
                : nil
            try db.execute(sql: "DELETE FROM \(target.table) WHERE \(target.keyColumn) = ?", arguments: [target.key])
            return imageFile
        }
        if let imageFile {
            try? FileManager.default.removeItem(at: imagesDirectory.appending(path: imageFile))
        }
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
                        sourceBundleID, timesCopied, pinnedAt, updatedAt, syncedAt, cloudSystemFields
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(contentHash) DO UPDATE SET
                        imageFile = COALESCE(imageFile, excluded.imageFile),
                        ocrText = COALESCE(ocrText, excluded.ocrText),
                        pinnedAt = CASE WHEN excluded.updatedAt > updatedAt THEN excluded.pinnedAt ELSE pinnedAt END,
                        sourceBundleID = CASE WHEN excluded.updatedAt > updatedAt THEN excluded.sourceBundleID ELSE sourceBundleID END,
                        copiedAt = MAX(copiedAt, excluded.copiedAt),
                        timesCopied = MAX(timesCopied, excluded.timesCopied),
                        updatedAt = MAX(updatedAt, excluded.updatedAt),
                        syncedAt = excluded.syncedAt,
                        cloudSystemFields = excluded.cloudSystemFields
                    """,
                arguments: [
                    item.hash, item.kind.rawValue, item.text, item.imageFile, item.imageWidth, item.imageHeight,
                    item.imageBytes, item.ocrText, item.copiedAt, item.sourceBundleID, item.timesCopied, item.pinnedAt,
                    item.updatedAt, Date.now, item.systemFields,
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
                    INSERT INTO calculation (expression, answer, mode, calculatedAt, syncKey, updatedAt, syncedAt, cloudSystemFields)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(expression, mode) DO UPDATE SET
                        answer = CASE WHEN excluded.calculatedAt > calculatedAt THEN excluded.answer ELSE answer END,
                        calculatedAt = MAX(calculatedAt, excluded.calculatedAt),
                        updatedAt = MAX(updatedAt, excluded.updatedAt),
                        syncedAt = excluded.syncedAt,
                        cloudSystemFields = excluded.cloudSystemFields
                    """,
                arguments: [
                    calculation.expression, calculation.answer, calculation.mode, calculation.calculatedAt,
                    calculation.key, calculation.updatedAt, Date.now, calculation.systemFields,
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
                table.column("syncedAt", .datetime)
                table.column("cloudSystemFields", .blob)
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
                table.column("syncedAt", .datetime)
                table.column("cloudSystemFields", .blob)
                table.uniqueKey(["expression", "mode"])
            }
            try db.create(indexOn: "calculation", columns: ["syncKey"], options: .unique)
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
    let systemFields: Data
}

/// The table and row a sync record name refers to.
private struct SyncTarget {
    let table: String
    let keyColumn: String
    let key: String

    init?(recordName: String) {
        if recordName.hasPrefix("clip-") {
            self.init(table: "clipboard", keyColumn: "contentHash", key: String(recordName.dropFirst(5)))
            return
        }
        guard recordName.hasPrefix("calc-") else { return nil }
        self.init(table: "calculation", keyColumn: "syncKey", key: String(recordName.dropFirst(5)))
    }

    private init(table: String, keyColumn: String, key: String) {
        self.table = table
        self.keyColumn = keyColumn
        self.key = key
    }
}
