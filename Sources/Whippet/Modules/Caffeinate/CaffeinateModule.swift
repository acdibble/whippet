import AppKit
import Observation

/// Keeping the Mac awake, for a while or until it's stopped, with an item in the menu bar.
@MainActor
final class CaffeinateModule: LauncherModule {
    let manifest = ModuleManifest.caffeinate
    let caffeine: Caffeine
    private var statusItem: CaffeineStatusItem?
    private weak var host: (any ModuleHost)?

    init(caffeine: Caffeine) {
        self.caffeine = caffeine
    }

    func attach(to host: any ModuleHost) {
        self.host = host
        statusItem = CaffeineStatusItem(caffeine: caffeine) { [weak host, manifest] in
            host?.modules.isEnabled(manifest.ref) ?? true
        }
    }

    var activity: [ActivityLock] {
        guard caffeine.isActive else { return [] }
        return [
            ActivityLock(
                module: manifest.id, rows: ["decaffeinate"], reason: String(localized: "This Mac is being kept awake"))
        ]
    }

    var revision: AnyHashable {
        [caffeine.isActive, caffeine.showsInMenuBar, caffeine.endsAt as AnyHashable]
    }

    func contributions(for query: String) -> [Contribution] {
        let awake = String(localized: "Keep this Mac awake")
        var items: [LauncherItem] = [
            .command(
                .caffeinate, id: "command:caffeinate", title: String(localized: "Caffeinate"),
                icon: .symbol("cup.and.heat.waves.fill"), subtitle: awake),
            .command(
                .caffeinateFor, id: "command:caffeinate-for", title: String(localized: "Caffeinate for…"),
                icon: .symbol("cup.and.heat.waves.fill"), subtitle: awake),
        ]
        if caffeine.isActive {
            items.append(
                .command(
                    .decaffeinate, id: "command:decaffeinate", title: String(localized: "Decaffeinate"),
                    icon: .symbol("cup.and.heat.waves"), subtitle: caffeine.untilDescription))
        }
        items.append(
            .command(
                .caffeinateMenuBar, id: "command:caffeinate-menu-bar",
                title: caffeine.showsInMenuBar
                    ? String(localized: "Hide Caffeinate in Menu Bar")
                    : String(localized: "Show Caffeinate in Menu Bar"),
                icon: .symbol("menubar.rectangle")))
        return items.map(Contribution.listed)
    }

    func actions(for item: LauncherItem) -> [ItemAction] {
        switch item.id {
        case "command:caffeinate":
            return [
                .command(owner: .caffeinate) { [caffeine] in
                    caffeine.start(seconds: nil)
                    return .dismiss
                }
            ]
        case "command:caffeinate-for":
            return [
                ItemAction(
                    id: "caffeinate.choose", title: String(localized: "Choose Duration"), icon: "return",
                    runsOnTab: true, owner: .caffeinateFor
                ) { [weak self] in
                    guard let self else { return .stay }
                    return .input(durationRequest)
                }
            ]
        case "command:decaffeinate":
            return [
                .command(owner: .decaffeinate) { [caffeine] in
                    caffeine.stop()
                    return .dismiss
                }
            ]
        default:
            return [
                .command(owner: .caffeinateMenuBar) { [weak self] in
                    self?.toggleMenuBar()
                    return .dismiss
                }
            ]
        }
    }

    /// The hours, minutes and seconds Caffeinate for… asks for. Blank fields count as zero, and a zero or invalid
    /// duration beeps.
    private var durationRequest: InputRequest {
        InputRequest(
            label: String(localized: "Caffeinate for…"),
            fields: [
                .init(placeholder: String(localized: "Hours"), isNarrow: true),
                .init(placeholder: String(localized: "Minutes"), isNarrow: true),
                .init(placeholder: String(localized: "Seconds"), isNarrow: true),
            ],
            submitTitle: String(localized: "Caffeinate"), launchKey: "command:caffeinate-for"
        ) { [caffeine] fields in
            guard let seconds = CaffeineDuration.seconds(hours: fields[0], minutes: fields[1], seconds: fields[2])
            else { return .fail() }
            caffeine.start(seconds: seconds)
            return .dismiss
        }
    }

    private func toggleMenuBar() {
        caffeine.showsInMenuBar.toggle()
        Toast.shared.show(
            caffeine.showsInMenuBar
                ? String(localized: "Caffeinate shown in menu bar")
                : String(localized: "Caffeinate hidden from menu bar"),
            symbol: "menubar.rectangle")
    }

    func run(command: String) {
        switch command {
        case "caffeinate": caffeine.toggle()
        case "caffeinate-for": host?.openDirectly { host?.beginInput(durationRequest) }
        case "decaffeinate" where caffeine.isActive: caffeine.stop()
        case "menu-bar": toggleMenuBar()
        default: break
        }
    }
}
