import AppKit

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
