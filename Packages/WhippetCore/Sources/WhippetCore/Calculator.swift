import Foundation

public struct Calculation: Hashable, Sendable {
    public let tokens: [Calculator.Token]
    public let value: Double
    public let isRPN: Bool
    /// Set for a unit conversion, whose value is in the target unit.
    public var conversion: Conversion?

    /// The number copied or pasted.
    public var answer: String {
        guard let conversion else { return Calculator.format(value) }
        return conversion.answer ?? Calculator.format(value, significantDigits: UnitConversion.significantDigits)
    }

    /// The answer as shown, with its unit for a conversion.
    public var displayAnswer: String {
        conversion?.output ?? answer
    }

    /// A number on its own, such as `0xFF`, shown with its value but not kept in calculator history.
    public var isPlainNumber: Bool {
        conversion == nil && !tokens.contains { if case .number = $0 { false } else { $0 != .open && $0 != .close } }
    }

    /// Names the operation when the input uses a single kind of operator, or what a conversion measures.
    public var operationName: String {
        if let conversion { return conversion.kind }
        if !isRPN, tokens.contains(.percent) { return String(localized: "Percentage", bundle: .module) }
        let operations = Set(
            tokens.compactMap { token -> Character? in
                guard case .operation(let operation) = token else { return nil }
                return operation
            })
        if operations.isEmpty { return String(localized: "Number", bundle: .module) }
        guard operations.count == 1, let operation = operations.first else {
            return String(localized: "Expression", bundle: .module)
        }
        switch operation {
        case "+": return String(localized: "Sum", bundle: .module)
        case "-": return String(localized: "Difference", bundle: .module)
        case "*": return String(localized: "Product", bundle: .module)
        case "/": return String(localized: "Quotient", bundle: .module)
        case "%": return String(localized: "Remainder", bundle: .module)
        default: return String(localized: "Power", bundle: .module)
        }
    }

    public var spelledAnswer: String {
        if let conversion { return conversion.outputLong }
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        let words = formatter.string(from: NSNumber(value: value)) ?? answer
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}

public enum Calculator {
    /// Evaluates `input` as standard notation, falling back to reverse Polish notation, or returns nil when it is neither.
    /// The two cannot both succeed: standard notation puts an operator between operands, which underflows the RPN stack.
    /// Input without an operator, such as a bare number, is not a calculation.
    static func evaluate(_ input: String) -> Calculation? {
        guard let tokens = tokenize(input) else { return nil }
        var parser = InfixParser(tokens: tokens)
        if let value = parser.parse(), value.isFinite {
            return Calculation(tokens: tokens, value: value, isRPN: false)
        }
        for rpnTokens in [tokens, tokenize(input, signedNumbers: true)].compactMap({ $0 }) {
            if let value = evaluateRPN(rpnTokens), value.isFinite {
                return Calculation(tokens: rpnTokens, value: value, isRPN: true)
            }
        }
        return nil
    }

    /// True for input that is, or is on its way to being, a calculation, such as `2+` or `(3`, so the launcher can
    /// treat it as one while it's typed instead of switching to search results between keystrokes.
    public static func looksLikeCalculation(_ input: String) -> Bool {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard let first = text.first, first.isASCIIDigit || "(.-+".contains(first) else { return false }
        // Letters only belong to radix literals such as 0xFF and to a percentage's word, as in `20% of`, or the word
        // being typed, as in `20% o`, so those are set aside first.
        let withoutLetters =
            text
            .replacingOccurrences(
                of: "0[xX][0-9a-fA-F_]*|0[bB][01_]*|0[oO][0-7_]*", with: "0", options: .regularExpression
            )
            .replacingOccurrences(of: #"%\s*(?i:off?|on?)\b"#, with: "%", options: .regularExpression)
        return withoutLetters.allSatisfy { $0.isASCIIDigit || $0.isWhitespace || "+-*/%^().,_".contains($0) }
    }

    /// A plain number, read like a copied one, so `0xFF`, `1,000.5` and `-4` show their value.
    static func evaluateNumber(_ input: String) -> Calculation? {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard let value = parseNumber(text), value.isFinite else { return nil }
        return Calculation(tokens: [.number(value, literal: text)], value: value, isRPN: false)
    }

    /// Without grouping, and to `significantDigits`, which conversions lower to hide floating-point noise.
    public static func format(_ value: Double, significantDigits: Int = 15) -> String {
        value.formatted(
            .number.locale(Locale(identifier: "en_US_POSIX")).grouping(.never)
                .precision(.significantDigits(1...significantDigits))
        )
    }

    public enum Token: Hashable, Sendable {
        case number(Double, literal: String)
        case operation(Character)
        /// A `%` after a number that isn't followed by another, as in `20%` or `50 + 20%`, rather than a remainder.
        case percent
        /// What a percentage is of: `of`, `off` or `on`, as in `20% of 50`, `15% off 80` or `15% on 80`.
        case word(String)
        case open
        case close
    }

    private static let operators: Set<Character> = ["+", "-", "*", "/", "%", "^"]
    private static let words: Set<String> = ["of", "off", "on"]

    /// With `signedNumbers`, a `-` that starts a word and is followed by a digit belongs to the number, as RPN needs for `3 -2 *`.
    /// A `%` is a remainder when a number or bracket follows it, as in `10 % 3`, and a percentage otherwise.
    private static func tokenize(_ input: String, signedNumbers: Bool = false) -> [Token]? {
        var tokens: [Token] = []
        var index = input.startIndex
        while index < input.endIndex {
            let char = input[index]
            let next = input.index(after: index)
            let startsWord = index == input.startIndex || input[input.index(before: index)].isWhitespace
            let isSigned =
                signedNumbers && char == "-" && startsWord && next < input.endIndex && input[next].isASCIIDigit
            if char == "." || char.isASCIIDigit || isSigned {
                let end = numberEnd(in: input, from: isSigned ? next : index)
                let literal = String(input[index..<end])
                guard let value = parseNumber(literal) else { return nil }
                tokens.append(.number(value, literal: literal))
                index = end
                continue
            }

            if char.isLetter {
                let end = input[index...].firstIndex { !$0.isLetter } ?? input.endIndex
                let word = input[index..<end].lowercased()
                guard words.contains(word) else { return nil }
                tokens.append(.word(word))
                index = end
                continue
            }

            switch char {
            case _ where char.isWhitespace: break
            case "%":
                let following = input[next...].first { !$0.isWhitespace }
                let isRemainder = following.map { $0.isASCIIDigit || ".(".contains($0) } ?? false
                tokens.append(isRemainder ? .operation(char) : .percent)
            case _ where operators.contains(char): tokens.append(.operation(char))
            case "(": tokens.append(.open)
            case ")": tokens.append(.close)
            default: return nil
            }
            index = input.index(after: index)
        }
        return tokens
    }

    /// Finds the end of a number literal: a radix-prefixed run like `0xFF_FF`, or digits with `.`, `,` and `_` separators.
    static func numberEnd(in input: String, from start: String.Index) -> String.Index {
        // Only the first two characters, since lowercasing the whole rest for every number is quadratic in long input.
        let prefix = input[start...].prefix(2).lowercased()
        let isPrefixed = ["0x", "0b", "0o"].contains(prefix)
        var end = isPrefixed ? input.index(start, offsetBy: 2) : start
        while end < input.endIndex {
            let char = input[end]
            let continues = isPrefixed ? char.isHexDigit || char == "_" : char.isASCIIDigit || ".,_".contains(char)
            guard continues else { break }
            end = input.index(after: end)
        }
        return end
    }

    /// Parses one number: decimal with `,` thousands separators or `_` groupings, or `0x` hex, `0b` binary or `0o` octal,
    /// with an optional sign and a leading or trailing currency symbol. A comma that is not a thousands separator, as in `3,5`, is rejected.
    static func parseNumber(_ input: String) -> Double? {
        var text = Substring(input.trimmingCharacters(in: .whitespacesAndNewlines))
        if let first = text.first, first.isCurrencySymbol { text.removeFirst() }
        if let last = text.last, last.isCurrencySymbol { text.removeLast() }
        var sign = 1.0
        if let first = text.first, first == "-" || first == "+" {
            sign = first == "-" ? -1 : 1
            text.removeFirst()
        }

        for (prefix, radix) in [("0x", 16), ("0b", 2), ("0o", 8)] where text.lowercased().hasPrefix(prefix) {
            let digits = text.dropFirst(2).replacingOccurrences(of: "_", with: "")
            return UInt64(digits, radix: radix).map { sign * Double($0) }
        }

        guard !text.isEmpty, text.allSatisfy({ $0.isASCIIDigit || ".,_".contains($0) }) else { return nil }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, parts.count == 1 || !parts[1].contains(",") else { return nil }
        let groups = parts[0].split(separator: ",", omittingEmptySubsequences: false)
        if groups.count > 1 {
            guard (1...3).contains(groups[0].count), groups.dropFirst().allSatisfy({ $0.count == 3 }) else {
                return nil
            }
        }
        let digits = text.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "_", with: "")
        return Double(digits).map { sign * $0 }
    }

    private static func evaluateRPN(_ tokens: [Token]) -> Double? {
        var stack: [Double] = []
        var appliedOperator = false
        for token in tokens {
            switch token {
            case .number(let value, _):
                stack.append(value)
            case .operation, .percent:
                // A `%` at the end, as in `7 3 %`, is still the remainder.
                guard stack.count >= 2 else { return nil }
                let rhs = stack.removeLast()
                let lhs = stack.removeLast()
                let operation: Character = if case .operation(let operation) = token { operation } else { "%" }
                stack.append(apply(operation, lhs, rhs))
                appliedOperator = true
            case .word, .open, .close:
                return nil
            }
        }
        guard appliedOperator, stack.count == 1 else { return nil }
        return stack[0]
    }

    static func apply(_ operation: Character, _ lhs: Double, _ rhs: Double) -> Double {
        switch operation {
        case "+": lhs + rhs
        case "-": lhs - rhs
        case "*": lhs * rhs
        case "/": lhs / rhs
        case "%": lhs.truncatingRemainder(dividingBy: rhs)
        default: pow(lhs, rhs)
        }
    }
}

/// Shows a number or calculation in another base: `255 in hex`, `0xFF to binary`, `0b1010 as decimal` or
/// `(12 + 4) in octal`, as a literal that can be typed back in, such as `0xFF`.
public enum BaseConversion {
    private static let bases: [String: (radix: Int, prefix: String, kind: String)] = {
        let hex = (16, "0x", String(localized: "Hexadecimal", bundle: .module))
        let binary = (2, "0b", String(localized: "Binary", bundle: .module))
        let octal = (8, "0o", String(localized: "Octal", bundle: .module))
        let decimal = (10, "", String(localized: "Decimal", bundle: .module))
        return [
            "hex": hex, "hexadecimal": hex, "binary": binary, "bin": binary, "octal": octal, "oct": octal,
            "decimal": decimal, "dec": decimal,
        ]
    }()

    static func convert(_ input: String) -> Calculation? {
        let text = input.trimmingCharacters(in: .whitespaces)
        for (amountText, targetText) in UnitConversion.splits(text) {
            guard
                let base = bases[targetText.lowercased()],
                let value = Calculator.number(amountText),
                value == value.rounded(), abs(value) < 0x1p63
            else { continue }
            let integer = Int64(value)
            let digits = String(integer.magnitude, radix: base.radix, uppercase: true)
            let output = (integer < 0 ? "-" : "") + base.prefix + digits
            let conversion = Conversion(
                input: amountText, output: output, outputLong: output, kind: base.kind, answer: output)
            return Calculation(tokens: [], value: value, isRPN: false, conversion: conversion)
        }
        return nil
    }

    /// True while the base is typed after a number, such as `255 in h`, so the calculator stays showing.
    public static func looksLikeConversion(_ input: String) -> Bool {
        let text = input.trimmingCharacters(in: .whitespaces)
        return UnitConversion.splits(text).contains { amountText, targetText in
            let typed = targetText.lowercased()
            return !typed.isEmpty && bases.keys.contains { $0.hasPrefix(typed) } && Calculator.number(amountText) != nil
        }
    }
}

/// Recursive descent over `expression := term (+|- term)*`, `term := unary (*|/|%|of|off|on unary)*`,
/// `unary := (+|-) unary | power`, right-associative `power := percentage (^ unary)?` and `percentage := primary %?`.
/// Adding or taking away a percentage changes by that share, so `50 + 20%` is 60, and `20% of 50` is 10.
private struct InfixParser {
    /// Every recursion, through brackets, signs or exponents, passes through `unary`, so limiting its depth keeps
    /// pasted input like thousands of `(` from overflowing the main thread's stack.
    private static let maxDepth = 100

    /// A value, and whether it was written as a percentage, which `+`, `-` and `of` treat as a share of the other side.
    private struct Operand {
        var value: Double
        var isPercent = false
    }

    let tokens: [Calculator.Token]
    private var position = 0
    private var sawBinaryOperator = false
    private var depth = 0

    init(tokens: [Calculator.Token]) {
        self.tokens = tokens
    }

    mutating func parse() -> Double? {
        guard let operand = expression(), position == tokens.count, sawBinaryOperator else { return nil }
        return operand.value
    }

    private var next: Calculator.Token? {
        tokens.indices.contains(position) ? tokens[position] : nil
    }

    private mutating func expression() -> Operand? {
        guard var lhs = term() else { return nil }
        while case .operation(let operation)? = next, operation == "+" || operation == "-" {
            position += 1
            sawBinaryOperator = true
            guard let rhs = term() else { return nil }
            if rhs.isPercent, !lhs.isPercent {
                lhs = Operand(value: lhs.value * Calculator.apply(operation, 1, rhs.value))
            } else {
                lhs = Operand(
                    value: Calculator.apply(operation, lhs.value, rhs.value), isPercent: lhs.isPercent && rhs.isPercent)
            }
        }
        return lhs
    }

    private mutating func term() -> Operand? {
        guard var lhs = unary() else { return nil }
        while true {
            switch next {
            case .operation(let operation)? where operation == "*" || operation == "/" || operation == "%":
                position += 1
                sawBinaryOperator = true
                guard let rhs = unary() else { return nil }
                lhs = Operand(value: Calculator.apply(operation, lhs.value, rhs.value))
            case .word(let word)?:
                // Only a percentage is of something: `20% of 50`, `15% off 80` or `15% on 80`.
                guard lhs.isPercent else { return nil }
                position += 1
                guard let rhs = unary() else { return nil }
                let share =
                    switch word {
                    case "off": 1 - lhs.value
                    case "on": 1 + lhs.value
                    default: lhs.value
                    }
                lhs = Operand(value: rhs.value * share)
            default:
                return lhs
            }
        }
    }

    private mutating func unary() -> Operand? {
        guard depth < Self.maxDepth else { return nil }
        depth += 1
        defer { depth -= 1 }
        if case .operation(let operation)? = next, operation == "-" || operation == "+" {
            position += 1
            guard var operand = unary() else { return nil }
            if operation == "-" { operand.value = -operand.value }
            return operand
        }
        return power()
    }

    private mutating func power() -> Operand? {
        guard let base = percentage() else { return nil }
        guard case .operation("^")? = next else { return base }
        position += 1
        sawBinaryOperator = true
        guard let exponent = unary() else { return nil }
        return Operand(value: pow(base.value, exponent.value))
    }

    /// A number or bracket, as a share of one when `%` follows it, so `20%` on its own is 0.2.
    private mutating func percentage() -> Operand? {
        guard let value = primary() else { return nil }
        guard case .percent? = next else { return Operand(value: value) }
        position += 1
        sawBinaryOperator = true
        return Operand(value: value / 100, isPercent: true)
    }

    private mutating func primary() -> Double? {
        switch next {
        case .number(let value, _)?:
            position += 1
            return value
        case .open?:
            position += 1
            guard let operand = expression(), case .close? = next else { return nil }
            position += 1
            return operand.value
        default:
            return nil
        }
    }
}

extension Character {
    fileprivate var isASCIIDigit: Bool {
        ("0"..."9").contains(self)
    }
}

extension String {
    /// Wraps the text in Unicode left-to-right isolate marks, so a maths expression keeps its order and its brackets
    /// unmirrored inside a right-to-left interface.
    public var leftToRightIsolated: String {
        "\u{2066}\(self)\u{2069}"
    }
}
