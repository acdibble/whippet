import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let togglePanel = Self("togglePanel", initial: .init(.space, modifiers: [.option]))
}

/// Commands that can have their own global hotkey in Settings › Shortcuts.
enum CommandShortcut: String, CaseIterable, Identifiable {
    case calculator
    case clipboardHistory
    case settings

    var id: Self { self }

    var name: KeyboardShortcuts.Name {
        KeyboardShortcuts.Name("command.\(rawValue)")
    }

    var title: String {
        switch self {
        case .calculator: String(localized: "Calculator")
        case .clipboardHistory: String(localized: "Clipboard History")
        case .settings: String(localized: "Settings")
        }
    }

    var symbol: String {
        switch self {
        case .calculator: "plus.forwardslash.minus"
        case .clipboardHistory: "list.clipboard"
        case .settings: "gearshape"
        }
    }
}

extension AppEntry {
    /// Keyed by bundle identifier so a hotkey survives the app moving folders.
    var shortcutName: KeyboardShortcuts.Name {
        KeyboardShortcuts.Name("app.\(stableID)")
    }
}
