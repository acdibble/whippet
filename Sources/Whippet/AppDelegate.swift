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
    private var model: LauncherModel!
    private var panel: LauncherPanel!
    private var registeredAppHotkeys: Set<String> = []

    override init() {
        clipboard = ClipboardHistory()
        cloudSync = CloudSync(store: clipboard.store)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        appIndex.refresh()
        clipboard.start()

        clipboard.onLocalChange = { [weak self] in self?.cloudSync.recordChanged($0) }
        cloudSync.onRemoteChanges = { [weak self] in self?.clipboard.didMergeRemoteChanges() }

        model = LauncherModel(appIndex: appIndex, clipboard: clipboard)
        model.onDismiss = { [weak self] in self?.dismissPanel() }
        model.onOpenSettings = { [weak self] in self?.showSettings() }

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
                model.activate(copyOnly: true)
            case kVK_LeftArrow where isPlainArrow, kVK_RightArrow where isPlainArrow:
                guard model.moveColumn(by: Int(event.keyCode) == kVK_LeftArrow ? -1 : 1) else { return event }
            case kVK_ANSI_P where modifiers == [.command, .shift]: model.togglePinnedSelection()
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
        NSApp.setActivationPolicy(.regular)
        openSettingsWindow()
        NSApp.activate()
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
        }
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
