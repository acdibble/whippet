import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let togglePanel = Self("togglePanel", initial: .init(.space, modifiers: [.option]))
}

/// Commands that can have their own global hotkey in Settings › Shortcuts.
enum CommandShortcut: String, CaseIterable, Identifiable {
    case calculator
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
        case .clipboardHistory: String(localized: "Clipboard History")
        case .settings: String(localized: "Settings")
        case .caffeinate: String(localized: "Caffeinate")
        }
    }

    var symbol: String {
        switch self {
        case .calculator: "plus.forwardslash.minus"
        case .clipboardHistory: "list.clipboard"
        case .settings: "gearshape"
        case .caffeinate: "cup.and.heat.waves.fill"
        }
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
        case .clipboardHistory: CommandShortcut.clipboardHistory.name
        case .settings: CommandShortcut.settings.name
        case .caffeinate: CommandShortcut.caffeinate.name
        default: nil
        }
        return name.flatMap { KeyboardShortcuts.getShortcut(for: $0) }
    }
}
