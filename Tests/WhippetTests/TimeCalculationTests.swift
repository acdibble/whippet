import Foundation
import Testing

struct TimeCalculationTests {
    /// Friday 30 October 2026 at 13:00 in Berlin, after Europe's clocks went back but before America's.
    private let context = TimeCalculation.Context(
        now: Date(timeIntervalSince1970: 1_793_361_600),
        timeZone: TimeZone(identifier: "Europe/Berlin")!,
        locale: Locale(identifier: "en_GB")
    )

    private func calculate(_ input: String) -> Calculation? {
        TimeCalculation.calculate(input, context: context)
    }

    private func answer(_ input: String) -> String? {
        calculate(input)?.answer
    }

    @Test(arguments: [
        ("tokyo", "Asia/Tokyo"),
        ("New York", "America/New_York"),
        ("são paulo", "America/Sao_Paulo"),
        ("Asia/Kolkata", "Asia/Kolkata"),
        ("nyc", "America/New_York"),
        ("japan", "Asia/Tokyo"),
        ("pst", "America/Los_Angeles"),
        ("PT", "America/Los_Angeles"),
        ("aest", "Australia/Sydney"),
    ])
    func findsTimeZones(_ name: String, _ identifier: String) {
        #expect(TimeCalculation.zone(named: name)?.identifier == identifier)
    }

    @Test func findsOffsetsAndLeavesOtherWordsAlone() {
        #expect(TimeCalculation.zone(named: "utc+2")?.secondsFromGMT() == 7200)
        #expect(TimeCalculation.zone(named: "GMT-5:30")?.secondsFromGMT() == -19800)
        #expect(TimeCalculation.zone(named: "safari") == nil)
        #expect(TimeCalculation.zone(named: "") == nil)
    }

    @Test(arguments: [
        ("time in tokyo", "21:00"),
        ("now in utc", "12:00"),
        ("3pm pst in london", "22:00"),
        ("15:30 to new york", "10:30"),
        ("9:30 a.m. in utc", "08:30"),
        ("noon tokyo to berlin", "04:00"),
        ("9am utc+2 to utc", "07:00"),
    ])
    func showsTheTimeElsewhere(_ input: String, _ expected: String) {
        #expect(answer(input) == expected, "got \(answer(input) ?? "nil")")
    }

    @Test func namesTheDayWhenItDiffers() throws {
        let conversion = try #require(calculate("11pm in tokyo")?.conversion)
        #expect(conversion.output == "Sat 07:00")
        #expect(conversion.outputLong.hasPrefix("Saturday 31 October"))
        #expect(conversion.kind == "Central European Time")
    }

    @Test(arguments: [
        ("days until 25 dec 2026", "56"),
        ("weeks until 25 dec 2026", "8"),
        ("days since 1 oct 2026", "29"),
        ("hours until 2026-10-31 13:00", "24"),
        ("minutes until 30 oct 2026 1:30pm", "30"),
        ("years since 5 may 1990", "36"),
    ])
    func countsUnits(_ input: String, _ expected: String) {
        #expect(answer(input) == expected, "got \(answer(input) ?? "nil")")
    }

    @Test func breaksDownTheTime() throws {
        let calculation = try #require(calculate("time until 25 dec 2026"))
        #expect(calculation.value == 55 * 86400 + 11 * 3600)
        #expect(calculation.conversion?.outputLong == "1 month, 24 days, 11 hours")
        #expect(calculation.conversion?.kind == "Time Until")
        #expect(calculate("time since 30 oct 2026 11:00")?.value == 7200)
    }

    @Test func aDateWithoutAYearIsTheNearestOneTheRightWay() throws {
        // The detector reads dates against the real clock, so this uses it too.
        let now = TimeCalculation.Context(timeZone: context.timeZone, locale: context.locale)
        for input in ["time since dec 25", "time until oct 1", "time since jan 1", "days until monday", "days since friday"] {
            let value = try #require(TimeCalculation.calculate(input, context: now)?.value, "\(input)")
            #expect(value >= 0, "\(input) gave \(value)")
            #expect(value <= 366 * 86400, "\(input) gave \(value)")
        }
    }

    /// A moment in Berlin, as the context sees it.
    private func berlin(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Double {
        context.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
            .timeIntervalSince1970
    }

    @Test func addsToADate() throws {
        #expect(calculate("30 oct 2026 + 3 weeks")?.value == berlin(2026, 11, 20))
        #expect(calculate("25 dec 2026 - 10 days")?.value == berlin(2026, 12, 15))
        #expect(calculate("25 dec - 10 days")?.value == berlin(2026, 12, 15))
        #expect(calculate("31 jan 2026 + 1 month")?.value == berlin(2026, 2, 28))
        #expect(calculate("2026-12-25 - 1 y")?.value == berlin(2025, 12, 25))
        #expect(calculate("30 oct 2026 1pm + 1 day 2 h")?.value == berlin(2026, 10, 31, 15))
        #expect(calculate("now + 90 min")?.value == context.now.timeIntervalSince1970 + 5400)
        #expect(calculate("now - 2 h 30 min")?.value == context.now.timeIntervalSince1970 - 9000)
        #expect(calculate("now + 1.5 h - 30 m")?.value == context.now.timeIntervalSince1970 + 3600)

        let calculation = try #require(calculate("30 oct 2026 + 3 weeks"))
        #expect(calculation.conversion?.kind == "Date")
        #expect(calculation.answer == calculation.displayAnswer)
        #expect(calculation.displayAnswer.contains("20 Nov 2026"), "got \(calculation.displayAnswer)")
        #expect(calculation.displayAnswer.contains(":") == false, "got \(calculation.displayAnswer)")
        #expect(try #require(calculate("now + 90 min")).displayAnswer.contains("14:30"))
    }

    @Test func addsToTodayAndTomorrow() throws {
        // The detector reads these against the real clock, so this uses it too.
        let now = TimeCalculation.Context(timeZone: context.timeZone, locale: context.locale)
        let today = now.calendar.startOfDay(for: .now)
        let nextWeek = try #require(TimeCalculation.calculate("today + 1 week", context: now)?.value)
        #expect(nextWeek == now.calendar.date(byAdding: .weekOfYear, value: 1, to: today)!.timeIntervalSince1970)
        #expect(TimeCalculation.calculate("tomorrow 9am + 2 h", context: now)?.conversion?.kind == "Date")
    }

    @Test(arguments: ["today + 1.5 days", "today + 3 bananas", "today +", "now + 5", "banana + 3 days", "5 + 3 days"])
    func notDateArithmetic(_ input: String) {
        #expect(TimeCalculation.calculate(input) == nil)
    }

    @Test func arithmeticOnTimeAloneStaysAnAmount() {
        #expect(Calculator.calculate("1 h + 30 min")?.conversion?.kind == "Time")
        #expect(Calculator.calculate("10 min - 5 min")?.conversion?.kind == "Time")
    }

    @Test func leavesOtherTextAlone() {
        for input in ["time", "time machine", "days", "time in nowhere", "13pm in tokyo", "3 in tokyo", "until dec 25"] {
            #expect(calculate(input) == nil, "\(input)")
        }
        // Picometres stay picometres.
        #expect(Calculator.calculate("3 pm to nm")?.answer == "0.003")
    }

    @Test(arguments: [
        "time in", "time in tok", "now in ", "days until", "time since 5 m", "3pm in", "3pm pst to l", "today +",
        "now - 2", "dec 25 - 10 d",
    ])
    func recognisesACalculationBeingTyped(_ input: String) {
        #expect(TimeCalculation.looksLikeTimeCalculation(input))
    }

    @Test(arguments: ["time", "timer", "time machine", "days", "3 in", "safari"])
    func leavesSearchesAlone(_ input: String) {
        #expect(!TimeCalculation.looksLikeTimeCalculation(input))
    }
}
