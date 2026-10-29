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
    var openFeedbackWindow: () -> Void = {}

    /// Launches from the panel and from hotkeys, which rank results and fill the Suggestions section.
    let launchHistory = LaunchHistory()
    let appIndex: AppIndex
    let caffeine = Caffeine()
    let timers = Timers()
    let feedbackStore = FeedbackStore()
    let settingsNavigation = SettingsNavigation()
    let quicklinks: Quicklinks
    private var registeredQuicklinkHotkeys: Set<String> = []
    private lazy var floatingCalculator = FloatingCalculator(clipboard: clipboard)
    /// Created with the delegate, as Sparkle recommends, so its scheduled checks start at launch.
    let updater = Updater()
    private var model: LauncherModel!
    private var panel: LauncherPanel!
    private var registeredAppHotkeys: Set<String> = []
    private var caffeineStatusItem: CaffeineStatusItem?
    private var timersStatusItem: TimersStatusItem?

    override init() {
        clipboard = ClipboardHistory()
        cloudSync = CloudSync(store: clipboard.store)
        appIndex = AppIndex(history: launchHistory)
        quicklinks = Quicklinks(store: clipboard.store)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppAppearance.current.apply()
        appIndex.refresh()
        clipboard.start()

        clipboard.onLocalChange = { [weak self] in self?.cloudSync.recordChanged($0) }
        clipboard.onLocalDelete = { [weak self] in self?.cloudSync.recordDeleted($0) }
        quicklinks.onLocalChange = { [weak self] in self?.cloudSync.recordChanged($0) }
        quicklinks.onLocalDelete = { [weak self] in self?.cloudSync.recordDeleted($0) }
        quicklinks.onListChange = { [weak self] in self?.registerQuicklinkHotkeys() }
        cloudSync.onRemoteChanges = { [weak self] in
            self?.clipboard.didMergeRemoteChanges()
            self?.quicklinks.reload()
        }

        model = LauncherModel(
            appIndex: appIndex,
            clipboard: clipboard,
            caffeine: caffeine,
            timers: timers,
            history: launchHistory,
            quicklinks: quicklinks
        )
        model.onDismiss = { [weak self] in self?.dismissPanel() }
        model.onOpenSettings = { [weak self] in self?.showSettings() }
        model.onSendFeedback = { [weak self] in self?.showFeedback() }
        model.onReadFeedback = { [weak self] in self?.showSettings(pane: .feedback) }
        Task { model.isFeedbackAdmin = await feedbackStore.isAdmin }
        model.onShowActions = { [weak self] in self?.showActions() }
        model.onCreateQuicklink = { [weak self] in
            self?.settingsNavigation.isCreatingQuicklink = true
            self?.showSettings(pane: .quicklinks)
        }
        model.onPopOutCalculator = { [weak self] expression in
            guard let self else { return }
            dismissPanel()
            floatingCalculator.show(expression: expression)
        }

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
        // Straight on the front window, without the panel.
        for command in WindowCommand.allCases {
            KeyboardShortcuts.onKeyDown(for: command.shortcutName) {
                WindowManager.perform(command, in: NSWorkspace.shared.frontmostApplication)
            }
        }
        registerAppHotkeys()
        registerQuicklinkHotkeys()
        appIndex.onChange = { [weak self] in self?.registerAppHotkeys() }
        appIndex.startWatching()
        caffeineStatusItem = CaffeineStatusItem(caffeine: caffeine)
        Notifications.shared.configure()
        timers.start()
        timersStatusItem = TimersStatusItem(timers: timers)
        timersStatusItem?.onStartTimer = { [weak self] in self?.run(.startTimer) }
        timersStatusItem?.onStartStopwatch = { [weak self] in self?.run(.startStopwatch) }
        timersStatusItem?.onOpenTimers = { [weak self] in self?.run(.timers) }
        timersStatusItem?.onCopyTime = { [weak self] item in self?.model.copyTime(of: item) }
        timersStatusItem?.onOpenStopwatch = { [weak self] id in
            guard let self else { return }
            showPanel()
            model.openDirectly { model.showStopwatch(id) }
        }
        timersStatusItem?.onRename = { [weak self] item in
            guard let self else { return }
            showPanel()
            model.openDirectly { model.beginArgument(.rename(item), text: item.name) }
        }

        // Navigation keys are handled before they reach the focused view, because text fields treat Escape as "complete"
        // and focus can sit outside the search field.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === panel else { return event }
            // While an input method is composing, arrows, Return and Escape pick and confirm its candidates.
            if let editor = panel.firstResponder as? NSTextView, editor.hasMarkedText() { return event }
            // Only these four, so Caps Lock and the keypad's own flag don't stop a shortcut matching.
            let modifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
            let isPlainArrow = modifiers.isEmpty
            switch Int(event.keyCode) {
            case kVK_Escape: model.back()
            case kVK_Return where model.usesPlainKeys && modifiers.isEmpty,
                 kVK_Space where model.usesPlainKeys && modifiers.isEmpty:
                model.activate()
            case kVK_Delete where model.usesPlainKeys && modifiers.isEmpty:
                model.deleteWithPlainKey()
            case kVK_Tab where modifiers.isEmpty:
                guard model.beginArgumentForSelection() else { return event }
            case kVK_UpArrow: model.moveSelection(by: -1)
            case kVK_DownArrow: model.moveSelection(by: 1)
            case kVK_Return where modifiers == [.command], kVK_ANSI_KeypadEnter where modifiers == [.command]:
                model.perform(.secondary)
            case kVK_LeftArrow where isPlainArrow, kVK_RightArrow where isPlainArrow:
                // Columns swap sides in right-to-left languages, so the arrow keys follow the screen rather than the column order.
                let towardStart = (Int(event.keyCode) == kVK_LeftArrow) == (NSApp.userInterfaceLayoutDirection == .leftToRight)
                guard model.moveColumn(by: towardStart ? -1 : 1) || model.switchStopwatch(by: towardStart ? -1 : 1) else {
                    return event
                }
            default:
                guard let key = Self.shortcutKey(for: event) else { return event }
                // Shift too, which types + on most layouts.
                if model.usesPlainKeys, modifiers.isEmpty || modifiers == [.shift] {
                    model.performPlainKey(key)
                    return nil
                }
                guard performShortcut(key, modifiers: modifiers) else { return event }
            }
            return nil
        }
    }

    /// Runs the panel shortcut for a key, returning false when there is none.
    private func performShortcut(_ key: Character, modifiers: NSEvent.ModifierFlags) -> Bool {
        switch (key, modifiers) {
        case ("p", [.command, .shift]): model.perform(.togglePin)
        case ("c", [.command, .shift]): model.perform(.copyPath)
        case ("x", [.control]):
            let dismisses = model.selectedResult.map(ResultAction.dismiss.isAvailable(for:)) ?? false
            model.perform(dismisses ? .dismiss : .delete)
        case ("o", [.command, .shift]): model.perform(.popOut)
        case ("=", [.command]): model.perform(.addMinute)
        case ("l", [.command]): model.perform(.lap)
        case ("r", [.command]): model.perform(.restart)
        case ("k", [.command]): showActions()
        case ("q", [.command]): NSApp.terminate(nil)
        case (",", [.command]): showSettings()
        default: return false
        }
        return true
    }

    /// The character a shortcut names: what the key types, so ⌘K is the key labelled K on AZERTY or Dvorak. Layouts
    /// without Latin letters fall back to the key's US position, as macOS does for menu shortcuts.
    private static func shortcutKey(for event: NSEvent) -> Character? {
        if let typed = event.charactersIgnoringModifiers?.lowercased(), typed.count == 1,
           let character = typed.first, character.isASCII, !character.isWhitespace {
            return character
        }
        return usKeys[Int(event.keyCode)]
    }

    private static let usKeys: [Int: Character] = [
        kVK_ANSI_P: "p", kVK_ANSI_C: "c", kVK_ANSI_X: "x", kVK_ANSI_K: "k", kVK_ANSI_Q: "q", kVK_ANSI_Comma: ",",
        kVK_ANSI_Equal: "=", kVK_ANSI_L: "l", kVK_ANSI_R: "r",
    ]

    /// Clicking the Dock icon, which only shows while Settings is open, brings Settings forward.
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

    /// Like app hotkeys, looked up when pressed. A quicklink that takes text opens the panel ready for it.
    private func registerQuicklinkHotkeys() {
        for quicklink in quicklinks.items where !registeredQuicklinkHotkeys.contains(quicklink.uuid) {
            registeredQuicklinkHotkeys.insert(quicklink.uuid)
            let uuid = quicklink.uuid
            KeyboardShortcuts.onKeyDown(for: quicklink.shortcutName) { [weak self] in
                guard let self, let quicklink = quicklinks.items.first(where: { $0.uuid == uuid }) else { return }
                guard quicklink.takesArgument else {
                    launchHistory.record("quicklink:\(uuid)")
                    Quicklinks.open(quicklink)
                    return
                }
                // Counted when it opens with the text.
                showPanel()
                model.openDirectly { model.beginArgument(for: quicklink) }
            }
        }
    }

    private func run(_ command: CommandShortcut) {
        switch command {
        case .calculator:
            showPanel()
            model.openDirectly { model.show(.calculator) }
        case .floatingCalculator:
            floatingCalculator.toggle()
        case .clipboardHistory:
            showPanel()
            model.openDirectly { model.show(.clipboard) }
        case .settings:
            showSettings()
        case .caffeinate:
            caffeine.toggle()
        case .startTimer:
            showPanel()
            model.openDirectly { model.beginArgument(.timerDuration) }
        case .startStopwatch:
            showPanel()
            model.openDirectly { model.startStopwatch() }
        case .stopwatch:
            showPanel()
            model.openDirectly { model.showStopwatch() }
        case .timers:
            showPanel()
            model.openDirectly { model.showTimers() }
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
            // Return without modifiers is left to the menu, which runs the highlighted action with it; as a key equivalent it
            // would run the primary action whichever is highlighted. The footer shows that Return runs it.
            if let shortcut = model.shortcut(for: action), !(shortcut.key == "\r" && shortcut.modifiers.isEmpty) {
                item.keyEquivalent = shortcut.key
                item.keyEquivalentModifierMask = shortcut.modifiers
            }
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
    /// Hiding Whippet would also hide the floating calculator, so while it's open, the app the panel opened over is
    /// brought back instead.
    private func dismissPanel() {
        panel.orderOut(nil)
        if let window = model.targetWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }
        // Hiding Whippet would hide its open window too, such as Settings.
        guard NSApp.isActive, openWindow == nil else { return }
        if floatingCalculator.isVisible, let targetApp = model.targetApp {
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
