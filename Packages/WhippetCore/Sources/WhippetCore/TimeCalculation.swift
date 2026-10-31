import Foundation
import RegexBuilder

/// The time somewhere else and the time between now and a date: `time in tokyo`, `3pm pst in london`,
/// `15:30 to new york`, `time until dec 25` or `days since 5 may 1990`.
public enum TimeCalculation {
    /// Pasted text is never a time calculation, as for unit conversion.
    private static let maximumLength = 100

    /// The clock, time zone and language to calculate with, which tests set.
    public struct Context: Sendable {
        public var now: Date
        public var timeZone: TimeZone
        public var locale: Locale

        public init(now: Date = .now, timeZone: TimeZone = .current, locale: Locale = .current) {
            self.now = now
            self.timeZone = timeZone
            self.locale = locale
        }

        public var calendar: Calendar {
            var calendar = Calendar.current
            calendar.timeZone = timeZone
            calendar.locale = locale
            return calendar
        }
    }

    public static func calculate(_ input: String, context: Context = Context()) -> Calculation? {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard text.count <= maximumLength, text.first?.isLetter == true || text.first?.isNumber == true else {
            return nil
        }
        return interval(text, context) ?? dateArithmetic(text, context) ?? zoneConversion(text, context)
    }

    /// True for a time calculation on its way, such as `time in`, `3pm in tok` or `today +`, so the launcher keeps the
    /// calculator showing while the place, date or time to add is typed.
    public static func looksLikeTimeCalculation(_ input: String) -> Bool {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard text.count <= maximumLength else { return false }
        if text.contains(/^(?i:time|now)\s+(?i:in|to)(?:\s|$)/) || text.contains(intervalStart) { return true }
        if let sign = text.firstMatch(of: /\s[+-]/),
            startDate(in: String(text[..<sign.range.lowerBound]), Context()) != nil
        {
            return true
        }
        return UnitConversion.splits(text).contains { moment(in: $0.0, Context()) != nil }
    }

    // MARK: - Date arithmetic

    /// A date with time added or taken away, such as `today + 3 weeks`, `dec 25 - 10 days`, `now + 90 min` or
    /// `tomorrow 9am + 2 h 30 min`. Amounts without a sign take the one before, so `+ 2 h 30 min` adds both.
    private static func dateArithmetic(_ text: String, _ context: Context) -> Calculation? {
        // The first sign with a number after it, since a date such as `2026-12-25` has its own.
        guard let start = text.firstMatch(of: /\s[+-]\s*\d/),
            let (date, hasDateTime) = startDate(
                in: String(text[..<start.range.lowerBound]), context
            )
        else { return nil }

        let calendar = context.calendar
        let steps = text[start.range.lowerBound...]
        guard isDuration(steps) else { return nil }
        var result = date
        var isAdding = true
        var addsTime = false
        for match in steps.matches(of: durationStep) {
            if let sign = match.output.1 { isAdding = sign == "+" }
            guard let amount = Double(match.output.2), let unit = durationUnits[match.output.3.lowercased()] else {
                return nil
            }
            let signed = isAdding ? amount : -amount
            if let seconds = unit.seconds {
                result.addTimeInterval(signed * seconds)
                addsTime = true
            } else {
                // Days, weeks, months and years follow the calendar, so they're whole.
                guard amount == amount.rounded(),
                    let added = calendar.date(byAdding: unit.component, value: Int(signed), to: result)
                else { return nil }
                result = added
            }
        }

        let showsTime = hasDateTime || addsTime
        func style(_ width: Date.FormatStyle.Symbol.Weekday, _ month: Date.FormatStyle.Symbol.Month) -> Date.FormatStyle
        {
            let style = Date.FormatStyle(locale: context.locale, calendar: calendar, timeZone: context.timeZone)
                .weekday(width).day().month(month).year()
            return showsTime ? style.hour().minute() : style
        }
        let output = result.formatted(style(.abbreviated, .abbreviated))
        let conversion = Conversion(
            input: date.formatted(style(.abbreviated, .abbreviated)),
            output: output,
            outputLong: result.formatted(style(.wide, .wide)),
            kind: String(localized: "Date", bundle: .module),
            answer: output
        )
        return Calculation(tokens: [], value: result.timeIntervalSince1970, isRPN: false, conversion: conversion)
    }

    /// The date that time is added to: `now`, or a date such as `today`, `dec 25` or `tomorrow 9am`, and whether it
    /// has a time.
    private static func startDate(in rawText: String, _ context: Context) -> (Date, hasTime: Bool)? {
        let text = rawText.trimmingCharacters(in: .whitespaces)
        // The detector reads `1 h` as a time of day, but `1 h + 30 min` is an amount of time.
        guard !text.isEmpty, !isDuration(text[...]) else { return nil }
        if text.lowercased() == "now" { return (context.now, true) }
        return date(in: text, future: true, context)
    }

    /// One amount of time, with the sign that applies from it on, such as `+ 2 h` or `30 min`.
    private static var durationStep: Regex<(Substring, Substring?, Substring, Substring)> {
        /\s*([+-])?\s*(\d+(?:\.\d+)?)\s*([a-zA-Z]+)/
    }

    /// True for text made only of amounts of time, such as `+ 2 h 30 min` or `1 h`, but not `25 dec`.
    private static func isDuration(_ text: Substring) -> Bool {
        text.wholeMatch(of: Regex { OneOrMore(durationStep) }) != nil
            && text.matches(of: durationStep).allSatisfy { durationUnits[$0.output.3.lowercased()] != nil }
    }

    /// Units of time to add, by what people type: the calendar's for days and longer, and seconds for shorter.
    private static let durationUnits: [String: (component: Calendar.Component, seconds: Double?)] = {
        var units: [String: (component: Calendar.Component, seconds: Double?)] = [:]
        func add(_ keys: [String], _ component: Calendar.Component, _ seconds: Double? = nil) {
            for key in keys { units[key] = (component, seconds) }
        }
        add(["y", "yr", "yrs", "year", "years"], .year)
        add(["mo", "mos", "month", "months"], .month)
        add(["w", "wk", "wks", "week", "weeks"], .weekOfYear)
        add(["d", "day", "days"], .day)
        add(["h", "hr", "hrs", "hour", "hours"], .hour, 3600)
        add(["m", "min", "mins", "minute", "minutes"], .minute, 60)
        add(["s", "sec", "secs", "second", "seconds"], .second, 1)
        return units
    }()

    // MARK: - Time since and until

    /// `time until`, or a unit such as `days until`, with `since`, `until`, `till` or `til`.
    private static var intervalStart: Regex<(Substring, Substring, Substring)> {
        /^(?i:(time|years?|months?|weeks?|days?|hours?|minutes?|seconds?))\s+(?i:(since|until|till|til))(?:\s|$)/
    }

    private static func interval(_ text: String, _ context: Context) -> Calculation? {
        guard let match = text.prefixMatch(of: intervalStart) else { return nil }
        let isSince = match.2.lowercased() == "since"
        let unit = component(named: match.1.lowercased())
        guard let (target, hasTime) = date(in: String(text[match.range.upperBound...]), future: !isSince, context)
        else { return nil }

        let calendar = context.calendar
        // Whole days count from the start of today, so `days until dec 25` doesn't depend on the time it's asked.
        let wholeDays: Set<Calendar.Component> = [.year, .month, .weekOfMonth, .day]
        let now = !hasTime && unit.map(wholeDays.contains) == true ? calendar.startOfDay(for: context.now) : context.now
        let (start, end) = isSince ? (target, now) : (now, target)

        let breakdown = durationFormatter(calendar: calendar, units: [.year, .month, .day, .hour, .minute, .second])
        breakdown.maximumUnitCount = 3
        breakdown.unitsStyle = .full
        guard let long = breakdown.string(from: start, to: end) else { return nil }

        let output: String
        let answer: String
        let value: Double
        if let unit {
            let single = durationFormatter(calendar: calendar, units: [unit])
            single.unitsStyle = .full
            let count = calendar.dateComponents([unit], from: start, to: end).value(for: unit) ?? 0
            guard let formatted = single.string(from: start, to: end) else { return nil }
            (output, answer, value) = (formatted, String(count), Double(count))
        } else {
            breakdown.unitsStyle = .abbreviated
            guard let short = breakdown.string(from: start, to: end) else { return nil }
            (output, answer, value) = (short, short, end.timeIntervalSince(start))
        }

        var style = Date.FormatStyle(locale: context.locale, calendar: calendar, timeZone: context.timeZone)
            .weekday(.abbreviated).day().month(.abbreviated).year()
        if hasTime { style = style.hour().minute() }
        let conversion = Conversion(
            input: target.formatted(style),
            output: output,
            outputLong: long,
            kind: isSince
                ? String(localized: "Time Since", bundle: .module) : String(localized: "Time Until", bundle: .module),
            answer: answer
        )
        return Calculation(tokens: [], value: value, isRPN: false, conversion: conversion)
    }

    private static func component(named word: String) -> Calendar.Component? {
        switch word.hasSuffix("s") ? String(word.dropLast()) : word {
        case "year": .year
        case "month": .month
        case "week": .weekOfMonth
        case "day": .day
        case "hour": .hour
        case "minute": .minute
        case "second": .second
        default: nil
        }
    }

    private static func durationFormatter(calendar: Calendar, units: [Calendar.Component]) -> DateComponentsFormatter {
        let flags: [Calendar.Component: NSCalendar.Unit] = [
            .year: .year, .month: .month, .weekOfMonth: .weekOfMonth, .day: .day, .hour: .hour, .minute: .minute,
            .second: .second,
        ]
        let formatter = DateComponentsFormatter()
        formatter.calendar = calendar
        formatter.allowedUnits = NSCalendar.Unit(units.compactMap { flags[$0] })
        return formatter
    }

    /// Reads dates as written in English, such as `dec 25`, `5 may 1990`, `next friday`, `tomorrow 5pm` or
    /// `2026-12-25 18:00`. It's read-only once made, which Foundation allows from any thread.
    nonisolated(unsafe) private static let detector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.date.rawValue
    )

    /// The date the whole text names, at the start of its day unless it gives a time. A date without a year is the
    /// nearest one in the direction asked, so `since dec 25` is last Christmas and `until oct 1` is next October.
    private static func date(in rawText: String, future: Bool, _ context: Context) -> (Date, hasTime: Bool)? {
        let text = rawText.trimmingCharacters(in: .whitespaces)
        let range = NSRange(text.startIndex..., in: text)
        guard
            let detector, let match = detector.firstMatch(in: text, range: range), match.range == range,
            var date = match.date
        else { return nil }

        let calendar = context.calendar
        // The detector reads a clock time in the system's time zone, so it's read again as the same clock time in the
        // context's, unless the text names a zone.
        if match.timeZone == nil {
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second], from: date)
            date = calendar.date(from: components) ?? date
        }
        let hasTime = text.contains(/\d\s*(?i:[ap]\.?m)|\d:\d\d/)
        if !hasTime {
            date = calendar.startOfDay(for: date)
        }
        let isWrongWay = future ? date < context.now : date > context.now
        if isWrongWay, !text.contains(/\d{4}/) {
            let lowered = text.lowercased()
            let namesWeekday = weekdayNames.contains { lowered.contains($0) }
            let step: Calendar.Component? = namesWeekday ? .weekOfYear : text.contains(/\d/) ? .year : nil
            if let step, let shifted = calendar.date(byAdding: step, value: future ? 1 : -1, to: date) {
                date = shifted
            }
        }
        return (date, hasTime)
    }

    private static let weekdayNames: [String] = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return (calendar.weekdaySymbols + calendar.shortWeekdaySymbols).map { $0.lowercased() }
    }()

    // MARK: - Time zones

    /// `<time> in <place>`, where the time is `time` or `now`, or a time of day today with an optional place:
    /// `time in tokyo`, `3pm in london`, `9:30 am pst to cet`.
    private static func zoneConversion(_ text: String, _ context: Context) -> Calculation? {
        for (sourceText, targetText) in UnitConversion.splits(text) {
            guard let target = zone(named: targetText), let (date, source) = moment(in: sourceText, context) else {
                continue
            }
            let sourceStyle = Date.FormatStyle(locale: context.locale, timeZone: source)
            let targetStyle = Date.FormatStyle(locale: context.locale, timeZone: target)
            var sourceCalendar = context.calendar
            sourceCalendar.timeZone = source
            var targetCalendar = context.calendar
            targetCalendar.timeZone = target
            let isSameDay =
                sourceCalendar.dateComponents([.year, .month, .day], from: date)
                == targetCalendar.dateComponents([.year, .month, .day], from: date)

            let output = date.formatted(isSameDay ? targetStyle.hour().minute() : targetStyle.weekday().hour().minute())
            let conversion = Conversion(
                input: date.formatted(sourceStyle.hour().minute()),
                output: output,
                outputLong:
                    "\(date.formatted(targetStyle.weekday(.wide).day().month(.wide))) · \(name(of: target, context))",
                kind: name(of: source, context),
                answer: output
            )
            return Calculation(tokens: [], value: date.timeIntervalSince1970, isRPN: false, conversion: conversion)
        }
        return nil
    }

    /// `time` or `now`, or a time of day today in the local time zone or the place that follows it.
    private static func moment(in text: String, _ context: Context) -> (Date, TimeZone)? {
        if ["time", "now"].contains(text.lowercased()) { return (context.now, context.timeZone) }
        if let date = today(at: text, in: context.timeZone, context) { return (date, context.timeZone) }
        for space in text.indices where text[space] == " " {
            if let zone = zone(named: String(text[space...])),
                let date = today(at: String(text[..<space]), in: zone, context)
            {
                return (date, zone)
            }
        }
        return nil
    }

    /// A time of day, such as `3pm`, `9:30 a.m.`, `15:30` or `noon`, today in the given time zone.
    private static func today(at rawText: String, in zone: TimeZone, _ context: Context) -> Date? {
        let text = rawText.trimmingCharacters(in: .whitespaces).lowercased()
        var hour: Int
        var minute = 0
        if text == "noon" {
            hour = 12
        } else if text == "midnight" {
            hour = 0
        } else if let match = text.wholeMatch(of: /(\d{1,2})(?::(\d{2}))?\s*([ap])\.?m\.?/) {
            guard let parsed = Int(match.1), (1...12).contains(parsed) else { return nil }
            hour = parsed % 12 + (match.3 == "p" ? 12 : 0)
            minute = match.2.flatMap { Int($0) } ?? 0
        } else if let match = text.wholeMatch(of: /(\d{1,2}):(\d{2})/) {
            guard let parsed = Int(match.1), parsed < 24 else { return nil }
            hour = parsed
            minute = Int(match.2) ?? 0
        } else {
            return nil
        }
        guard minute < 60 else { return nil }
        var calendar = context.calendar
        calendar.timeZone = zone
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: context.now)
    }

    /// A time zone by city, such as `tokyo` or `new york`, its identifier, such as `Asia/Tokyo`, a nickname or country
    /// with one time zone, such as `nyc` or `japan`, an abbreviation, such as `pst` or `cet`, or an offset, such as
    /// `utc+2`.
    public static func zone(named rawText: String) -> TimeZone? {
        let text = rawText.trimmingCharacters(in: .whitespaces)
        let key = normalized(text)
        guard !key.isEmpty else { return nil }
        if let identifier = aliases[key] ?? cities[key] { return TimeZone(identifier: identifier) }
        // Identifiers macOS doesn't list but knows, such as `Asia/Kolkata` for `Asia/Calcutta`.
        if text.contains("/"), let zone = TimeZone(identifier: text) { return zone }
        if let match = text.lowercased().wholeMatch(of: /(?:utc|gmt) ?([+-])(\d{1,2})(?::?(\d{2}))?/) {
            guard let hours = Int(match.2), hours <= 14 else { return nil }
            let minutes = match.3.flatMap { Int($0) } ?? 0
            let seconds = (hours * 3600 + minutes * 60) * (match.1 == "-" ? -1 : 1)
            return TimeZone(secondsFromGMT: seconds)
        }
        guard key.count >= 2, key.count <= 5, key.allSatisfy(\.isLetter) else { return nil }
        if let identifier = abbreviations[key] { return TimeZone(identifier: identifier) }
        return TimeZone(abbreviation: key.uppercased())
    }

    /// Lowercased without accents, with `_` and `-` as spaces, so `Sao_Paulo` and `são paulo` match.
    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
    }

    /// Every identifier, such as `america/new york`, and its city, such as `new york`.
    private static let cities: [String: String] = {
        var cities: [String: String] = [:]
        for identifier in TimeZone.knownTimeZoneIdentifiers {
            cities[normalized(identifier)] = identifier
            if let city = identifier.split(separator: "/").last, cities[normalized(String(city))] == nil {
                cities[normalized(String(city))] = identifier
            }
        }
        return cities
    }()

    /// Places people name that aren't a time zone's city, by normalized text.
    private static let aliases: [String: String] = {
        var aliases: [String: String] = [:]
        func add(_ keys: [String], _ identifier: String) {
            for key in keys { aliases[key] = identifier }
        }
        add(
            ["nyc", "new york city", "boston", "washington", "dc", "miami", "atlanta", "philadelphia"],
            "America/New_York")
        add(["sf", "san francisco", "la", "seattle", "portland", "san diego", "california"], "America/Los_Angeles")
        add(["austin", "dallas", "houston", "texas"], "America/Chicago")
        add(["hawaii"], "Pacific/Honolulu")
        add(["uk", "england", "britain", "great britain", "scotland"], "Europe/London")
        add(["ireland"], "Europe/Dublin")
        add(["germany", "munich", "frankfurt", "hamburg"], "Europe/Berlin")
        add(["france"], "Europe/Paris")
        add(["spain", "barcelona"], "Europe/Madrid")
        add(["italy", "milan"], "Europe/Rome")
        add(["netherlands"], "Europe/Amsterdam")
        add(["switzerland", "geneva"], "Europe/Zurich")
        add(["india", "kolkata", "mumbai", "delhi", "new delhi", "bangalore", "bengaluru"], "Asia/Kolkata")
        add(["china", "beijing"], "Asia/Shanghai")
        add(["japan", "osaka", "kyoto"], "Asia/Tokyo")
        add(["korea", "south korea"], "Asia/Seoul")
        add(["iran"], "Asia/Tehran")
        add(["israel", "tel aviv"], "Asia/Jerusalem")
        add(["uae", "abu dhabi"], "Asia/Dubai")
        add(["brazil", "rio", "rio de janeiro"], "America/Sao_Paulo")
        add(["new zealand", "nz"], "Pacific/Auckland")
        return aliases
    }()

    /// Abbreviations Foundation doesn't know, and generic ones for regions whose clocks change.
    private static let abbreviations = [
        "et": "America/New_York", "ct": "America/Chicago", "mt": "America/Denver", "pt": "America/Los_Angeles",
        "aest": "Australia/Sydney", "aedt": "Australia/Sydney", "acst": "Australia/Adelaide",
        "awst": "Australia/Perth", "nzst": "Pacific/Auckland", "nzdt": "Pacific/Auckland", "sgt": "Asia/Singapore",
        "hkt": "Asia/Hong_Kong", "kst": "Asia/Seoul", "msk": "Europe/Moscow",
    ]

    /// The zone's name, such as `Japan Standard Time` or `GMT+02:00`.
    private static func name(of zone: TimeZone, _ context: Context) -> String {
        zone.localizedName(for: .generic, locale: context.locale) ?? zone.identifier
    }
}
