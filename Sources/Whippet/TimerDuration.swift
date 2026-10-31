import Foundation

/// Reads a timer typed into the search bar, such as `25m`, `1h30m`, `4:30` or `timer 5 tea`: a duration, then an
/// optional name.
enum TimerDuration {
    struct Parsed: Equatable {
        let seconds: Int
        /// What follows the duration, or nil when nothing does.
        let name: String?
    }

    /// The longest timer, the same week Caffeinate allows.
    static let maximumSeconds = CaffeineDuration.maximumSeconds

    /// A leading `timer` is optional. Without it a number needs a unit, so a plain number stays a calculation; with it,
    /// or when `plainNumberIsMinutes` is set, a plain number counts as minutes.
    static func parse(_ input: String, plainNumberIsMinutes: Bool = false) -> Parsed? {
        var scanner = Scanner(text: normalized(input))
        let hasKeyword = scanner.skipKeyword()
        guard
            let seconds = scanner.clock() ?? scanner.units()
                ?? scanner.plainMinutes(allowed: hasKeyword || plainNumberIsMinutes)
        else { return nil }
        guard scanner.isAtEnd || scanner.skipSpaces() else { return nil }
        guard seconds > 0, seconds <= Double(maximumSeconds) else { return nil }
        let name = scanner.remainder.trimmingCharacters(in: .whitespaces)
        return Parsed(seconds: Int(seconds.rounded()), name: name.isEmpty ? nil : name)
    }

    /// With Farsi and Arabic digits as ASCII, so `۲۵ دقیقه` reads like `25 دقیقه`.
    private static func normalized(_ input: String) -> String {
        let digits = input.map { character -> Character in
            guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else {
                return character
            }
            switch scalar.value {
            case 0x06F0...0x06F9: return Character(String(scalar.value - 0x06F0))
            case 0x0660...0x0669: return Character(String(scalar.value - 0x0660))
            case 0x066B: return "."
            default: return character
            }
        }
        return String(digits).trimmingCharacters(in: .whitespaces)
    }

    /// Longest first within each unit, so `min` isn't read as `m` followed by `in`.
    private static let units: [(names: [String], seconds: Double)] = [
        (["hours", "hour", "hrs", "hr", "h", "ساعت"], 3600),
        (["minutes", "minute", "mins", "min", "m", "دقیقه"], 60),
        (["seconds", "second", "secs", "sec", "s", "ثانیه"], 1),
    ]

    private static let keywords = ["timer", "تایمر"]

    private struct Scanner {
        let characters: [Character]
        var index = 0

        init(text: String) {
            characters = Array(text)
        }

        var isAtEnd: Bool { index == characters.count }
        var remainder: String { String(characters[index...]) }

        /// Skips at least one space, returning false when there was none.
        mutating func skipSpaces() -> Bool {
            let start = index
            while index < characters.count, characters[index].isWhitespace { index += 1 }
            return index > start
        }

        mutating func skipKeyword() -> Bool {
            for keyword in TimerDuration.keywords where startsWord(keyword) {
                let start = index
                index += keyword.count
                if skipSpaces() { return true }
                index = start
            }
            return false
        }

        /// `m:ss` or `h:mm:ss`.
        mutating func clock() -> Double? {
            let start = index
            var parts: [Int] = []
            while let part = integer() {
                parts.append(part)
                guard index < characters.count, characters[index] == ":", parts.count < 3 else { break }
                index += 1
            }
            guard parts.count >= 2, parts.dropFirst().allSatisfy({ $0 < 60 }), endsWord else {
                index = start
                return nil
            }
            return parts.reduce(0) { Double($0) * 60 + Double($1) }
        }

        /// One or more amounts with units, such as `1h30m` or `1 hour 30 min`, each unit used once and largest first.
        mutating func units() -> Double? {
            let start = index
            var total: Double = 0
            var nextUnit = 0
            // Where the last amount with a unit ended, before any spaces, so a number that turns out to start the name
            // leaves the space in front of it.
            var afterPrevious: Int?
            while true {
                let partStart = index
                guard let amount = decimal() else {
                    index = afterPrevious ?? partStart
                    break
                }
                _ = skipSpaces()
                guard let unit = unit(from: nextUnit) else {
                    index = afterPrevious ?? partStart
                    break
                }
                total += amount * TimerDuration.units[unit].seconds
                nextUnit = unit + 1
                let afterPart = index
                _ = skipSpaces()
                guard startsNumber else {
                    index = afterPart
                    break
                }
                afterPrevious = afterPart
            }
            guard nextUnit > 0 else {
                index = start
                return nil
            }
            return total
        }

        mutating func plainMinutes(allowed: Bool) -> Double? {
            guard allowed else { return nil }
            let start = index
            guard let amount = decimal(), endsWord else {
                index = start
                return nil
            }
            return amount * 60
        }

        /// The first unit, from `first` on, whose name is next and ends a word.
        private mutating func unit(from first: Int) -> Int? {
            for unit in first..<TimerDuration.units.count {
                for name in TimerDuration.units[unit].names where startsWord(name) {
                    let start = index
                    index += name.count
                    if endsWord || startsNumber { return unit }
                    index = start
                }
            }
            return nil
        }

        private func startsWord(_ word: String) -> Bool {
            let end = index + word.count
            return end <= characters.count && String(characters[index..<end]).lowercased() == word
        }

        private var endsWord: Bool { isAtEnd || characters[index].isWhitespace }
        private var startsNumber: Bool { !isAtEnd && characters[index].isASCIIDigit }

        private mutating func integer() -> Int? {
            let start = index
            while index < characters.count, characters[index].isASCIIDigit, index - start < 9 { index += 1 }
            guard index > start, !startsNumber else {
                index = start
                return nil
            }
            return Int(String(characters[start..<index]))
        }

        private mutating func decimal() -> Double? {
            let start = index
            guard integer() != nil else { return nil }
            if index < characters.count, characters[index] == ".", index + 1 < characters.count,
                characters[index + 1].isASCIIDigit
            {
                index += 1
                _ = integer()
            }
            return Double(String(characters[start..<index]))
        }
    }
}

extension Character {
    fileprivate var isASCIIDigit: Bool {
        ("0"..."9").contains(self)
    }
}
