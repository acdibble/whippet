import Testing

struct CalculatorTests {
    @Test(arguments: [
        ("2 + 3 * 4", 14.0),
        ("(2 + 3) * 4", 20),
        ("7 / 2", 3.5),
        ("10 % 3", 1),
        ("-3 + 5", 2),
        ("2 * -3", -6),
        ("2 ^ 3 ^ 2", 512),
        ("-2 ^ 2", -4),
    ])
    func infix(_ input: String, _ expected: Double) throws {
        let calculation = try #require(Calculator.evaluate(input))
        #expect(calculation.value == expected)
        #expect(!calculation.isRPN)
    }

    @Test(arguments: [
        ("3 4 +", 7.0),
        ("5 1 2 + 4 * + 3 -", 14),
        ("3 -2 *", -6),
        ("2 3 ^", 8),
    ])
    func reversePolish(_ input: String, _ expected: Double) throws {
        let calculation = try #require(Calculator.evaluate(input))
        #expect(calculation.value == expected)
        #expect(calculation.isRPN)
    }

    @Test(arguments: ["42", "", "  ", "abc", "2 +", "(2 + 3", "3 4", "1 + * 2"])
    func notACalculation(_ input: String) {
        #expect(Calculator.evaluate(input) == nil)
    }

    @Test(arguments: [
        ("1,000 + 1", 1001.0),
        ("1,234,567 * 1", 1_234_567),
        ("1_000 * 2", 2000),
        ("1.5 + .5", 2),
    ])
    func separators(_ input: String, _ expected: Double) throws {
        #expect(try #require(Calculator.evaluate(input)).value == expected)
    }

    @Test(arguments: ["3,5 + 1", "1,00 + 1", "1.2.3 + 1"])
    func malformedSeparators(_ input: String) {
        #expect(Calculator.evaluate(input) == nil)
    }

    @Test(arguments: [
        ("0xFF + 1", 256.0),
        ("0XFF + 1", 256),
        ("0xFF_FF + 0", 65535),
        ("0b101 * 2", 10),
        ("0o17 + 1", 16),
    ])
    func radixes(_ input: String, _ expected: Double) throws {
        #expect(try #require(Calculator.evaluate(input)).value == expected)
    }

    @Test(arguments: ["10 ^ 400", "1 / 0", "0 / 0", "0x1FFFFFFFFFFFFFFFF + 1"])
    func overflowIsNotACalculation(_ input: String) {
        #expect(Calculator.evaluate(input) == nil)
    }

    /// Built here rather than passed as arguments, which the test log would print in full.
    @Test(arguments: ["brackets", "signs", "exponents"])
    func deepNestingIsNotACalculation(_ nesting: String) {
        let depth = 100_000
        let input = switch nesting {
        case "brackets": String(repeating: "(", count: depth) + "1"
        case "signs": String(repeating: "-", count: depth) + "1 + 1"
        default: Array(repeating: "2", count: depth).joined(separator: "^")
        }
        #expect(Calculator.evaluate(input) == nil)
    }

    @Test func moderateNestingStillEvaluates() throws {
        let nested = String(repeating: "(", count: 50) + "1 + 1" + String(repeating: ")", count: 50)
        #expect(try #require(Calculator.evaluate(nested)).value == 2)
        #expect(try #require(Calculator.evaluate(String(repeating: "-", count: 50) + "1 + 1")).value == 2)
    }

    @Test(arguments: [
        (0.1 + 0.2, "0.3"),
        (1_000_000, "1000000"),
        (-2.5, "-2.5"),
        (1.0 / 3, "0.333333333333333"),
    ])
    func format(_ value: Double, _ expected: String) {
        #expect(Calculator.format(value) == expected)
    }

    @Test(arguments: [
        ("1 + 2 + 3", "Sum"),
        ("6 * 7", "Product"),
        ("1 + 2 * 3", "Expression"),
    ])
    func operationName(_ input: String, _ expected: String) throws {
        #expect(try #require(Calculator.evaluate(input)).operationName == expected)
    }

    @Test(arguments: [
        ("$1,234.50", 1234.5 as Double?),
        ("-12", -12),
        ("+0x10", 16),
        ("12€", 12),
        ("1,23", nil),
        ("12 apples", nil),
    ])
    func parseNumber(_ input: String, _ expected: Double?) {
        #expect(Calculator.parseNumber(input) == expected)
    }
}

struct ClipboardKindTests {
    @Test(arguments: [
        ("42", ClipboardKind.number),
        ("1,234.5", .number),
        ("https://example.com/path", .link),
        ("  http://example.com  ", .link),
        ("ftp://example.com", .text),
        ("https://example.com and more", .text),
        ("hello world", .text),
    ])
    func classify(_ text: String, _ expected: ClipboardKind) {
        #expect(ClipboardKind.classify(text) == expected)
    }
}

struct FuzzyMatchTests {
    @Test func emptyQueryMatchesEverything() {
        #expect(FuzzyMatch.score("", in: "Safari") == 0)
    }

    @Test func requiresCharactersInOrder() {
        #expect(FuzzyMatch.score("sfr", in: "Safari") != nil)
        #expect(FuzzyMatch.score("rfs", in: "Safari") == nil)
        #expect(FuzzyMatch.score("x", in: "Safari") == nil)
    }

    @Test func ignoresCase() {
        #expect(FuzzyMatch.score("SAF", in: "safari") == FuzzyMatch.score("saf", in: "Safari"))
    }

    @Test func prefersPrefixesWordStartsAndShortNames() throws {
        let prefix = try #require(FuzzyMatch.score("cal", in: "Calendar"))
        let scattered = try #require(FuzzyMatch.score("cal", in: "Chemical"))
        #expect(prefix > scattered)

        let wordStarts = try #require(FuzzyMatch.score("vs", in: "Visual Studio"))
        let inside = try #require(FuzzyMatch.score("vs", in: "Previews"))
        #expect(wordStarts > inside)

        let short = try #require(FuzzyMatch.score("notes", in: "Notes"))
        let long = try #require(FuzzyMatch.score("notes", in: "Notes and a Very Long Application Name"))
        #expect(short > long)
    }
}
