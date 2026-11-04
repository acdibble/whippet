import Foundation
import WhippetCore

extension ModuleManifest {
    static let timers = ModuleManifest(
        id: "timers",
        title: String(localized: "Timers"),
        summary: String(localized: "Timers and stopwatches, in the search and the menu bar."),
        icon: "timer",
        tint: .red,
        commands: [
            ModuleCommand(
                id: "start-timer", title: String(localized: "Start Timer…"), icon: "timer",
                permissions: [.notifications], legacyHotkey: "command.startTimer"),
            ModuleCommand(
                id: "timers", title: String(localized: "Timers"), icon: "list.bullet", legacyHotkey: "command.timers"),
            ModuleCommand(
                id: "start-stopwatch", title: String(localized: "Start Stopwatch"), icon: "stopwatch",
                legacyHotkey: "command.startStopwatch"),
            ModuleCommand(
                id: "stopwatch", title: String(localized: "Stopwatch"), icon: "stopwatch",
                legacyHotkey: "command.stopwatch"),
        ],
        features: [
            ModuleFeature(
                id: "typed-timers", title: String(localized: "Timers from the Search Bar"),
                summary: String(localized: "Typing a duration, such as 25m tea, offers to start a timer."),
                permissions: [.notifications])
        ]
    )
}

extension ModuleRef {
    static let timersModule = ModuleManifest.timers.ref
    static let startTimer = ModuleManifest.timers.ref("start-timer")
    static let timers = ModuleManifest.timers.ref("timers")
    static let startStopwatch = ModuleManifest.timers.ref("start-stopwatch")
    static let stopwatch = ModuleManifest.timers.ref("stopwatch")
    static let typedTimers = ModuleManifest.timers.ref("typed-timers")
}
