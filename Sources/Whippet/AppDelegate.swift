import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts

/// Owns the search panel, the global hotkey and the services shared with the SwiftUI scenes in `WhippetApp`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let clipboard: ClipboardHistory
    /// Created with the delegate because SwiftUI builds the Settings scene before the app finishes launching.
    let cloudSync: CloudSync
    /// Set by `WhippetApp`, which is the only place SwiftUI's `openWindow` action is available.
    var openSettingsWindow: () -> Void = {}

    let appIndex = AppIndex()
    let caffeine = Caffeine()
    private var model: LauncherModel!
    private var panel: LauncherPanel!
    private var registeredAppHotkeys: Set<String> = []
    private var caffeineStatusItem: CaffeineStatusItem?

    override init() {
        LegacySettings.migrate()
        clipboard = ClipboardHistory()
        cloudSync = CloudSync(store: clipboard.store)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        appIndex.refresh()
        clipboard.start()

        clipboard.onLocalChange = { [weak self] in self?.cloudSync.recordChanged($0) }
        clipboard.onLocalDelete = { [weak self] in self?.cloudSync.recordDeleted($0) }
        cloudSync.onRemoteChanges = { [weak self] in self?.clipboard.didMergeRemoteChanges() }

        model = LauncherModel(appIndex: appIndex, clipboard: clipboard, caffeine: caffeine)
        model.onDismiss = { [weak self] in self?.dismissPanel() }
        model.onOpenSettings = { [weak self] in self?.showSettings() }
        model.onShowActions = { [weak self] in self?.showActions() }

        panel = LauncherPanel(rootView: SearchView(model: model))
        panel.delegate = self

        KeyboardShortcuts.onKeyDown(for: .togglePanel) { [weak self] in
            self?.togglePanel()
        }
        for command in CommandShortcut.allCases {
            KeyboardShortcuts.onKeyDown(for: command.name) { [weak self] in
                self?.run(command)
            }
        }
        registerAppHotkeys()
        appIndex.onChange = { [weak self] in self?.registerAppHotkeys() }
        appIndex.startWatching()
        caffeineStatusItem = CaffeineStatusItem(caffeine: caffeine)

        // Navigation keys are handled before they reach the focused view, because text fields treat Escape as "complete"
        // and focus can sit outside the search field.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === panel else { return event }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isPlainArrow = modifiers.isDisjoint(with: [.shift, .command, .option, .control])
            switch Int(event.keyCode) {
            case kVK_Escape: model.back()
            case kVK_UpArrow: model.moveSelection(by: -1)
            case kVK_DownArrow: model.moveSelection(by: 1)
            case kVK_Return where modifiers == [.command], kVK_ANSI_KeypadEnter where modifiers == [.command]:
                model.perform(.secondary)
            case kVK_LeftArrow where isPlainArrow, kVK_RightArrow where isPlainArrow:
                // Columns swap sides in right-to-left languages, so the arrow keys follow the screen rather than the column order.
                let towardStart = (Int(event.keyCode) == kVK_LeftArrow) == (NSApp.userInterfaceLayoutDirection == .leftToRight)
                guard model.moveColumn(by: towardStart ? -1 : 1) else { return event }
            case kVK_ANSI_P where modifiers == [.command, .shift]: model.perform(.togglePin)
            case kVK_ANSI_C where modifiers == [.command, .shift]: model.perform(.copyPath)
            case kVK_ANSI_X where modifiers == [.control]: model.perform(.delete)
            case kVK_ANSI_K where modifiers == [.command]: showActions()
            case kVK_ANSI_Q where modifiers == [.command]: NSApp.terminate(nil)
            case kVK_ANSI_Comma where modifiers == [.command]: showSettings()
            default: return event
            }
            return nil
        }
    }

    /// Clicking the Dock icon, which only shows while Settings is open, brings Settings forward.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    /// Clicking into another app takes focus away from the panel; that app is already active, so only the panel closes.
    func windowDidResignKey(_ notification: Notification) {
        panel.orderOut(nil)
    }

    /// Activates Whippet, as Raycast does, so anything opened from the panel such as Settings can come to the front.
    /// The hotkey is the user's own input, which is what lets macOS grant the activation.
    func showPanel() {
        model.reset()
        let frontmost = NSWorkspace.shared.frontmostApplication
        model.targetApp = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : frontmost
        NSApp.activate()
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }

    /// Whippet runs without a Dock icon and takes one while Settings is open; `SettingsView` gives it up on close.
    func showSettings() {
        panel.orderOut(nil)
        // From the menu bar Whippet is a background app, and macOS refuses the cooperative NSApp.activate() request then,
        // so Settings opens behind the front app. The deprecated call still forces activation, as other menu bar apps rely on.
        NSApp.activate(ignoringOtherApps: true)
        NSApp.setActivationPolicy(.regular)
        openSettingsWindow()
    }

    /// Registers a handler once per app; the handler looks the app up when pressed, so it follows the app if it moves.
    private func registerAppHotkeys() {
        for app in appIndex.apps where !registeredAppHotkeys.contains(app.stableID) {
            registeredAppHotkeys.insert(app.stableID)
            let name = app.shortcutName
            KeyboardShortcuts.onKeyDown(for: name) { [weak self] in
                guard let self, let app = appIndex.apps.first(where: { $0.shortcutName == name }) else { return }
                appIndex.open(app)
            }
        }
    }

    private func run(_ command: CommandShortcut) {
        switch command {
        case .calculator:
            showPanel()
            model.show(.calculator)
        case .clipboardHistory:
            showPanel()
            model.show(.clipboard)
        case .settings:
            showSettings()
        case .caffeinate:
            caffeine.toggle()
        }
    }

    /// A native menu of the selected result's actions, which brings arrow keys, Return, Escape and type-to-select with it.
    /// It opens above the footer at the panel's bottom right, or bottom left in right-to-left languages, beside the footer actions.
    private func showActions() {
        guard let result = model.selectedResult, let view = panel.contentView else { return }
        let menu = NSMenu()
        for action in ResultAction.allCases where action.isAvailable(for: result) {
            let item = ActionMenuItem(title: action.title(for: result, model: model)) { [weak self] in
                self?.model.perform(action)
            }
            item.image = NSImage(systemSymbolName: action.symbol, accessibilityDescription: nil)
            item.keyEquivalent = action.shortcut.key
            item.keyEquivalentModifierMask = action.shortcut.modifiers
            menu.addItem(item)
        }

        let inset = LauncherPanel.shadowInset
        let size = LauncherPanel.contentSize
        let footerHeight: CGFloat = 44
        let isRightToLeft = NSApp.userInterfaceLayoutDirection == .rightToLeft
        let origin = NSPoint(
            x: isRightToLeft ? inset + 12 : inset + size.width - menu.size.width - 12,
            y: inset + size.height - footerHeight - menu.size.height
        )
        menu.popUp(positioning: nil, at: origin, in: view)
    }

    private func togglePanel() {
        if panel.isVisible {
            dismissPanel()
            return
        }
        showPanel()
    }

    /// Hiding Whippet hands focus back to the app the panel opened over, which is where pastes land.
    /// While Settings is open only the panel closes, so Settings is not hidden with it.
    private func dismissPanel() {
        panel.orderOut(nil)
        guard NSApp.isActive, !isSettingsOpen else { return }
        NSApp.hide(nil)
    }

    private var isSettingsOpen: Bool {
        NSApp.windows.contains { $0.identifier?.rawValue.hasPrefix(SettingsView.windowID) == true && $0.isVisible }
    }
}

/// Copies settings saved under the app's previous bundle identifier, once, so moving to codes.dibble.whippet keeps
/// hotkeys, launch counts and preferences. The last-synced time and CloudKit's own caches belong to the old app and container,
/// so they are left out.
private enum LegacySettings {
    private static let legacyDomain = "com.acdibble.whippet"
    private static let migratedKey = "migratedSettingsFromComAcdibble"
    private static let skippedKeys: Set<String> = ["cloudLastSyncedAt"]
    private static let skippedPrefixes = ["CK", "CloudKit"]

    static func migrate() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migratedKey) else { return }
        defaults.set(true, forKey: migratedKey)
        guard let legacy = defaults.persistentDomain(forName: legacyDomain) else { return }
        for (key, value) in legacy where defaults.object(forKey: key) == nil {
            if skippedKeys.contains(key) || skippedPrefixes.contains(where: key.hasPrefix) { continue }
            defaults.set(value, forKey: key)
        }
    }
}

/// A menu item that runs a closure, so actions do not need an Objective-C selector each.
final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    @objc private func run() {
        handler()
    }
}
