import AppKit
import SwiftUI

/// Checking for and installing new versions, with Sparkle.
@MainActor
final class UpdatesModule: LauncherModule {
    let manifest = ModuleManifest.updates
    private let updater: Updater

    init(updater: Updater) {
        self.updater = updater
    }

    func update(_ modules: ModuleSettings) {
        updater.isAllowed = modules.isEnabled(manifest.ref)
    }

    /// Checking automatically is Sparkle's own setting, also switched in Settings › General.
    func externalSwitch(for feature: ModuleRef) -> Binding<Bool>? {
        feature == .automaticUpdateChecks ? Bindable(updater).automaticallyChecksForUpdates : nil
    }

    var generalSettings: GeneralSettings? {
        GeneralSettings(section: { [updater] in AnyView(UpdatesSettings(updater: updater)) })
    }

    func actions(for item: LauncherItem) -> [ItemAction] {
        [
            .command(owner: .checkForUpdates) { [updater] in
                // Once the panel has closed, so Sparkle's window comes to the front.
                DispatchQueue.main.async { updater.checkForUpdates() }
                return .dismiss
            }
        ]
    }
}

/// Updates in Settings › General.
private struct UpdatesSettings: View {
    @Bindable var updater: Updater

    var body: some View {
        Section("Updates") {
            Toggle("Check for Updates Automatically", isOn: $updater.automaticallyChecksForUpdates)
            LabeledContent("Check for Updates") {
                Button("Check Now") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
        }
    }
}
