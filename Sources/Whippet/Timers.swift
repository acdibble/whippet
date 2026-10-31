import AppKit
import Observation

/// Running timers and stopwatches, shared by the launcher, the menu bar item and Settings. They're kept on this Mac
/// only, in UserDefaults, and come back after a relaunch; a timer that ended while Whippet wasn't running rings at launch.
@MainActor
@Observable
final class Timers {
    /// Running and paused timers and stopwatches, oldest first.
    private(set) var items: [TimerItem] = []
    /// Timers that have ended, until stopped or snoozed. Their sound stops after a minute, but they stay done, with
    /// their notification, so a timer that ends while you're away still shows that it did.
    private(set) var ringing: [TimerItem] = []
    /// Timers started before, most recent first, offered again in the launcher.
    private(set) var presets: [TimerPreset] = []

    var showsInMenuBar: Bool {
        didSet { defaults.set(showsInMenuBar, forKey: Keys.showsInMenuBar) }
    }
    /// A sound in /System/Library/Sounds, or empty for none.
    var sound: String {
        didSet { defaults.set(sound, forKey: Keys.sound) }
    }
    var snoozeMinutes: Int {
        didSet { defaults.set(snoozeMinutes, forKey: Keys.snoozeMinutes) }
    }

    static let sounds = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse", "Ping", "Pop", "Purr",
        "Sosumi", "Submarine", "Tink",
    ]
    static let snoozeChoices = [1, 5, 10, 15]
    private static let presetLimit = 5
    /// How long a finished timer's sound plays before it goes quiet.
    private static let ringDuration: Duration = .seconds(60)

    private enum Keys {
        static let items = "timers"
        static let presets = "timerPresets"
        static let showsInMenuBar = "showsTimersInMenuBar"
        static let sound = "timerSound"
        static let snoozeMinutes = "timerSnoozeMinutes"
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var expiry: Task<Void, Never>?
    @ObservationIgnored private var ringers: [UUID: Task<Void, Never>] = [:]
    /// Finished timers waiting for the alert shown when notifications aren't allowed.
    @ObservationIgnored private var pendingAlerts: [UUID] = []
    @ObservationIgnored private var isShowingAlert = false
    /// Called after timers are added, removed, changed or finished, so the launcher can keep the same one selected.
    @ObservationIgnored var onChange: () -> Void = {}

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showsInMenuBar = defaults.bool(forKey: Keys.showsInMenuBar)
        sound = defaults.string(forKey: Keys.sound) ?? "Glass"
        let snooze = defaults.integer(forKey: Keys.snoozeMinutes)
        snoozeMinutes = snooze > 0 ? snooze : 5
        items = Self.decode([TimerItem].self, from: defaults.data(forKey: Keys.items)) ?? []
        presets = Self.decode([TimerPreset].self, from: defaults.data(forKey: Keys.presets)) ?? []
    }

    /// Rings timers that ended while Whippet wasn't running, and waits for the next one.
    func start() {
        Notifications.shared.onTimerResponse = { [weak self] identifier, action in
            guard let self, let id = UUID(uuidString: identifier) else { return }
            switch action {
            case .snooze: snooze(id)
            case .stop, nil: stop(id)
            }
        }
        scheduleNext()
    }

    var hasAny: Bool { !items.isEmpty || !ringing.isEmpty }

    // MARK: - Starting

    /// Without a name, the timer is named after its length. `announces` shows a toast, which the timers view doesn't
    /// need since it lists the new timer.
    @discardableResult
    func startTimer(seconds: Int, name: String?, remembers: Bool = true, announces: Bool = true) -> TimerItem {
        let base = name ?? TimerNaming.defaultTimerName(seconds: seconds)
        let item = TimerItem.timer(name: TimerNaming.unique(base, among: allNames), seconds: seconds)
        items.append(item)
        if remembers {
            remember(TimerPreset(name: name, seconds: seconds))
        }
        save()
        scheduleNext()
        if Notifications.wants(.timerDone) {
            Task { _ = await Notifications.shared.requestAuthorization() }
        }
        if announces {
            Toast.shared.show(String(localized: "\(item.name) started"), symbol: "timer")
        }
        return item
    }

    /// Stopwatches start in the stopwatch view, which shows them, so there's no toast.
    @discardableResult
    func startStopwatch(name: String?) -> TimerItem {
        let base = name ?? TimerNaming.defaultStopwatchName
        let item = TimerItem.stopwatch(name: TimerNaming.unique(base, among: allNames))
        items.append(item)
        save()
        return item
    }

    private var allNames: [String] { (items + ringing).map(\.name) }

    private func remember(_ preset: TimerPreset) {
        presets.removeAll { $0 == preset }
        presets.insert(preset, at: 0)
        presets = Array(presets.prefix(Self.presetLimit))
        defaults.set(try? JSONEncoder().encode(presets), forKey: Keys.presets)
    }

    func forget(_ preset: TimerPreset) {
        presets.removeAll { $0 == preset }
        defaults.set(try? JSONEncoder().encode(presets), forKey: Keys.presets)
    }

    // MARK: - Changing

    func togglePause(_ id: UUID) {
        update(id) { item in
            if item.isPaused { item.resume() } else { item.pause() }
        }
    }

    func add(_ seconds: TimeInterval, to id: UUID) {
        update(id) { $0.add(seconds) }
    }

    func restart(_ id: UUID) {
        update(id) { $0.restart() }
    }

    func lap(_ id: UUID) {
        update(id) { $0.lap() }
    }

    /// Keeps names unique, so a rename can't make two the same.
    func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let others = (items + ringing).filter { $0.id != id }.map(\.name)
        update(id) { $0.name = TimerNaming.unique(trimmed, among: others) }
    }

    /// Cancels a timer or stops a stopwatch, or stops one that's ringing.
    func remove(_ id: UUID) {
        if ringing.contains(where: { $0.id == id }) {
            stop(id)
            return
        }
        items.removeAll { $0.id == id }
        save()
        scheduleNext()
    }

    func item(_ id: UUID) -> TimerItem? {
        items.first { $0.id == id } ?? ringing.first { $0.id == id }
    }

    private func update(_ id: UUID, _ change: (inout TimerItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
        save()
        scheduleNext()
    }

    // MARK: - Ending

    /// Sleeps until the next timer ends. The continuous clock keeps counting while the Mac sleeps, so a timer that ended
    /// during sleep rings on waking.
    private func scheduleNext() {
        expiry?.cancel()
        let now = Date.now
        for item in items where item.isFinished(at: now) {
            finish(item)
        }
        guard let next = items.compactMap(\.endsAt).min() else { return }
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, next.timeIntervalSinceNow)), clock: .continuous)
            guard !Task.isCancelled else { return }
            self?.scheduleNext()
        }
    }

    private func finish(_ item: TimerItem) {
        items.removeAll { $0.id == item.id }
        ringing.append(item)
        save()
        ring(item)
        // Turned off in Settings, it still rings and shows as done in the launcher and menu bar.
        guard Notifications.wants(.timerDone) else { return }
        Task {
            if await Notifications.shared.isAuthorized {
                Notifications.shared.postTimer(
                    identifier: item.id.uuidString,
                    title: String(localized: "\(item.name) is done"),
                    body: String(localized: "\(TimerNaming.duration(item.duration)) timer")
                )
            } else {
                pendingAlerts.append(item.id)
                showPendingAlert()
            }
        }
    }

    /// Plays the alert sound every few seconds until the timer is stopped or snoozed, or a minute passes.
    private func ring(_ item: TimerItem) {
        let sound = sound.isEmpty ? nil : NSSound(named: NSSound.Name(sound))
        ringers[item.id] = Task { [weak self] in
            let clock = ContinuousClock()
            let end = clock.now.advanced(by: Self.ringDuration)
            while !Task.isCancelled, clock.now < end {
                sound?.stop()
                sound?.play()
                try? await Task.sleep(for: .seconds(3))
            }
            guard !Task.isCancelled else { return }
            self?.ringers[item.id] = nil
        }
    }

    /// When notifications are wanted but macOS doesn't allow them, one alert at a time asks instead, covering every
    /// timer that has finished since the last. Timers finishing while it's open get the next one.
    private func showPendingAlert() {
        guard !isShowingAlert else { return }
        let covered = pendingAlerts.compactMap { id in ringing.first { $0.id == id } }
        pendingAlerts = []
        guard let first = covered.first else { return }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        if covered.count == 1 {
            alert.messageText = String(localized: "\(first.name) is done")
            alert.informativeText = String(localized: "\(TimerNaming.duration(first.duration)) timer")
        } else {
            alert.messageText = String(localized: "\(covered.count) timers are done")
            alert.informativeText = covered.map(\.name).formatted(.list(type: .and))
        }
        alert.addButton(withTitle: String(localized: "Stop"))
        alert.addButton(withTitle: String(localized: "Snooze"))
        isShowingAlert = true
        let response = alert.runModal()
        isShowingAlert = false

        for item in covered where ringing.contains(where: { $0.id == item.id }) {
            if response == .alertSecondButtonReturn {
                snooze(item.id)
            } else {
                stop(item.id)
            }
        }
        showPendingAlert()
    }

    func stop(_ id: UUID) {
        ringers.removeValue(forKey: id)?.cancel()
        ringing.removeAll { $0.id == id }
        Notifications.shared.remove(identifier: id.uuidString)
        onChange()
    }

    /// Stops it ringing and starts it again for the snooze length, under the same name.
    func snooze(_ id: UUID) {
        guard let item = ringing.first(where: { $0.id == id }) else { return }
        stop(id)
        startTimer(seconds: snoozeMinutes * 60, name: item.name, remembers: false)
    }

    // MARK: - Storage

    private func save() {
        defaults.set(try? JSONEncoder().encode(items), forKey: Keys.items)
        onChange()
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, from data: Data?) -> Value? {
        data.flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}
