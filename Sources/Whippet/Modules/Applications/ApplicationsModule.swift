import AppKit
import KeyboardShortcuts

/// Opening apps from the search, and with their own hotkeys.
@MainActor
final class ApplicationsModule: LauncherModule {
    let manifest = ModuleManifest.applications
    let appIndex: AppIndex
    private let clipboard: ClipboardHistory
    private weak var host: (any ModuleHost)?
    private var registeredHotkeys: Set<String> = []

    /// `history` counts each app's launches, from the search and from its hotkey.
    init(history: LaunchHistory, clipboard: ClipboardHistory) {
        appIndex = AppIndex(history: history)
        self.clipboard = clipboard
    }

    func attach(to host: any ModuleHost) {
        self.host = host
        appIndex.refresh()
        appIndex.onChange = { [weak self] in self?.registerHotkeys() }
        registerHotkeys()
    }

    /// Watching the application folders is what keeps the list current, so it stops while the module is off.
    func update(_ modules: ModuleSettings) {
        if modules.isEnabled(manifest.ref) {
            appIndex.startWatching()
        } else {
            appIndex.stopWatching()
        }
    }

    var revision: AnyHashable { appIndex.apps }

    func contributions(for query: String) -> [Contribution] {
        appIndex.apps.map { app in
            .listed(
                LauncherItem(
                    id: "app:\(app.url.path)", module: manifest.id, title: app.name,
                    subtitle: String(localized: "Application"), icon: .file(app.url),
                    section: String(localized: "Applications"), launchKey: app.stableID, favoriteKey: app.stableID,
                    refs: [.app(app.stableID)], hotkey: app.shortcutName, payload: app))
        }
    }

    func actions(for item: LauncherItem) -> [ItemAction] {
        guard let app = item.payload(as: AppEntry.self) else { return [] }
        return [
            // AppIndex.open records the launch, as hotkeys use it too.
            ItemAction(id: "app.open", title: String(localized: "Open Application"), icon: "return") { [appIndex] in
                appIndex.open(app)
                return .dismiss
            },
            ItemAction(id: "app.show-in-finder", title: String(localized: "Show in Finder"), icon: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([app.url])
                return .dismiss
            },
            ItemAction(
                id: "app.copy-path", title: String(localized: "Copy Path"), icon: "link",
                shortcut: KeyShortcut("c", [.command, .shift])
            ) { [clipboard] in
                clipboard.copy(text: app.url.path)
                Toast.shared.show(String(localized: "Copied Path"), symbol: "link")
                return .dismiss
            },
        ]
    }

    func traits(of item: LauncherItem) -> ItemTraits {
        ItemTraits(fileURL: item.payload(as: AppEntry.self)?.url)
    }

    var dynamicRows: [DynamicRow] {
        appIndex.apps.map { app in
            DynamicRow(ref: .app(app.stableID), title: app.name, icon: .file(app.url), hotkey: app.shortcutName)
        }
    }

    /// Registers a handler once per app, which looks the app up when pressed, so it follows the app if it moves.
    private func registerHotkeys() {
        defer { host?.hotkeysChanged() }
        for app in appIndex.apps where !registeredHotkeys.contains(app.stableID) {
            registeredHotkeys.insert(app.stableID)
            let name = app.shortcutName
            KeyboardShortcuts.onKeyDown(for: name) { [weak self] in
                guard let self, let app = appIndex.apps.first(where: { $0.shortcutName == name }),
                    host?.modules.isEnabled(.app(app.stableID)) ?? true
                else { return }
                appIndex.open(app)
            }
        }
    }
}
