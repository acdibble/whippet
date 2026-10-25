import Foundation

/// A named countdown or stopwatch. Running ones keep a date rather than a count, so they stay right through sleep and
/// relaunch.
struct TimerItem: Identifiable, Hashable, Codable {
    enum Kind: String, Codable {
        case timer
        case stopwatch
    }

    let id: UUID
    let kind: Kind
    var name: String
    /// A timer's length when started, used by Restart; zero for a stopwatch.
    var duration: TimeInterval
    /// While running: when a timer ends, or when a stopwatch would have started had it never paused. Nil while paused.
    var anchor: Date?
    /// While paused: a timer's time left, or a stopwatch's elapsed time.
    var pausedValue: TimeInterval
    /// A stopwatch's elapsed time at each lap.
    var laps: [TimeInterval]

    static func timer(name: String, seconds: Int, now: Date = .now) -> TimerItem {
        TimerItem(
            id: UUID(),
            kind: .timer,
            name: name,
            duration: TimeInterval(seconds),
            anchor: now.addingTimeInterval(TimeInterval(seconds)),
            pausedValue: 0,
            laps: []
        )
    }

    static func stopwatch(name: String, now: Date = .now) -> TimerItem {
        TimerItem(id: UUID(), kind: .stopwatch, name: name, duration: 0, anchor: now, pausedValue: 0, laps: [])
    }

    var isPaused: Bool { anchor == nil }

    /// A timer's time left, never below zero, or a stopwatch's elapsed time.
    func value(at now: Date = .now) -> TimeInterval {
        guard let anchor else { return pausedValue }
        switch kind {
        case .timer: return max(0, anchor.timeIntervalSince(now))
        case .stopwatch: return now.timeIntervalSince(anchor)
        }
    }

    /// When a running timer ends; nil for a paused timer or a stopwatch.
    var endsAt: Date? {
        kind == .timer ? anchor : nil
    }

    func isFinished(at now: Date = .now) -> Bool {
        guard kind == .timer, let anchor else { return false }
        return anchor <= now
    }

    mutating func pause(at now: Date = .now) {
        guard !isPaused else { return }
        pausedValue = value(at: now)
        anchor = nil
    }

    mutating func resume(at now: Date = .now) {
        guard isPaused else { return }
        anchor = switch kind {
        case .timer: now.addingTimeInterval(pausedValue)
        case .stopwatch: now.addingTimeInterval(-pausedValue)
        }
        pausedValue = 0
    }

    /// Adds time to a timer, paused or running, up to the longest a timer can be.
    mutating func add(_ seconds: TimeInterval, at now: Date = .now) {
        guard kind == .timer else { return }
        let added = min(seconds, max(0, TimeInterval(TimerDuration.maximumSeconds) - value(at: now)))
        if let anchor {
            self.anchor = anchor.addingTimeInterval(added)
        } else {
            pausedValue += added
        }
        duration += added
    }

    /// Starts a timer again from its full length, or sets a stopwatch back to zero and clears its laps. Either keeps
    /// running if it was.
    mutating func restart(at now: Date = .now) {
        let wasPaused = isPaused
        switch kind {
        case .timer:
            anchor = nil
            pausedValue = duration
        case .stopwatch:
            anchor = nil
            pausedValue = 0
            laps = []
        }
        if !wasPaused {
            resume(at: now)
        }
    }

    mutating func lap(at now: Date = .now) {
        guard kind == .stopwatch else { return }
        laps.append(value(at: now))
    }

    /// The time since the last lap, or since the start.
    func currentLap(at now: Date = .now) -> TimeInterval {
        value(at: now) - (laps.last ?? 0)
    }
}

/// A timer started before, offered again in the launcher.
struct TimerPreset: Hashable, Codable {
    /// Nil when it was started without a name.
    let name: String?
    let seconds: Int

    /// The key launches are recorded under, which ranks it.
    var launchKey: String { "timer-preset:\(seconds):\(name ?? "")" }
}

enum TimerNaming {
    /// `25 min` or `1 hr, 30 min`, in the app's language.
    static func duration(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds.rounded()).formatted(
            .units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 3)
        )
    }

    /// `4:05` or `1:02:03`, for time left or elapsed.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        let (hours, minutes, secs) = (total / 3600, total % 3600 / 60, total % 60)
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// A stopwatch's elapsed time to the tenth of a second, such as `1:02.3`.
    static func stopwatchClock(_ seconds: TimeInterval) -> String {
        let tenths = Int((seconds * 10).rounded(.down))
        let whole = tenths / 10
        let (hours, minutes, secs) = (whole / 3600, whole % 3600 / 60, whole % 60)
        if hours > 0 {
            return String(format: "%d:%02d:%02d.%d", hours, minutes, secs, tenths % 10)
        }
        return String(format: "%d:%02d.%d", minutes, secs, tenths % 10)
    }

    static func defaultTimerName(seconds: Int) -> String {
        String(localized: "\(duration(TimeInterval(seconds))) timer")
    }

    static var defaultStopwatchName: String { String(localized: "Stopwatch") }

    /// `base`, or `base 2`, `base 3` and so on when that name is taken, so notifications and rows tell timers apart.
    static func unique(_ base: String, among names: [String]) -> String {
        let taken = Set(names.map { $0.lowercased() })
        guard taken.contains(base.lowercased()) else { return base }
        var number = 2
        while taken.contains("\(base) \(number)".lowercased()) { number += 1 }
        return "\(base) \(number)"
    }
}
