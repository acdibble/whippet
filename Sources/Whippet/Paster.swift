import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Pastes into the frontmost app by sending ⌘V, which macOS only allows once Whippet has Accessibility permission.
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

    /// Pastes into one of Whippet's own windows by queueing ⌘V in the app itself, which needs no permission and goes
    /// through the same key handling as a real ⌘V, such as the feedback window attaching pasted images.
    @MainActor
    static func paste(into window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(
                with: type,
                location: .zero,
                modifierFlags: .command,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                characters: "v",
                charactersIgnoringModifiers: "v",
                isARepeat: false,
                keyCode: UInt16(kVK_ANSI_V)
            ) else { continue }
            NSApp.postEvent(event, atStart: false)
        }
    }
}
