import AppKit
import Observation
import SwiftUI

/// Sending feedback to the developer, and, for accounts with the CloudKit Admin role, reading it.
@MainActor
@Observable
final class FeedbackModule: LauncherModule {
    let manifest = ModuleManifest.feedback
    /// Set at launch when this iCloud account has the CloudKit Admin role, which shows Read Feedback.
    var isAdmin = false
    @ObservationIgnored private let store: FeedbackStore
    @ObservationIgnored private let showFeedback: () -> Void
    @ObservationIgnored private let readFeedback: () -> Void

    init(store: FeedbackStore, showFeedback: @escaping () -> Void, readFeedback: @escaping () -> Void) {
        self.store = store
        self.showFeedback = showFeedback
        self.readFeedback = readFeedback
        Task { isAdmin = await store.isAdmin }
    }

    /// Reading feedback, for accounts with the Admin role and the key that opens it on this Mac.
    var settingsPane: ModuleSettingsPane? {
        ModuleSettingsPane(
            title: String(localized: "Feedback"), symbol: "tray.full.fill", tint: .orange, ref: .readFeedback,
            isAdminOnly: true, isShown: { [weak self] in self?.isAdmin ?? false },
            view: { [store] in AnyView(FeedbackAdminPane(store: store)) })
    }

    var revision: AnyHashable { isAdmin }

    func contributions(for query: String) -> [Contribution] {
        var items: [LauncherItem] = [
            .command(
                .sendFeedback, id: "command:send-feedback", title: String(localized: "Send Feedback"),
                icon: .symbol("bubble.left"))
        ]
        if isAdmin {
            var read = LauncherItem.command(
                .readFeedback, id: "command:read-feedback", title: String(localized: "Read Feedback"),
                icon: .symbol("tray.full"))
            read.isAdminOnly = true
            items.append(read)
        }
        return items.map(Contribution.listed)
    }

    func actions(for item: LauncherItem) -> [ItemAction] {
        if item.id == "command:read-feedback" {
            return [
                .open(owner: .readFeedback) { [readFeedback] in
                    readFeedback()
                    return .stay
                }
            ]
        }
        return [
            .open(owner: .sendFeedback) { [showFeedback] in
                showFeedback()
                return .stay
            }
        ]
    }

    func run(command: String) {
        switch command {
        case "send-feedback": showFeedback()
        case "read-feedback" where isAdmin: readFeedback()
        default: break
        }
    }
}
