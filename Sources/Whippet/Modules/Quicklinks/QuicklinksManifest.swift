import Foundation

extension ModuleManifest {
    static let quicklinks = ModuleManifest(
        id: "quicklinks",
        title: String(localized: "Quicklinks"),
        summary: String(localized: "Opens links and searches you save, with text you type."),
        icon: "link",
        tint: .indigo,
        commands: [
            ModuleCommand(id: "create-quicklink", title: String(localized: "Create Quicklink"), icon: "link.badge.plus")
        ],
        features: [
            ModuleFeature(
                id: "fallbacks", title: String(localized: "Search with Quicklinks from the Search Bar"),
                summary: String(localized: "Quicklinks that take text are offered for anything you type."))
        ],
        dynamicRows: .quicklinks
    )
}

extension ModuleRef {
    static let quicklinksModule = ModuleManifest.quicklinks.ref
    static let createQuicklink = ModuleManifest.quicklinks.ref("create-quicklink")
    static let quicklinkFallbacks = ModuleManifest.quicklinks.ref("fallbacks")

    /// A quicklink, keyed by UUID as its hotkey is.
    static func quicklink(_ uuid: String) -> ModuleRef {
        ModuleManifest.quicklinks.ref("quicklink:\(uuid)")
    }
}
