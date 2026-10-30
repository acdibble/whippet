import Foundation
import Units

/// Arithmetic on amounts with units, for the amount in a unit conversion, such as `2100 seconds / 3`, `1 h + 30 min`,
/// `5 ft 10 in`, `100 km / 2 h` or `20 items / second * 1 h`. A unit follows a number or a bracket and applies to it
/// alone, so `2 * 3 km` is 6 km and `(1 + 1) gal` is 2 gal. A word that isn't a unit, such as `items`, is something
/// counted, which can be added to more of the same or divided into a rate.
enum QuantityExpression {
    enum Token: Equatable {
        case number(Double)
        /// A unit as typed, such as `km`, `light years` or `items per second`.
        case unit(String)
        case operation(Character)
        case open
        case close

        var isOperation: Bool {
            if case .operation = self { true } else { false }
        }
    }

    /// A worked-out amount, whose reading is nil for a plain number.
    struct Quantity {
        var value: Double
        var reading: UnitConversion.Reading?
    }

    /// Readings tried for every unit together, so text full of ambiguous units such as `m` stays quick.
    private static let maximumCombinations = 64

    static func tokenize(_ text: String) -> [Token]? {
        var tokens: [Token] = []
        var index = text.startIndex
        while index < text.endIndex {
            let char = text[index]
            if char.isWhitespace {
                index = text.index(after: index)
            } else if (char.isASCII && char.isNumber) || char == "." {
                let end = Calculator.numberEnd(in: text, from: index)
                guard let value = Calculator.parseNumber(String(text[index..<end])) else { return nil }
                tokens.append(.number(value))
                index = end
            } else if UnitConversion.isUnitStart(char) {
                // A unit follows what it measures, so `km to mi` and `5 + km` aren't amounts.
                switch tokens.last {
                case .number?, .close?: break
                default: return nil
                }
                let end = unitEnd(in: text, from: index)
                tokens.append(.unit(String(text[index..<end])))
                index = end
            } else {
                switch char {
                case "+", "-", "*", "/", "%", "^": tokens.append(.operation(char))
                case "(": tokens.append(.open)
                case ")": tokens.append(.close)
                default: return nil
                }
                index = text.index(after: index)
            }
        }
        return tokens
    }

    /// The end of a unit from its first character. It runs on through a space, `/` or `-` when another word follows,
    /// as in `light years`, `km / h`, `items per second` or `light-years`, and into a power, as in `m2` or `m^2`, but
    /// stops before a number, so `2100 s / 3` divides by 3.
    private static func unitEnd(in text: String, from start: String.Index) -> String.Index {
        var end = text.index(after: start)
        while end < text.endIndex {
            let char = text[end]
            let after = text.index(after: end)
            if UnitConversion.isUnitStart(char) || char.isNumber || char == "_" {
                end = after
            } else if char == "^", after < text.endIndex, text[after].isNumber {
                end = after
            } else {
                var next = text[end...].drop(while: \.isWhitespace).startIndex
                if next < text.endIndex, text[next] == "/" || text[next] == "-" {
                    next = text[text.index(after: next)...].drop(while: \.isWhitespace).startIndex
                }
                guard next != end, next < text.endIndex, UnitConversion.isUnitStart(text[next]) else { break }
                end = next
            }
        }
        return end
    }

    /// Every way to work out the tokens, one for each meaning of their units, most likely first, leaving out those
    /// whose units don't fit together, such as `5 km + 2 kg`.
    static func evaluate(_ tokens: [Token]) -> [Quantity] {
        var combinations: [[UnitConversion.Reading]] = [[]]
        for case .unit(let text) in tokens {
            let readings = readings(named: text)
            guard !readings.isEmpty else { return [] }
            combinations = Array(combinations.flatMap { combination in readings.map { combination + [$0] } }
                .prefix(maximumCombinations))
        }
        return combinations.compactMap { readings in
            var parser = Parser(tokens: tokens, readings: readings)
            return parser.parse()
        }
    }

    /// A unit's meanings, or failing that, something counted, such as `items` or `page views`. A keyword or `per` can't
    /// be counted, so `5 km to` and `5 per second` aren't read as counting.
    private static func readings(named text: String) -> [UnitConversion.Reading] {
        let readings = UnitConversion.readings(named: text)
        guard readings.isEmpty else { return readings }
        let words = text.split(separator: " ").map { $0.lowercased() }
        guard
            text.allSatisfy({ $0.isLetter || $0 == " " }),
            !words.contains(where: { UnitConversion.keywords.contains($0) || $0 == "per" })
        else { return [] }
        return [UnitConversion.Reading(unit: .none, counted: text)]
    }

    // MARK: - Arithmetic

    /// `lhs` and `rhs` combined, or nil when their units don't allow it. A plain number added to an amount takes its
    /// unit, as in `1 + 1 hogsheads`, and dividing by an amount makes a rate, as in `100 km / 2 h`.
    fileprivate static func apply(_ operation: Character, _ lhs: Quantity, _ rhs: Quantity) -> Quantity? {
        guard let left = lhs.reading, let right = rhs.reading else {
            switch operation {
            case "+", "-", "*":
                return Quantity(value: Calculator.apply(operation, lhs.value, rhs.value), reading: lhs.reading ?? rhs.reading)
            case "/" where rhs.reading == nil, "%" where rhs.reading == nil:
                return Quantity(value: Calculator.apply(operation, lhs.value, rhs.value), reading: lhs.reading)
            case "/":
                return quotient(lhs, rhs)
            case "^" where rhs.reading == nil:
                return power(lhs, rhs.value)
            default:
                return nil
            }
        }
        switch operation {
        case "+", "-", "%":
            guard let value = value(of: rhs, in: left) else { return nil }
            return Quantity(value: Calculator.apply(operation, lhs.value, value), reading: left)
        case "*":
            return product(lhs, rhs)
        case "/":
            // Like amounts divide to a plain number, as in `1 h / 30 min`.
            if let value = value(of: rhs, in: left) {
                return Quantity(value: lhs.value / value, reading: nil)
            }
            return quotient(lhs, rhs)
        default:
            return nil
        }
    }

    /// An amount's value in another reading's unit, when they measure the same thing.
    private static func value(of quantity: Quantity, in target: UnitConversion.Reading) -> Double? {
        guard
            let reading = quantity.reading, reading.counted?.lowercased() == target.counted?.lowercased(),
            let converted = try? PhysicalMeasurement(value: quantity.value, unit: reading.unit).convert(to: target.unit)
        else { return nil }
        return converted.value
    }

    private static func product(_ lhs: Quantity, _ rhs: Quantity) -> Quantity? {
        guard let left = lhs.reading, let right = rhs.reading, left.counted == nil || right.counted == nil else { return nil }
        let counted = left.counted ?? right.counted
        let product = simplified(
            PhysicalMeasurement(value: lhs.value, unit: left.unit) * PhysicalMeasurement(value: rhs.value, unit: right.unit),
            like: [left, right]
        )
        // Counting can only lose its rate, as in `20 items/s * 1 h`.
        guard let product, counted == nil || product.unit.dimension.isEmpty else { return nil }
        return Quantity(value: product.value, reading: UnitConversion.Reading(unit: product.unit, counted: counted))
    }

    /// `lhs` per `rhs`, which is a plain number when `lhs` is.
    private static func quotient(_ lhs: Quantity, _ rhs: Quantity) -> Quantity? {
        guard let right = rhs.reading, right.counted == nil else { return nil }
        let left = lhs.reading ?? UnitConversion.Reading(unit: .none)
        // A rate of something counted can't be divided again, as in `20 items/s / 2 s`.
        guard left.counted == nil || left.per == nil else { return nil }
        let unit = left.unit / right.unit
        guard let quotient = simplified(
            PhysicalMeasurement(value: lhs.value / rhs.value, unit: unit),
            like: [left, right]
        ) else { return nil }
        // What it's per, so a target can name only that, unless it cancelled out, as in `6 m2 / 2 m`.
        let isRate = left.per == nil && right.per == nil
            && right.unit.dimension.keys.allSatisfy { (quotient.unit.dimension[$0] ?? 0) < 0 }
        return Quantity(
            value: quotient.value,
            reading: UnitConversion.Reading(unit: quotient.unit, per: isRate ? right.unit : nil, counted: left.counted)
        )
    }

    private static func power(_ base: Quantity, _ exponent: Double) -> Quantity? {
        guard let reading = base.reading else {
            return Quantity(value: pow(base.value, exponent), reading: nil)
        }
        guard reading.counted == nil, exponent == exponent.rounded(), abs(exponent) <= 10 else { return nil }
        let power = PhysicalMeasurement(value: base.value, unit: reading.unit).pow(Int(exponent))
        return Quantity(value: power.value, reading: UnitConversion.Reading(unit: power.unit))
    }

    /// A unit made by multiplying or dividing, in the unit of an amount it came from when it measures the same thing,
    /// so `6 m2 / 2 m` is 3 m rather than 3 m²/m and `60 mph * 30 min` is 30 mi. Units that cancel leave a plain count.
    private static func simplified(
        _ measurement: PhysicalMeasurement,
        like readings: [UnitConversion.Reading]
    ) -> PhysicalMeasurement? {
        let units = readings.flatMap { reading in [reading.unit] + (reading.per.map { [reading.unit * $0] } ?? []) }
        let target = measurement.unit.dimension.isEmpty
            ? PhysicalUnit.none
            : units.first { $0 != measurement.unit && $0.isDimensionallyEquivalent(to: measurement.unit) }
        guard let target else { return measurement }
        return try? measurement.convert(to: target)
    }
}

/// Recursive descent like `Calculator`'s, over `expression := term (+|- term)*`, `term := unary (*|/|% unary)*`,
/// `unary := (+|-) unary | power`, `power := amount (^ unary)?` and `amount := (number | (expression)) unit?`,
/// where amounts side by side add up, as in `5 ft 10 in` or `1 h 30 min`.
private struct Parser {
    typealias Quantity = QuantityExpression.Quantity

    /// As in `Calculator`, so pasted brackets can't overflow the stack.
    private static let maxDepth = 100

    let tokens: [QuantityExpression.Token]
    /// One meaning for each unit, in the order they're typed.
    let readings: [UnitConversion.Reading]
    private var position = 0
    private var unitIndex = 0
    private var depth = 0

    init(tokens: [QuantityExpression.Token], readings: [UnitConversion.Reading]) {
        self.tokens = tokens
        self.readings = readings
    }

    mutating func parse() -> Quantity? {
        guard let quantity = expression(), position == tokens.count else { return nil }
        return quantity
    }

    private var next: QuantityExpression.Token? {
        tokens.indices.contains(position) ? tokens[position] : nil
    }

    private mutating func expression() -> Quantity? {
        guard var value = term() else { return nil }
        while case .operation(let operation)? = next, operation == "+" || operation == "-" {
            position += 1
            guard let rhs = term(), let result = QuantityExpression.apply(operation, value, rhs) else { return nil }
            value = result
        }
        return value
    }

    private mutating func term() -> Quantity? {
        guard var value = unary() else { return nil }
        while case .operation(let operation)? = next, operation == "*" || operation == "/" || operation == "%" {
            position += 1
            guard let rhs = unary(), let result = QuantityExpression.apply(operation, value, rhs) else { return nil }
            value = result
        }
        return value
    }

    private mutating func unary() -> Quantity? {
        guard depth < Self.maxDepth else { return nil }
        depth += 1
        defer { depth -= 1 }
        if case .operation(let operation)? = next, operation == "-" || operation == "+" {
            position += 1
            guard var value = unary() else { return nil }
            if operation == "-" { value.value = -value.value }
            return value
        }
        return power()
    }

    private mutating func power() -> Quantity? {
        guard let base = amounts() else { return nil }
        guard case .operation("^")? = next else { return base }
        position += 1
        guard let exponent = unary() else { return nil }
        return QuantityExpression.apply("^", base, exponent)
    }

    /// An amount, then any more with units that follow it, added together.
    private mutating func amounts() -> Quantity? {
        guard var total = amount() else { return nil }
        while total.reading != nil, case .number? = next, tokens.indices.contains(position + 1),
              case .unit = tokens[position + 1] {
            guard let more = amount(), let sum = QuantityExpression.apply("+", total, more) else { return nil }
            total = sum
        }
        return total
    }

    private mutating func amount() -> Quantity? {
        var quantity: Quantity
        switch next {
        case .number(let value)?:
            position += 1
            quantity = Quantity(value: value, reading: nil)
        case .open?:
            position += 1
            guard let value = expression(), case .close? = next else { return nil }
            position += 1
            quantity = value
        default:
            return nil
        }
        if case .unit? = next {
            // `(2 km) m` gives an amount two units.
            guard quantity.reading == nil, readings.indices.contains(unitIndex) else { return nil }
            quantity.reading = readings[unitIndex]
            unitIndex += 1
            position += 1
        }
        return quantity
    }
}
