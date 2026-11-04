import KeyboardShortcuts
import WhippetCore

extension KeyboardShortcuts.Name {
    static let togglePanel = Self("togglePanel", initial: .init(.space, modifiers: [.option]))
}

extension Quicklink {
    /// Keyed by UUID, so a hotkey survives renaming the quicklink.
    var shortcutName: KeyboardShortcuts.Name {
        KeyboardShortcuts.Name("quicklink.\(uuid)")
    }
}

extension ExtensionCommandInfo {
    /// Keyed by extension and command name, so a hotkey survives the extension being updated.
    var shortcutName: KeyboardShortcuts.Name {
        KeyboardShortcuts.Name("extension.\(key)")
    }
}

extension AppEntry {
    /// Keyed by bundle identifier so a hotkey survives the app moving folders.
    var shortcutName: KeyboardShortcuts.Name {
        KeyboardShortcuts.Name("app.\(stableID)")
    }
}

extension LauncherResult {
    /// The global hotkey set for this app or command in Settings, if any.
    @MainActor var hotkey: KeyboardShortcuts.Shortcut? {
        hotkeyName.flatMap { KeyboardShortcuts.getShortcut(for: $0) }
    }
}
