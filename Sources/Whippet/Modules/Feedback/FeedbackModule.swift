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
    /// Whether the admin check has been made for Read Feedback being on.
    @ObservationIgnored private var checksAdmin = false
    @ObservationIgnored private let store: FeedbackStore
    @ObservationIgnored private let showFeedback: () -> Void
    @ObservationIgnored private let readFeedback: () -> Void

    init(store: FeedbackStore, showFeedback: @escaping () -> Void, readFeedback: @escaping () -> Void) {
        self.store = store
        self.showFeedback = showFeedback
        self.readFeedback = readFeedback
    }

    /// Asks iCloud whether this account is an admin once Read Feedback is on, and forgets the answer when it's
    /// turned off, so nothing is asked of iCloud for a command that's off.
    func update(_ modules: ModuleSettings) {
        let isOn = modules.isEnabled(.readFeedback)
        guard isOn != checksAdmin else { return }
        checksAdmin = isOn
        guard isOn else {
            isAdmin = false
            return
        }
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

    func row(for command: ModuleRef, _ item: LauncherItem) -> LauncherItem? {
        command == .readFeedback && !isAdmin ? nil : item
    }

    func actions(for item: LauncherItem) -> [ItemAction] {
        switch item.command {
        case .sendFeedback?:
            return [
                .open(owner: .sendFeedback) { [showFeedback] in
                    showFeedback()
                    return .stay
                }
            ]
        case .readFeedback?:
            return [
                .open(owner: .readFeedback) { [readFeedback] in
                    readFeedback()
                    return .stay
                }
            ]
        default:
            return []
        }
    }
}
