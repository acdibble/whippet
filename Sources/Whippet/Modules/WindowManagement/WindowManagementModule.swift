import AppKit

/// Moving and resizing the front window, into halves, thirds and the like.
@MainActor
final class WindowManagementModule: LauncherModule {
    let manifest = ModuleManifest.windowManagement
    private weak var host: (any ModuleHost)?

    func attach(to host: any ModuleHost) {
        self.host = host
    }

    func contributions(for query: String) -> [Contribution] {
        WindowCommand.allCases.map { command in
            .listed(
                .command(
                    command.moduleRef, id: "command:window.\(command.rawValue)", title: command.title,
                    // Center Third's symbol is Whippet's own, in the asset catalog.
                    icon: command == .centerThird ? .assetSymbol(command.symbol) : .symbol(command.symbol),
                    subtitle: String(localized: "Window"), section: String(localized: "Window"), payload: command))
        }
    }

    func actions(for item: LauncherItem) -> [ItemAction] {
        guard let command = item.payload(as: WindowCommand.self), let host else { return [] }
        return [
            .command(String(localized: "Move Window"), owner: command.moduleRef) {
                // The app the panel opened over, or Whippet itself over one of its own windows.
                let app = host.targetWindow != nil ? NSRunningApplication.current : host.targetApp
                DispatchQueue.main.async { WindowManager.perform(command, in: app) }
                return .dismiss
            }
        ]
    }

    func run(command: String) {
        guard let command = WindowCommand(rawValue: command) else { return }
        WindowManager.perform(command, in: NSWorkspace.shared.frontmostApplication)
    }
}
