import CryptoKit
import Foundation
import GRDB

enum ClipboardKind: String, Codable, CaseIterable, Identifiable {
    case text
    case link
    case image

    var id: Self { self }

    var title: String {
        switch self {
        case .text: "Text"
        case .link: "Link"
        case .image: "Image"
        }
    }

    var pluralTitle: String {
        switch self {
        case .text: "Text"
        case .link: "Links"
        case .image: "Images"
        }
    }

    static func classify(_ text: String) -> ClipboardKind {
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
            return "Image (\(imageWidth ?? 0)×\(imageHeight ?? 0))"
        }
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.split(whereSeparator: \.isNewline).first.map(String.init) ?? trimmed
    }
}

struct ClipboardUsage {
    let directory: URL
    let databaseBytes: Int
    let imageBytes: Int
    let imageFiles: Int
    let counts: [ClipboardKind: Int]
    let imagesAwaitingRecognition: Int
}

/// Clipboard history in a SQLite database in Application Support, with an FTS5 index over copied and recognized text.
/// Images live beside it as PNG files named by their content hash.
final class ClipboardStore: Sendable {
    let directory: URL
    let imagesDirectory: URL
    private let databaseURL: URL
    private let database: DatabaseQueue

    init() throws {
        directory = URL.applicationSupportDirectory.appending(path: "Launcher")
        imagesDirectory = directory.appending(path: "Images")
        try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        databaseURL = directory.appending(path: "clipboard.sqlite")
        database = try DatabaseQueue(path: databaseURL.path)
        try Self.migrator.migrate(database)
    }

    /// Records a copy, moving content that is already in history to the top.
    func recordText(_ text: String, sourceBundleID: String?) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO clipboard (contentHash, kind, text, copiedAt, sourceBundleID) VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(contentHash) DO UPDATE SET
                        copiedAt = excluded.copiedAt,
                        sourceBundleID = excluded.sourceBundleID,
                        timesCopied = timesCopied + 1
                    """,
                arguments: [
                    Self.hash(Data(text.utf8)), ClipboardKind.classify(text).rawValue, text, Date.now, sourceBundleID,
                ]
            )
        }
    }

    func recordImage(png: Data, width: Int, height: Int, sourceBundleID: String?) throws {
        let hash = Self.hash(png)
        let file = imagesDirectory.appending(path: "\(hash).png")
        if !FileManager.default.fileExists(atPath: file.path) {
            try png.write(to: file)
        }
        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO clipboard (contentHash, kind, imageFile, imageWidth, imageHeight, imageBytes, copiedAt, sourceBundleID)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(contentHash) DO UPDATE SET
                        copiedAt = excluded.copiedAt,
                        sourceBundleID = excluded.sourceBundleID,
                        timesCopied = timesCopied + 1
                    """,
                arguments: [
                    hash, ClipboardKind.image.rawValue, file.lastPathComponent, width, height, png.count, Date.now,
                    sourceBundleID,
                ]
            )
        }
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

    func setRecognizedText(_ text: String, hash: String) throws {
        try database.write { db in
            try db.execute(sql: "UPDATE clipboard SET ocrText = ? WHERE contentHash = ?", arguments: [text, hash])
        }
    }

    func imageURL(for item: ClipboardItem) -> URL? {
        item.imageFile.map { imagesDirectory.appending(path: $0) }
    }

    func setPinned(_ pinned: Bool, id: Int64) throws {
        try database.write { db in
            try db.execute(
                sql: "UPDATE clipboard SET pinnedAt = ? WHERE id = ?",
                arguments: [pinned ? Date.now : nil, id]
            )
        }
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
        let (counts, awaiting) = try database.read { db in
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
            return (counts, awaiting ?? 0)
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
            imagesAwaitingRecognition: awaiting
        )
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
        migrator.registerMigration("createClipboard") { db in
            try db.create(table: "clipboard") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("text", .text).notNull().unique()
                table.column("copiedAt", .datetime).notNull().indexed()
            }
            try db.create(virtualTable: "clipboardFts", using: FTS5()) { table in
                table.synchronize(withTable: "clipboard")
                table.tokenizer = .unicode61()
                table.column("text")
            }
        }
        migrator.registerMigration("addClipboardMetadata") { db in
            try db.alter(table: "clipboard") { table in
                table.add(column: "kind", .text).notNull().defaults(to: ClipboardKind.text.rawValue)
                table.add(column: "sourceBundleID", .text)
                table.add(column: "timesCopied", .integer).notNull().defaults(to: 1)
            }
            for item in try Row.fetchAll(db, sql: "SELECT id, text FROM clipboard") {
                let text: String = item["text"]
                try db.execute(
                    sql: "UPDATE clipboard SET kind = ? WHERE id = ?",
                    arguments: [ClipboardKind.classify(text).rawValue, item["id"]]
                )
            }
        }
        // SQLite cannot drop the NOT NULL on `text`, so the table is rebuilt with images deduplicated by content hash.
        migrator.registerMigration("supportImages") { db in
            try db.create(table: "clipboardNew") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("contentHash", .text).notNull().unique()
                table.column("kind", .text).notNull()
                table.column("text", .text)
                table.column("imageFile", .text)
                table.column("imageWidth", .integer)
                table.column("imageHeight", .integer)
                table.column("imageBytes", .integer)
                table.column("ocrText", .text)
                table.column("copiedAt", .datetime).notNull()
                table.column("sourceBundleID", .text)
                table.column("timesCopied", .integer).notNull().defaults(to: 1)
            }
            for row in try Row.fetchAll(db, sql: "SELECT * FROM clipboard") {
                let text: String = row["text"]
                let kind: String = row["kind"]
                let copiedAt: Date = row["copiedAt"]
                let sourceBundleID: String? = row["sourceBundleID"]
                let timesCopied: Int = row["timesCopied"]
                try db.execute(
                    sql: """
                        INSERT INTO clipboardNew (contentHash, kind, text, copiedAt, sourceBundleID, timesCopied)
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [hash(Data(text.utf8)), kind, text, copiedAt, sourceBundleID, timesCopied]
                )
            }
            try db.drop(table: "clipboardFts")
            try db.drop(table: "clipboard")
            try db.rename(table: "clipboardNew", to: "clipboard")
            try db.create(indexOn: "clipboard", columns: ["copiedAt"])
            try db.create(virtualTable: "clipboardFts", using: FTS5()) { table in
                table.synchronize(withTable: "clipboard")
                table.tokenizer = .unicode61()
                table.column("text")
                table.column("ocrText")
            }
        }
        migrator.registerMigration("addPinning") { db in
            try db.alter(table: "clipboard") { table in
                table.add(column: "pinnedAt", .datetime)
            }
        }
        return migrator
    }
}
