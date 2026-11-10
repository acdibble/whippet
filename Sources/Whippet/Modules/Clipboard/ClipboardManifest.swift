import Foundation
import WhippetCore

extension ModuleManifest {
    static let clipboard = ModuleManifest(
        id: "clipboard",
        title: String(localized: "Clipboard History"),
        summary: String(localized: "Keeps what you copy, to search and paste again."),
        icon: "list.clipboard",
        tint: .teal,
        commands: [
            ModuleCommand(
                id: "clipboard-history", title: String(localized: "Clipboard History"), icon: "list.clipboard",
                permissions: [.accessibility(.paste)], legacyHotkey: "command.clipboardHistory")
        ],
        features: [
            ModuleFeature(
                id: "recording", title: String(localized: "Save What You Copy"),
                summary: String(localized: "Adds what you copy, in any app, to clipboard history."),
                permissions: [.clipboardRead]),
            ModuleFeature(
                id: "link-previews", title: String(localized: "Link Previews"),
                summary: String(localized: "Fetches the title and preview image of links you copy."),
                permissions: [.network(["*"])]),
            ModuleFeature(
                id: "search-fallback", title: String(localized: "Search Clipboard History from the Search Bar"),
                summary: String(localized: "Offered for anything you type, under “Use … with”.")),
        ]
    )
}

extension ModuleRef {
    static let clipboardModule = ModuleManifest.clipboard.ref
    static let clipboardHistory = ModuleManifest.clipboard.ref("clipboard-history")
    static let clipboardRecording = ModuleManifest.clipboard.ref("recording")
    static let linkPreviews = ModuleManifest.clipboard.ref("link-previews")
    static let clipboardSearchFallback = ModuleManifest.clipboard.ref("search-fallback")
}
