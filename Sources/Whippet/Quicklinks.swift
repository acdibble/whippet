import AppKit
import Observation
import WhippetCore

/// The user's quicklinks, shared by the launcher and Settings, and synced like clipboard history.
@MainActor
@Observable
final class Quicklinks {
    private(set) var items: [Quicklink] = []

    /// Called with every quicklink changed on this Mac.
    @ObservationIgnored var onLocalChange: (SyncItem) -> Void = { _ in }
    /// Called with the iCloud record name of every synced quicklink deleted on this Mac.
    @ObservationIgnored var onLocalDelete: (String) -> Void = { _ in }
    /// Called after the list changes, here or from another Mac, so new quicklinks' hotkeys can be registered.
    @ObservationIgnored var onListChange: () -> Void = {}

    @ObservationIgnored private let store: ClipboardStore?

    init(store: ClipboardStore?) {
        self.store = store
        addStarters()
        reload()
    }

    /// Re-reads the list, after a change here or one merged from another Mac.
    func reload() {
        items = (try? store?.quicklinks()) ?? []
        onListChange()
    }

    func save(_ quicklink: Quicklink) throws {
        guard let store else { return }
        onLocalChange(try store.saveQuicklink(quicklink))
        reload()
    }

    func delete(_ quicklink: Quicklink) {
        do {
            if let recordName = try store?.deleteQuicklink(uuid: quicklink.uuid) {
                onLocalDelete(recordName)
            }
        } catch {
            NSLog("Failed to delete quicklink: \(error)")
        }
        reload()
    }

    /// Whether another quicklink already uses the keyword, ignoring case.
    func isKeywordTaken(_ keyword: String, except uuid: String) -> Bool {
        items.contains { $0.uuid != uuid && $0.keyword?.caseInsensitiveCompare(keyword) == .orderedSame }
    }

    /// The icon of the app that opens the link.
    static func icon(for quicklink: Quicklink) -> NSImage? {
        let appURL = quicklink.appBundleID.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
            ?? QuicklinkTemplate.url(quicklink.template).flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) }
        return appURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
    }

    /// Opens the link with its argument, in the chosen app or the default one. Returns false when it isn't a valid URL.
    @discardableResult
    static func open(_ quicklink: Quicklink, argument: String = "") -> Bool {
        guard let url = QuicklinkTemplate.url(quicklink.template, argument: argument) else { return false }
        if let bundleID = quicklink.appBundleID,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
        return true
    }

    /// Starters are added once per Mac; deleting one doesn't bring it back.
    private func addStarters() {
        guard let store, !UserDefaults.standard.bool(forKey: "addedStarterQuicklinks") else { return }
        for starter in Quicklink.starters {
            _ = try? store.addQuicklinkIfMissing(starter)
        }
        UserDefaults.standard.set(true, forKey: "addedStarterQuicklinks")
    }
}
