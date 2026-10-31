import Foundation
import GRDB
import Testing

@testable import WhippetCore

struct QuicklinkTemplateTests {
    @Test(arguments: [
        ("https://github.com/search?q={query}", "react hooks", "https://github.com/search?q=react%20hooks"),
        ("https://example.com/?q={query}", "a&b=c#d?e/f", "https://example.com/?q=a%26b%3Dc%23d%3Fe%2Ff"),
        ("https://example.com/?q={query}", "café", "https://example.com/?q=caf%C3%A9"),
        ("https://example.com/{query:raw}", "docs/guide", "https://example.com/docs/guide"),
        ("https://example.com/", "ignored", "https://example.com/"),
    ])
    func fillsTheArgument(_ template: String, _ argument: String, _ expected: String) {
        #expect(QuicklinkTemplate.url(template, argument: argument)?.absoluteString == expected)
    }

    @Test func knowsWhichTemplatesTakeAnArgument() {
        #expect(QuicklinkTemplate.takesArgument("https://x.com/?q={query}"))
        #expect(QuicklinkTemplate.takesArgument("https://x.com/{query:raw}"))
        #expect(!QuicklinkTemplate.takesArgument("https://x.com/"))
    }

    @Test(arguments: ["", "not a url", "example.com/{query}", "https://exa mple.com/{query:raw}"])
    func rejectsTemplatesThatArentLinks(_ template: String) {
        #expect(!QuicklinkTemplate.isValid(template))
    }

    @Test func acceptsAppLinks() {
        #expect(QuicklinkTemplate.isValid("maps://?q={query}"))
        #expect(QuicklinkTemplate.isValid("mailto:{query}"))
    }
}

final class QuicklinkStoreTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "WhippetQuicklinks-\(UUID().uuidString)")

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    private func link(_ uuid: String = UUID().uuidString, name: String = "Search Example") -> Quicklink {
        Quicklink(uuid: uuid, name: name, keyword: "ex", template: "https://example.com/?q={query}")
    }

    @Test func upgradesADatabaseFrom070() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appending(path: "clipboard.sqlite").path
        do {
            let database = try DatabaseQueue(path: path)
            try ClipboardStore.migrator.migrate(database, upTo: "createSchema")
            try database.write { db in
                try db.execute(
                    sql:
                        "INSERT INTO clipboard (contentHash, kind, text, copiedAt, updatedAt) VALUES ('h', 'text', 'kept', ?, ?)",
                    arguments: [Date.now, Date.now]
                )
            }
        }

        let store = try ClipboardStore(directory: directory)
        #expect(try store.search("", kind: nil, limit: 10).compactMap(\.text) == ["kept"])
        #expect(try store.quicklinks().isEmpty)
        try store.saveQuicklink(link())
        #expect(try store.quicklinks().count == 1)
    }

    @Test func savesUpdatesAndDeletes() throws {
        let store = try ClipboardStore(directory: directory)
        var quicklink = link("one", name: "B")
        let item = try store.saveQuicklink(quicklink)
        try store.saveQuicklink(link("two", name: "a"))
        #expect(try store.quicklinks().map(\.name) == ["a", "B"])
        #expect(try store.unsyncedItems(includeImages: true).contains(item))

        quicklink.name = "Renamed"
        quicklink.appBundleID = "com.apple.Safari"
        try store.saveQuicklink(quicklink)
        let saved = try #require(try store.quicklinks().first { $0.uuid == "one" })
        #expect(saved.name == "Renamed")
        #expect(saved.appBundleID == "com.apple.Safari")

        try store.assignRecordNames([item: "link-one"])
        #expect(try store.deleteQuicklink(uuid: "one") == "link-one")
        #expect(try store.pendingDeletions() == ["link-one"])
        #expect(try store.quicklinks().map(\.uuid) == ["two"])
    }

    @Test func startersAreOnlyAddedWhenMissing() throws {
        let store = try ClipboardStore(directory: directory)
        let starter = try #require(Quicklink.starters.first)
        #expect(try store.addQuicklinkIfMissing(starter) == .quicklink(uuid: starter.uuid))
        var renamed = starter
        renamed.name = "My Search"
        try store.saveQuicklink(renamed)
        #expect(try store.addQuicklinkIfMissing(starter) == nil)
        #expect(try store.quicklinks().first?.name == "My Search")
    }

    @Test func mergingKeepsTheNewerSide() throws {
        let store = try ClipboardStore(directory: directory)
        try store.saveQuicklink(link("shared", name: "Local"))
        func remote(_ name: String, at date: Date) -> RemoteQuicklink {
            RemoteQuicklink(
                uuid: "shared", name: name, keyword: nil, template: "https://example.com/?q={query}", appBundleID: nil,
                createdAt: date, updatedAt: date, recordName: "link-shared", systemFields: Data()
            )
        }

        #expect(try store.mergeRemote(remote("Older", at: .now.addingTimeInterval(-60))))
        #expect(try store.quicklinks().first?.name == "Local")

        #expect(try !store.mergeRemote(remote("Newer", at: .now.addingTimeInterval(60))))
        #expect(try store.quicklinks().first?.name == "Newer")
        #expect(try store.syncRow(recordName: "link-shared") != nil)
    }
}
