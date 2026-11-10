import AppKit

/// Locking, sleeping, restarting and shutting down the Mac, emptying the Trash and switching appearance.
@MainActor
final class SystemModule: LauncherModule {
    let manifest = ModuleManifest.system

    func contributions(for query: String) -> [Contribution] {
        SystemCommand.allCases.map { command in
            .listed(
                .command(
                    command.moduleRef, id: "command:system.\(command.rawValue)", title: command.title,
                    icon: .symbol(command.symbol), payload: command))
        }
    }

    func actions(for item: LauncherItem) -> [ItemAction] {
        guard let command = item.payload(as: SystemCommand.self) else { return [] }
        return [
            .command(owner: command.moduleRef) {
                // After the panel has gone, so neither a confirmation nor the system's own response is hidden behind it.
                DispatchQueue.main.async { command.confirmAndRun() }
                return .dismiss
            }
        ]
    }

    func run(command: String) {
        SystemCommand(rawValue: command)?.confirmAndRun()
    }
}
