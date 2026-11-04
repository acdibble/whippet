import Foundation

extension ModuleManifest {
    static let applications = ModuleManifest(
        id: "applications",
        title: String(localized: "Applications"),
        summary: String(localized: "Opens apps from the search, and with their own hotkeys."),
        icon: "square.grid.2x2",
        tint: .blue,
        dynamicRows: .apps
    )
}

extension ModuleRef {
    static let applications = ModuleManifest.applications.ref

    /// An app, keyed by its bundle identifier as its hotkey and launches are.
    static func app(_ stableID: String) -> ModuleRef {
        ModuleManifest.applications.ref("app:\(stableID)")
    }
}
