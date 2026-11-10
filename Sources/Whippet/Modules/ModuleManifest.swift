import Foundation
import WhippetCore

/// A module, or one of its commands or features: what Settings › Commands turns on and off, and what launcher results,
/// hotkeys and background work check before they run.
struct ModuleRef: Hashable, Sendable {
    let module: String
    /// The command or feature, unique within the module, such as `start-timer`; nil for the module itself.
    let row: String?

    init(module: String, row: String? = nil) {
        self.module = module
        self.row = row
    }

    /// The module an extension is listed as, such as `extension.com.example.hello`, from its id.
    static func `extension`(_ id: String, row: String? = nil) -> ModuleRef {
        ModuleRef(module: extensionPrefix + id, row: row)
    }

    private static let extensionPrefix = "extension."

    /// Whether it's an extension, or one of an extension's commands, rather than a built-in module.
    var isExtension: Bool {
        module.hasPrefix(Self.extensionPrefix)
    }

    /// The extension's id, for an extension or one of its commands.
    var extensionID: String? {
        isExtension ? String(module.dropFirst(Self.extensionPrefix.count)) : nil
    }

    /// The module this command or feature belongs to, or the module itself.
    var moduleRef: ModuleRef {
        ModuleRef(module: module)
    }

    /// Where its switch is kept in user defaults, such as `module.timers.enabled` or
    /// `module.timers.start-timer.enabled`.
    var defaultsKey: String {
        row.map { "module.\(module).\($0).enabled" } ?? "module.\(module).enabled"
    }

    /// The name its hotkey is kept under, for a command that had none before modules: `command.<module>.<command>`.
    var hotkeyName: String {
        "command.\(module).\(row ?? "")"
    }
}

/// What a module adds to Whippet and what each part of it needs, so the user can see it in Settings › Commands and turn
/// off what they don't want. Built-in modules declare theirs beside their code, in `Modules/<Name>/`.
struct ModuleManifest: Identifiable {
    let id: String
    let title: String
    let summary: String
    /// An SF Symbol.
    let icon: String
    /// The colour of its icon's tile in Settings.
    var tint = ModuleTint.gray
    var commands: [ModuleCommand] = []
    var features: [ModuleFeature] = []
    /// A beta module starts off, and is turned on under Settings › General › Beta Features.
    var stage = ModuleStage.stable
    /// Listed in Settings › Commands by what it holds rather than as itself, as Extensions is by each extension.
    var isListedByItsParts = false

    var ref: ModuleRef {
        ModuleRef(module: id)
    }

    /// The switch a beta module is turned on with.
    var flag: FeatureFlag? {
        FeatureFlag(self)
    }

    /// Everything its commands and features need, gathered.
    var permissions: [Permission] {
        (commands.flatMap(\.permissions) + features.flatMap(\.permissions)).combined
    }

    /// A module can't be turned off when one of its commands can't, as for Settings.
    var isRequired: Bool {
        commands.contains(where: \.isRequired)
    }

    func ref(_ row: String) -> ModuleRef {
        ModuleRef(module: id, row: row)
    }

    func command(_ id: String) -> ModuleCommand? {
        commands.first { $0.id == id }
    }
}

/// How finished a module is.
enum ModuleStage: Equatable {
    case stable
    /// Still being tried out, with a sentence for Beta Features saying what it does.
    case beta(summary: String)
}

/// The colour of a module's icon tile in Settings › Commands, as System Settings colours its own panes.
enum ModuleTint {
    case blue, brown, cyan, gray, green, indigo, mint, orange, pink, purple, red, teal
}

/// A command a module adds to the search, which can also have a hotkey.
struct ModuleCommand: Identifiable {
    let id: String
    let title: String
    /// An SF Symbol.
    let icon: String
    var permissions: [Permission] = []
    /// The hotkey name from before modules, such as `command.calculator`, so a hotkey set then still works.
    var legacyHotkey: String?
    /// The id of its row from before modules, where that isn't `command:<id>`, such as `command:system.sleep`, so
    /// its launches and its place in Favorites are kept.
    var legacyItemID: String?
    /// Settings and Quit, which stay on so Settings can always be reached from the search.
    var isRequired = false
    /// Listed only for accounts with the CloudKit Admin role, as Read Feedback is in the search.
    var isAdminOnly = false
}

/// Something a module does without being a command, such as converting currencies or fetching link previews.
struct ModuleFeature: Identifiable {
    let id: String
    let title: String
    let summary: String
    var permissions: [Permission] = []
}

/// Something running that keeps part of a module on until it ends, such as a timer counting down: turning Timers off
/// then would leave it running with no way to stop it.
struct ActivityLock: Hashable {
    let module: String
    /// The commands and features needed to manage what's running. The module itself is always locked.
    let rows: Set<String>
    /// Shown beside the switch, such as “A timer or stopwatch is running”.
    let reason: String

    func locks(_ ref: ModuleRef) -> Bool {
        guard ref.module == module else { return false }
        return ref.row.map(rows.contains) ?? true
    }
}

/// Every module's manifest, in the order Settings › Commands lists them, and the one list of what Whippet is made of:
/// the launcher refuses to start with modules that don't match it. Each extension is listed after them.
enum ModuleRegistry {
    static let all: [ModuleManifest] = [
        .applications, .calculator, .clipboard, .captureText, .quicklinks, .timers, .caffeinate, .system,
        .windowManagement, .translation, .cloudSync, .feedback, .updates, .whippet, .extensions,
    ]

    /// The modules Settings › Commands lists as themselves, which is all but Extensions.
    static var listed: [ModuleManifest] {
        all.filter { !$0.isListedByItsParts }
    }

    static func manifest(_ id: String) -> ModuleManifest? {
        all.first { $0.id == id }
    }

    static func command(_ ref: ModuleRef) -> ModuleCommand? {
        ref.row.flatMap { manifest(ref.module)?.command($0) }
    }

    /// What a command or feature declares in its module's manifest, or, for the module itself, what all of them do.
    static func permissions(of ref: ModuleRef) -> [Permission] {
        guard let manifest = manifest(ref.module) else { return [] }
        guard let row = ref.row else { return manifest.permissions }
        return manifest.command(row)?.permissions ?? manifest.features.first { $0.id == row }?.permissions ?? []
    }

    /// Whether a command or feature declares `permission` in its module's manifest, so `PermissionGate` lets it be used.
    /// For the module itself, whether any of its commands or features does.
    static func declares(_ permission: Permission, for ref: ModuleRef) -> Bool {
        permissions(of: ref).covers(permission)
    }

    /// The name a command's hotkey is kept under: its name from before modules, or one made from its module and id.
    static func hotkeyName(for ref: ModuleRef) -> String {
        command(ref)?.legacyHotkey ?? ref.hotkeyName
    }
}
