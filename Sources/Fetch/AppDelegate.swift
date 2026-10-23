import AppKit
import Carbon.HIToolbox

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let appIndex = AppIndex()
    private let clipboard = ClipboardHistory()
    private var model: LauncherModel!
    private var panel: LauncherPanel!
    private var hotKey: HotKey?
    private var menuBarItem: MenuBarItem?
    private var cloudSync: CloudSync!
    private var settingsWindow: SettingsWindow!

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        appIndex.refresh()
        clipboard.start()

        cloudSync = CloudSync(store: clipboard.store)
        clipboard.onLocalChange = { [weak self] in self?.cloudSync.recordChanged($0) }
        cloudSync.onRemoteChanges = { [weak self] in self?.clipboard.didMergeRemoteChanges() }
        settingsWindow = SettingsWindow(cloudSync: cloudSync, clipboard: clipboard)

        model = LauncherModel(appIndex: appIndex, clipboard: clipboard)
        model.onDismiss = { [weak self] in self?.hidePanel() }
        model.onOpenSettings = { [weak self] in self?.showSettings() }

        panel = LauncherPanel(rootView: SearchView(model: model))
        panel.delegate = self
        NSApp.mainMenu = makeMainMenu()
        menuBarItem = MenuBarItem(
            onOpen: { [weak self] in self?.showPanel() },
            onSettings: { [weak self] in self?.showSettings() }
        )

        hotKey = HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)) { [weak self] in
            self?.togglePanel()
        }

        // Navigation keys are handled before they reach the focused view, because text fields treat Escape as "complete"
        // and focus can sit outside the search field.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = event.window else { return event }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if window === settingsWindow.window {
                return handleSettingsKey(event, modifiers: modifiers) ? nil : event
            }
            guard window === panel else { return event }
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

    func windowDidResignKey(_ notification: Notification) {
        hidePanel()
    }

    private func togglePanel() {
        if panel.isVisible {
            hidePanel()
            return
        }
        showPanel()
    }

    private func showPanel() {
        model.reset()
        let frontmost = NSWorkspace.shared.frontmostApplication
        model.targetApp = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : frontmost
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }

    private func hidePanel() {
        panel.orderOut(nil)
    }

    /// Never shown, since an accessory app has no menu bar, but it is what gives windows their standard shortcuts.
    private func makeMainMenu() -> NSMenu {
        let about = NSMenuItem(title: String(localized: "About Fetch"), action: #selector(showAboutFromMenu), keyEquivalent: "")
        about.target = self
        let settings = NSMenuItem(title: String(localized: "Settings…"), action: #selector(showSettingsFromMenu), keyEquivalent: ",")
        settings.target = self
        let sections: [(String, [NSMenuItem])] = [
            ("Fetch", [
                about,
                .separator(),
                settings,
                .separator(),
                NSMenuItem(title: String(localized: "Quit Fetch"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"),
            ]),
            (String(localized: "Edit"), [
                NSMenuItem(title: String(localized: "Undo"), action: Selector(("undo:")), keyEquivalent: "z"),
                Self.menuItem(String(localized: "Redo"), action: Selector(("redo:")), key: "z", modifiers: [.command, .shift]),
                .separator(),
                NSMenuItem(title: String(localized: "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x"),
                NSMenuItem(title: String(localized: "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c"),
                NSMenuItem(title: String(localized: "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v"),
                NSMenuItem(title: String(localized: "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"),
            ]),
            (String(localized: "Window"), [
                NSMenuItem(title: String(localized: "Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"),
                NSMenuItem(title: String(localized: "Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"),
            ]),
        ]

        let mainMenu = NSMenu()
        for (title, items) in sections {
            let submenu = NSMenu(title: title)
            submenu.items = items
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = submenu
            mainMenu.addItem(item)
        }
        return mainMenu
    }

    private static func menuItem(_ title: String, action: Selector, key: String, modifiers: NSEvent.ModifierFlags) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    @objc private func showAboutFromMenu() {
        NSApp.showAboutPanel()
    }

    @objc private func showSettingsFromMenu() {
        showSettings()
    }

    /// The main menu only handles shortcuts while Fetch is active, and the Settings window can have focus without that.
    private func handleSettingsKey(_ event: NSEvent, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard modifiers == [.command] else { return false }
        switch Int(event.keyCode) {
        case kVK_ANSI_W: settingsWindow.window?.performClose(nil)
        case kVK_ANSI_Q: NSApp.terminate(nil)
        case kVK_ANSI_Comma: settingsWindow.show()
        default: return false
        }
        return true
    }

    private func showSettings() {
        hidePanel()
        settingsWindow.show()
    }
}
