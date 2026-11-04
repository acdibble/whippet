import Foundation
import WhippetCore

extension ModuleManifest {
    static let windowManagement = ModuleManifest(
        id: "window",
        title: String(localized: "Window Management"),
        summary: String(localized: "Moves and resizes the front window."),
        icon: "macwindow",
        tint: .cyan,
        commands: WindowCommand.allCases.map { command in
            ModuleCommand(
                id: command.rawValue, title: command.title, icon: command.symbol,
                permissions: [.accessibility(.windows)], legacyHotkey: "window.\(command.rawValue)")
        }
    )
}

extension WindowCommand {
    var moduleRef: ModuleRef {
        ModuleManifest.windowManagement.ref(rawValue)
    }
}

extension ModuleRef {
    static let windowModule = ModuleManifest.windowManagement.ref
}
