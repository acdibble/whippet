import Foundation
import WhippetCore

extension ModuleManifest {
    static let translation = ModuleManifest(
        id: "translation",
        title: String(localized: "Translation"),
        summary: String(localized: "Translates text on this Mac."),
        icon: "translate",
        tint: .blue,
        commands: [
            ModuleCommand(
                id: "translate", title: String(localized: "Translate"), icon: "translate",
                permissions: [.accessibility(.paste), .systemDownloads], legacyHotkey: "command.translate")
        ],
        features: [
            ModuleFeature(
                id: "card", title: String(localized: "Translations in the Search Bar"),
                summary: String(localized: "Typing text and a language, such as “hello in french”, translates it."),
                permissions: [.accessibility(.paste), .systemDownloads]),
            ModuleFeature(
                id: "fallback", title: String(localized: "Translate from the Search Bar"),
                summary: String(localized: "Offered for anything you type, under “Use … with”.")),
        ],
        stage: .beta(
            summary: String(
                localized: "Translate text on this Mac by typing the language after it, or with the Translate command.")
        )
    )
}

extension ModuleRef {
    static let translationModule = ModuleManifest.translation.ref
    static let translate = ModuleManifest.translation.ref("translate")
    static let translationCard = ModuleManifest.translation.ref("card")
    static let translationFallback = ModuleManifest.translation.ref("fallback")
}
