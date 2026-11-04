import Foundation
import KeyboardShortcuts
import WhippetCore

extension ExtensionCommandInfo {
    /// The extension as a module, so its commands are turned on and off like built-in ones.
    var moduleRef: ModuleRef {
        ModuleRef(module: "extension.\(extensionID)", row: command.name)
    }
}

extension LauncherResult {
    /// The modules, commands and features a result belongs to, all of which must be on for it to be listed. Results
    /// shown only inside a view, such as an extension's list items, belong to nothing here: the view is reached only
    /// through a command that's on.
    var moduleRefs: [ModuleRef] {
        switch self {
        case .calculation, .pastCalculation: [.calculatorModule]
        case .calculator: [.calculator]
        case .floatingCalculator: [.floatingCalculator]
        case .settings: [.settings]
        case .sendFeedback: [.sendFeedback]
        case .readFeedback: [.readFeedback]
        case .checkForUpdates: [.checkForUpdates]
        case .changelog, .release: [.changelog]
        case .whatsNew: [.whatsNew]
        case .shareWhippet: [.shareWhippet]
        case .quit: [.quit]
        case .clipboardHistory: [.clipboardHistory]
        case .searchClipboard: [.clipboardHistory, .clipboardSearchFallback]
        case .clipboard: [.clipboardModule]
        case .captureText: [.captureText]
        case .translate: [.translate]
        case .translateText: [.translate, .translationFallback]
        case .translation: [.translationCard]
        case .caffeinate: [.caffeinate]
        case .caffeinateFor: [.caffeinateFor]
        case .decaffeinate: [.decaffeinate]
        case .caffeinateMenuBar: [.caffeinateMenuBar]
        case .system(let command): [command.moduleRef]
        case .window(let command): [command.moduleRef]
        case .quicklink(let quicklink): [.quicklink(quicklink.uuid)]
        case .createQuicklink: [.createQuicklink]
        case .searchWithQuicklink(let quicklink): [.quicklink(quicklink.uuid), .quicklinkFallbacks]
        case .searchWithExtension(let info), .extensionCommand(let info): [info.moduleRef]
        case .startTimer: [.typedTimers]
        case .newTimer: [.startTimer]
        case .newStopwatch: [.startStopwatch]
        case .stopwatch: [.stopwatch]
        case .timersView: [.timers]
        case .timer, .ringingTimer, .timerPreset: [.timersModule]
        case .app(let app): [.app(app.stableID)]
        case .extensionItem: []
        }
    }

    /// The command whose hotkey runs this result, for the hotkey shown beside it.
    var hotkeyName: KeyboardShortcuts.Name? {
        switch self {
        case .app(let app): app.shortcutName
        case .quicklink(let quicklink): quicklink.shortcutName
        case .extensionCommand(let info): info.shortcutName
        case .calculation, .pastCalculation, .clipboard, .timer, .ringingTimer, .timerPreset, .whatsNew, .release,
            .translation, .extensionItem, .startTimer, .searchWithQuicklink, .searchWithExtension, .searchClipboard,
            .translateText:
            nil
        default:
            moduleRefs.first.flatMap { ModuleRegistry.command($0) != nil ? KeyboardShortcuts.Name(for: $0) : nil }
        }
    }
}

extension ModuleSettings {
    /// Whether a result may be listed: everything it belongs to is on.
    func isListed(_ result: LauncherResult) -> Bool {
        result.moduleRefs.allSatisfy(isEnabled)
    }
}

extension KeyboardShortcuts.Name {
    /// A built-in command's hotkey.
    init(for ref: ModuleRef) {
        self.init(ModuleRegistry.hotkeyName(for: ref))
    }
}
