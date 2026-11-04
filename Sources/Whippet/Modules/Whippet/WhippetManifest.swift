import Foundation

extension ModuleManifest {
    static let whippet = ModuleManifest(
        id: "whippet",
        title: String(localized: "Whippet"),
        summary: String(localized: "Settings, what's new, and quitting."),
        icon: "gearshape",
        tint: .gray,
        commands: [
            ModuleCommand(
                id: "settings", title: String(localized: "Settings"), icon: "gearshape",
                legacyHotkey: "command.settings", isRequired: true),
            ModuleCommand(id: "changelog", title: String(localized: "Changelog"), icon: "list.bullet.rectangle"),
            ModuleCommand(
                id: "share-whippet", title: String(localized: "Share Whippet with a Friend"),
                icon: "square.and.arrow.up"),
            ModuleCommand(id: "quit", title: String(localized: "Quit Whippet"), icon: "power", isRequired: true),
        ],
        features: [
            ModuleFeature(
                id: "whats-new", title: String(localized: "What's New After Updates"),
                summary: String(localized: "Lists what changed at the top of the search for a week after an update."))
        ]
    )
}

extension ModuleRef {
    static let whippetModule = ModuleManifest.whippet.ref
    static let settings = ModuleManifest.whippet.ref("settings")
    static let changelog = ModuleManifest.whippet.ref("changelog")
    static let shareWhippet = ModuleManifest.whippet.ref("share-whippet")
    static let quit = ModuleManifest.whippet.ref("quit")
    static let whatsNew = ModuleManifest.whippet.ref("whats-new")
}
