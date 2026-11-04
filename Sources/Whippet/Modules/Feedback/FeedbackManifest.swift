import Foundation
import WhippetCore

extension ModuleManifest {
    static let feedback = ModuleManifest(
        id: "feedback",
        title: String(localized: "Feedback"),
        summary: String(localized: "Sends a bug report or idea to the developer."),
        icon: "bubble.left",
        tint: .orange,
        commands: [
            ModuleCommand(
                id: "send-feedback", title: String(localized: "Send Feedback"), icon: "bubble.left",
                permissions: [.iCloud(.publicDatabase)]),
            ModuleCommand(
                id: "read-feedback", title: String(localized: "Read Feedback"), icon: "tray.full",
                permissions: [.iCloud(.publicDatabase)], isAdminOnly: true),
        ]
    )
}

extension ModuleRef {
    static let feedbackModule = ModuleManifest.feedback.ref
    static let sendFeedback = ModuleManifest.feedback.ref("send-feedback")
    static let readFeedback = ModuleManifest.feedback.ref("read-feedback")
}
