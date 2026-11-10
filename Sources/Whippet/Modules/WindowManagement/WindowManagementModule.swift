import AppKit

/// Moving and resizing the front window, into halves, thirds and the like.
@MainActor
final class WindowManagementModule: LauncherModule {
    let manifest = ModuleManifest.windowManagement
    private weak var host: (any ModuleHost)?

    func attach(to host: any ModuleHost) {
        self.host = host
    }

    func row(for command: ModuleRef, _ item: LauncherItem) -> LauncherItem? {
        var item = item
        item.subtitle = String(localized: "Window")
        item.section = String(localized: "Window")
        // Center Third's symbol is Whippet's own, in the asset catalog.
        if WindowCommand(command) == .centerThird {
            item.icon = .assetSymbol(WindowCommand.centerThird.symbol)
        }
        return item
    }

    func actions(for item: LauncherItem) -> [ItemAction] {
        guard let command = WindowCommand(item.command), let host else { return [] }
        return [
            .command(String(localized: "Move Window"), owner: command.moduleRef) {
                // The app the panel opened over, or Whippet itself over one of its own windows.
                let app = host.targetWindow != nil ? NSRunningApplication.current : host.targetApp
                DispatchQueue.main.async { WindowManager.perform(command, in: app) }
                return .dismiss
            }
        ]
    }

    /// A hotkey moves the window of the app in front, with no panel to have opened over one.
    func runHotkey(for command: ModuleRef) -> Bool {
        guard let command = WindowCommand(command) else { return false }
        WindowManager.perform(command, in: NSWorkspace.shared.frontmostApplication)
        return true
    }
}
