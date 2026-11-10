import KeyboardShortcuts
import WhippetCore

extension LauncherItem {
    /// A command's row: listed under Commands, ranked by use, a favorite, and showing its hotkey. `id` is what its
    /// launches and favorite were kept under before modules, such as `command:calculator`.
    static func command(
        _ ref: ModuleRef, id: String, title: String, icon: ItemIcon, subtitle: String = String(localized: "Command"),
        section: String = String(localized: "Commands"), payload: AnyHashable? = nil
    ) -> LauncherItem {
        LauncherItem(
            id: id, module: ref.module, title: title, subtitle: subtitle, icon: icon, section: section, launchKey: id,
            favoriteKey: id, refs: [ref],
            hotkey: ModuleRegistry.command(ref) != nil ? KeyboardShortcuts.Name(for: ref) : nil,
            payload: payload)
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
