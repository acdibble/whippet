import AppKit
import KeyboardShortcuts
import Observation
import SwiftUI
import WhippetCore

/// Extensions' commands: in the main search, with their own hotkeys, as fallbacks for the search text, and their
/// views in the panel.
@MainActor
final class ExtensionsModule: LauncherModule {
    let manifest = ModuleManifest.extensions
    let extensions: ExtensionManager
    private weak var host: (any ModuleHost)?
    private var registeredHotkeys: Set<String> = []
    /// The view command that's open, which keeps its extension on.
    private weak var openScreen: ExtensionScreen?

    init(extensions: ExtensionManager) {
        self.extensions = extensions
    }

    func attach(to host: any ModuleHost) {
        self.host = host
        extensions.onEvent = { [weak self] _, event in self?.openScreen?.handle(event) }
        extensions.host = { [weak self] request in self?.handle(request) ?? .null }
        extensions.onReload = { [weak self] ids in self?.reloaded(ids) }
        extensions.onCommandsChange = { [weak self] in self?.registerHotkeys() }
    }

    func update(_ modules: ModuleSettings) {
        extensions.setActive(modules.isEnabled(manifest.ref))
    }

    var activity: [ActivityLock] {
        guard let info = openScreen?.session.command else { return [] }
        return [
            ActivityLock(
                module: info.moduleRef.module, rows: [info.command.name], reason: String(localized: "Open in Whippet"))
        ]
    }

    var revision: AnyHashable { extensions.commands }

    func contributions(for query: String) -> [Contribution] {
        var contributions = extensions.commands.map { Contribution.listed(item(for: $0)) }
        if !query.isEmpty {
            for info in extensions.commands where info.command.fallback {
                var item = item(for: info)
                item = LauncherItem(
                    id: "with:extension:\(info.key)", module: manifest.id, title: info.title,
                    subtitle: item.subtitle, icon: item.icon, launchKey: item.id, refs: [info.moduleRef],
                    payload: Fallback(info: info))
                contributions.append(.fallback(item))
            }
        }
        return contributions
    }

    /// A command marked `fallback`, offered for the whole search text and run with it straight away.
    private struct Fallback: Hashable {
        let info: ExtensionCommandInfo
    }

    private func item(for info: ExtensionCommandInfo) -> LauncherItem {
        let id = "extension:\(info.key)"
        return LauncherItem(
            id: id, module: manifest.id, title: info.title, subtitle: info.command.subtitle ?? info.extensionName,
            icon: .extension(info.icon, info.directory), section: String(localized: "Extensions"),
            searchText: "\(info.title) \(info.extensionName)", launchKey: id, favoriteKey: id, refs: [info.moduleRef],
            hotkey: info.shortcutName, payload: info)
    }

    func actions(for item: LauncherItem) -> [ItemAction] {
        if let fallback = item.payload(as: Fallback.self) {
            let info = fallback.info
            return [
                ItemAction(
                    id: "extension.run",
                    title: info.command.mode == .noView
                        ? String(localized: "Run Command") : String(localized: "Open Command"),
                    icon: "return", recordsLaunch: true
                ) { [weak self] in
                    guard let self, let host else { return .stay }
                    let text = host.query.trimmingCharacters(in: .whitespaces)
                    return launch(
                        info, arguments: info.command.argument.map { [$0.name: text] } ?? [:], fallbackText: text)
                }
            ]
        }
        guard let info = item.payload(as: ExtensionCommandInfo.self) else { return [] }
        if info.command.argument != nil {
            return [
                ItemAction(
                    id: "extension.enter-text", title: String(localized: "Enter Text"), icon: "return",
                    runsOnTab: true
                ) { [weak self] in
                    self.map { .input($0.request(for: info)) } ?? .stay
                }
            ]
        }
        return [
            ItemAction(
                id: "extension.run",
                title: info.command.mode == .noView
                    ? String(localized: "Run Command") : String(localized: "Open Command"),
                icon: "return", recordsLaunch: true
            ) { [weak self] in
                self?.launch(info) ?? .stay
            }
        ]
    }

    /// The argument a command asks for, typed in the search bar.
    private func request(for info: ExtensionCommandInfo) -> InputRequest {
        InputRequest(
            label: info.title,
            placeholder: info.command.argument?.placeholder ?? String(localized: "Type and press Return"),
            submitTitle: info.command.mode == .noView
                ? String(localized: "Run Command") : String(localized: "Open Command"),
            launchKey: "extension:\(info.key)"
        ) { [weak self] text in
            self?.launch(info, arguments: info.command.argument.map { [$0.name: text] } ?? [:]) ?? .stay
        }
    }

    /// Opens a view command in the panel, or runs a command without a view after closing it. A command whose required
    /// preferences are empty opens Settings instead, since it would only fail. `fallbackText` is the search text it
    /// was chosen for under “Use … with”, which a command without an argument also starts with in its search bar.
    func launch(_ info: ExtensionCommandInfo, arguments: [String: String] = [:], fallbackText: String? = nil)
        -> ActionOutcome
    {
        guard let installed = extensions.installed(id: info.extensionID) else { return .fail() }
        let missing = extensions.missingPreferences(for: installed)
        if !missing.isEmpty {
            let names = missing.map(\.title).formatted(.list(type: .and))
            Toast.shared.show(String(localized: "Set \(names) for \(installed.manifest.name)"), symbol: "gearshape")
            host?.openSettings(.extensions)
            return .stay
        }
        guard let runtime = extensions.runtime(for: info.extensionID) else { return .fail() }
        switch info.command.mode {
        case .view:
            let session = ExtensionSession(command: info, runtime: runtime)
            let screen = ExtensionScreen(session: session, module: self)
            openScreen = screen
            host?.push(screen)
            session.launch(arguments: arguments, fallbackText: fallbackText)
            if let fallbackText, info.command.argument == nil {
                host?.query = fallbackText
            }
            return .stay
        case .noView:
            runtime.launch(
                session: UUID().uuidString, command: info.command.name, mode: .noView, arguments: arguments,
                fallbackText: fallbackText)
            return .dismiss
        }
    }

    /// Starts the open command again when its extension was rebuilt, so changes show as they're saved.
    private func reloaded(_ ids: Set<String>) {
        guard let screen = openScreen, let host, ids.contains(screen.session.command.extensionID) else { return }
        guard let info = extensions.commands.first(where: { $0.key == screen.session.command.key }) else {
            host.leave()
            return
        }
        host.pop()
        _ = launch(info, arguments: screen.session.arguments, fallbackText: screen.session.fallbackText)
    }

    /// Does what an extension asked of Whippet.
    private func handle(_ request: ExtensionRuntime.HostRequest) -> JSONValue {
        switch request {
        case .toast(let title, let message, let isFailure):
            let text = [title, message].compactMap { $0 }.joined(separator: " · ")
            Toast.shared.show(text, symbol: isFailure ? "xmark.circle" : "checkmark.circle")
        case .closeMainWindow:
            host?.dismiss()
        case .popToRoot:
            openScreen?.session.popToRoot()
        case .open(let url):
            NSWorkspace.shared.open(url)
        case .copy(let text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        case .paste(let text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            _ = host?.dismissAndPaste(
                copyOnly: false,
                for: openScreen?.session.command.moduleRef.moduleRef ?? .extension("unknown"))
        case .readClipboard:
            return NSPasteboard.general.string(forType: .string).map(JSONValue.string) ?? .null
        }
        return .null
    }

    /// Installing extensions, their preferences, approval and logs.
    var settingsPane: ModuleSettingsPane? {
        ModuleSettingsPane(
            title: String(localized: "Extensions"), symbol: "puzzlepiece.extension.fill", tint: .pink,
            view: { [extensions] in AnyView(ExtensionsPane(extensions: extensions)) })
    }

    var dynamicRows: [DynamicRow] {
        extensions.commands.map { info in
            DynamicRow(
                ref: info.moduleRef, title: info.title, icon: .extension(info.icon, info.directory),
                hotkey: info.shortcutName, searchText: info.extensionName)
        }
    }

    /// Registers a handler once per command, which looks it up when pressed, so it follows the command through its
    /// extension reloading. A command without a view or argument runs without the panel, into the app in front;
    /// others open the panel on the command, or on its argument.
    private func registerHotkeys() {
        defer { host?.hotkeysChanged() }
        for info in extensions.commands where !registeredHotkeys.contains(info.key) {
            registeredHotkeys.insert(info.key)
            let key = info.key
            KeyboardShortcuts.onKeyDown(for: info.shortcutName) { [weak self] in
                guard let self, let host, let info = extensions.commands.first(where: { $0.key == key }),
                    host.modules.isEnabled(info.moduleRef)
                else { return }
                host.recordLaunch("extension:\(info.key)")
                if info.command.mode == .noView, info.command.argument == nil {
                    _ = launch(info)
                    return
                }
                host.openDirectly {
                    if info.command.argument != nil {
                        host.beginInput(request(for: info))
                    } else {
                        _ = launch(info)
                    }
                }
            }
        }
    }
}

/// An open view command: its list, detail or form. A list searches with the bar, filtered by Whippet unless the
/// extension searches for itself; a detail or form shows its title there instead.
@MainActor
final class ExtensionScreen: LauncherScreen {
    let session: ExtensionSession
    private unowned let module: ExtensionsModule
    /// The item to select once it appears, after going back to a list that searches again for its restored text.
    private var pendingSelection: String?

    init(session: ExtensionSession, module: ExtensionsModule) {
        self.session = session
        self.module = module
    }

    var id: String { "extension.\(session.id)" }

    private var host: (any ModuleHost)? {
        module.hostForScreens
    }

    var searchBar: SearchBar {
        switch session.view {
        case .detail, .form:
            .title(session.view.navigationTitle ?? session.command.title)
        default:
            .field(
                placeholder: session.list?.searchBarPlaceholder
                    ?? String(localized: "Search \(session.list?.navigationTitle ?? session.command.title)…"))
        }
    }

    func accessory() -> AnyView? {
        guard session.view.isLoading else { return nil }
        return AnyView(ProgressView().controlSize(.small))
    }

    var revision: AnyHashable { session.revision }

    var content: ScreenContent {
        .custom(AnyView(ExtensionContent(screen: self, permissions: permissions)))
    }

    /// A form submits with ⌘Return, since Return belongs to its fields.
    var footer: ScreenFooter {
        if case .form = session.view { return .actions(primaryKeys: ["command", "return"]) }
        return .actions()
    }

    private var permissions: ExtensionPermissions {
        module.extensions.installed(id: session.command.extensionID)?.manifest.permissions ?? ExtensionPermissions()
    }

    var keys: KeyPolicy {
        switch session.view {
        case .detail, .form: KeyPolicy(leavesArrows: true)
        default: KeyPolicy()
        }
    }

    func items(for query: String) -> [LauncherItem] {
        guard let list = session.list else { return [] }
        let text = query.trimmingCharacters(in: .whitespaces)
        let items =
            list.filtering && !text.isEmpty
            ? list.items.filter { FuzzyMatch.score(text, in: $0.searchText) != nil } : list.items
        return items.map { item in
            LauncherItem(
                id: "extension-item:\(item.id)", module: ModuleManifest.extensions.id, title: item.title,
                subtitle: item.subtitle ?? "", icon: .extension(item.icon, nil), searchText: item.searchText,
                subtitleBesideTitle: true, payload: item)
        }
    }

    func sectionTitle(at index: Int, in items: [LauncherItem]) -> String? {
        guard items.indices.contains(index), let item = items[index].payload(as: ExtensionListItem.self) else {
            return nil
        }
        return item.section ?? session.view.navigationTitle ?? session.command.title
    }

    func rowView(for item: LauncherItem, index: Int, isSelected: Bool) -> AnyView? {
        guard let listItem = item.payload(as: ExtensionListItem.self) else { return nil }
        return AnyView(
            ResultRow(item: item, isSelected: isSelected) { ExtensionAccessories(accessories: listItem.accessories) }
                .environment(
                    \.extensionContext, ExtensionContext(directory: session.command.directory, permissions: permissions)
                ))
    }

    func actions(for item: LauncherItem) -> [ItemAction] {
        guard let listItem = item.payload(as: ExtensionListItem.self) else { return [] }
        return listItem.actions.map(itemAction)
    }

    /// The view's own actions while no item is selected, as in a detail, a form or an empty list. A form's first is
    /// its submit, which ⌘Return runs too.
    var screenActions: [ItemAction] {
        guard host?.selectedItem == nil else { return [] }
        var actions = session.view.actions.map(itemAction)
        if case .form = session.view, !actions.isEmpty, actions[0].shortcut == nil {
            actions[0].shortcut = .commandReturn
        }
        return actions
    }

    private func itemAction(_ action: ExtensionAction) -> ItemAction {
        ItemAction(
            id: "extension.action.\(action.id)", title: action.title, icon: action.icon,
            shortcut: action.shortcut.map { KeyShortcut($0.key, Self.modifierFlags($0.modifiers)) },
            section: action.section, isDestructive: action.isDestructive
        ) { [session] in
            session.run(action)
            return .stay
        }
    }

    private static func modifierFlags(_ modifiers: ExtensionShortcut.Modifiers) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.command) { flags.insert(.command) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.control) { flags.insert(.control) }
        return flags
    }

    func queryChanged(_ query: String) {
        session.searchTextChanged(query)
    }

    /// Escape goes back through the command's own pages first.
    func back() -> Bool {
        Task { [session, weak host] in
            guard await !session.pop() else { return }
            host?.leave()
        }
        return true
    }

    func close() {
        session.close()
    }

    /// Draws a new render, keeping the selected item selected while the list changes under it.
    func handle(_ event: ExtensionRuntime.Event) {
        guard let host else { return }
        switch event {
        case .render(let sessionID, let depth, let route, let view):
            guard session.id == sessionID else { return }
            let previousDepth = session.depth
            let previousQuery = host.query
            let selectedID = host.selectedItem?.id
            let isFirstView = if case .loading = session.view { true } else { false }
            switch session.apply(view, depth: depth, route: route) {
            case .update:
                // A list that searches for itself only hears of the search text once it's shown, so text the command
                // started with, from “Use … with”, is passed on now.
                if isFirstView, !host.query.isEmpty {
                    session.searchTextChanged(host.query)
                }
                let results = host.results
                if let pending = pendingSelection, let index = results.firstIndex(where: { $0.id == pending }) {
                    pendingSelection = nil
                    host.selection = index
                    return
                }
                host.selection =
                    results.firstIndex { $0.id == selectedID } ?? min(host.selection, max(results.count - 1, 0))
            case .forward:
                // A new page starts with an empty search and its first item selected; the page it came from is kept
                // for going back.
                session.save(query: previousQuery, selectedID: selectedID, at: previousDepth)
                pendingSelection = nil
                host.query = ""
                host.selection = 0
            case .back:
                let saved = session.restore(at: depth)
                host.query = saved?.query ?? ""
                let index = saved?.selectedID.flatMap { id in host.results.firstIndex { $0.id == id } }
                pendingSelection = index == nil ? saved?.selectedID : nil
                host.selection = index ?? 0
            case .replace:
                pendingSelection = nil
                host.query = ""
                host.selection = 0
            }
        case .failed(let sessionID?, let message, _):
            Toast.shared.show(message, symbol: "exclamationmark.triangle")
            // A view command that failed to start has nothing to show, so it goes back rather than staying blank.
            if session.id == sessionID, case .loading = session.view {
                host.leave()
            }
        case .failed, .done, .log:
            break
        }
    }
}

extension ExtensionsModule {
    fileprivate var hostForScreens: (any ModuleHost)? { host }
}

extension ExtensionCommandInfo {
    /// The extension as a module, so its commands are turned on and off like built-in ones.
    var moduleRef: ModuleRef {
        .extension(extensionID, row: command.name)
    }
}
