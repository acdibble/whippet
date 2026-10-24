import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let togglePanel = Self("togglePanel", initial: .init(.space, modifiers: [.option]))
}

/// Commands that can have their own global hotkey in Settings › Shortcuts.
enum CommandShortcut: String, CaseIterable, Identifiable {
    case calculator
    case floatingCalculator
    case clipboardHistory
    case settings
    case caffeinate

    var id: Self { self }

    var name: KeyboardShortcuts.Name {
        KeyboardShortcuts.Name("command.\(rawValue)")
    }

    var title: String {
        switch self {
        case .calculator: String(localized: "Calculator")
        case .floatingCalculator: String(localized: "Floating Calculator")
        case .clipboardHistory: String(localized: "Clipboard History")
        case .settings: String(localized: "Settings")
        case .caffeinate: String(localized: "Caffeinate")
        }
    }

    var symbol: String {
        switch self {
        case .calculator: "plus.forwardslash.minus"
        case .floatingCalculator: "macwindow.on.rectangle"
        case .clipboardHistory: "list.clipboard"
        case .settings: "gearshape"
        case .caffeinate: "cup.and.heat.waves.fill"
        }
    }
}

extension Quicklink {
    /// Keyed by UUID, so a hotkey survives renaming the quicklink.
    var shortcutName: KeyboardShortcuts.Name {
        KeyboardShortcuts.Name("quicklink.\(uuid)")
    }
}

extension AppEntry {
    /// Keyed by bundle identifier so a hotkey survives the app moving folders.
    var shortcutName: KeyboardShortcuts.Name {
        KeyboardShortcuts.Name("app.\(stableID)")
    }
}

extension LauncherResult {
    /// The global hotkey set for this app or command in Settings › Shortcuts, if any.
    @MainActor var hotkey: KeyboardShortcuts.Shortcut? {
        let name: KeyboardShortcuts.Name? = switch self {
        case .app(let app): app.shortcutName
        case .calculator: CommandShortcut.calculator.name
        case .floatingCalculator: CommandShortcut.floatingCalculator.name
        case .clipboardHistory: CommandShortcut.clipboardHistory.name
        case .settings: CommandShortcut.settings.name
        case .caffeinate: CommandShortcut.caffeinate.name
        case .quicklink(let quicklink): quicklink.shortcutName
        default: nil
        }
        return name.flatMap { KeyboardShortcuts.getShortcut(for: $0) }
    }
}
