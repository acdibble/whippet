import Foundation
import Testing

struct TimerDurationTests {
    @Test(arguments: [
        ("25m", 1500, nil),
        ("25 min", 1500, nil),
        ("5 minutes", 300, nil),
        ("90s", 90, nil),
        ("1h30m", 5400, nil),
        ("1 hour 30 min", 5400, nil),
        ("1h 30m 15s", 5415, nil),
        ("1.5h", 5400, nil),
        ("4:30", 270, nil),
        ("1:02:03", 3723, nil),
        ("25m tea", 1500, "tea"),
        ("4:30 eggs and toast", 270, "eggs and toast"),
        ("25m 2 eggs", 1500, "2 eggs"),
        ("1h 30", 3600, "30"),
        ("timer 5", 300, nil),
        ("timer 5 tea", 300, "tea"),
        ("Timer 10M Pasta", 600, "Pasta"),
        ("۲۵ دقیقه", 1500, nil),
        ("تایمر ۵ چای", 300, "چای"),
        ("1 ساعت", 3600, nil),
    ] as [(String, Int, String?)])
    func parses(_ input: String, _ seconds: Int, _ name: String?) {
        #expect(TimerDuration.parse(input) == .init(seconds: seconds, name: name))
    }

    @Test(arguments: [
        "", "5", "25", "tea", "timer", "timer tea", "5 mango", "25mtea", "0m", "0:00", "4:75", "30m10h", "169h",
        "1m1m", "2+2", "1:2:3:4",
    ])
    func rejects(_ input: String) {
        #expect(TimerDuration.parse(input) == nil)
    }

    @Test func plainNumberIsMinutesWhenAsked() {
        #expect(TimerDuration.parse("5", plainNumberIsMinutes: true) == .init(seconds: 300, name: nil))
        #expect(TimerDuration.parse("5 tea", plainNumberIsMinutes: true) == .init(seconds: 300, name: "tea"))
        #expect(TimerDuration.parse("5 mango") == nil)
    }
}

struct TimerItemTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000_000)

    @Test func timerCountsDownAndFinishes() {
        let timer = TimerItem.timer(name: "Tea", seconds: 240, now: start)
        #expect(timer.value(at: start.addingTimeInterval(40)) == 200)
        #expect(!timer.isFinished(at: start.addingTimeInterval(239)))
        #expect(timer.isFinished(at: start.addingTimeInterval(240)))
        #expect(timer.value(at: start.addingTimeInterval(300)) == 0)
    }

    @Test func pausedTimerKeepsItsTimeLeft() {
        var timer = TimerItem.timer(name: "Tea", seconds: 240, now: start)
        timer.pause(at: start.addingTimeInterval(40))
        #expect(timer.isPaused)
        #expect(timer.endsAt == nil)
        #expect(timer.value(at: start.addingTimeInterval(1000)) == 200)
        #expect(!timer.isFinished(at: start.addingTimeInterval(1000)))
        timer.resume(at: start.addingTimeInterval(1000))
        #expect(timer.endsAt == start.addingTimeInterval(1200))
    }

    @Test func addingTimeExtendsRunningAndPausedTimers() {
        var running = TimerItem.timer(name: "Tea", seconds: 240, now: start)
        running.add(60, at: start)
        #expect(running.value(at: start) == 300)
        #expect(running.duration == 300)

        var paused = TimerItem.timer(name: "Tea", seconds: 240, now: start)
        paused.pause(at: start.addingTimeInterval(40))
        paused.add(300, at: start.addingTimeInterval(40))
        #expect(paused.value() == 500)
    }

    @Test func addingTimeStopsAtTheLongestTimer() {
        var timer = TimerItem.timer(name: "Long", seconds: TimerDuration.maximumSeconds - 30, now: start)
        timer.add(300, at: start)
        #expect(timer.value(at: start) == TimeInterval(TimerDuration.maximumSeconds))
    }

    @Test func restartKeepsPausedOrRunning() {
        var timer = TimerItem.timer(name: "Tea", seconds: 240, now: start)
        timer.restart(at: start.addingTimeInterval(100))
        #expect(timer.endsAt == start.addingTimeInterval(340))

        timer.pause(at: start.addingTimeInterval(150))
        timer.restart(at: start.addingTimeInterval(200))
        #expect(timer.isPaused)
        #expect(timer.value() == 240)
    }

    @Test func stopwatchCountsUpThroughPausesAndLaps() {
        var stopwatch = TimerItem.stopwatch(name: "Run", now: start)
        #expect(stopwatch.value(at: start.addingTimeInterval(10)) == 10)
        stopwatch.lap(at: start.addingTimeInterval(10))
        stopwatch.pause(at: start.addingTimeInterval(15))
        #expect(stopwatch.value(at: start.addingTimeInterval(100)) == 15)
        stopwatch.resume(at: start.addingTimeInterval(100))
        #expect(stopwatch.value(at: start.addingTimeInterval(105)) == 20)
        #expect(stopwatch.currentLap(at: start.addingTimeInterval(105)) == 10)
        #expect(stopwatch.laps == [10])
        #expect(stopwatch.endsAt == nil)
        #expect(!stopwatch.isFinished(at: .distantFuture))

        stopwatch.restart(at: start.addingTimeInterval(110))
        #expect(stopwatch.laps.isEmpty)
        #expect(stopwatch.value(at: start.addingTimeInterval(112)) == 2)
    }

    @Test func survivesEncoding() throws {
        var stopwatch = TimerItem.stopwatch(name: "Run", now: start)
        stopwatch.lap(at: start.addingTimeInterval(3))
        let decoded = try JSONDecoder().decode(TimerItem.self, from: JSONEncoder().encode(stopwatch))
        #expect(decoded == stopwatch)
    }
}

struct TimerNamingTests {
    @Test func uniqueNamesCountUp() {
        #expect(TimerNaming.unique("Tea", among: []) == "Tea")
        #expect(TimerNaming.unique("Tea", among: ["tea"]) == "Tea 2")
        #expect(TimerNaming.unique("Tea", among: ["Tea", "Tea 2", "Coffee"]) == "Tea 3")
    }

    @Test func clocks() {
        #expect(TimerNaming.clock(0) == "0:00")
        #expect(TimerNaming.clock(59.2) == "1:00")
        #expect(TimerNaming.clock(252) == "4:12")
        #expect(TimerNaming.clock(3723) == "1:02:03")
        #expect(TimerNaming.stopwatchClock(62.37) == "1:02.3")
        #expect(TimerNaming.stopwatchClock(3723.05) == "1:02:03.0")
    }

    @Test func presetKeysDifferByNameAndLength() {
        #expect(TimerPreset(name: nil, seconds: 300).launchKey != TimerPreset(name: "Tea", seconds: 300).launchKey)
        #expect(TimerPreset(name: "Tea", seconds: 300).launchKey != TimerPreset(name: "Tea", seconds: 240).launchKey)
    }
}
