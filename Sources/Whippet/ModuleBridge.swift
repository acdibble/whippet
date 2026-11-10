import Foundation
import KeyboardShortcuts
import WhippetCore

extension KeyboardShortcuts.Name {
    /// A built-in command's hotkey.
    init(for ref: ModuleRef) {
        self.init(ModuleRegistry.hotkeyName(for: ref))
    }
}
