import SwiftUI
import WhippetCore

/// Syncing clipboard history, calculations and quicklinks across the user's Macs, end-to-end encrypted.
@MainActor
final class CloudSyncModule: LauncherModule {
    let manifest = ModuleManifest.cloudSync
    private let cloudSync: CloudSync

    init(cloudSync: CloudSync) {
        self.cloudSync = cloudSync
    }

    func update(_ modules: ModuleSettings) {
        cloudSync.isAllowed = modules.isEnabled(manifest.ref)
    }

    /// Sync with iCloud is the switch in the Cloud Sync pane.
    func externalSwitch(for feature: ModuleRef) -> Binding<Bool>? {
        feature == .iCloudSync ? Bindable(cloudSync).isEnabled : nil
    }

    var settingsPane: ModuleSettingsPane? {
        ModuleSettingsPane(title: String(localized: "Cloud Sync"), symbol: "icloud.fill", tint: .blue) { [cloudSync] in
            AnyView(CloudSyncPane(cloudSync: cloudSync))
        }
    }
}
