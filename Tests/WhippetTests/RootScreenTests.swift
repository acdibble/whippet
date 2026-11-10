import AppKit
import Foundation
import Testing
import WhippetCore

/// A host for testing modules and the main search without the launcher panel: it records what it's asked to do.
@MainActor
final class FakeHost: ModuleHost {
    var query = ""
    var selection = 0
    var results: [LauncherItem] = []
    var selectedItem: LauncherItem? { results.indices.contains(selection) ? results[selection] : nil }
    var targetApp: NSRunningApplication?
    var targetWindow: NSWindow?
    let modules: ModuleSettings
    let history: LaunchHistory
    /// The modules the main search is made of, which a test installs.
    var launcherModules: [any LauncherModule] = []
    private(set) lazy var root = RootScreen(host: self) { [unowned self] in launcherModules }
    var activeScreen: any LauncherScreen { pushed.last ?? root }
    var isExpanded = true
    private(set) var pushed: [any LauncherScreen] = []
    private(set) var inputs: [InputRequest] = []
    private(set) var dismissals = 0

    init(defaults: UserDefaults) {
        modules = ModuleSettings(defaults: defaults)
        history = LaunchHistory(defaults: defaults)
    }

    var isPanelVisible = true
    var panelWindowNumber: Int?
    func dismiss() { dismissals += 1 }
    func closePanelForWindow() { dismissals += 1 }
    func restoreTarget(_ app: NSRunningApplication?) {
        targetApp = app
        targetWindow = nil
    }
    func push(_ screen: any LauncherScreen) { pushed.append(screen) }
    func pop() { _ = pushed.popLast() }
    func leave() { pop() }
    func beginInput(_ request: InputRequest) { inputs.append(request) }
    func openDirectly(_ open: () -> Void) { open() }
    func showActions() {}
    func openSettings(_ pane: SettingsPane?) {}
    func dismissAndPaste(copyOnly: Bool, for ref: ModuleRef) -> ActionOutcome {
        dismiss()
        return .stay
    }
    func recordLaunch(_ key: String) { history.record(key) }
    func keepSelection() {}
    func select(_ id: String) {}
    func fallbacks(for query: String, excluding excluded: String) -> [LauncherItem] {
        root.fallbacks(for: query, excluding: excluded)
    }
    func ownActions(for item: LauncherItem) -> [ItemAction] { root.ownActions(for: item) }
    private(set) var commandsRun: [ModuleRef] = []
    func runCommand(_ ref: ModuleRef) { commandsRun.append(ref) }
    func run(_ action: ItemAction, on item: LauncherItem?) { _ = action.perform() }
    func hotkeysChanged() {}
}

/// A module whose contributions a test sets. Its manifest's commands are left out of the search unless a test says
/// how they're listed, so a test sees only the rows it gives.
@MainActor
final class FakeModule: LauncherModule {
    let manifest: ModuleManifest
    var contribute: (String) -> [Contribution]
    var listCommand: (ModuleRef, LauncherItem) -> LauncherItem? = { _, _ in nil }

    init(_ manifest: ModuleManifest, contribute: @escaping (String) -> [Contribution] = { _ in [] }) {
        self.manifest = manifest
        self.contribute = contribute
    }

    func row(for command: ModuleRef, _ item: LauncherItem) -> LauncherItem? {
        listCommand(command, item)
    }

    func contributions(for query: String) -> [Contribution] {
        contribute(query)
    }
}

@MainActor
final class RootScreenTests {
    let suiteName = "WhippetRootScreen-\(UUID().uuidString)"
    let defaults: UserDefaults
    let host: FakeHost

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
        host = FakeHost(defaults: defaults)
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    private func item(
        _ id: String, _ title: String, module: ModuleManifest = .calculator, section: String = "Commands",
        refs: [ModuleRef] = []
    ) -> LauncherItem {
        LauncherItem(
            id: id, module: module.id, title: title, section: section, launchKey: id, favoriteKey: id, refs: refs)
    }

    private func install(_ modules: FakeModule...) -> RootScreen {
        host.launcherModules = modules
        return host.root
    }

    @Test func emptySearchLeadsWithTopsThenFavoritesSuggestionsAndSections() {
        let root = install(
            FakeModule(.calculator) { [self] _ in
                [
                    .listed(item("a", "Alpha")), .listed(item("b", "Bravo")),
                    .listed(item("app", "Safari", section: "Applications")), .listed(item("c", "Charlie")),
                ]
            },
            FakeModule(.timers) { [self] _ in [.top(item("t", "Tea", module: .timers), section: "Timers", rank: 1)] },
            FakeModule(.whippet) { [self] _ in
                [.top(item("w", "What's New", module: .whippet), section: "Whippet Updated", rank: 0)]
            })
        host.history.toggleFavorite("c")
        host.history.record("b")

        let (items, exclusive) = root.resolve("")

        #expect(exclusive == nil)
        #expect(items.map(\.id) == ["w", "t", "c", "b", "a", "app"])
        #expect(
            items.indices.map { root.sectionTitle(at: $0, in: items) } == [
                "Whippet Updated", "Timers", "Favorites", "Suggestions", "Commands", "Applications",
            ])
    }

    @Test func searchingRanksThenOffersFallbacks() {
        let root = install(
            FakeModule(.calculator) { [self] query in
                [
                    .listed(item("timers", "Timers")), .listed(item("tea", "Tea Timer")),
                    .leading(item("typed", "Start Timer for 25 min")),
                    .fallback(item("clip", "Search Clipboard History"), tier: 2),
                    .fallback(item("google", "Search Google")), .fallback(item("maps", "Search Maps")),
                ]
            })
        host.history.record("maps")

        let items = root.resolve("timer").items

        #expect(items.map(\.id) == ["typed", "timers", "tea", "maps", "google", "clip"])
        #expect(root.sectionTitle(at: 0, in: items) == "Results")
        #expect(root.sectionTitle(at: 3, in: items) == "Use “timer” with…")
        #expect(root.pinnedCount(in: items) == 0)
    }

    @Test func somethingPinnedKeepsTheFallbacksUnderIt() {
        let root = install(
            FakeModule(.translation) { [self] _ in
                [
                    .pinned(item("card", "Translation", section: "Translate")),
                    .fallback(item("google", "Search Google")), .listed(item("hello", "Hello")),
                ]
            })

        let items = root.resolve("hello in french").items

        #expect(items.map(\.id) == ["card", "google"])
        #expect(root.pinnedCount(in: items) == 1)
        #expect(root.sectionTitle(at: 0, in: items) == "Translate")
    }

    @Test func aModuleCanTakeTheSearchOver() {
        let screen = StubScreen(items: [item("calculation", "4")])
        let root = install(
            FakeModule(.calculator) { query in query == "2+2" ? [.exclusive(screen)] : [] },
            FakeModule(.clipboard) { [self] _ in [.listed(item("clip", "Clipboard History"))] })

        let (items, exclusive) = root.resolve("2+2")

        #expect(exclusive === screen)
        #expect(items.map(\.id) == ["calculation"])
        #expect(root.resolve("clip").items.map(\.id) == ["clip"])
    }

    /// Every command in a module's manifest gets a row made from it, before the module's other rows, under the id
    /// its launches were kept under before modules.
    @Test func commandsAreListedFromTheManifest() {
        let caffeinate = FakeModule(.caffeinate) { [self] _ in [.listed(item("extra", "Extra", module: .caffeinate))] }
        caffeinate.listCommand = { command, item in
            guard command != .decaffeinate else { return nil }
            var item = item
            if command == .caffeinate { item.subtitle = "Keep this Mac awake" }
            return item
        }
        let system = FakeModule(.system)
        system.listCommand = { _, item in item }
        let root = install(caffeinate, system)

        let items = root.resolve("").items
        #expect(
            items.map(\.id) == [
                "command:caffeinate", "command:caffeinate-for", "command:caffeinate-menu-bar", "extra",
            ] + SystemCommand.allCases.map { "command:system.\($0.rawValue)" })
        let first = items[0]
        #expect(first.title == "Caffeinate")
        #expect(first.subtitle == "Keep this Mac awake")
        #expect(first.command == .caffeinate)
        #expect(first.refs == [.caffeinate])
        #expect(first.launchKey == "command:caffeinate")
        #expect(first.hotkey?.rawValue == "command.caffeinate")

        // A command that's off, or that its module leaves out, has no row to run.
        #expect(root.commandItem(.caffeinateFor)?.id == "command:caffeinate-for")
        #expect(root.commandItem(.decaffeinate) == nil)
        host.modules.setOn(.caffeinateFor, false)
        #expect(root.commandItem(.caffeinateFor) == nil)
        #expect(!root.resolve("").items.contains { $0.command == .caffeinateFor })
    }

    /// A screen can list what its text can be used with through the host, leaving its own module out.
    @Test func aScreenCanListFallbacksFromOtherModules() {
        _ = install(
            FakeModule(.translation) { [self] _ in [.fallback(item("translate", "Translate", module: .translation))] },
            FakeModule(.quicklinks) { [self] _ in
                [.fallback(item("google", "Google", module: .quicklinks)), .listed(item("new", "Create Quicklink"))]
            })

        #expect(host.fallbacks(for: "hello", excluding: "translation").map(\.id) == ["google"])
        #expect(host.fallbacks(for: "hello", excluding: "quicklinks").map(\.id) == ["translate"])
    }

    /// What's turned off in Settings › Commands isn't listed, and a module that's off isn't asked at all.
    @Test func whatsOffIsLeftOut() {
        var asked = false
        let root = install(
            FakeModule(.calculator) { [self] _ in
                [.listed(item("on", "On")), .listed(item("off", "Off", refs: [.floatingCalculator]))]
            },
            FakeModule(.clipboard) { [self] _ in
                asked = true
                return [.listed(item("clip", "Clipboard History"))]
            })
        host.modules.setOn(.floatingCalculator, false)
        host.modules.setOn(.clipboardModule, false)

        #expect(root.resolve("").items.map(\.id) == ["on"])
        #expect(!asked)
    }
}

/// A screen that lists what it's given.
@MainActor
final class StubScreen: LauncherScreen {
    let items: [LauncherItem]

    init(items: [LauncherItem]) {
        self.items = items
    }

    let id = "stub"
    var searchBar: SearchBar { .field(placeholder: "") }
    var revision: AnyHashable { 0 }
    func items(for query: String) -> [LauncherItem] { items }
    func actions(for item: LauncherItem) -> [ItemAction] { [] }
}
