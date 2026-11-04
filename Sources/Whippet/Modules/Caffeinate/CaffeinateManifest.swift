import Foundation

extension ModuleManifest {
    static let caffeinate = ModuleManifest(
        id: "caffeinate",
        title: String(localized: "Caffeinate"),
        summary: String(localized: "Keeps this Mac awake, for a while or until you stop it."),
        icon: "cup.and.heat.waves.fill",
        tint: .brown,
        commands: [
            ModuleCommand(
                id: "caffeinate", title: String(localized: "Caffeinate"), icon: "cup.and.heat.waves.fill",
                legacyHotkey: "command.caffeinate"),
            ModuleCommand(
                id: "caffeinate-for", title: String(localized: "Caffeinate for…"), icon: "cup.and.heat.waves.fill"),
            ModuleCommand(id: "decaffeinate", title: String(localized: "Decaffeinate"), icon: "cup.and.heat.waves"),
            ModuleCommand(
                id: "menu-bar", title: String(localized: "Show or Hide Caffeinate in Menu Bar"),
                icon: "menubar.rectangle"),
        ]
    )
}

extension ModuleRef {
    static let caffeinateModule = ModuleManifest.caffeinate.ref
    static let caffeinate = ModuleManifest.caffeinate.ref("caffeinate")
    static let caffeinateFor = ModuleManifest.caffeinate.ref("caffeinate-for")
    static let decaffeinate = ModuleManifest.caffeinate.ref("decaffeinate")
    static let caffeinateMenuBar = ModuleManifest.caffeinate.ref("menu-bar")
}
