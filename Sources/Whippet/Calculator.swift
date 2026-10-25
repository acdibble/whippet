import Foundation

struct Calculation: Hashable {
    let tokens: [Calculator.Token]
    let value: Double
    let isRPN: Bool
    /// Set for a unit conversion, whose value is in the target unit.
    var conversion: Conversion?

    /// The number copied or pasted.
    var answer: String {
        conversion == nil ? Calculator.format(value) : Calculator.format(value, significantDigits: UnitConversion.significantDigits)
    }

    /// The answer as shown, with its unit for a conversion.
    var displayAnswer: String {
        conversion?.output ?? answer
    }

    /// A number on its own, such as `0xFF`, shown with its value but not kept in calculator history.
    var isPlainNumber: Bool {
        conversion == nil && !tokens.contains { if case .operation = $0 { true } else { false } }
    }

    /// Names the operation when the input uses a single kind of operator, or what a conversion measures.
    var operationName: String {
        if let conversion { return conversion.kind }
        let operations = Set(tokens.compactMap { token -> Character? in
            guard case .operation(let operation) = token else { return nil }
            return operation
        })
        if operations.isEmpty { return String(localized: "Number") }
        guard operations.count == 1, let operation = operations.first else { return String(localized: "Expression") }
        switch operation {
        case "+": return String(localized: "Sum")
        case "-": return String(localized: "Difference")
        case "*": return String(localized: "Product")
        case "/": return String(localized: "Quotient")
        case "%": return String(localized: "Remainder")
        default: return String(localized: "Power")
        }
    }

    var spelledAnswer: String {
        if let conversion { return conversion.outputLong }
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        let words = formatter.string(from: NSNumber(value: value)) ?? answer
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}

enum Calculator {
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
    static func looksLikeCalculation(_ input: String) -> Bool {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard let first = text.first, first.isASCIIDigit || "(.-+".contains(first) else { return false }
        // Letters only belong to radix literals such as 0xFF, so those are set aside first.
        let withoutRadixLiterals = text.replacingOccurrences(
            of: "0[xX][0-9a-fA-F_]*|0[bB][01_]*|0[oO][0-7_]*",
            with: "0",
            options: .regularExpression
        )
        return withoutRadixLiterals.allSatisfy { $0.isASCIIDigit || $0.isWhitespace || "+-*/%^().,_".contains($0) }
    }

    /// A plain number, read like a copied one, so `0xFF`, `1,000.5` and `-4` show their value.
    static func evaluateNumber(_ input: String) -> Calculation? {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard let value = parseNumber(text), value.isFinite else { return nil }
        return Calculation(tokens: [.number(value, literal: text)], value: value, isRPN: false)
    }

    /// Without grouping, and to `significantDigits`, which conversions lower to hide floating-point noise.
    static func format(_ value: Double, significantDigits: Int = 15) -> String {
        value.formatted(
            .number.locale(Locale(identifier: "en_US_POSIX")).grouping(.never)
                .precision(.significantDigits(1...significantDigits))
        )
    }

    enum Token: Hashable {
        case number(Double, literal: String)
        case operation(Character)
        case open
        case close
    }

    private static let operators: Set<Character> = ["+", "-", "*", "/", "%", "^"]

    /// With `signedNumbers`, a `-` that starts a word and is followed by a digit belongs to the number, as RPN needs for `3 -2 *`.
    private static func tokenize(_ input: String, signedNumbers: Bool = false) -> [Token]? {
        var tokens: [Token] = []
        var index = input.startIndex
        while index < input.endIndex {
            let char = input[index]
            let next = input.index(after: index)
            let startsWord = index == input.startIndex || input[input.index(before: index)].isWhitespace
            let isSigned = signedNumbers && char == "-" && startsWord && next < input.endIndex && input[next].isASCIIDigit
            if char == "." || char.isASCIIDigit || isSigned {
                let end = numberEnd(in: input, from: isSigned ? next : index)
                let literal = String(input[index..<end])
                guard let value = parseNumber(literal) else { return nil }
                tokens.append(.number(value, literal: literal))
                index = end
                continue
            }

            switch char {
            case _ where char.isWhitespace: break
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
    private static func numberEnd(in input: String, from start: String.Index) -> String.Index {
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
            guard (1...3).contains(groups[0].count), groups.dropFirst().allSatisfy({ $0.count == 3 }) else { return nil }
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
            case .operation(let operation):
                guard stack.count >= 2 else { return nil }
                let rhs = stack.removeLast()
                let lhs = stack.removeLast()
                stack.append(apply(operation, lhs, rhs))
                appliedOperator = true
            case .open, .close:
                return nil
            }
        }
        guard appliedOperator, stack.count == 1 else { return nil }
        return stack[0]
    }

    fileprivate static func apply(_ operation: Character, _ lhs: Double, _ rhs: Double) -> Double {
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

/// Recursive descent over `expression := term (+|- term)*`, `term := unary (*|/|% unary)*`,
/// `unary := (+|-) unary | power` and right-associative `power := primary (^ unary)?`.
private struct InfixParser {
    /// Every recursion, through brackets, signs or exponents, passes through `unary`, so limiting its depth keeps
    /// pasted input like thousands of `(` from overflowing the main thread's stack.
    private static let maxDepth = 100

    let tokens: [Calculator.Token]
    private var position = 0
    private var sawBinaryOperator = false
    private var depth = 0

    init(tokens: [Calculator.Token]) {
        self.tokens = tokens
    }

    mutating func parse() -> Double? {
        guard let value = expression(), position == tokens.count, sawBinaryOperator else { return nil }
        return value
    }

    private var next: Calculator.Token? {
        tokens.indices.contains(position) ? tokens[position] : nil
    }

    private mutating func expression() -> Double? {
        guard var value = term() else { return nil }
        while case .operation(let operation)? = next, operation == "+" || operation == "-" {
            position += 1
            sawBinaryOperator = true
            guard let rhs = term() else { return nil }
            value = Calculator.apply(operation, value, rhs)
        }
        return value
    }

    private mutating func term() -> Double? {
        guard var value = unary() else { return nil }
        while case .operation(let operation)? = next, operation == "*" || operation == "/" || operation == "%" {
            position += 1
            sawBinaryOperator = true
            guard let rhs = unary() else { return nil }
            value = Calculator.apply(operation, value, rhs)
        }
        return value
    }

    private mutating func unary() -> Double? {
        guard depth < Self.maxDepth else { return nil }
        depth += 1
        defer { depth -= 1 }
        if case .operation(let operation)? = next, operation == "-" || operation == "+" {
            position += 1
            guard let value = unary() else { return nil }
            return operation == "-" ? -value : value
        }
        return power()
    }

    private mutating func power() -> Double? {
        guard let base = primary() else { return nil }
        guard case .operation("^")? = next else { return base }
        position += 1
        sawBinaryOperator = true
        guard let exponent = unary() else { return nil }
        return pow(base, exponent)
    }

    private mutating func primary() -> Double? {
        switch next {
        case .number(let value, _)?:
            position += 1
            return value
        case .open?:
            position += 1
            guard let value = expression(), case .close? = next else { return nil }
            position += 1
            return value
        default:
            return nil
        }
    }
}

private extension Character {
    var isASCIIDigit: Bool {
        ("0"..."9").contains(self)
    }
}

extension String {
    /// Wraps the text in Unicode left-to-right isolate marks, so a maths expression keeps its order and its brackets
    /// unmirrored inside a right-to-left interface.
    var leftToRightIsolated: String {
        "\u{2066}\(self)\u{2069}"
    }
}
