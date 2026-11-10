import Foundation
import WhippetCore

extension ModuleManifest {
    /// Sparkle reads the appcast attached to the newest GitHub release, whose files GitHub serves from its own hosts.
    private static let updateHosts = ["github.com", "*.githubusercontent.com"]

    static let updates = ModuleManifest(
        id: "updates",
        title: String(localized: "Updates"),
        summary: String(localized: "Checks for and installs new versions of Whippet."),
        icon: "arrow.down.circle",
        tint: .green,
        commands: [
            ModuleCommand(
                id: "check-for-updates", title: String(localized: "Check for Updates"), icon: "arrow.down.circle",
                permissions: [.network(updateHosts)])
        ],
        features: [
            ModuleFeature(
                id: "automatic-checks", title: String(localized: "Check for Updates Automatically"),
                summary: String(localized: "Looks for a new version once a day."),
                permissions: [.network(updateHosts)])
        ]
    )
}

extension ModuleRef {
    static let updatesModule = ModuleManifest.updates.ref
    static let checkForUpdates = ModuleManifest.updates.ref("check-for-updates")
    static let automaticUpdateChecks = ModuleManifest.updates.ref("automatic-checks")
}
