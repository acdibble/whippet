import AppKit

/// Locking, sleeping, restarting and shutting down the Mac, emptying the Trash and switching appearance.
@MainActor
final class SystemModule: LauncherModule {
    let manifest = ModuleManifest.system

    func actions(for item: LauncherItem) -> [ItemAction] {
        guard let command = SystemCommand(item.command) else { return [] }
        return [
            .command(owner: command.moduleRef) {
                // After the panel has gone, so neither a confirmation nor the system's own response is hidden behind it.
                DispatchQueue.main.async { command.confirmAndRun() }
                return .dismiss
            }
        ]
    }
}
