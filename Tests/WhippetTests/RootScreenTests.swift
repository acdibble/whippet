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
    var launcherModules: [any LauncherModule] = []
    private(set) var pushed: [any LauncherScreen] = []
    private(set) var inputs: [InputRequest] = []
    private(set) var dismissals = 0

    init(defaults: UserDefaults) {
        modules = ModuleSettings(defaults: defaults)
        history = LaunchHistory(defaults: defaults)
    }

    func dismiss() { dismissals += 1 }
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
    func module<Module: LauncherModule>(_ type: Module.Type) -> Module? {
        launcherModules.lazy.compactMap { $0 as? Module }.first
    }
    func run(_ action: ItemAction, on item: LauncherItem?) { _ = action.perform() }
    func hotkeysChanged() {}
}

/// A module whose contributions a test sets.
@MainActor
final class FakeModule: LauncherModule {
    let manifest: ModuleManifest
    var contribute: (String) -> [Contribution]

    init(_ manifest: ModuleManifest, contribute: @escaping (String) -> [Contribution]) {
        self.manifest = manifest
        self.contribute = contribute
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
        return RootScreen(host: host)
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
