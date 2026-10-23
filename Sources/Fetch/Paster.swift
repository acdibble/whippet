import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Pastes into the frontmost app by sending ⌘V, which macOS only allows once Fetch has Accessibility permission.
enum Paster {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt that leads to Accessibility settings; macOS shows it only while permission is missing.
    static func requestTrust() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Sends ⌘V once the panel has closed and keyboard focus has returned to the app underneath.
    @MainActor
    static func pasteAfterPanelCloses() {
        Task {
            try? await Task.sleep(for: .milliseconds(80))
            let source = CGEventSource(stateID: .combinedSessionState)
            for isKeyDown in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: isKeyDown)
                event?.flags = .maskCommand
                event?.post(tap: .cghidEventTap)
            }
        }
    }
}
