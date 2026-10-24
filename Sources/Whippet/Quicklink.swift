import AppKit
import GRDB
import Observation

/// A saved link, opened from the launcher. `{query}` in its template is replaced with what's typed after pressing Tab.
struct Quicklink: Identifiable, Hashable, Codable, FetchableRecord, TableRecord {
    static let databaseTableName = "quicklink"

    let uuid: String
    var name: String
    /// An extra search term, such as `gh` for Search GitHub.
    var keyword: String?
    var template: String
    /// The app that opens the link, or nil for the default app for the URL.
    var appBundleID: String?

    var id: String { uuid }

    var takesArgument: Bool {
        QuicklinkTemplate.takesArgument(template)
    }

    /// What search matches against: the name, then the keyword.
    var searchText: String {
        [name, keyword].compactMap { $0 }.joined(separator: " ")
    }

    /// Starters are created once, with fixed UUIDs so two Macs creating them make the same records rather than
    /// duplicates.
    static let starters = [
        Quicklink(uuid: "starter-google", name: "Search Google", keyword: "g", template: "https://www.google.com/search?q={query}"),
        Quicklink(uuid: "starter-github", name: "Search GitHub", keyword: "gh", template: "https://github.com/search?q={query}"),
        Quicklink(
            uuid: "starter-wikipedia",
            name: "Search Wikipedia",
            keyword: "wiki",
            template: "https://en.wikipedia.org/w/index.php?search={query}"
        ),
        Quicklink(uuid: "starter-maps", name: "Search Maps", keyword: "maps", template: "maps://?q={query}"),
    ]
}

enum QuicklinkTemplate {
    static let queryPlaceholder = "{query}"
    static let rawQueryPlaceholder = "{query:raw}"

    static func takesArgument(_ template: String) -> Bool {
        template.contains(queryPlaceholder) || template.contains(rawQueryPlaceholder)
    }

    /// The link with the argument filled in: percent-encoded for `{query}`, as typed for `{query:raw}`. Nil when the
    /// result isn't a URL with a scheme.
    static func url(_ template: String, argument: String = "") -> URL? {
        let encoded = argument.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
        let filled = template
            .replacingOccurrences(of: rawQueryPlaceholder, with: argument)
            .replacingOccurrences(of: queryPlaceholder, with: encoded)
        guard let url = URL(string: filled), let scheme = url.scheme, !scheme.isEmpty else { return nil }
        return url
    }

    /// Whether a template makes a valid link, checked with a sample argument.
    static func isValid(_ template: String) -> Bool {
        url(template, argument: "whippet test") != nil
    }

    /// RFC 3986's unreserved characters, so anything with meaning in a URL, such as `&`, `#` or a space, is encoded.
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )
}

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
