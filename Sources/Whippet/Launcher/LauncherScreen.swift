import AppKit
import SwiftUI

/// A view in the launcher panel, such as clipboard history or the timers. The host owns the search bar, the selection
/// and the stack of screens, and asks the top screen what to show in them and what can be done with its items.
@MainActor
protocol LauncherScreen: AnyObject {
    /// Tells screens apart, such as `timers`, for focus and for the stack.
    var id: String { get }
    var searchBar: SearchBar { get }
    /// What sits at the end of the search bar, such as clipboard history's kind menu or the answer to a calculation.
    func accessory() -> AnyView?
    /// What fills the panel between the search bar and the footer. It gets whatever height is left between them and
    /// is clipped to it, so it scrolls what doesn't fit rather than pushing the footer out.
    var content: ScreenContent { get }
    /// The bar along the bottom of the panel, which stays put whatever the content.
    var footer: ScreenFooter { get }
    /// What's read to work out its items, so they're worked out again only when it changes. Reading it registers it
    /// with Observation, so the panel updates as it does.
    var revision: AnyHashable { get }
    func items(for query: String) -> [LauncherItem]
    /// What can be done with an item it shows, first the one Return runs, then the one ⌘Return runs.
    func actions(for item: LauncherItem) -> [ItemAction]
    /// What it offers whatever is selected, or with nothing to select, such as New Timer: after the item's in ⌘K, and
    /// on Return when there's no item.
    var screenActions: [ItemAction] { get }
    /// The heading over an item, where it differs from the one before.
    func sectionTitle(at index: Int, in items: [LauncherItem]) -> String?
    /// How many items stay put above the scrolling list, such as a translation.
    func pinnedCount(in items: [LauncherItem]) -> Int
    /// A row of its own for an item in a `.list`, in place of the standard one.
    func rowView(for item: LauncherItem, index: Int, isSelected: Bool) -> AnyView?
    var keys: KeyPolicy { get }
    /// Return beeps rather than running anything, as for a calculation in the search bar that isn't finished.
    var blocksReturn: Bool { get }
    /// ↑ and ↓ in a layout of its own, such as the calculator's columns: the new selection, or nil to move in order.
    func verticalMove(from selection: Int, by offset: Int, in items: [LauncherItem]) -> Int?
    /// ← and →, such as between the calculator's columns or stopwatches. False leaves the key to the search field.
    func horizontalMove(by offset: Int) -> Bool
    /// Escape, before the host clears the search or closes the screen: true when it went back itself, as an
    /// extension does through its own pages.
    func back() -> Bool
    /// Where the selection starts, such as clipboard history's newest item rather than the pinned ones above it.
    func initialSelection(in items: [LauncherItem]) -> Int
    /// Called with the search text as it changes.
    func queryChanged(_ query: String)
    /// Called when it's closed, so it can stop what it started.
    func close()
}

extension LauncherScreen {
    func accessory() -> AnyView? { nil }
    var content: ScreenContent { .list }
    var footer: ScreenFooter { .actions() }
    var screenActions: [ItemAction] { [] }
    func sectionTitle(at index: Int, in items: [LauncherItem]) -> String? { nil }
    func pinnedCount(in items: [LauncherItem]) -> Int { 0 }
    func rowView(for item: LauncherItem, index: Int, isSelected: Bool) -> AnyView? { nil }
    var keys: KeyPolicy { KeyPolicy() }
    var blocksReturn: Bool { false }
    func verticalMove(from selection: Int, by offset: Int, in items: [LauncherItem]) -> Int? { nil }
    func horizontalMove(by offset: Int) -> Bool { false }
    func back() -> Bool { false }
    func initialSelection(in items: [LauncherItem]) -> Int { 0 }
    func queryChanged(_ query: String) {}
    func close() {}
}

/// What the search bar shows for a screen.
enum SearchBar: Equatable {
    /// A field for the search text.
    case field(placeholder: String)
    /// A title in place of the field, as for a stopwatch's name or an extension's detail, so plain keys reach the
    /// screen. Dimmed for a placeholder, such as a stopwatch not yet started.
    case title(String, isDimmed: Bool = false)

    var isField: Bool {
        if case .field = self { return true }
        return false
    }
}

/// How a screen fills the panel between the search bar and the footer.
enum ScreenContent {
    /// The host's list of its items, with sections and selection.
    case list
    /// A view of its own, which still lists `items` so selection, ⌘K and the action shortcuts work. Whatever might not
    /// fit goes in a scroll view, such as a `SelectableList`.
    case custom(AnyView)
}

/// The bar along the bottom of the panel.
enum ScreenFooter {
    /// The selected item's actions: the one Return runs, drawn with `primaryKeys`, and the ⌘K menu. `badge` names the
    /// command the screen belongs to, as in clipboard history.
    case actions(badge: CommandBadge? = nil, primaryKeys: [String] = ["return"])
    /// A footer of its own, such as the stopwatch's Lap and Reset.
    case custom(AnyView)
}

/// A command's icon and name in a footer, such as `Clipboard History`.
struct CommandBadge {
    let title: String
    let symbol: String
    let tint: Color
}

/// Which keys a screen takes.
struct KeyPolicy {
    /// Keys without modifiers run actions, as in Timers, where the bar has no field to type in: Return and Space run
    /// the first action, and each action's `plainKey` runs it.
    var plainKeys = false
    /// ↑ and ↓ are left to the screen's own fields and scrolling, as in an extension's form.
    var leavesArrows = false
    /// Return goes to the focused field rather than the selection, as in an extension's form whose fields have their
    /// own.
    var leavesReturn = false
}
