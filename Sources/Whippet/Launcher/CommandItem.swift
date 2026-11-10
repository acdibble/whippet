import KeyboardShortcuts
import WhippetCore

extension LauncherItem {
    /// A command's row, made from its manifest so the search and Settings › Commands always agree: listed under
    /// Commands, ranked by use, a favorite, and showing its hotkey. The host makes one for every command, and the
    /// module changes what differs in `row(for:_:)`.
    static func command(_ command: ModuleCommand, of manifest: ModuleManifest) -> LauncherItem {
        let ref = manifest.ref(command.id)
        let id = command.legacyItemID ?? "command:\(command.id)"
        return LauncherItem(
            id: id, module: manifest.id, title: command.title, subtitle: String(localized: "Command"),
            icon: .symbol(command.icon), launchKey: id, favoriteKey: id, refs: [ref],
            hotkey: KeyboardShortcuts.Name(for: ref), isAdminOnly: command.isAdminOnly, command: ref)
    }
}

extension ItemAction {
    /// A command's action, recorded as a launch, titled Open Command for one that opens something and Run Command for
    /// one that acts straight away.
    static func command(
        _ title: String = String(localized: "Run Command"), id: String = "command.run", owner: ModuleRef,
        perform: @escaping @MainActor () -> ActionOutcome
    ) -> ItemAction {
        ItemAction(id: id, title: title, icon: "return", owner: owner, recordsLaunch: true, perform: perform)
    }

    static func open(owner: ModuleRef, perform: @escaping @MainActor () -> ActionOutcome) -> ItemAction {
        command(String(localized: "Open Command"), id: "command.open", owner: owner, perform: perform)
    }
}
