import AppKit
import Observation
import WhippetCore

/// The launcher's host: the search text, the selection, the stack of screens with the main search at the bottom, and
/// text asked for in the search bar. Modules fill it through their contributions and screens, and it runs whatever
/// actions the top screen offers, handling their outcomes the same way for every module.
@MainActor
@Observable
final class LauncherModel: ModuleHost {
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            // The main search tells every module, even while one has taken it over.
            (screens.last ?? root).queryChanged(query)
            resetSelection()
        }
    }
    var selection = 0
    /// Screens opened over the main search, the top one last.
    private(set) var screens: [any LauncherScreen] = []
    /// Text asked for in the search bar, and what's typed into each of its fields.
    private(set) var input: InputRequest?
    var inputValues: [String] = []
    /// True after ↓ in the empty search field, which shows Suggestions, then every command and app.
    private(set) var isShowingAll = false
    /// True when the panel opened straight on this screen or field from a hotkey or the menu bar, so Escape closes
    /// Whippet instead of going back to a search that was never seen.
    private var openedDirectly = false
    /// Changes whenever the search field should take focus again, such as after a screen or a request for input.
    private(set) var focusRevision = 0

    var targetApp: NSRunningApplication?
    weak var targetWindow: NSWindow?

    @ObservationIgnored var onDismiss: () -> Void = {}
    @ObservationIgnored var onShowPanel: () -> Void = {}
    @ObservationIgnored var onShowActions: () -> Void = {}
    @ObservationIgnored var onOpenSettings: (SettingsPane?) -> Void = { _ in }
    @ObservationIgnored var onHotkeysChanged: () -> Void = {}

    let modules: ModuleSettings
    let history: LaunchHistory
    /// Every built-in module, in the order their rows are listed.
    private(set) var launcherModules: [any LauncherModule] = []
    @ObservationIgnored private lazy var root = RootScreen(host: self)

    /// The results of the top screen, with what the main search was taken over by, worked out again only when what
    /// they depend on changes.
    private struct ResultsKey: Equatable {
        let screen: ObjectIdentifier
        let query: String
        let revision: AnyHashable
        let settings: Int
        let launches: Int
        let isShowingAll: Bool
    }

    @ObservationIgnored private var cached: (key: ResultsKey, items: [LauncherItem], exclusive: (any LauncherScreen)?)?

    init(modules: ModuleSettings, history: LaunchHistory) {
        self.modules = modules
        self.history = history
    }

    /// Installs the modules, which can then reach the launcher.
    func install(_ modules: [any LauncherModule]) {
        launcherModules = modules
        for module in modules {
            module.attach(to: self)
        }
    }

    // MARK: - Screens

    /// The screen the panel shows: the top one, or the one the main search was taken over by, such as the calculator
    /// for `2+3`.
    var activeScreen: any LauncherScreen {
        guard screens.isEmpty else { return screens[screens.count - 1] }
        _ = results
        return cached?.exclusive ?? root
    }

    /// True while the main search shows another screen in its place, such as the answer to a calculation.
    var isTakenOver: Bool {
        guard screens.isEmpty else { return false }
        _ = results
        return cached?.exclusive != nil
    }

    var isRoot: Bool { screens.isEmpty }

    var results: [LauncherItem] {
        let screen: any LauncherScreen = screens.last ?? root
        let key = ResultsKey(
            screen: ObjectIdentifier(screen), query: query, revision: screen.revision, settings: modules.revision,
            launches: history.revision, isShowingAll: isShowingAll)
        if let cached, cached.key == key {
            return cached.items
        }
        let items: [LauncherItem]
        var exclusive: (any LauncherScreen)?
        if screens.isEmpty {
            (items, exclusive) = root.resolve(query)
        } else {
            items = screen.items(for: query)
        }
        cached = (key, items, exclusive)
        return items
    }

    var selectedItem: LauncherItem? {
        let results = results
        return results.indices.contains(selection) ? results[selection] : nil
    }

    func push(_ screen: any LauncherScreen) {
        input = nil
        isShowingAll = false
        openedDirectly = false
        screens.append(screen)
        query = ""
        resetSelection()
        focusRevision += 1
    }

    func pop() {
        guard let screen = screens.popLast() else { return }
        screen.close()
        input = nil
        query = ""
        resetSelection()
        focusRevision += 1
    }

    /// Back to the empty main search, as when the panel opens.
    func reset() {
        for screen in screens.reversed() {
            screen.close()
        }
        screens = []
        input = nil
        isShowingAll = false
        openedDirectly = false
        query = ""
        for module in launcherModules {
            module.panelWillShow()
        }
        selection = 0
        focusRevision += 1
    }

    func openDirectly(_ open: () -> Void) {
        onShowPanel()
        open()
        openedDirectly = true
    }

    func dismiss() {
        onDismiss()
    }

    func showActions() {
        onShowActions()
    }

    func openSettings(_ pane: SettingsPane?) {
        onOpenSettings(pane)
    }

    func module<Module: LauncherModule>(_ type: Module.Type) -> Module? {
        launcherModules.lazy.compactMap { $0 as? Module }.first
    }

    func fallbacks(for query: String, excluding module: String) -> [LauncherItem] {
        root.fallbacks(for: query, excluding: module)
    }

    func launcherModule(_ id: String) -> (any LauncherModule)? {
        launcherModules.first { $0.id == id }
    }

    /// The panel shows more than the search bar: a screen, every result, or results for what's typed.
    var isExpanded: Bool {
        guard input == nil else { return false }
        return !screens.isEmpty || isShowingAll || (!query.isEmpty && !isTakenOver)
    }

    /// The item shown under the empty search bar while the list is hidden, such as What's New, which leads the
    /// results so Return opens it.
    var banner: LauncherItem? {
        guard screens.isEmpty, query.isEmpty, input == nil, !isExpanded, let first = results.first, first.isBanner
        else { return nil }
        return first
    }

    // MARK: - Selection

    private func resetSelection() {
        selection = activeScreen.initialSelection(in: results)
    }

    func moveSelection(by offset: Int) {
        if !isExpanded, offset > 0 {
            isShowingAll = true
            selection = 0
            return
        }
        let results = results
        if let target = activeScreen.verticalMove(from: selection, by: offset, in: results) {
            selection = target
            return
        }
        guard !results.isEmpty else { return }
        selection = min(max(selection + offset, 0), results.count - 1)
    }

    func horizontalMove(by offset: Int) -> Bool {
        input == nil && activeScreen.horizontalMove(by: offset)
    }

    func keepSelection() {
        guard let previous = cached?.items, previous.indices.contains(selection) else { return }
        let selected = previous[selection]
        let key = selected.selectionKey ?? selected.id
        let current = results
        guard let index = current.firstIndex(where: { ($0.selectionKey ?? $0.id) == key }) else {
            clampSelection()
            return
        }
        selection = index
    }

    func select(_ id: String) {
        selection = results.firstIndex { $0.id == id } ?? selection
    }

    private func clampSelection() {
        selection = min(selection, max(results.count - 1, 0))
    }

    // MARK: - Sections

    func sectionTitle(at index: Int) -> String? {
        activeScreen.sectionTitle(at: index, in: results)
    }

    func pinnedCount() -> Int {
        activeScreen.pinnedCount(in: results)
    }

    // MARK: - Actions

    /// What can be done with an item: what its screen offers, then what other modules add for what it holds, then
    /// Favorites and Set Hotkey…. Those whose command or feature is off aren't offered.
    func actions(for item: LauncherItem) -> [ItemAction] {
        let screen = activeScreen
        var actions =
            screen === root ? launcherModule(item.module)?.actions(for: item) ?? [] : screen.actions(for: item)
        if let owner = launcherModule(item.module) {
            let traits = owner.traits(of: item)
            for module in launcherModules where module !== owner && modules.isEnabled(module.manifest.ref) {
                actions += module.contributedActions(for: item, traits: traits)
            }
        }
        if let key = item.favoriteKey {
            let isFavorite = history.isFavorite(key)
            actions.append(
                ItemAction(
                    id: "host.favorite",
                    title: isFavorite
                        ? String(localized: "Remove from Favorites") : String(localized: "Add to Favorites"),
                    icon: "star", shortcut: KeyShortcut("f", [.command, .shift])
                ) { [history] in
                    history.toggleFavorite(key)
                    return .keepSelection
                })
        }
        if item.hotkey != nil {
            actions.append(
                ItemAction(id: "host.set-hotkey", title: String(localized: "Set Hotkey…"), icon: "keyboard") {
                    [weak self] in
                    self?.openSettings(.shortcuts)
                    return .dismiss
                })
        }
        return actions.filter { $0.owner.map(modules.isEnabled) ?? true }
    }

    /// Every action for the selection and the screen, as ⌘K lists them.
    var menuActions: [ItemAction] {
        (selectedItem.map(actions(for:)) ?? []) + activeScreen.screenActions
    }

    /// What Return runs: what's typed is submitted, or the selected item's first action, or the screen's first when
    /// nothing is selected.
    var primaryTitle: String? {
        if let input { return input.submitTitle }
        if let item = selectedItem { return actions(for: item).first?.title }
        return activeScreen.screenActions.first?.title
    }

    /// Return: submits what's typed, or runs the selected item's first action, or the screen's first action.
    func activate() {
        if let input {
            submit(input)
            return
        }
        if activeScreen.blocksReturn {
            NSSound.beep()
            return
        }
        guard let item = selectedItem else {
            guard let action = activeScreen.screenActions.first else {
                NSSound.beep()
                return
            }
            run(action, on: nil)
            return
        }
        guard let action = actions(for: item).first else {
            NSSound.beep()
            return
        }
        run(action, on: item)
    }

    /// ⌘Return: the selected item's second action, or with nothing selected, the screen's action for ⌘Return, such as
    /// submitting an extension's form.
    func activateSecondary() {
        guard input == nil else { return }
        guard let item = selectedItem else {
            if !performShortcut(.commandReturn) { NSSound.beep() }
            return
        }
        let actions = actions(for: item)
        guard actions.count > 1 else {
            NSSound.beep()
            return
        }
        run(actions[1], on: item)
    }

    /// Runs the action with this id for the item at `index`, as a row's buttons do, selecting it first.
    func perform(_ actionID: String, at index: Int) {
        let results = results
        guard results.indices.contains(index) else { return }
        selection = index
        guard let action = actions(for: results[index]).first(where: { $0.id == actionID }) else { return }
        run(action, on: results[index])
    }

    /// Tab: the selected item's action that asks for text, such as a quicklink's. False leaves Tab to the field.
    func runTabAction() -> Bool {
        guard input == nil, let item = selectedItem, let action = actions(for: item).first(where: \.runsOnTab)
        else { return false }
        run(action, on: item)
        return true
    }

    /// The action for the selection or the screen with this shortcut. False when there's none.
    func performShortcut(_ shortcut: KeyShortcut) -> Bool {
        guard let action = menuActions.first(where: { $0.shortcut == shortcut }) else { return false }
        run(action, on: selectedItem)
        return true
    }

    /// A key without modifiers on a screen that takes them, such as `+` in Timers. False when no action has it.
    func performPlainKey(_ key: Character) -> Bool {
        guard let action = menuActions.first(where: { $0.plainKeys?.contains(key) == true }) else { return false }
        run(action, on: selectedItem)
        return true
    }

    var usesPlainKeys: Bool {
        input == nil && activeScreen.keys.plainKeys
    }

    func run(_ action: ItemAction, on item: LauncherItem?) {
        let outcome = action.perform()
        if action.recordsLaunch, let key = item?.launchKey {
            if case .input = outcome {
            } else {
                history.record(key)
            }
        }
        handle(outcome, for: item)
    }

    private func handle(_ outcome: ActionOutcome, for item: LauncherItem?) {
        switch outcome {
        case .dismiss:
            onDismiss()
        case .stay:
            break
        case .keepSelection:
            if let item { select(item.id) }
        case .removed:
            clampSelection()
        case .push(let screen):
            push(screen)
        case .input(let request):
            beginInput(request)
        case .fail(let message):
            NSSound.beep()
            if let message {
                Toast.shared.show(message, symbol: "exclamationmark.triangle")
            }
        }
    }

    // MARK: - Input

    func beginInput(_ request: InputRequest) {
        input = request
        inputValues = request.fields.map(\.text)
        focusRevision += 1
    }

    private func submit(_ request: InputRequest) {
        let outcome = request.submit(inputValues)
        switch outcome {
        case .input(let next):
            if let key = request.launchKey { history.record(key) }
            beginInput(next)
        case .fail:
            handle(outcome, for: nil)
        default:
            if let key = request.launchKey { history.record(key) }
            input = nil
            focusRevision += 1
            handle(outcome, for: nil)
        }
    }

    // MARK: - Escape

    /// Escape clears what's typed first, then goes back to where you came from, closing Whippet when that was outside.
    func back() {
        if let input {
            if input.escapeClears, inputValues.contains(where: { !$0.isEmpty }) {
                inputValues = inputValues.map { _ in "" }
                return
            }
            // Only a field opened over the main search closes Whippet; one opened from a screen returns to it.
            if openedDirectly, screens.isEmpty {
                onDismiss()
                return
            }
            self.input = nil
            focusRevision += 1
            return
        }
        if !query.isEmpty {
            query = ""
            return
        }
        if activeScreen.back() {
            return
        }
        if !screens.isEmpty {
            leave()
            return
        }
        if isShowingAll {
            isShowingAll = false
            selection = 0
            return
        }
        onDismiss()
    }

    func leave() {
        if openedDirectly, screens.count <= 1 {
            onDismiss()
        } else {
            pop()
        }
    }

    // MARK: - Pasting

    func dismissAndPaste(copyOnly: Bool, for ref: ModuleRef) -> ActionOutcome {
        onDismiss()
        if !copyOnly, let targetWindow {
            // One of Whippet's own windows, which needs no permission.
            Paster.paste(into: targetWindow)
            return .stay
        }
        if !copyOnly, let targetApp, PermissionGate.shared.paste(into: targetApp, for: ref) {
            return .stay
        }
        Toast.shared.show(String(localized: "Copied to Clipboard"), symbol: "doc.on.doc")
        return .stay
    }

    /// “Paste to Safari” when there's an app to paste into, otherwise “Copy to Clipboard”.
    var pasteTitle: String {
        targetApp?.localizedName.map { String(localized: "Paste to \($0)") } ?? String(localized: "Copy to Clipboard")
    }

    func hotkeysChanged() {
        onHotkeysChanged()
    }

    func recordLaunch(_ key: String) {
        history.record(key)
    }

    func frecency(of item: LauncherItem) -> Double {
        item.launchKey.map { history.frecency(of: $0) } ?? 0
    }

    func isListed(_ item: LauncherItem) -> Bool {
        item.refs.allSatisfy(modules.isEnabled)
    }
}
