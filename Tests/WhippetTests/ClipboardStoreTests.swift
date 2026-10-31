import Foundation
import GRDB
import Testing

@testable import WhippetCore

/// Each test gets its own store in a temporary folder, migrated from an empty database.
final class ClipboardStoreTests {
    let directory: URL
    let store: ClipboardStore

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "WhippetTests-\(UUID().uuidString)")
        store = try ClipboardStore(directory: directory)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    /// The store keeps dates to the millisecond, so changes made within one would tie when ordered by time.
    private func pause() async throws {
        try await Task.sleep(for: .milliseconds(5))
    }

    private func items(_ query: String = "", kind: ClipboardKind? = nil) throws -> [ClipboardItem] {
        try store.search(query, kind: kind, limit: 100)
    }

    // MARK: - Recording

    @Test func recordingClassifiesText() throws {
        try store.recordText("hello", sourceBundleID: "com.example.editor")
        try store.recordText("https://example.com", sourceBundleID: nil)
        try store.recordText("1,234", sourceBundleID: nil)

        let kinds = Dictionary(uniqueKeysWithValues: try items().map { ($0.text ?? "", $0.kind) })
        #expect(kinds == ["hello": .text, "https://example.com": .link, "1,234": .number])
    }

    @Test func copyingAgainMovesToTheTopAndCounts() async throws {
        let first = try store.recordText("first", sourceBundleID: "com.example.a")
        try await pause()
        try store.recordText("second", sourceBundleID: nil)
        try await pause()
        let again = try store.recordText("first", sourceBundleID: "com.example.b")

        #expect(first == again)
        let all = try items()
        #expect(all.map(\.text) == ["first", "second"])
        #expect(all[0].timesCopied == 2)
        #expect(all[0].sourceBundleID == "com.example.b")
    }

    @Test func copyingFromHistoryMovesTheItemUpWithoutADuplicate() async throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 4, 5, 6])
        let image = try store.recordImage(png: png, width: 2, height: 2, sourceBundleID: "com.example.source")
        try await pause()
        try store.recordText("newer", sourceBundleID: nil)
        try await pause()
        guard case .clipboard(let hash) = image else {
            Issue.record("Expected a clipboard item")
            return
        }

        #expect(try store.recordCopy(contentHash: hash) == image)
        let all = try items()
        #expect(all.count == 2)
        #expect(all.first?.contentHash == hash)
        #expect(all.first?.timesCopied == 2)
        #expect(all.first?.sourceBundleID == "com.example.source")
        #expect(try store.recordCopy(contentHash: String(repeating: "0", count: 64)) == nil)
    }

    @Test func recordingAnImageStoresItOnce() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
        try store.recordImage(png: png, width: 4, height: 2, sourceBundleID: nil)
        try store.recordImage(png: png, width: 4, height: 2, sourceBundleID: nil)

        let item = try #require(try items(kind: .image).first)
        #expect(item.timesCopied == 2)
        #expect(item.title == "Image (4×2)")
        let file = try #require(store.imageURL(for: item))
        #expect(try Data(contentsOf: file) == png)
        #expect(try store.nextImageAwaitingRecognition()?.hash == item.contentHash)

        try store.setRecognizedText("receipt total", hash: item.contentHash)
        #expect(try store.nextImageAwaitingRecognition() == nil)
        #expect(try items("receipt").map(\.id) == [item.id])
    }

    @Test func imagesShowTheirFileNameOrFormat() throws {
        try store.recordImage(png: Data([1]), width: 4, height: 2, type: "public.jpeg", sourceBundleID: nil)
        try store.recordImage(
            png: Data([2]), width: 4, height: 2, type: "public.png", path: "/tmp/Photo One.jpg", sourceBundleID: nil)

        let titles = Set(try items(kind: .image).map(\.title))
        #expect(titles.contains("Photo One.jpg"))
        #expect(titles.contains { $0.localizedCaseInsensitiveContains("JPEG") && $0.hasSuffix("(4×2)") })
        #expect(try items("photo").count == 1)
    }

    @Test func copyingAnImageAgainKeepsItsNameUnlessTheNewCopyHasOne() throws {
        try store.recordImage(png: Data([1]), width: 1, height: 1, path: "/tmp/a.png", sourceBundleID: nil)
        try store.recordImage(png: Data([1]), width: 1, height: 1, type: "public.tiff", sourceBundleID: nil)
        #expect(try items(kind: .image).first?.title == "a.png")

        try store.recordImage(png: Data([1]), width: 1, height: 1, path: "/tmp/b.png", sourceBundleID: nil)
        let item = try #require(try items(kind: .image).first)
        #expect(item.title == "b.png")
        #expect(item.imageType == "public.tiff")
    }

    @Test func photosLibraryPathsAreForgotten() throws {
        try store.recordImage(
            png: Data([1]), width: 1, height: 1,
            path: "/Users/me/Pictures/Photos Library.photoslibrary/resources/derivatives/A_1_c.jpeg",
            sourceBundleID: nil)
        try store.recordImage(
            png: Data([2]), width: 1, height: 1, path: "/Users/me/Pictures/Beach.heic", sourceBundleID: nil)
        try DatabaseQueue(path: directory.appending(path: "clipboard.sqlite").path).write { db in
            try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'forgetPhotosLibraryPaths'")
        }

        let reopened = try ClipboardStore(directory: directory)
        let titles = Set(try reopened.search("", kind: .image, limit: 10).map(\.title))
        #expect(titles == ["Image (1×1)", "Beach.heic"])
    }

    @Test func filesKeepTheirExtensionsAndStayOnThisMac() throws {
        try store.recordFiles(["/Users/me/Report.pdf"], sourceBundleID: "com.apple.finder")
        try store.recordFiles(["/Users/me/a.txt", "/Users/me/b.txt", "/Users/me/Folder"], sourceBundleID: nil)
        try store.recordText("/Users/me/Report.pdf", sourceBundleID: nil)

        let files = try items(kind: .file)
        #expect(Set(files.map(\.title)) == ["Report.pdf", "a.txt and 2 More"])
        #expect(files.first { $0.title == "Report.pdf" }?.fileURLs == [URL(filePath: "/Users/me/Report.pdf")])
        #expect(try items("report").count == 2)
        #expect(try store.unsyncedItems(includeImages: true).count == 1)
    }

    @Test func calculationsKeepTheLatestAnswerPerExpression() async throws {
        try store.recordCalculation(expression: "1 + 1", answer: "2", mode: "standard")
        try await pause()
        try store.recordCalculation(expression: "2 3 +", answer: "5", mode: "rpn")
        try await pause()
        try store.recordCalculation(expression: "1 + 1", answer: "two", mode: "standard")

        let recent = try store.recentCalculations(limit: 10)
        #expect(recent.map(\.expression) == ["1 + 1", "2 3 +"])
        #expect(recent[0].answer == "two")
    }

    // MARK: - Search

    @Test func searchMatchesWordPrefixesAndFiltersByKind() throws {
        try store.recordText("apple pie recipe", sourceBundleID: nil)
        try store.recordText("banana bread", sourceBundleID: nil)
        try store.recordText("https://apple.com", sourceBundleID: nil)

        #expect(Set(try items("app").compactMap(\.text)) == ["apple pie recipe", "https://apple.com"])
        #expect(try items("app pie").compactMap(\.text) == ["apple pie recipe"])
        #expect(try items("app", kind: .link).compactMap(\.text) == ["https://apple.com"])
        #expect(try items("cherry").isEmpty)
    }

    @Test func pinnedItemsComeFirstInPinOrder() async throws {
        try store.recordText("one", sourceBundleID: nil)
        try await pause()
        try store.recordText("two", sourceBundleID: nil)
        try await pause()
        try store.recordText("three", sourceBundleID: nil)
        let byText = Dictionary(uniqueKeysWithValues: try items().map { ($0.text ?? "", $0.id) })

        _ = try store.setPinned(true, id: try #require(byText["one"]))
        try await pause()
        _ = try store.setPinned(true, id: try #require(byText["two"]))
        #expect(try items().compactMap(\.text) == ["one", "two", "three"])

        _ = try store.setPinned(false, id: try #require(byText["one"]))
        #expect(try items().compactMap(\.text) == ["two", "three", "one"])
    }

    // MARK: - Sync bookkeeping

    @Test func changedItemsWaitForUploadUntilMarkedSynced() throws {
        let item = try store.recordText("hello", sourceBundleID: nil)
        try store.recordCalculation(expression: "1 + 1", answer: "2", mode: "standard")
        #expect(try store.unsyncedItems(includeImages: true).count == 2)

        try store.assignRecordNames([item: "clip-name"])
        try store.markSynced(recordName: "clip-name", systemFields: Data())
        #expect(try store.unsyncedItems(includeImages: true).count == 1)
        #expect(try store.syncRow(recordName: "clip-name") != nil)

        try store.forgetAllSyncState()
        #expect(try store.unsyncedItems(includeImages: true).count == 2)
        #expect(try store.syncRow(recordName: "clip-name") == nil)
    }

    @Test func unsyncedItemsCanLeaveOutImages() throws {
        try store.recordText("hello", sourceBundleID: nil)
        try store.recordImage(png: Data([1, 2, 3]), width: 1, height: 1, sourceBundleID: nil)
        #expect(try store.unsyncedItems(includeImages: true).count == 2)
        #expect(try store.unsyncedItems(includeImages: false).count == 1)
    }

    @Test func deletingReturnsTheRecordNameOnlyOnceNamed() throws {
        let named = try store.recordText("named", sourceBundleID: nil)
        try store.recordText("unnamed", sourceBundleID: nil)
        try store.assignRecordNames([named: "clip-named"])
        let hashes = Dictionary(uniqueKeysWithValues: try items().map { ($0.text ?? "", $0.contentHash) })

        #expect(try store.delete(contentHash: try #require(hashes["unnamed"])) == nil)
        #expect(try store.delete(contentHash: try #require(hashes["named"])) == "clip-named")
        #expect(try items().isEmpty)
    }

    @Test func deletionsAreRememberedUntilTheyReachICloud() throws {
        let synced = try store.recordText("synced", sourceBundleID: nil)
        try store.recordText("local only", sourceBundleID: nil)
        try store.assignRecordNames([synced: "clip-synced"])
        for item in try items() {
            _ = try store.delete(contentHash: item.contentHash)
        }

        #expect(try store.pendingDeletions() == ["clip-synced"])
        try store.forgetDeletions(["clip-synced"])
        #expect(try store.pendingDeletions().isEmpty)
    }

    @Test func copyingAgainCancelsAPendingDeletion() throws {
        let item = try store.recordText("back again", sourceBundleID: nil)
        try store.assignRecordNames([item: "clip-again"])
        guard case .clipboard(let hash) = item else {
            Issue.record("Expected a clipboard item")
            return
        }
        _ = try store.delete(contentHash: hash)
        #expect(try store.pendingDeletions() == ["clip-again"])

        let copiedAgain = try store.recordText("back again", sourceBundleID: nil)
        try store.assignRecordNames([copiedAgain: "clip-again"])
        #expect(try store.pendingDeletions().isEmpty)
    }

    @Test func aDeletionFromAnotherMacOrAResetClearsPendingDeletions() throws {
        let first = try store.recordText("first", sourceBundleID: nil)
        let second = try store.recordText("second", sourceBundleID: nil)
        try store.assignRecordNames([first: "clip-first", second: "clip-second"])
        for item in try items() {
            _ = try store.delete(contentHash: item.contentHash)
        }
        #expect(Set(try store.pendingDeletions()) == ["clip-first", "clip-second"])

        try store.deleteRecord(named: "clip-first")
        #expect(try store.pendingDeletions() == ["clip-second"])

        try store.forgetAllSyncState()
        #expect(try store.pendingDeletions().isEmpty)
    }

    @Test func deletingOldItemsKeepsPinnedAndRecentOnes() async throws {
        let old = try store.recordText("old", sourceBundleID: nil)
        let oldImage = try store.recordImage(png: Data([1, 2, 3]), width: 1, height: 1, sourceBundleID: nil)
        try store.recordText("old but pinned", sourceBundleID: nil)
        try await pause()
        let cutoff = Date.now
        try await pause()
        try store.recordText("recent", sourceBundleID: nil)
        try store.assignRecordNames([old: "clip-old", oldImage: "clip-old-image"])
        let pinned = try #require(try items().first { $0.text == "old but pinned" })
        _ = try store.setPinned(true, id: pinned.id)
        let image = try #require(try items(kind: .image).first)
        let imageFile = try #require(store.imageURL(for: image))

        let deleted = try store.deleteItems(copiedBefore: cutoff)

        #expect(Set(deleted) == ["clip-old", "clip-old-image"])
        #expect(Set(try items().compactMap(\.text)) == ["old but pinned", "recent"])
        #expect(Set(try store.pendingDeletions()) == ["clip-old", "clip-old-image"])
        #expect(!FileManager.default.fileExists(atPath: imageFile.path))
    }

    @Test func clearingCanIncludePinnedItems() throws {
        try store.recordText("plain", sourceBundleID: nil)
        try store.recordText("pinned", sourceBundleID: nil)
        _ = try store.setPinned(true, id: try #require(try items().first { $0.text == "pinned" }).id)

        _ = try store.deleteItems(copiedBefore: nil)
        #expect(try items().compactMap(\.text) == ["pinned"])

        _ = try store.deleteItems(copiedBefore: nil, includingPinned: true)
        #expect(try items().isEmpty)
    }

    @Test func titlesAreTheFirstLine() throws {
        try store.recordText("  \n  first line  \nsecond line", sourceBundleID: nil)
        try store.recordText(String(repeating: "x", count: 2000), sourceBundleID: nil)
        let titles = Set(try items().map(\.title))
        #expect(titles == ["first line", String(repeating: "x", count: 500)])
    }

    @Test func deletingARecordFromAnotherMacRemovesTheImage() throws {
        let item = try store.recordImage(png: Data([1, 2, 3]), width: 1, height: 1, sourceBundleID: nil)
        try store.assignRecordNames([item: "clip-image"])
        let stored = try #require(try items().first)
        let file = try #require(store.imageURL(for: stored))

        try store.deleteRecord(named: "clip-image")
        #expect(try items().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    // MARK: - Merging

    private func remote(
        hash: String = String(repeating: "a", count: 64),
        text: String = "from another Mac",
        copiedAt: Date,
        timesCopied: Int = 1,
        pinnedAt: Date? = nil,
        sourceBundleID: String? = nil,
        updatedAt: Date
    ) -> RemoteClipboardItem {
        RemoteClipboardItem(
            hash: hash, kind: .text, text: text, ocrText: nil, imageFile: nil, imageWidth: nil, imageHeight: nil,
            imageBytes: nil, copiedAt: copiedAt, sourceBundleID: sourceBundleID, timesCopied: timesCopied,
            pinnedAt: pinnedAt, updatedAt: updatedAt, recordName: "clip-remote", systemFields: Data()
        )
    }

    @Test func mergingANewItemInsertsItAsSynced() throws {
        let isLocalAhead = try store.mergeRemote(remote(copiedAt: .now, updatedAt: .now))

        #expect(isLocalAhead == false)
        #expect(try items().compactMap(\.text) == ["from another Mac"])
        #expect(try store.unsyncedItems(includeImages: true).isEmpty)
        #expect(try store.syncRow(recordName: "clip-remote") != nil)
    }

    @Test func aRecordDeletedHereStaysDeletedWhenICloudSendsItBack() throws {
        let item = try store.recordText("deleted", sourceBundleID: nil)
        guard case .clipboard(let hash) = item else {
            Issue.record("Expected a clipboard item")
            return
        }
        try store.assignRecordNames([item: "clip-remote"])
        _ = try store.delete(contentHash: hash)

        // A fetch returns the copy this Mac uploaded before the deletion was sent.
        let isLocalAhead = try store.mergeRemote(remote(hash: hash, text: "deleted", copiedAt: .now, updatedAt: .now))

        #expect(isLocalAhead == false)
        #expect(try items().isEmpty)
        #expect(try store.pendingDeletions() == ["clip-remote"])
    }

    @Test func recognizingTextOfADeletedImageChangesNothing() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 4, 5, 6])
        let item = try store.recordImage(png: png, width: 1, height: 1, sourceBundleID: nil)
        guard case .clipboard(let hash) = item else {
            Issue.record("Expected a clipboard item")
            return
        }
        try store.assignRecordNames([item: "clip-image"])
        _ = try store.delete(contentHash: hash)

        #expect(try store.setRecognizedText("too late", hash: hash) == nil)
        #expect(try store.pendingDeletions() == ["clip-image"])
    }

    @Test func mergingKeepsTheLatestCopyAndHighestCount() throws {
        let local = try store.recordText("shared", sourceBundleID: nil)
        guard case .clipboard(let hash) = local else {
            Issue.record("Expected a clipboard item")
            return
        }
        let localItem = try #require(try items().first)

        let older = localItem.copiedAt.addingTimeInterval(-60)
        let isLocalAhead = try store.mergeRemote(
            remote(hash: hash, text: "shared", copiedAt: older, timesCopied: 5, updatedAt: older))

        let merged = try #require(try items().first)
        #expect(isLocalAhead)
        #expect(merged.copiedAt == localItem.copiedAt)
        #expect(merged.timesCopied == 5)
    }

    @Test func theMostRecentlyChangedSideDecidesThePinAndSource() throws {
        let local = try store.recordText("shared", sourceBundleID: "com.example.local")
        guard case .clipboard(let hash) = local else {
            Issue.record("Expected a clipboard item")
            return
        }
        let localItem = try #require(try items().first)

        let newer = Date.now.addingTimeInterval(60)
        let isLocalAhead = try store.mergeRemote(
            remote(
                hash: hash, text: "shared", copiedAt: localItem.copiedAt, timesCopied: 1, pinnedAt: newer,
                sourceBundleID: "com.example.remote", updatedAt: newer)
        )
        #expect(!isLocalAhead)
        var merged = try #require(try items().first)
        #expect(merged.pinnedAt.map { $0.isSameMillisecond(as: newer) } == true)
        #expect(merged.sourceBundleID == "com.example.remote")

        let stale = Date.now.addingTimeInterval(-3600)
        _ = try store.mergeRemote(
            remote(
                hash: hash, text: "shared", copiedAt: localItem.copiedAt, pinnedAt: nil,
                sourceBundleID: "com.example.stale", updatedAt: stale)
        )
        merged = try #require(try items().first)
        #expect(merged.pinnedAt.map { $0.isSameMillisecond(as: newer) } == true)
        #expect(merged.sourceBundleID == "com.example.remote")
    }

    @Test func anImageWithoutAFileIsRejected() throws {
        let image = RemoteClipboardItem(
            hash: String(repeating: "b", count: 64), kind: .image, text: nil, ocrText: nil, imageFile: nil,
            imageWidth: 1, imageHeight: 1, imageBytes: 3, copiedAt: .now, sourceBundleID: nil, timesCopied: 1,
            pinnedAt: nil, updatedAt: .now, recordName: "clip-image", systemFields: Data()
        )
        #expect(throws: DatabaseError.self) { try self.store.mergeRemote(image) }
        #expect(try items().isEmpty)
        #expect(try store.nextImageAwaitingRecognition() == nil)
    }

    @Test func mergingACalculationKeepsTheNewerAnswer() throws {
        try store.recordCalculation(expression: "rate * 2", answer: "10", mode: "standard")
        let key = ClipboardStore.calculationKey(expression: "rate * 2", mode: "standard")
        func remote(answer: String, at date: Date) -> RemoteCalculation {
            RemoteCalculation(
                key: key, expression: "rate * 2", answer: answer, mode: "standard", calculatedAt: date,
                updatedAt: date, recordName: "calc-remote", systemFields: Data()
            )
        }

        #expect(try store.mergeRemote(remote(answer: "8", at: .now.addingTimeInterval(-60))))
        #expect(try store.recentCalculations(limit: 1).first?.answer == "10")

        #expect(try !store.mergeRemote(remote(answer: "12", at: .now.addingTimeInterval(60))))
        #expect(try store.recentCalculations(limit: 1).first?.answer == "12")
    }

    // MARK: - Link previews

    @Test func linksAwaitTheirPreviewNewestFirst() async throws {
        try store.recordText("https://example.com/old", sourceBundleID: nil)
        try await pause()
        try store.recordText("not a link", sourceBundleID: nil)
        try await pause()
        try store.recordText("https://example.com/new", sourceBundleID: nil)

        #expect(try store.nextLinkAwaitingPreview()?.url.absoluteString == "https://example.com/new")
        let new = try #require(try store.nextLinkAwaitingPreview())
        try store.setLinkPreview(title: "", imagePNG: nil, hash: new.hash)
        #expect(try store.nextLinkAwaitingPreview()?.url.absoluteString == "https://example.com/old")
    }

    @Test func aPreviewIsSearchableAndShowsItsTitle() throws {
        try store.recordText("https://example.com/a", sourceBundleID: nil)
        let pending = try #require(try store.nextLinkAwaitingPreview())
        try store.setLinkPreview(title: "Whippet Racing Results", imagePNG: Data([1, 2, 3]), hash: pending.hash)

        let item = try #require(try items("racing").first)
        #expect(item.title == "Whippet Racing Results")
        #expect(item.linkHost == "example.com")
        let file = try #require(store.imageURL(for: item))
        #expect(FileManager.default.fileExists(atPath: file.path))

        // The preview image's text is recognized like a copied image's, and searchable too.
        let awaiting = try #require(try store.nextImageAwaitingRecognition())
        #expect(awaiting.isLinkPreview)
        try store.setLinkPreviewRecognizedText("finish line photo", hash: awaiting.hash)
        #expect(try items("finish").map(\.id) == [item.id])
        #expect(try store.nextImageAwaitingRecognition() == nil)
    }

    @Test func previewsStayLocal() throws {
        let link = try store.recordText("https://example.com", sourceBundleID: nil)
        try store.assignRecordNames([link: "clip-link"])
        try store.markSynced(recordName: "clip-link", systemFields: Data())
        let pending = try #require(try store.nextLinkAwaitingPreview())
        try store.setLinkPreview(title: "Example", imagePNG: Data([1]), hash: pending.hash)
        try store.setLinkPreviewRecognizedText("text", hash: pending.hash)

        #expect(try store.unsyncedItems(includeImages: true).isEmpty)
    }

    @Test func previewsFetchedBeforeThePageImageFallbackAreFetchedAgain() throws {
        try store.recordText("https://example.com", sourceBundleID: nil)
        try store.recordText("not a link", sourceBundleID: nil)
        let pending = try #require(try store.nextLinkAwaitingPreview())
        try store.setLinkPreview(title: "Example", imagePNG: Data([1]), hash: pending.hash)
        #expect(try store.nextLinkAwaitingPreview() == nil)

        // As if the database were from a version before the migration.
        let database = try DatabaseQueue(path: directory.appending(path: "clipboard.sqlite").path)
        try database.write {
            try $0.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'refetchLinkPreviews'")
        }
        try database.close()
        let reopened = try ClipboardStore(directory: directory)

        #expect(try reopened.nextLinkAwaitingPreview()?.hash == pending.hash)
        // The old image is kept until it's replaced, so it's still shown, and deleted with the link.
        let link = try #require(try reopened.search("", kind: .link, limit: 10).first)
        let file = try #require(reopened.imageURL(for: link))
        #expect(FileManager.default.fileExists(atPath: file.path))
        _ = try reopened.deleteItems(copiedBefore: nil, includingPinned: true)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func aPreviewFetchedAgainGetsANewFileAndRemovesTheOldOne() throws {
        try store.recordText("https://example.com", sourceBundleID: nil)
        let pending = try #require(try store.nextLinkAwaitingPreview())
        try store.setLinkPreview(title: "Example", imagePNG: Data([1]), hash: pending.hash)
        let firstItem = try #require(try items().first)
        let first = try #require(store.imageURL(for: firstItem))

        try store.setLinkPreview(title: "Example", imagePNG: Data([2]), hash: pending.hash)
        let secondItem = try #require(try items().first)
        let second = try #require(store.imageURL(for: secondItem))
        #expect(second != first)
        #expect(!FileManager.default.fileExists(atPath: first.path))
        #expect(FileManager.default.fileExists(atPath: second.path))

        try store.setLinkPreview(title: "Example", imagePNG: nil, hash: pending.hash)
        #expect(try items().first?.linkImageFile == nil)
        #expect(!FileManager.default.fileExists(atPath: second.path))
    }

    @Test func refreshingAndDeletingRemoveThePreviewImage() throws {
        try store.recordText("https://example.com", sourceBundleID: nil)
        let pending = try #require(try store.nextLinkAwaitingPreview())
        try store.setLinkPreview(title: "Example", imagePNG: Data([1]), hash: pending.hash)
        let item = try #require(try items().first)
        let file = try #require(store.imageURL(for: item))

        try store.clearLinkPreview(hash: pending.hash)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(try store.nextLinkAwaitingPreview()?.hash == pending.hash)

        try store.setLinkPreview(title: "Example", imagePNG: Data([1]), hash: pending.hash)
        _ = try store.delete(contentHash: pending.hash)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }
}

/// Upgrading a database from before link previews.
struct LinkPreviewMigrationTests {
    @Test func existingHistoryStaysSearchable() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "WhippetTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let queue = try DatabaseQueue(path: directory.appending(path: "clipboard.sqlite").path)
        try ClipboardStore.migrator.migrate(queue, upTo: "addQuicklinks")
        try queue.write { db in
            try db.execute(
                sql: "INSERT INTO clipboard (contentHash, kind, text, copiedAt, updatedAt) VALUES (?, ?, ?, ?, ?)",
                arguments: ["hash", "link", "https://example.com/greyhound", Date.now, Date.now]
            )
        }
        try queue.close()

        let store = try ClipboardStore(directory: directory)
        #expect(try store.search("greyhound", kind: nil, limit: 10).count == 1)
        #expect(try store.nextLinkAwaitingPreview()?.hash == "hash")
    }
}

extension Date {
    /// The store keeps dates to the millisecond, so a date read back can differ from the one written by less than that.
    fileprivate func isSameMillisecond(as other: Date) -> Bool {
        abs(timeIntervalSince(other)) < 0.001
    }
}
