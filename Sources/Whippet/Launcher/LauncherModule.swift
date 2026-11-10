import AppKit
import KeyboardShortcuts
import SwiftUI
import WhippetCore

/// A built-in module: what it adds to the main search, its screens, what it runs on its own and its settings. Adding or
/// removing one is a folder in `Modules/`, its manifest in `ModuleRegistry.all` and a line in
/// `AppDelegate.makeModules()`.
@MainActor
protocol LauncherModule: AnyObject {
    var manifest: ModuleManifest { get }
    /// Called once at launch, with the host it reaches the launcher through.
    func attach(to host: any ModuleHost)
    /// Called at launch and after any switch in Settings › Commands changes, to start or stop what runs on its own
    /// according to what's on, such as a status item or a background fetch.
    func update(_ modules: ModuleSettings)
    /// What's running that keeps parts of it on, such as a timer counting down.
    var activity: [ActivityLock] { get }
    /// Called as the panel opens, such as to notice What's New running out while Whippet stays open.
    func panelWillShow()
    /// Called as the main search's text changes, for work that follows it, such as translating it.
    func searchTextChanged(_ query: String)

    /// What the main search's items depend on, read like `LauncherScreen.revision`.
    var revision: AnyHashable { get }
    /// How one of its manifest's commands is listed in the main search. The host makes `item` from the manifest, and
    /// the module returns it with what differs, such as a subtitle saying what's running, or nil to leave the command
    /// out for now, as Decaffeinate is while nothing keeps the Mac awake. A command that's left out can't be run.
    func row(for command: ModuleRef, _ item: LauncherItem) -> LauncherItem?
    /// Its other rows in the main search for `query`, which is empty for the empty search: those that come and go,
    /// such as each app or a typed timer. Its commands are listed for it, before these.
    func contributions(for query: String) -> [Contribution]
    /// What can be done with its items in screens it doesn't own, such as the main search.
    func actions(for item: LauncherItem) -> [ItemAction]
    /// A row of its own for one of its items in those screens.
    func rowView(for item: LauncherItem, isSelected: Bool) -> AnyView?
    /// What one of its items holds, for other modules' actions.
    func traits(of item: LauncherItem) -> ItemTraits
    /// Actions it offers on other modules' items, from what they hold.
    func contributedActions(for item: LauncherItem, traits: ItemTraits) -> [ItemAction]

    /// Runs one of its commands from its hotkey where that differs from choosing it in the search, such as
    /// Caffeinate's also stopping it: true when it did. False, the default, has the host run the first action of the
    /// command's row, opening the panel on whatever screen or input it asks for.
    func runHotkey(for command: ModuleRef) -> Bool
    /// Hotkeys for rows that come and go, such as each app's, with whether each is on. It registers their handlers
    /// itself, and calls `ModuleHost.hotkeysChanged()` when the list changes.
    func hotkeys(_ modules: ModuleSettings) -> [(name: KeyboardShortcuts.Name, isOn: Bool)]
    /// Its pane in Settings, listed while it's on.
    var settingsPane: ModuleSettingsPane? { get }
}

extension LauncherModule {
    func attach(to host: any ModuleHost) {}
    func update(_ modules: ModuleSettings) {}
    var activity: [ActivityLock] { [] }
    func panelWillShow() {}
    func searchTextChanged(_ query: String) {}
    var revision: AnyHashable { 0 }
    func row(for command: ModuleRef, _ item: LauncherItem) -> LauncherItem? { item }
    func contributions(for query: String) -> [Contribution] { [] }
    func actions(for item: LauncherItem) -> [ItemAction] { [] }
    func rowView(for item: LauncherItem, isSelected: Bool) -> AnyView? { nil }
    func traits(of item: LauncherItem) -> ItemTraits { ItemTraits() }
    func contributedActions(for item: LauncherItem, traits: ItemTraits) -> [ItemAction] { [] }
    func runHotkey(for command: ModuleRef) -> Bool { false }
    func hotkeys(_ modules: ModuleSettings) -> [(name: KeyboardShortcuts.Name, isOn: Bool)] { [] }
    var settingsPane: ModuleSettingsPane? { nil }

    var id: String { manifest.id }
}

/// Where a row goes in the main search.
enum Contribution {
    /// Ranked by the search, and in the empty search under Favorites, Suggestions or its section.
    case listed(LauncherItem)
    /// At the top of the empty search under its own heading, ordered by `rank`, such as What's New and the running
    /// timers, and ranked with the rest while searching.
    case top(LauncherItem, section: String, rank: Int)
    /// Above the ranked results while searching, such as a typed timer.
    case leading(LauncherItem)
    /// Under “Use … with” at the end, for the search text even when nothing matches it. Tier 0 is ordered by use;
    /// higher tiers follow in order.
    case fallback(LauncherItem, tier: Int = 0)
    /// Fixed above the scrolling list with the fallbacks under it, such as a translation of what's typed.
    case pinned(LauncherItem)
    /// Takes over the search, as the calculator does for `2+3`: the main search shows this screen in its place.
    case exclusive(any LauncherScreen)
}

/// A module's pane in Settings, listed while the module is on.
struct ModuleSettingsPane {
    let title: String
    let symbol: String
    let tint: Color
    /// What has to be on for it to be listed, when that's one of the module's commands or features, such as Read
    /// Feedback.
    var ref: ModuleRef?
    /// Listed with Whippet's own admin panes, with an Admin badge.
    var isAdminOnly = false
    /// Whether it's listed, beyond the module being on, such as only once Extensions is turned on.
    var isShown: () -> Bool = { true }
    let view: () -> AnyView
}

/// What modules reach the launcher through.
@MainActor
protocol ModuleHost: AnyObject {
    var query: String { get set }
    var selection: Int { get set }
    /// The top screen's items.
    var results: [LauncherItem] { get }
    var selectedItem: LauncherItem? { get }
    /// The app the panel opened over, which receives pastes.
    var targetApp: NSRunningApplication? { get }
    /// One of Whippet's own windows when the panel opened over it.
    var targetWindow: NSWindow? { get }
    /// The screen the panel shows, for a module to tell whether it's one of its own.
    var activeScreen: any LauncherScreen { get }
    /// Whether the panel shows more than the search bar, which is all it shows for an answer typed into it.
    var isExpanded: Bool { get }
    var modules: ModuleSettings { get }
    var history: LaunchHistory { get }

    func dismiss()
    func push(_ screen: any LauncherScreen)
    /// Goes back to the screen under the top one.
    func pop()
    /// Leaves the top screen as Escape does once there's nothing left to clear in it: back to the screen under it, or
    /// closing Whippet when the panel opened straight on it.
    func leave()
    func beginInput(_ request: InputRequest)
    /// Shows the panel on `open`'s screen or input, as from a hotkey: Escape then closes Whippet rather than going
    /// back to a search that was never seen.
    func openDirectly(_ open: () -> Void)
    func showActions()
    func openSettings(_ pane: SettingsPane?)
    /// Closes the panel and pastes what was just copied, for `ref`, unless `copyOnly`.
    func dismissAndPaste(copyOnly: Bool, for ref: ModuleRef) -> ActionOutcome
    func recordLaunch(_ key: String)
    /// Selects the same item again after the items change under it, such as a timer that finishes.
    func keepSelection()
    func select(_ id: String)
    /// What `query` can be used with, from every module but `excluded`, for a screen that lists them under what it
    /// shows, as Translate does.
    func fallbacks(for query: String, excluding excluded: String) -> [LauncherItem]
    /// What an item's own module offers for it, for a screen showing another module's items, such as those fallbacks.
    func ownActions(for item: LauncherItem) -> [ItemAction]
    /// Runs a command as its hotkey does, such as from a menu bar item's menu, if it's on.
    func runCommand(_ ref: ModuleRef)
    /// Runs an action as the host would, handling its outcome.
    func run(_ action: ItemAction, on item: LauncherItem?)
    /// Turns modules' hotkeys on and off again, after one's list of them changed.
    func hotkeysChanged()
}
