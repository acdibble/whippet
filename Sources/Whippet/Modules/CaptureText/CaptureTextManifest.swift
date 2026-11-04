import Foundation
import WhippetCore

extension ModuleManifest {
    static let captureText = ModuleManifest(
        id: "capture-text",
        title: String(localized: "Capture Text"),
        summary: String(localized: "Copies the text in an area of the screen."),
        icon: "text.viewfinder",
        tint: .purple,
        commands: [
            ModuleCommand(
                id: "capture-text", title: String(localized: "Capture Text"), icon: "text.viewfinder",
                permissions: [.screenRecording], legacyHotkey: "command.captureText")
        ]
    )
}

extension ModuleRef {
    static let captureTextModule = ModuleManifest.captureText.ref
    static let captureText = ModuleManifest.captureText.ref("capture-text")
}
