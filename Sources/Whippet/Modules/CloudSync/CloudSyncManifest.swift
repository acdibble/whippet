import Foundation
import WhippetCore

extension ModuleManifest {
    static let cloudSync = ModuleManifest(
        id: "cloud-sync",
        title: String(localized: "Cloud Sync"),
        summary: String(localized: "Syncs clipboard history, calculations and quicklinks across your Macs."),
        icon: "icloud",
        tint: .blue,
        features: [
            ModuleFeature(
                id: "sync", title: String(localized: "Sync with iCloud"),
                summary: String(localized: "End-to-end encrypted, set up under Settings › Cloud Sync."),
                permissions: [.iCloud(.privateDatabase)])
        ]
    )
}

extension ModuleRef {
    static let cloudSyncModule = ModuleManifest.cloudSync.ref
    static let iCloudSync = ModuleManifest.cloudSync.ref("sync")
}
