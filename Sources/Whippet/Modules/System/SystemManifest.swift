import Foundation
import WhippetCore

extension ModuleManifest {
    static let system = ModuleManifest(
        id: "system",
        title: String(localized: "System"),
        summary: String(localized: "Locks, sleeps, restarts or shuts down this Mac, and more."),
        icon: "desktopcomputer",
        tint: .gray,
        commands: SystemCommand.allCases.map { command in
            ModuleCommand(
                id: command.rawValue, title: command.title, icon: command.symbol, permissions: command.permissions,
                legacyItemID: "command:system.\(command.rawValue)")
        }
    )
}

extension SystemCommand {
    /// Restarting, shutting down and switching appearance go through System Events, and emptying the Trash through
    /// Finder, so each asks to control that app.
    var permissions: [Permission] {
        switch self {
        case .restart, .shutDown, .toggleDarkMode: [.automation([.systemEvents])]
        case .emptyTrash: [.automation([.finder])]
        case .lockScreen, .sleep: []
        }
    }

    var moduleRef: ModuleRef {
        ModuleManifest.system.ref(rawValue)
    }

    /// The command a row or hotkey of the System module is for.
    init?(_ ref: ModuleRef?) {
        guard let row = ref?.row, ref?.module == ModuleManifest.system.id else { return nil }
        self.init(rawValue: row)
    }
}

extension ModuleRef {
    static let systemModule = ModuleManifest.system.ref
}
