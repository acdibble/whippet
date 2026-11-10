import SwiftUI

/// A pane in Settings: one of Whippet's own, or a module's, which is listed while the module is on.
enum SettingsPane: Hashable, Identifiable {
    case general
    case commands
    case shortcuts
    case usage
    case developer
    case about
    /// A module's pane, by the module's id.
    case module(String)

    static let clipboard = SettingsPane.module(ModuleManifest.clipboard.id)
    static let quicklinks = SettingsPane.module(ModuleManifest.quicklinks.id)
    static let extensions = SettingsPane.module(ModuleManifest.extensions.id)
    static let feedback = SettingsPane.module(ModuleManifest.feedback.id)

    var id: Self { self }

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .commands: String(localized: "Commands")
        case .shortcuts: String(localized: "Shortcuts")
        case .usage: String(localized: "Usage")
        case .developer: String(localized: "Developer")
        case .about: String(localized: "About")
        case .module(let id): id
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .commands: "switch.2"
        case .shortcuts: "command"
        case .usage: "chart.bar.fill"
        case .developer: "hammer.fill"
        case .about: "info.circle.fill"
        case .module: "square.fill"
        }
    }

    var tint: Color {
        switch self {
        case .commands, .shortcuts: .purple
        case .usage: .green
        default: .gray
        }
    }
}
