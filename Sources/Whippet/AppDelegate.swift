import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts
import SwiftUI
import WhippetCore

/// Owns the search panel, the global hotkey, the services shared with the SwiftUI scenes in `WhippetApp`, and the
/// modules, which it builds from those services.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let clipboard: ClipboardHistory
    /// Created with the delegate because SwiftUI builds the Settings scene before the app finishes launching.
    let cloudSync: CloudSync
    /// Set by `WhippetApp`, which is the only place SwiftUI's `openWindow` action is available.
    var openSettingsWindow: () -> Void = {}
    var openFeedbackWindow: () -> Void = {}

    /// Launches from the panel and from hotkeys, which rank results and fill the Suggestions section.
    let launchHistory = LaunchHistory()
    let feedbackStore = FeedbackStore()
    let settingsNavigation = SettingsNavigation()
    let quicklinks: Quicklinks
    let featureFlags = FeatureFlags()
    /// What's turned on in Settings › Commands.
    let moduleSettings: ModuleSettings
    let extensions = ExtensionManager()
    /// Created with the delegate, as Sparkle recommends, so its scheduled checks start at launch.
    let updater = Updater()
    let model: LauncherModel
    private var panel: LauncherPanel!

    override init() {
        let moduleSettings = ModuleSettings(flags: featureFlags)
        self.moduleSettings = moduleSettings
        PermissionGate.shared.modules = moduleSettings
        clipboard = ClipboardHistory()
        cloudSync = CloudSync(
            store: clipboard.store, directory: ClipboardStore.defaultDirectory,
            isAllowed: moduleSettings.isEnabled(.cloudSyncModule))
        quicklinks = Quicklinks(store: clipboard.store)
        model = LauncherModel(modules: moduleSettings, history: launchHistory)
        super.init()
    }

    /// A module for every manifest in `ModuleRegistry.all`, in the order their rows are listed in the empty search:
    /// the commands first, then windows, quicklinks, extensions, recent timers and apps.
    private func makeModules() -> [any LauncherModule] {
        return [
            CalculatorModule(clipboard: clipboard),
            ClipboardModule(clipboard: clipboard),
            CaptureTextModule(),
            WhippetModule(clipboard: clipboard),
            FeedbackModule(
                store: feedbackStore, showFeedback: { [weak self] in self?.showFeedback() },
                readFeedback: { [weak self] in self?.showSettings(pane: .feedback) }),
            UpdatesModule(updater: updater),
            TranslationModule(),
            CaffeinateModule(),
            SystemModule(),
            WindowManagementModule(),
            QuicklinksModule(quicklinks: quicklinks, navigation: settingsNavigation) { [weak self] in
                self?.settingsNavigation.isCreatingQuicklink = true
                self?.showSettings(pane: .quicklinks)
            },
            ExtensionsModule(extensions: extensions),
            TimersModule(),
            ApplicationsModule(history: launchHistory, clipboard: clipboard),
            CloudSyncModule(cloudSync: cloudSync),
        ]
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppAppearance.current.apply()
        clipboard.start()

        clipboard.onLocalChange = { [weak self] in self?.cloudSync.recordChanged($0) }
        clipboard.onLocalDelete = { [weak self] in self?.cloudSync.recordDeleted($0) }
        quicklinks.onLocalChange = { [weak self] in self?.cloudSync.recordChanged($0) }
        quicklinks.onLocalDelete = { [weak self] in self?.cloudSync.recordDeleted($0) }
        cloudSync.onRemoteChanges = { [weak self] in
            self?.clipboard.didMergeRemoteChanges()
            self?.quicklinks.reload()
        }

        model.onDismiss = { [weak self] in self?.dismissPanel() }
        model.onShowPanel = { [weak self] in self?.showPanel() }
        model.onShowActions = { [weak self] in self?.showActions() }
        model.onOpenSettings = { [weak self] pane in self?.showSettings(pane: pane) }
        model.onHotkeysChanged = { [weak self] in self?.syncHotkeys() }
        Notifications.shared.configure()
        model.install(makeModules())
        moduleSettings.locks = { [weak self] in self?.model.launcherModules.flatMap(\.activity) ?? [] }
        moduleSettings.onChange = { [weak self] in self?.applyModules() }

        panel = LauncherPanel(rootView: SearchView(model: model))
        panel.delegate = self
        model.panel = panel

        KeyboardShortcuts.onKeyDown(for: .togglePanel) { [weak self] in
            self?.togglePanel()
        }
        for manifest in ModuleRegistry.all {
            for command in manifest.commands {
                let ref = manifest.ref(command.id)
                KeyboardShortcuts.onKeyDown(for: KeyboardShortcuts.Name(for: ref)) { [weak self] in
                    self?.model.runCommand(ref)
                }
            }
        }
        applyModules()

        // Navigation keys are handled before they reach the focused view, because text fields treat Escape as "complete"
        // and focus can sit outside the search field.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === panel else { return event }
            return handleKey(event) ? nil : event
        }
    }

    /// A key pressed in the panel, true when the launcher took it.
    private func handleKey(_ event: NSEvent) -> Bool {
        // While an input method is composing, arrows, Return and Escape pick and confirm its candidates.
        if let editor = panel.firstResponder as? NSTextView, editor.hasMarkedText() { return false }
        // Only these four, so Caps Lock and the keypad's own flag don't stop a shortcut matching.
        let modifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
        let keys = model.activeScreen.keys
        let isInField = panel.firstResponder is NSTextView
        switch Int(event.keyCode) {
        case kVK_Escape:
            model.back()
        case kVK_Return where modifiers.isEmpty && (model.usesPlainKeys || !isInField),
            kVK_Space where modifiers.isEmpty && model.usesPlainKeys:
            model.activate()
        case kVK_Return where modifiers.isEmpty, kVK_ANSI_KeypadEnter where modifiers.isEmpty:
            // The focused field submits, which runs the same.
            return false
        case kVK_Delete where modifiers.isEmpty && model.usesPlainKeys:
            return model.performPlainKey("\u{8}")
        case kVK_Tab where modifiers.isEmpty:
            return model.runTabAction()
        case kVK_UpArrow where keys.leavesArrows && model.input == nil,
            kVK_DownArrow where keys.leavesArrows && model.input == nil:
            return false
        case kVK_UpArrow:
            model.moveSelection(by: -1)
        case kVK_DownArrow:
            model.moveSelection(by: 1)
        case kVK_Return where modifiers == [.command], kVK_ANSI_KeypadEnter where modifiers == [.command]:
            model.activateSecondary()
        case kVK_LeftArrow where modifiers.isEmpty, kVK_RightArrow where modifiers.isEmpty:
            // Columns swap sides in right-to-left languages, so the arrow keys follow the screen rather than the order.
            let towardStart =
                (Int(event.keyCode) == kVK_LeftArrow) == (NSApp.userInterfaceLayoutDirection == .leftToRight)
            return model.horizontalMove(by: towardStart ? -1 : 1)
        default:
            guard let key = Self.shortcutKey(for: event) else { return false }
            // Shift too, which types + on most layouts.
            if model.usesPlainKeys, modifiers.isEmpty || modifiers == [.shift] {
                _ = model.performPlainKey(key)
                return true
            }
            return performShortcut(key, modifiers: modifiers)
        }
        return true
    }

    /// The launcher's own shortcuts, then the selection's and the screen's actions. False when nothing has the key.
    private func performShortcut(_ key: Character, modifiers: NSEvent.ModifierFlags) -> Bool {
        switch (key, modifiers) {
        case ("k", [.command]): showActions()
        case ("q", [.command]): NSApp.terminate(nil)
        case (",", [.command]): showSettings()
        default: return model.performShortcut(KeyShortcut(String(key), modifiers))
        }
        return true
    }

    /// The character a shortcut names: what the key types, so ⌘K is the key labelled K on AZERTY or Dvorak. Layouts
    /// without Latin letters fall back to the key's US position, as macOS does for menu shortcuts.
    private static func shortcutKey(for event: NSEvent) -> Character? {
        if let typed = event.charactersIgnoringModifiers?.lowercased(), typed.count == 1,
            let character = typed.first, character.isASCII, !character.isWhitespace
        {
            return character
        }
        return usKeys[Int(event.keyCode)]
    }

    private static let usKeys: [Int: Character] = [
        kVK_ANSI_P: "p", kVK_ANSI_C: "c", kVK_ANSI_X: "x", kVK_ANSI_K: "k", kVK_ANSI_Q: "q", kVK_ANSI_Comma: ",",
        kVK_ANSI_Equal: "=", kVK_ANSI_L: "l", kVK_ANSI_R: "r", kVK_ANSI_T: "t", kVK_ANSI_F: "f", kVK_ANSI_S: "s",
        kVK_ANSI_O: "o", kVK_ANSI_N: "n",
    ]

    /// The Dock icon only shows while a window is open, so clicking it brings back that window, such as Send Feedback,
    /// and opens Settings only when nothing is open.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard let openWindow else {
            showSettings()
            return false
        }
        openWindow.makeKeyAndOrderFront(nil)
        return false
    }

    /// Clicking into another app takes focus away from the panel; that app is already active, so only the panel closes.
    func windowDidResignKey(_ notification: Notification) {
        panel.orderOut(nil)
    }

    /// Activates Whippet, so anything opened from the panel such as Settings can come to the front.
    /// The hotkey is the user's own input, which is what lets macOS grant the activation.
    func showPanel() {
        model.reset()
        let frontmost = NSWorkspace.shared.frontmostApplication
        let isWhippetInFront = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier
        // Over one of Whippet's own windows, such as Send Feedback, pastes go to that window.
        model.targetWindow = isWhippetInFront ? NSApp.keyWindow.flatMap { $0 === panel ? nil : $0 } : nil
        model.targetApp = isWhippetInFront && model.targetWindow == nil ? nil : frontmost
        // The screen is chosen from the app in front, before Whippet activates and its own windows take focus.
        panel.center(onScreenOf: frontmost)
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    /// Whippet runs without a Dock icon and takes one while Settings is open; `SettingsView` gives it up on close.
    func showSettings(pane: SettingsPane? = nil) {
        if let pane {
            settingsNavigation.pane = pane
        }
        panel.orderOut(nil)
        // From the menu bar Whippet is a background app, and macOS refuses the cooperative NSApp.activate() request then,
        // so Settings opens behind the front app. The deprecated call still forces activation, as other menu bar apps rely on.
        NSApp.activate(ignoringOtherApps: true)
        NSApp.setActivationPolicy(.regular)
        openSettingsWindow()
    }

    func showFeedback() {
        panel.orderOut(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.setActivationPolicy(.regular)
        openFeedbackWindow()
    }

    /// Starts and stops what Settings › Commands turns on and off, so a module that's off does no work.
    private func applyModules() {
        for module in model.launcherModules {
            module.update(moduleSettings)
        }
        syncHotkeys()
    }

    /// Turns each hotkey on or off with its command. The keys set for a command that's off are kept for when it's
    /// turned back on.
    private func syncHotkeys() {
        var names: [(name: KeyboardShortcuts.Name, isOn: Bool)] = []
        for manifest in ModuleRegistry.all {
            for command in manifest.commands {
                let ref = manifest.ref(command.id)
                names.append((KeyboardShortcuts.Name(for: ref), moduleSettings.isEnabled(ref)))
            }
        }
        for module in model.launcherModules {
            names += module.dynamicRows.map { ($0.hotkey, moduleSettings.isEnabled($0.ref)) }
        }
        KeyboardShortcuts.enable(names.filter(\.isOn).map(\.name))
        KeyboardShortcuts.disable(names.filter { !$0.isOn }.map(\.name))
    }

    /// A native menu of the selection's and the screen's actions, which brings arrow keys, Return, Escape and
    /// type-to-select with it, with their sections as headers and destructive ones in red. It opens above the footer
    /// at the panel's bottom right, or bottom left in right-to-left languages, beside the footer actions, so it's only
    /// offered while the panel is expanded. Collapsed, as for an inline answer, the actions' own shortcuts still work.
    private func showActions() {
        guard model.isExpanded, let view = panel.contentView else { return }
        let menu = NSMenu()
        let item = model.selectedItem
        var section: String?
        for (index, action) in model.menuActions.enumerated() {
            if action.section != section {
                section = action.section
                if index > 0 {
                    menu.addItem(.separator())
                }
                if let section {
                    menu.addItem(.sectionHeader(title: section))
                }
            }
            let menuItem = ActionMenuItem(title: action.title) { [weak self] in
                self?.model.run(action, on: item)
            }
            menuItem.image = action.icon.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
            if action.isDestructive {
                menuItem.attributedTitle = NSAttributedString(
                    string: action.title, attributes: [.foregroundColor: NSColor.systemRed])
            }
            // Return without modifiers is left to the menu, which runs the highlighted action with it; as a key
            // equivalent it would run the first action whichever is highlighted.
            if let shortcut = action.shortcut, shortcut != .returnKey {
                menuItem.keyEquivalent = shortcut.key
                menuItem.keyEquivalentModifierMask = shortcut.modifiers
            } else if index == 1, item != nil {
                menuItem.keyEquivalent = "\r"
                menuItem.keyEquivalentModifierMask = .command
            } else if model.usesPlainKeys, let key = action.plainKeys?.first, key != "\u{8}" {
                menuItem.keyEquivalent = String(key)
                menuItem.keyEquivalentModifierMask = []
            }
            menu.addItem(menuItem)
        }
        guard !menu.items.isEmpty else { return }

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
    /// Hiding Whippet would also hide a module's own window, such as the floating calculator, so while one is open,
    /// the app the panel opened over is brought back instead.
    private func dismissPanel() {
        panel.orderOut(nil)
        if let window = model.targetWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }
        // Hiding Whippet would hide its open window too, such as Settings.
        guard NSApp.isActive, openWindow == nil else { return }
        if model.launcherModules.contains(where: \.hasOpenWindow), let targetApp = model.targetApp {
            targetApp.activate()
            return
        }
        NSApp.hide(nil)
    }

    /// Settings or Send Feedback, when one is open.
    private var openWindow: NSWindow? {
        let windowIDs = [SettingsView.windowID, FeedbackView.windowID]
        return NSApp.windows.first { window in
            window.isVisible && windowIDs.contains { window.identifier?.rawValue.hasPrefix($0) == true }
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
