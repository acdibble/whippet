import AppKit
import SwiftUI
import WhippetCore

/// Timers and stopwatches: started from the search, typed as a duration such as `25m tea`, managed in their own
/// screens and from the menu bar, and announced with a notification when a timer finishes.
@MainActor
final class TimersModule: LauncherModule {
    let manifest = ModuleManifest.timers
    let timers: Timers
    private var statusItem: TimersStatusItem?
    private weak var host: (any ModuleHost)?

    init(timers: Timers) {
        self.timers = timers
    }

    /// What a timers row stands for.
    enum Row: Hashable {
        case running(TimerItem)
        case ringing(TimerItem)
        case preset(TimerPreset)
        /// A timer typed into the search bar, such as `25m tea`.
        case typed(seconds: Int, name: String?)
    }

    func attach(to host: any ModuleHost) {
        self.host = host
        // Timers move between sections as they finish and stop, so a selected one is found again by its ID.
        timers.onChange = { [weak host] in host?.keepSelection() }
        let item = TimersStatusItem(timers: timers) { [weak host, manifest] in
            host?.modules.isEnabled(manifest.ref) ?? true
        }
        item.onStartTimer = { [weak host] in host?.runCommand(.startTimer) }
        item.onStartStopwatch = { [weak host] in host?.runCommand(.startStopwatch) }
        item.onOpenTimers = { [weak host] in host?.runCommand(.timers) }
        item.onCopyTime = { [weak self] timer in _ = self?.copyTime(of: timer) }
        item.onOpenStopwatch = { [weak self] id in
            guard let self, let host = self.host else { return }
            host.openDirectly { host.push(StopwatchScreen(module: self, showing: id)) }
        }
        item.onRename = { [weak self] timer in
            guard let self, let host = self.host else { return }
            host.openDirectly { host.beginInput(self.renameRequest(for: timer)) }
        }
        statusItem = item
        timers.start()
    }

    var activity: [ActivityLock] {
        guard timers.hasAny else { return [] }
        return [
            ActivityLock(
                module: manifest.id, rows: ["timers", "stopwatch"],
                reason: String(localized: "A timer or stopwatch is running"))
        ]
    }

    var revision: AnyHashable {
        [AnyHashable(timers.items), AnyHashable(timers.ringing), AnyHashable(timers.presets)]
    }

    // MARK: - The main search

    func contributions(for query: String) -> [Contribution] {
        var contributions: [Contribution] = []
        let section = String(localized: "Timers")
        for item in timers.ringing {
            contributions.append(.top(row(.ringing(item)), section: section, rank: 1))
        }
        for item in timers.items {
            contributions.append(.top(row(.running(item)), section: section, rank: 1))
        }
        contributions += timers.presets.map { .listed(row(.preset($0))) }
        if !query.isEmpty, let typed = TimerDuration.parse(query) {
            contributions.append(.leading(row(.typed(seconds: typed.seconds, name: typed.name))))
        }
        return contributions
    }

    func row(_ row: Row) -> LauncherItem {
        let module = manifest.id
        switch row {
        case .running(let item):
            let symbol = item.isPaused ? "pause.circle" : item.kind == .timer ? "timer" : "stopwatch"
            return LauncherItem(
                id: "timer:\(item.id)", module: module, title: item.name,
                subtitle: item.kind == .timer ? String(localized: "Timer") : String(localized: "Stopwatch"),
                icon: .symbol(symbol), refs: [.timersModule], selectionKey: "timer:\(item.id)", payload: row)
        case .ringing(let item):
            return LauncherItem(
                id: "ringing:\(item.id)", module: module, title: item.name, subtitle: String(localized: "Done"),
                icon: .symbol("bell.and.waves.left.and.right"), refs: [.timersModule],
                selectionKey: "timer:\(item.id)", payload: row)
        case .preset(let preset):
            let title =
                preset.name.map { "\($0) · \(TimerNaming.duration(TimeInterval(preset.seconds)))" }
                ?? TimerNaming.defaultTimerName(seconds: preset.seconds)
            return LauncherItem(
                id: preset.launchKey, module: module, title: title, subtitle: String(localized: "Timer"),
                icon: .symbol("timer"), section: String(localized: "Recent Timers"), launchKey: preset.launchKey,
                favoriteKey: preset.launchKey, refs: [.timersModule], payload: row)
        case .typed(let seconds, let name):
            let duration = TimerNaming.duration(TimeInterval(seconds))
            return LauncherItem(
                id: "timer:start", module: module,
                title: name.map { String(localized: "Start “\($0)” for \(duration)") }
                    ?? String(localized: "Start Timer for \(duration)"),
                subtitle: String(localized: "Timer"), icon: .symbol("timer"),
                // Counted as using the timer it starts, which then ranks among Recent Timers.
                launchKey: TimerPreset(name: name, seconds: seconds).launchKey, refs: [.typedTimers], payload: row)
        }
    }

    func rowView(for item: LauncherItem, isSelected: Bool) -> AnyView? {
        guard case .running(let timer)? = item.payload(as: Row.self) else { return nil }
        return AnyView(ResultRow(item: item, isSelected: isSelected) { TimerCountdown(item: timer) })
    }

    func actions(for item: LauncherItem) -> [ItemAction] {
        guard let host else { return [] }
        if let command = item.command {
            return commandActions(command, launchKey: item.id, host: host)
        }
        guard let row = item.payload(as: Row.self) else { return [] }
        switch row {
        case .running(let timer):
            let open =
                timer.kind == .stopwatch
                ? ItemAction(id: "timers.open-stopwatch", title: String(localized: "Open Stopwatch"), icon: "return") {
                    [weak self] in
                    self.map { .push(StopwatchScreen(module: $0, showing: timer.id)) } ?? .stay
                }
                : ItemAction(id: "timers.open-timers", title: String(localized: "Open Timers"), icon: "return") {
                    [weak self] in
                    self.map { .push(TimersScreen(module: $0, selecting: timer.id)) } ?? .stay
                }
            return [open] + timerActions(for: timer, inScreen: false)
        case .ringing(let timer):
            return [
                ItemAction(id: "timers.stop", title: String(localized: "Stop"), icon: "return") { [timers] in
                    timers.stop(timer.id)
                    return .dismiss
                },
                ItemAction(id: "timers.snooze", title: String(localized: "Snooze"), icon: "zzz") { [timers] in
                    timers.snooze(timer.id)
                    return .dismiss
                },
            ]
        case .preset(let preset):
            return [
                ItemAction(
                    id: "timers.start", title: String(localized: "Start Timer"), icon: "return",
                    recordsLaunch: true
                ) { [timers] in
                    _ = timers.startTimer(seconds: preset.seconds, name: preset.name)
                    return .dismiss
                },
                forget(preset),
            ]
        case .typed(let seconds, let name):
            var actions = [
                ItemAction(
                    id: "timers.start", title: String(localized: "Start Timer"), icon: "return",
                    owner: .typedTimers, recordsLaunch: true
                ) { [timers] in
                    _ = timers.startTimer(seconds: seconds, name: name)
                    return .dismiss
                }
            ]
            if name == nil {
                actions.append(
                    ItemAction(
                        id: "timers.name", title: String(localized: "Name…"), icon: "pencil", runsOnTab: true,
                        owner: .typedTimers
                    ) { [weak self] in
                        self.map { .input($0.nameRequest(seconds: seconds, inScreen: false)) } ?? .stay
                    })
            }
            return actions
        }
    }

    private func commandActions(_ command: ModuleRef, launchKey id: String, host: any ModuleHost) -> [ItemAction] {
        switch command {
        case .startTimer:
            return [
                ItemAction(
                    id: "timers.enter-duration", title: String(localized: "Enter Duration"), icon: "return",
                    runsOnTab: true, owner: .startTimer
                ) { [weak self] in
                    host.recordLaunch(id)
                    return self.map { .input($0.durationRequest(inScreen: false)) } ?? .stay
                }
            ]
        case .startStopwatch:
            return [
                .command(String(localized: "Start Stopwatch"), owner: .startStopwatch) { [weak self] in
                    guard let self else { return .stay }
                    return .push(StopwatchScreen(module: self, showing: timers.startStopwatch(name: nil).id))
                },
                ItemAction(
                    id: "timers.name-stopwatch", title: String(localized: "Name…"), icon: "pencil",
                    runsOnTab: true, owner: .startStopwatch
                ) { [weak self] in
                    host.recordLaunch(id)
                    return self.map { .input($0.stopwatchNameRequest) } ?? .stay
                },
            ]
        case .stopwatch:
            return [
                .open(owner: .stopwatch) { [weak self] in self.map { .push(StopwatchScreen(module: $0)) } ?? .stay }
            ]
        case .timers:
            return [.open(owner: .timers) { [weak self] in self.map { .push(TimersScreen(module: $0)) } ?? .stay }]
        default:
            return []
        }
    }

    /// Start Timer for a duration, on anything that holds one, such as a calculation of `25 min`.
    func contributedActions(for item: LauncherItem, traits: ItemTraits) -> [ItemAction] {
        guard let duration = traits.duration, let seconds = duration() else { return [] }
        return [
            ItemAction(
                id: "timers.start-for",
                title: String(localized: "Start Timer for \(TimerNaming.duration(TimeInterval(seconds)))"),
                icon: "timer", shortcut: KeyShortcut("t", .command), owner: .timersModule
            ) { [timers] in
                // Worked out again, so a timer counting down to a moment starts from when it's chosen.
                guard let seconds = duration() else { return .fail() }
                _ = timers.startTimer(seconds: seconds, name: nil)
                return .dismiss
            }
        ]
    }

    // MARK: - Shared

    /// What can be done with a running timer or stopwatch, after its first action: in a timers screen, with plain
    /// keys for the most used.
    func timerActions(for timer: TimerItem, inScreen: Bool) -> [ItemAction] {
        let isStopwatch = timer.kind == .stopwatch
        var actions = [
            ItemAction(
                id: "timers.copy-time",
                title: isStopwatch ? String(localized: "Copy Elapsed Time") : String(localized: "Copy Time Left"),
                icon: "doc.on.doc", shortcut: .commandReturn
            ) { [weak self] in self?.copyTime(of: timer) ?? .stay }
        ]
        if !isStopwatch {
            actions.append(
                ItemAction(
                    id: "timers.add-minute", title: String(localized: "Add 1 Minute"), icon: "plus",
                    shortcut: KeyShortcut("=", .command), plainKeys: inScreen ? "+=" : nil
                ) { [timers] in
                    timers.add(60, to: timer.id)
                    return .stay
                })
            actions.append(
                ItemAction(
                    id: "timers.add-five-minutes", title: String(localized: "Add 5 Minutes"),
                    icon: "goforward.5"
                ) { [timers] in
                    timers.add(300, to: timer.id)
                    return .stay
                })
        }
        if isStopwatch, !timer.isPaused {
            actions.append(
                ItemAction(
                    id: "timers.lap", title: String(localized: "Lap"), icon: "flag",
                    shortcut: KeyShortcut("l", .command), plainKeys: inScreen ? "l" : nil
                ) { [timers] in
                    timers.lap(timer.id)
                    return .stay
                })
        }
        actions.append(
            ItemAction(
                id: "timers.restart",
                title: isStopwatch ? String(localized: "Reset") : String(localized: "Restart"),
                icon: "arrow.counterclockwise", shortcut: KeyShortcut("r", .command),
                plainKeys: inScreen ? "r" : nil
            ) { [timers] in
                timers.restart(timer.id)
                return .stay
            })
        actions.append(
            ItemAction(id: "timers.rename", title: String(localized: "Rename…"), icon: "pencil") { [weak self] in
                self.map { .input($0.renameRequest(for: timer)) } ?? .stay
            })
        actions.append(
            ItemAction(
                id: "timers.remove",
                title: isStopwatch ? String(localized: "Stop Stopwatch") : String(localized: "Cancel Timer"),
                icon: "trash", shortcut: .delete,
                // A stopwatch is stopped from ⌘K, so one key can't lose it.
                plainKeys: inScreen && !isStopwatch ? "\u{8}" : nil, isDestructive: true
            ) { [timers] in
                timers.remove(timer.id)
                return .removed
            })
        return actions
    }

    func forget(_ preset: TimerPreset, inScreen: Bool = false) -> ItemAction {
        ItemAction(
            id: "timers.forget", title: String(localized: "Remove from Recent Timers"), icon: "trash",
            shortcut: .delete, plainKeys: inScreen ? "\u{8}" : nil, isDestructive: true
        ) { [timers] in
            timers.forget(preset)
            return .removed
        }
    }

    /// Copies a timer's time left or a stopwatch's elapsed time.
    private func copyTime(of timer: TimerItem) -> ActionOutcome {
        let value = timer.value()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            timer.kind == .stopwatch ? TimerNaming.stopwatchClock(value) : TimerNaming.clock(value), forType: .string)
        return host?.dismissAndPaste(copyOnly: true, for: .timersModule) ?? .stay
    }

    /// The duration Start Timer… asks for, then its name. Started from the timers screen, the timer is selected
    /// there; from the search, the panel closes.
    func durationRequest(inScreen: Bool) -> InputRequest {
        InputRequest(
            label: String(localized: "Start Timer"),
            placeholder: String(localized: "Duration, such as 25m, 1h30m or 4:30"),
            submitTitle: String(localized: "Start Timer")
        ) { [weak self] text in
            guard let self else { return .stay }
            guard
                let parsed = TimerDuration.parse(text.trimmingCharacters(in: .whitespaces), plainNumberIsMinutes: true)
            else { return .fail() }
            guard let name = parsed.name else {
                return .input(nameRequest(seconds: parsed.seconds, inScreen: inScreen))
            }
            return start(seconds: parsed.seconds, name: name, inScreen: inScreen)
        }
    }

    func nameRequest(seconds: Int, inScreen: Bool) -> InputRequest {
        InputRequest(
            label: String(localized: "Timer for \(TimerNaming.duration(TimeInterval(seconds)))"),
            placeholder: String(localized: "Name, or Return for “\(TimerNaming.defaultTimerName(seconds: seconds))”"),
            submitTitle: String(localized: "Start Timer")
        ) { [weak self] text in
            let name = text.trimmingCharacters(in: .whitespaces)
            return self?.start(seconds: seconds, name: name.isEmpty ? nil : name, inScreen: inScreen) ?? .stay
        }
    }

    private func start(seconds: Int, name: String?, inScreen: Bool) -> ActionOutcome {
        host?.recordLaunch(TimerPreset(name: name, seconds: seconds).launchKey)
        let item = timers.startTimer(seconds: seconds, name: name, announces: !inScreen)
        guard inScreen else { return .dismiss }
        host?.select("timer:\(item.id)")
        return .stay
    }

    private var stopwatchNameRequest: InputRequest {
        InputRequest(
            label: String(localized: "Start Stopwatch"),
            placeholder: String(localized: "Name, or Return for “\(TimerNaming.defaultStopwatchName)”"),
            submitTitle: String(localized: "Start Stopwatch")
        ) { [weak self] text in
            guard let self else { return .stay }
            let name = text.trimmingCharacters(in: .whitespaces)
            return .push(
                StopwatchScreen(module: self, showing: timers.startStopwatch(name: name.isEmpty ? nil : name).id))
        }
    }

    /// A rename starts from the saved name, so Escape cancels it outright and keeps that name.
    func renameRequest(for timer: TimerItem) -> InputRequest {
        InputRequest(
            label: String(localized: "Rename \(timer.name)"), placeholder: String(localized: "New name"),
            text: timer.name, submitTitle: String(localized: "Rename"), escapeClears: false
        ) { [timers] text in
            let name = text.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return .fail() }
            timers.rename(timer.id, to: name)
            return .stay
        }
    }

    /// Start Timer…'s hotkey asks for the duration without counting as a use of the command, which choosing it in the
    /// search does.
    func runHotkey(for command: ModuleRef) -> Bool {
        guard command == .startTimer, let host else { return false }
        host.openDirectly { host.beginInput(durationRequest(inScreen: false)) }
        return true
    }

    var settingsPane: ModuleSettingsPane? {
        ModuleSettingsPane(title: String(localized: "Notifications"), symbol: "bell.badge.fill", tint: .red) {
            [timers] in AnyView(NotificationsPane(timers: timers))
        }
    }
}

/// A running timer's time left, or a stopwatch's elapsed time, counting in place.
struct TimerCountdown: View {
    let item: TimerItem

    var body: some View {
        if item.isPaused {
            Text("Paused · \(time(at: .now))")
                .monospacedDigit()
        } else {
            // A stopwatch shows tenths of a second, so it ticks faster.
            TimelineView(.periodic(from: .now, by: item.kind == .stopwatch ? 0.1 : 1)) { context in
                Text(time(at: context.date))
                    .monospacedDigit()
            }
        }
    }

    private func time(at date: Date) -> String {
        switch item.kind {
        case .timer:
            return String(localized: "\(TimerNaming.clock(item.value(at: date))) left")
        case .stopwatch:
            let total = TimerNaming.stopwatchClock(item.value(at: date))
            guard !item.laps.isEmpty else { return total }
            return String(
                localized:
                    "Lap \(item.laps.count + 1) \(TimerNaming.stopwatchClock(item.currentLap(at: date))) · \(total)")
        }
    }
}

/// Every timer in one list, managed in place: ringing timers first, then running and paused ones, then recent timers to
/// start again. Plain keys act on the selected row, and N starts a new timer.
@MainActor
final class TimersScreen: LauncherScreen {
    let module: TimersModule
    private let selecting: UUID?

    init(module: TimersModule, selecting: UUID? = nil) {
        self.module = module
        self.selecting = selecting
    }

    let id = "timers"

    var searchBar: SearchBar { .title(String(localized: "Timers")) }

    func accessory() -> AnyView? {
        AnyView(
            HStack(spacing: 4) {
                Text("New Timer")
                    .padding(.trailing, 4)
                KeyCap("N")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.launcherSecondary))
    }

    var revision: AnyHashable { module.revision }

    var content: ScreenContent { .custom(AnyView(TimersView(screen: self))) }

    var keys: KeyPolicy { KeyPolicy(plainKeys: true) }

    func items(for query: String) -> [LauncherItem] {
        let timers = module.timers
        return timers.ringing.map { module.row(.ringing($0)) }
            + timers.items.filter { $0.kind == .timer }.map { module.row(.running($0)) }
            + timers.presets.map { module.row(.preset($0)) }
    }

    func initialSelection(in items: [LauncherItem]) -> Int {
        guard let selecting else { return 0 }
        return items.firstIndex { $0.selectionKey == "timer:\(selecting)" } ?? 0
    }

    func sectionTitle(at index: Int, in items: [LauncherItem]) -> String? {
        guard items.indices.contains(index) else { return nil }
        if case .preset? = items[index].payload(as: TimersModule.Row.self) { return String(localized: "Recent") }
        return String(localized: "Timers")
    }

    func actions(for item: LauncherItem) -> [ItemAction] {
        let timers = module.timers
        switch item.payload(as: TimersModule.Row.self) {
        case .running(let timer)?:
            return [
                ItemAction(
                    id: "timers.toggle",
                    title: timer.isPaused ? String(localized: "Resume") : String(localized: "Pause"), icon: "playpause"
                ) {
                    timers.togglePause(timer.id)
                    return .stay
                }
            ] + module.timerActions(for: timer, inScreen: true)
        case .ringing(let timer)?:
            return [
                ItemAction(id: "timers.stop", title: String(localized: "Stop"), icon: "return") {
                    timers.stop(timer.id)
                    return .removed
                },
                ItemAction(id: "timers.snooze", title: String(localized: "Snooze"), icon: "zzz", plainKeys: "s") {
                    timers.snooze(timer.id)
                    return .stay
                },
            ]
        case .preset(let preset)?:
            return [
                ItemAction(id: "timers.start", title: String(localized: "Start"), icon: "return", recordsLaunch: true) {
                    [weak host = (module as TimersModule).hostForScreens] in
                    let started = timers.startTimer(seconds: preset.seconds, name: preset.name, announces: false)
                    host?.select("timer:\(started.id)")
                    return .stay
                },
                module.forget(preset, inScreen: true),
            ]
        default:
            return []
        }
    }

    var screenActions: [ItemAction] {
        [
            ItemAction(id: "timers.new", title: String(localized: "New Timer"), icon: "plus", plainKeys: "n") {
                [module] in .input(module.durationRequest(inScreen: true))
            }
        ]
    }
}

extension TimersModule {
    /// The host, for screens that select what they start.
    fileprivate var hostForScreens: (any ModuleHost)? { host }
}

/// A stopwatch filling the panel, with its laps. Plain keys control it, ← and → switch between stopwatches, and with
/// none running Return or Space starts one.
@MainActor
@Observable
final class StopwatchScreen: LauncherScreen {
    @ObservationIgnored let module: TimersModule
    private var stopwatchID: UUID?

    init(module: TimersModule, showing id: UUID? = nil) {
        self.module = module
        stopwatchID = id
    }

    let id = "stopwatch"

    var stopwatches: [TimerItem] {
        module.timers.items.filter { $0.kind == .stopwatch }
    }

    /// The stopwatch shown, or another one if it was stopped elsewhere, such as from the menu bar.
    var current: TimerItem? {
        let stopwatches = stopwatches
        return stopwatches.first { $0.id == stopwatchID } ?? stopwatches.last
    }

    var searchBar: SearchBar {
        .title(current?.name ?? TimerNaming.defaultStopwatchName, isDimmed: current == nil)
    }

    func accessory() -> AnyView? {
        AnyView(StopwatchSwitcher(screen: self))
    }

    var revision: AnyHashable {
        [AnyHashable(module.timers.items), AnyHashable(stopwatchID)]
    }

    var content: ScreenContent { .custom(AnyView(StopwatchView(screen: self))) }

    var footer: ScreenFooter { .custom(AnyView(StopwatchFooter(screen: self))) }

    var keys: KeyPolicy { KeyPolicy(plainKeys: true) }

    func items(for query: String) -> [LauncherItem] {
        current.map { [module.row(.running($0))] } ?? []
    }

    func actions(for item: LauncherItem) -> [ItemAction] {
        guard let stopwatch = current else { return [] }
        let timers = module.timers
        var actions = [
            ItemAction(
                id: "timers.toggle",
                title: stopwatch.isPaused ? String(localized: "Start") : String(localized: "Pause"), icon: "playpause"
            ) {
                timers.togglePause(stopwatch.id)
                return .stay
            }
        ]
        actions += module.timerActions(for: stopwatch, inScreen: true).map { action in
            guard action.id == "timers.remove" else { return action }
            // Stopping it shows the next one, or none.
            return ItemAction(
                id: action.id, title: action.title, icon: action.icon, shortcut: action.shortcut,
                isDestructive: true
            ) { [weak self] in
                timers.remove(stopwatch.id)
                self?.stopwatchID = nil
                return .removed
            }
        }
        return actions
    }

    var screenActions: [ItemAction] {
        guard current == nil else { return [] }
        return [
            ItemAction(id: "timers.start-stopwatch", title: String(localized: "Start"), icon: "return") { [weak self] in
                guard let self else { return .stay }
                stopwatchID = module.timers.startStopwatch(name: nil).id
                return .stay
            }
        ]
    }

    /// Moves to the previous or next stopwatch; with only one, the key is left alone.
    func horizontalMove(by offset: Int) -> Bool {
        let stopwatches = stopwatches
        guard stopwatches.count > 1 else { return false }
        let index = stopwatches.firstIndex { $0.id == current?.id } ?? 0
        stopwatchID = stopwatches[(index + offset + stopwatches.count) % stopwatches.count].id
        return true
    }
}
