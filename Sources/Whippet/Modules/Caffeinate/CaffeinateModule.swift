import AppKit
import Observation

/// Keeping the Mac awake, for a while or until it's stopped, with an item in the menu bar.
@MainActor
final class CaffeinateModule: LauncherModule {
    let manifest = ModuleManifest.caffeinate
    let caffeine: Caffeine
    private var statusItem: CaffeineStatusItem?

    init(caffeine: Caffeine) {
        self.caffeine = caffeine
    }

    func attach(to host: any ModuleHost) {
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

    func row(for command: ModuleRef, _ item: LauncherItem) -> LauncherItem? {
        var item = item
        switch command {
        case .caffeinate, .caffeinateFor:
            item.subtitle = String(localized: "Keep this Mac awake")
        case .decaffeinate:
            guard caffeine.isActive else { return nil }
            item.subtitle = caffeine.untilDescription
        case .caffeinateMenuBar:
            item.title =
                caffeine.showsInMenuBar
                ? String(localized: "Hide Caffeinate in Menu Bar") : String(localized: "Show Caffeinate in Menu Bar")
        default:
            break
        }
        return item
    }

    func actions(for item: LauncherItem) -> [ItemAction] {
        switch item.command {
        case .caffeinate?:
            return [
                .command(owner: .caffeinate) { [caffeine] in
                    caffeine.start(seconds: nil)
                    return .dismiss
                }
            ]
        case .caffeinateFor?:
            return [
                ItemAction(
                    id: "caffeinate.choose", title: String(localized: "Choose Duration"), icon: "return",
                    runsOnTab: true, owner: .caffeinateFor
                ) { [weak self] in
                    guard let self else { return .stay }
                    return .input(durationRequest)
                }
            ]
        case .decaffeinate?:
            return [
                .command(owner: .decaffeinate) { [caffeine] in
                    caffeine.stop()
                    return .dismiss
                }
            ]
        case .caffeinateMenuBar?:
            return [
                .command(owner: .caffeinateMenuBar) { [weak self] in
                    self?.toggleMenuBar()
                    return .dismiss
                }
            ]
        default:
            return []
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

    /// Caffeinate's hotkey stops it too, where the command in the search only starts it, with Decaffeinate beside it.
    func runHotkey(for command: ModuleRef) -> Bool {
        guard command == .caffeinate else { return false }
        caffeine.toggle()
        return true
    }
}
