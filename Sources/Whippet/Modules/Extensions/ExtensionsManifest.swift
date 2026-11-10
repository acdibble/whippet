import Foundation

extension ModuleManifest {
    /// Every installed extension, which Settings › Commands lists as a module each, from its own manifest.
    static let extensions = ModuleManifest(
        id: "extensions",
        title: String(localized: "Extensions"),
        summary: String(localized: "Commands written in JavaScript with React, installed in Settings › Extensions."),
        icon: "puzzlepiece.extension",
        tint: .purple,
        stage: .beta(
            summary: String(localized: "Commands written in JavaScript with React, installed in Settings › Extensions.")
        )
    )
}
