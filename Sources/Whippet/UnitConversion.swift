import Foundation
import Units

/// The Units package's types, named apart from Foundation's.
typealias PhysicalUnit = Units.Unit
typealias PhysicalMeasurement = Units.Measurement

/// A unit conversion's input and result as shown, alongside its value in `Calculation`.
struct Conversion: Hashable {
    /// The amount converted, such as `5 km`.
    let input: String
    /// The result with its unit, such as `3.106855961 mi`.
    let output: String
    /// The result with the unit spelled out, such as `3.106855961 miles`.
    let outputLong: String
    /// What's measured, such as Length.
    let kind: String
    /// The number copied, when it isn't the value to `UnitConversion.significantDigits`, such as money in cents.
    var answer: String?
}

/// Converts `<number or calculation> <unit> to|in <unit>`, such as `5 km to mi`, `72 f in c` or `2 * 3 hogsheads to l`.
/// Units come from the Units package, plus a few of our own, with aliases for what people type. A unit that could mean
/// two things, such as `m` (metres or minutes), takes the meaning that matches the other unit.
enum UnitConversion {
    /// Pasted text is never a conversion, and splitting it at every position would be slow.
    private static let maximumLength = 100
    /// Floating-point arithmetic leaves noise past this, such as 72 °F → 22.222222222224616 °C.
    static let significantDigits = 10

    static func convert(_ input: String) -> Calculation? {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard text.count <= maximumLength else { return nil }
        // `in` is also a unit, so `12 in to cm` and `5 in in cm` try each keyword from the last.
        for (amountText, targetText) in splits(text) where !targetText.isEmpty {
            if let calculation = convert(amountText, to: targetText) {
                return calculation
            }
        }
        return nil
    }

    private static func convert(_ amountText: String, to targetText: String) -> Calculation? {
        let named = readings(named: targetText)
        let pers = units(named: targetText.replacing(/^(?i:per)(?:\s+|$)/, with: ""))
        guard !named.isEmpty || !pers.isEmpty else { return nil }

        for (amount, sources) in amounts(in: amountText) {
            for source in sources {
                for target in targets(for: source, named: named, pers: pers) {
                    guard
                        let converted = try? PhysicalMeasurement(value: amount, unit: source.unit).convert(to: target.unit),
                        converted.value.isFinite
                    else { continue }
                    let conversion = Conversion(
                        input: UnitDisplay.format(amount, source, style: .medium),
                        output: UnitDisplay.format(converted.value, target, style: .medium),
                        outputLong: UnitDisplay.format(converted.value, target, style: .long),
                        kind: target.counted == nil ? UnitDisplay.kind(of: target.unit) : String(localized: "Rate")
                    )
                    return Calculation(tokens: [], value: converted.value, isRPN: false, conversion: conversion)
                }
            }
        }
        return nil
    }

    /// What a source can be converted to: a unit of the same kind the target names, or for a rate, the same rate per
    /// what the target names, as in `9.35 items per second in hours` or `60 km/h to per minute`.
    private static func targets(for source: Reading, named: [Reading], pers: [PhysicalUnit]) -> [Reading] {
        var targets: [Reading] = []
        if let per = source.per {
            let numerator = source.unit * per
            for unit in pers where unit.isDimensionallyEquivalent(to: per) {
                targets.append(Reading(unit: numerator / unit, per: unit, counted: source.counted))
            }
        }
        for target in named where target.unit.isDimensionallyEquivalent(to: source.unit) {
            // `items per second to requests per hour` changes what's counted, which isn't a conversion.
            if let counted = target.counted, counted.lowercased() != source.counted?.lowercased() { continue }
            targets.append(target)
        }
        return targets
    }

    /// True for a conversion on its way, such as `5 km to` or `5 km to m`, so the launcher keeps the calculator showing
    /// while the target is typed. Until `to` or `in` follows a unit, the text could be a search, such as `2 f`.
    /// With `requiresTarget`, as for text that's also a named timer, the target must have begun with a unit that fits.
    static func looksLikeConversion(_ input: String, requiresTarget: Bool = false) -> Bool {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard text.count <= maximumLength else { return false }

        // The keyword itself being typed: `5 km t`.
        if !requiresTarget, let space = text.lastIndex(where: \.isWhitespace) {
            let word = text[text.index(after: space)...].lowercased()
            if keywords.contains(where: { $0.hasPrefix(word) }), !amounts(in: String(text[..<space])).isEmpty {
                return true
            }
        }
        // The target being typed: `5 km to` or `5 km to light y`.
        for (amountText, targetText) in splits(text) {
            let sources = amounts(in: amountText).flatMap(\.1)
            guard !sources.isEmpty else { continue }
            if targetText.isEmpty { return !requiresTarget }
            // A rate's target can name only what it's per: `5 items per s to per h` or `to h`.
            let typed = normalized(targetText.replacing(/^(?i:per)(?:\s+|$)/, with: ""))
            if typed.isEmpty { return !requiresTarget && sources.contains { $0.per != nil } }
            let kinds = sources.flatMap { [$0.unit] + ($0.per.map { [$0] } ?? []) }
            return vocabularyUnits.contains { word, units in
                word.hasPrefix(typed) && units.contains { unit in kinds.contains { $0.isDimensionallyEquivalent(to: unit) } }
            }
        }
        return false
    }

    // MARK: - Parsing

    static let keywords: Set<String> = ["to", "in", "into", "as"]

    private static func isUnitStart(_ character: Character) -> Bool {
        character.isLetter || "°\"'μ".contains(character)
    }

    /// Each way to split the text into an amount and a target at a keyword, from the last keyword. The space after the
    /// keyword is only looked at, so `12 in to cm` finds both ` in` and ` to`. The target is empty when the text ends at
    /// the keyword.
    static func splits(_ text: String) -> [(String, String)] {
        let pattern = /\s+(?i:to|in|into|as)(?=\s|$)/
        return text.matches(of: pattern).reversed().compactMap { match in
            let amount = text[..<match.range.lowerBound].trimmingCharacters(in: .whitespaces)
            let target = text[match.range.upperBound...].trimmingCharacters(in: .whitespaces)
            return amount.isEmpty ? nil : (amount, target)
        }
    }

    /// Every way to read the amount as a number or calculation followed by a unit, longest unit first. A unit can only
    /// start after a space, a digit, `)` or `.`, so only a few places are tried.
    private static func amounts(in text: String) -> [(Double, [Reading])] {
        var amounts: [(Double, [Reading])] = []
        var previous: Character?
        for index in text.indices {
            defer { previous = text[index] }
            guard
                let previous, isUnitStart(text[index]),
                previous.isWhitespace || previous.isNumber || previous == ")" || previous == "."
            else { continue }
            let number = text[..<index].trimmingCharacters(in: .whitespaces)
            guard let value = Calculator.number(number) else { continue }
            let readings = readings(named: String(text[index...]))
            if !readings.isEmpty {
                amounts.append((value, readings))
            }
        }
        return amounts
    }

    /// A unit an amount is in. A rate, such as `km per h` or `items/s`, keeps what it's per, so a target can name only
    /// that.
    struct Reading {
        let unit: PhysicalUnit
        /// What a rate is per, such as hours.
        var per: PhysicalUnit?
        /// What a rate counts when it isn't a unit, such as `items`, which is kept as typed for showing.
        var counted: String?
    }

    /// What a unit's text could mean, as `units(named:)`, then as a rate: `<unit or word> per <unit>`, or with `/`.
    private static func readings(named text: String) -> [Reading] {
        // A unit that's a rate itself, such as `mph` (`mi/hr`), is per what follows its last `/`.
        var readings = units(named: text).map { unit in
            let perSymbol = unit.symbol.split(separator: "/").dropFirst().last.map(String.init) ?? perSymbols[unit.symbol]
            return Reading(unit: unit, per: perSymbol.flatMap { try? PhysicalUnit(fromSymbol: $0, registry: registry) })
        }
        for match in text.matches(of: /\s+(?i:per)\s+|\s*\/\s*/) {
            let numeratorText = text[..<match.range.lowerBound].trimmingCharacters(in: .whitespaces)
            let pers = units(named: String(text[match.range.upperBound...]))
            guard !numeratorText.isEmpty, !pers.isEmpty else { continue }
            let numerators = units(named: numeratorText)
            if numerators.isEmpty {
                // Anything counted, such as `items` or `page views`, but not a number or a calculation.
                guard numeratorText.allSatisfy({ $0.isLetter || $0 == " " }) else { continue }
                readings += pers.map { Reading(unit: PhysicalUnit.none / $0, per: $0, counted: numeratorText) }
            } else {
                for numerator in numerators {
                    readings += pers.map { Reading(unit: numerator / $0, per: $0) }
                }
            }
        }
        return readings
    }

    // MARK: - Units

    /// What a unit's text could mean, most likely first: an alias, then an exact symbol, then a name, singular or
    /// plural, then a symbol in any case. Aliases come first so they can correct the package, such as `dm`.
    static func units(named rawText: String) -> [PhysicalUnit] {
        let text = rawText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return [] }
        let key = normalized(text)
        var symbols = aliases[key] ?? []
        if (try? PhysicalUnit(fromSymbol: text, registry: registry)) != nil {
            symbols.append(text)
        }
        for candidate in [key, String(key.dropLast()), String(key.dropLast(2))] where candidate.count > 1 {
            if let symbol = nameIndex[candidate] {
                symbols.append(symbol)
                break
            }
        }
        symbols += symbolIndex[key] ?? []

        var seen = replacedSymbols
        return symbols.compactMap { symbol in
            guard seen.insert(symbol).inserted else { return nil }
            return try? PhysicalUnit(fromSymbol: symbol, registry: registry)
        }
    }

    /// Lowercased without spaces, hyphens or full stops, and with British spellings, so `Light-years` and `lightyears`
    /// match, as do `litre` and `liter`.
    private static func normalized(_ text: String) -> String {
        text.lowercased()
            .filter { !$0.isWhitespace && $0 != "-" && $0 != "." }
            .replacingOccurrences(of: "metre", with: "meter")
            .replacingOccurrences(of: "litre", with: "liter")
    }

    /// The Units package's registry, with units it doesn't have.
    static let registry: Registry = {
        let builder = RegistryBuilder()
        for unit in extraUnits {
            // The definitions are fixed, so this only fails if the package gains a unit with the same name or symbol,
            // which would leave aliases such as `month` or `deg` pointing nowhere.
            do {
                try builder.addUnit(name: unit.name, symbol: unit.symbol, dimension: unit.dimension, coefficient: unit.coefficient)
            } catch {
                assertionFailure("Couldn't add \(unit.name): \(error)")
            }
        }
        return builder.registry()
    }()

    /// Rates whose symbol doesn't say what they're per.
    private static let perSymbols = ["knot": "hr"]

    /// The package's degree is 180/π radians rather than π/180, so it's replaced by `deg`.
    private static let replacedSymbols: Set<String> = ["°"]

    /// Our own definitions, in the base units of their dimension (metres, kilograms, seconds, joules, radians), from
    /// the standard values. The package's `dm` is the decametre, so the decimetre is added here.
    private static let extraUnits: [(name: String, symbol: String, dimension: [Quantity: Int], coefficient: Double)] = [
        ("angleDegree", "deg", [.angle: 1], Double.pi / 180),
        ("decimeter", "decim", [.length: 1], 0.1),
        ("angstrom", "Å", [.length: 1], 1e-10),
        ("mil", "mil", [.length: 1], 0.0000254),
        ("barleycorn", "barleycorn", [.length: 1], 0.0254 / 3),
        ("hand", "hand", [.length: 1], 0.1016),
        ("cubit", "cubit", [.length: 1], 0.4572),
        ("smoot", "smoot", [.length: 1], 1.7018),
        ("rod", "rod", [.length: 1], 5.0292),
        ("chain", "chain", [.length: 1], 20.1168),
        ("league", "league", [.length: 1], 4828.032),
        ("hogshead", "hogshead", [.length: 3], 0.238480942392),
        ("barrel", "bbl", [.length: 3], 0.158987294928),
        ("grain", "gr", [.mass: 1], 0.00006479891),
        ("longTon", "longton", [.mass: 1], 1016.0469088),
        ("fortnight", "fortnight", [.time: 1], 1_209_600),
        ("month", "month", [.time: 1], 2_629_800),
        ("decade", "decade", [.time: 1], 315_576_000),
        ("century", "century", [.time: 1], 3_155_760_000),
        ("millennium", "millennium", [.time: 1], 31_557_600_000),
        ("wattHour", "Wh", [.mass: 1, .length: 2, .time: -2], 3600),
        ("kilowattHour", "kWh", [.mass: 1, .length: 2, .time: -2], 3_600_000),
    ]

    /// What people type that the registry doesn't spell, by normalized text, most likely meaning first.
    private static let aliases: [String: [String]] = {
        var aliases: [String: [String]] = [:]
        func add(_ keys: [String], _ symbols: [String]) {
            for key in keys { aliases[key, default: []] += symbols }
        }
        // Length
        add(["m"], ["m", "min"])
        add(["in", "inch", "inches", "\""], ["in"])
        add(["ft", "foot", "feet", "'"], ["ft"])
        add(["nmi", "nauticalmiles"], ["NM"])
        add(["dm", "decimeters"], ["decim"])
        add(["dam", "decameter", "decameters", "dekameter", "dekameters"], ["dm"])
        add(["um", "micron", "microns"], ["μm"])
        add(["nanometer", "nanometers"], ["nm"])
        add(["thou"], ["mil"])
        add(["angstroms", "Å"], ["Å"])
        // Mass
        add(["kgs", "kilo", "kilos"], ["kg"])
        add(["gram", "grams", "gramme", "grammes"], ["g"])
        add(["lb", "lbs", "pound", "pounds"], ["lb"])
        add(["oz", "ounce", "ounces"], ["oz", "fl_oz"])
        add(["troyoz", "troyounce"], ["troyOunces"])
        add(["ton", "tons", "shortton", "shorttons"], ["ton"])
        add(["tonne", "tonnes", "metricton", "metrictons", "mt"], ["t"])
        add(["longtons"], ["longton"])
        add(["st", "stone", "stones"], ["st"])
        add(["grains"], ["gr"])
        // Volume
        add(["floz", "fluidounce", "fluidounces"], ["fl_oz"])
        add(["impfloz"], ["ifl_oz"])
        add(["l", "liter", "liters"], ["L"])
        add(["ml"], ["mL"])
        add(["cl"], ["cL"])
        add(["dl"], ["dL"])
        add(["gal", "gallon", "gallons", "usgal"], ["gal"])
        add(["impgal", "ukgal", "imperialgallons"], ["igal"])
        add(["pt", "pint", "pints"], ["pt"])
        add(["imppt", "ukpt", "imperialpints"], ["ipt"])
        add(["qt", "quart", "quarts"], ["qt"])
        add(["impqt", "imperialquarts"], ["iqt"])
        add(["cup", "cups"], ["cup"])
        add(["tbs", "tbsp", "tablespoons"], ["tbsp"])
        add(["tsp", "teaspoons"], ["tsp"])
        add(["barrels"], ["bbl"])
        // Temperature
        add(["c"], ["°C", "cup"])
        add(["°c", "degc", "degreesc", "celsius", "degreescelsius", "centigrade"], ["°C"])
        add(["f", "°f", "degf", "degreesf", "fahrenheit", "degreesfahrenheit"], ["°F"])
        add(["k", "kelvin", "kelvins"], ["K"])
        // Time
        add(["s", "sec", "secs", "second", "seconds"], ["s"])
        add(["msec", "msecs"], ["ms"])
        add(["min", "mins", "minute", "minutes"], ["min"])
        add(["h", "hr", "hrs", "hour", "hours"], ["hr"])
        add(["d", "day", "days"], ["d"])
        add(["wk", "wks", "week", "weeks"], ["week"])
        add(["y", "yr", "yrs", "year", "years"], ["yr"])
        add(["mo", "mos", "month", "months"], ["month"])
        add(["centuries"], ["century"])
        add(["millennia"], ["millennium"])
        // Data
        add(["b", "byte", "bytes"], ["byte"])
        add(["kb"], ["kB"])
        add(["mb"], ["MB"])
        add(["gb"], ["GB"])
        add(["tb"], ["TB"])
        add(["pb"], ["PB"])
        add(["bit", "bits"], ["bit"])
        // Speed
        add(["mph"], ["mi/hr"])
        add(["kph", "kmh", "km/h", "kmph"], ["km/hr"])
        add(["mps", "m/s"], ["m/s"])
        add(["fps", "ft/s"], ["ft/s"])
        add(["kn", "kt", "kts", "knot", "knots"], ["knot"])
        // Area
        add(["acre", "acres"], ["ac"])
        add(["ha", "hectare", "hectares"], ["ha"])
        add(["sqm", "m2", "m²", "squaremeter", "squaremeters"], ["m^2"])
        add(["sqkm", "km2", "km²", "squarekilometer", "squarekilometers"], ["km^2"])
        add(["sqcm", "cm2", "cm²", "squarecentimeter", "squarecentimeters"], ["cm^2"])
        add(["sqyd", "yd2", "yd²", "squareyard", "squareyards"], ["yd^2"])
        add(["sqft", "ft2", "ft²", "squarefoot", "squarefeet"], ["ft^2"])
        add(["sqin", "in2", "in²", "squareinch", "squareinches"], ["in^2"])
        add(["sqmi", "mi2", "mi²", "squaremile", "squaremiles"], ["mi^2"])
        // Energy, power, pressure
        add(["cal", "calorie", "calories"], ["cal"])
        add(["kcal", "kilocalorie", "kilocalories"], ["kCal"])
        add(["j", "joule", "joules"], ["J"])
        add(["kj"], ["kJ"])
        add(["kwh"], ["kWh"])
        add(["wh"], ["Wh"])
        add(["w", "watt", "watts"], ["W"])
        add(["kw"], ["kW"])
        add(["hp", "horsepower"], ["hp"])
        add(["pa", "pascal", "pascals"], ["Pa"])
        add(["kpa"], ["kPa"])
        add(["hpa"], ["hPa"])
        add(["bar", "bars"], ["bar"])
        add(["psi"], ["lbf/in^2"])
        // Angle and frequency
        add(["°", "deg", "degree", "degrees"], ["deg"])
        add(["rad", "rads", "radian", "radians"], ["rad"])
        add(["rev", "revs", "turn", "turns"], ["rev"])
        add(["hz"], ["Hz"])
        add(["khz"], ["kHz"])
        add(["mhz"], ["MHz"])
        add(["ghz"], ["GHz"])
        return aliases
    }()

    /// Registry names, lowercased, to their symbols.
    private static let nameIndex: [String: String] = Dictionary(
        registry.allUnits().map { ($0.name.lowercased(), $0.symbol) },
        uniquingKeysWith: { first, _ in first }
    )

    /// Registry symbols by their lowercased form, for symbols typed in the wrong case.
    private static let symbolIndex: [String: [String]] = Dictionary(
        grouping: registry.allUnits().map(\.symbol).sorted(),
        by: { $0.lowercased() }
    )

    /// Every word a unit can be typed as, with what it means, for recognising a target while it's typed. Built the
    /// first time it's needed.
    private static let vocabularyUnits: [(word: String, units: [PhysicalUnit])] =
        Set(aliases.keys).union(nameIndex.keys).union(symbolIndex.keys).map { ($0, units(named: $0)) }
}

extension Calculator {
    /// A calculation, a plain number, a unit conversion, a currency conversion with `rates`, or a time calculation,
    /// in that order.
    static func calculate(_ input: String, rates: ExchangeRates? = nil) -> Calculation? {
        evaluate(input) ?? evaluateNumber(input) ?? UnitConversion.convert(input)
            ?? rates.flatMap { CurrencyConversion.convert(input, rates: $0) } ?? TimeCalculation.calculate(input)
    }

    /// The value of a number or calculation, such as the amount in a conversion.
    static func number(_ text: String) -> Double? {
        (evaluate(text) ?? evaluateNumber(text))?.value
    }

}

extension CalculationRecord {
    /// The answer as shown in history, with its unit for a conversion. History keeps the number alone, which is what
    /// copying it gives, so the unit is read again from the expression. Money is shown as it was converted rather
    /// than at today's rates.
    var displayAnswer: String {
        if let calculation = UnitConversion.convert(expression) { return calculation.displayAnswer }
        if let currency = CurrencyConversion.targetCurrency(of: expression), let value = Double(answer) {
            return value.formatted(.currency(code: currency))
        }
        return answer
    }
}

/// Shows a converted amount with Foundation's units where there is one, which are localized, and the unit's own symbol
/// otherwise.
enum UnitDisplay {
    /// A rate of something counted shows it with the unit it's per, such as `33,660 items/h`.
    static func format(_ value: Double, _ reading: UnitConversion.Reading, style: Formatter.UnitStyle) -> String {
        guard let counted = reading.counted, let per = reading.per else { return format(value, reading.unit, style: style) }
        let formatter = style == .long ? longFormatter : mediumFormatter
        let number = formatter.numberFormatter.string(from: NSNumber(value: value))
            ?? Calculator.format(value, significantDigits: UnitConversion.significantDigits)
        return style == .long
            ? "\(number) \(counted) per \(name(of: per, style: .long))"
            : "\(number) \(counted)/\(name(of: per, style: .short))"
    }

    /// One of a unit as shown without the number, such as `hour`, or `h` when short.
    private static func name(of unit: PhysicalUnit, style: Formatter.UnitStyle) -> String {
        guard let foundationUnit = foundationUnits[unit.symbol] else { return symbol(of: unit, plural: false) }
        let formatter = style == .long ? longFormatter : shortFormatter
        return formatter.string(from: Foundation.Measurement(value: 1, unit: foundationUnit))
            .replacingOccurrences(of: "1", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    static func format(_ value: Double, _ unit: PhysicalUnit, style: Formatter.UnitStyle) -> String {
        let formatter = style == .long ? longFormatter : mediumFormatter
        if let foundationUnit = foundationUnits[unit.symbol] {
            return formatter.string(from: Foundation.Measurement(value: value, unit: foundationUnit))
        }
        let digits = UnitConversion.significantDigits
        let number = formatter.numberFormatter.string(from: NSNumber(value: value))
            ?? Calculator.format(value, significantDigits: digits)
        // Read from the rounded number, so 0.9999999999 and -1 show as "1 hogshead" and "-1 hogshead".
        let isOne = Calculator.format(abs(value), significantDigits: digits) == "1"
        return "\(number) \(symbol(of: unit, plural: !isOne))"
    }

    /// Formatters are slow to make and are only read once set up, which Foundation allows from any thread.
    nonisolated(unsafe) private static let mediumFormatter = makeFormatter(style: .medium)
    nonisolated(unsafe) private static let longFormatter = makeFormatter(style: .long)
    nonisolated(unsafe) private static let shortFormatter = makeFormatter(style: .short)

    private static func makeFormatter(style: Formatter.UnitStyle) -> MeasurementFormatter {
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = style
        formatter.numberFormatter.usesSignificantDigits = true
        formatter.numberFormatter.maximumSignificantDigits = UnitConversion.significantDigits
        return formatter
    }

    /// Symbols that read badly as typed, and words that take a plural.
    private static func symbol(of unit: PhysicalUnit, plural: Bool) -> String {
        let symbol = unit.symbol
        if let display = displaySymbols[symbol] { return display }
        let isWord = symbol.count > 2 && symbol.allSatisfy(\.isLowercase)
        guard isWord, plural, !symbol.hasSuffix("s") else { return symbol }
        if symbol == "century" { return "centuries" }
        if symbol == "millennium" { return "millennia" }
        return symbol + "s"
    }

    private static let displaySymbols = [
        "fl_oz": "fl oz", "ifl_oz": "imp fl oz", "igal": "imp gal", "ipt": "imp pt", "iqt": "imp qt", "icup": "imp cup",
        "ipk": "imp pk", "mcup": "metric cup", "decim": "dm", "dm": "dam", "longton": "long tons", "troyOunces": "oz t",
        "hr": "h", "gr": "gr", "bbl": "bbl",
    ]

    static func kind(of unit: PhysicalUnit) -> String {
        let dimension = unit.dimension
        switch dimension {
        case [.length: 1]: return String(localized: "Length")
        case [.length: 2]: return String(localized: "Area")
        case [.length: 3]: return String(localized: "Volume")
        case [.mass: 1]: return String(localized: "Mass")
        case [.time: 1]: return String(localized: "Time")
        case [.temperature: 1]: return String(localized: "Temperature")
        case [.data: 1]: return String(localized: "Data")
        case [.angle: 1]: return String(localized: "Angle")
        case [.time: -1]: return String(localized: "Frequency")
        case [.length: 1, .time: -1]: return String(localized: "Speed")
        case [.mass: 1, .length: 2, .time: -2]: return String(localized: "Energy")
        case [.mass: 1, .length: 2, .time: -3]: return String(localized: "Power")
        case [.mass: 1, .length: -1, .time: -2]: return String(localized: "Pressure")
        default: return String(localized: "Conversion")
        }
    }

    /// The Units package's symbols that Foundation also has.
    private static let foundationUnits: [String: Dimension] = [
        // Length
        "m": UnitLength.meters, "km": UnitLength.kilometers, "cm": UnitLength.centimeters, "mm": UnitLength.millimeters,
        "μm": UnitLength.micrometers, "nm": UnitLength.nanometers, "pm": UnitLength.picometers,
        "decim": UnitLength.decimeters, "dm": UnitLength.decameters, "hm": UnitLength.hectometers,
        "Mm": UnitLength.megameters, "in": UnitLength.inches, "ft": UnitLength.feet, "yd": UnitLength.yards,
        "mi": UnitLength.miles, "smi": UnitLength.scandinavianMiles, "NM": UnitLength.nauticalMiles,
        "fathom": UnitLength.fathoms, "furlong": UnitLength.furlongs, "au": UnitLength.astronomicalUnits,
        "ly": UnitLength.lightyears, "pc": UnitLength.parsecs,
        // Mass
        "kg": UnitMass.kilograms, "g": UnitMass.grams, "dg": UnitMass.decigrams, "cg": UnitMass.centigrams,
        "mg": UnitMass.milligrams, "μg": UnitMass.micrograms, "ng": UnitMass.nanograms, "pg": UnitMass.picograms,
        "t": UnitMass.metricTons, "ct": UnitMass.carats, "oz": UnitMass.ounces, "lb": UnitMass.pounds,
        "st": UnitMass.stones, "ton": UnitMass.shortTons, "troyOunces": UnitMass.ouncesTroy, "slug": UnitMass.slugs,
        // Volume
        "L": UnitVolume.liters, "mL": UnitVolume.milliliters, "cL": UnitVolume.centiliters, "dL": UnitVolume.deciliters,
        "kL": UnitVolume.kiloliters, "ML": UnitVolume.megaliters, "tsp": UnitVolume.teaspoons,
        "tbsp": UnitVolume.tablespoons, "fl_oz": UnitVolume.fluidOunces, "cup": UnitVolume.cups, "pt": UnitVolume.pints,
        "qt": UnitVolume.quarts, "gal": UnitVolume.gallons, "bu": UnitVolume.bushels,
        "ifl_oz": UnitVolume.imperialFluidOunces, "ipt": UnitVolume.imperialPints, "iqt": UnitVolume.imperialQuarts,
        "igal": UnitVolume.imperialGallons, "mcup": UnitVolume.metricCups,
        "m^3": UnitVolume.cubicMeters, "cm^3": UnitVolume.cubicCentimeters, "ft^3": UnitVolume.cubicFeet,
        "in^3": UnitVolume.cubicInches,
        // Temperature
        "°C": UnitTemperature.celsius, "°F": UnitTemperature.fahrenheit, "K": UnitTemperature.kelvin,
        // Time
        "s": UnitDuration.seconds, "ms": UnitDuration.milliseconds, "μs": UnitDuration.microseconds,
        "ns": UnitDuration.nanoseconds, "min": UnitDuration.minutes, "hr": UnitDuration.hours,
        // Data
        "bit": UnitInformationStorage.bits, "kbit": UnitInformationStorage.kilobits,
        "Mbit": UnitInformationStorage.megabits, "Gbit": UnitInformationStorage.gigabits,
        "Tbit": UnitInformationStorage.terabits, "byte": UnitInformationStorage.bytes,
        "kB": UnitInformationStorage.kilobytes, "MB": UnitInformationStorage.megabytes,
        "GB": UnitInformationStorage.gigabytes, "TB": UnitInformationStorage.terabytes,
        "PB": UnitInformationStorage.petabytes, "KiB": UnitInformationStorage.kibibytes,
        "MiB": UnitInformationStorage.mebibytes, "GiB": UnitInformationStorage.gibibytes,
        "TiB": UnitInformationStorage.tebibytes, "PiB": UnitInformationStorage.pebibytes,
        // Speed
        "mi/hr": UnitSpeed.milesPerHour, "km/hr": UnitSpeed.kilometersPerHour, "m/s": UnitSpeed.metersPerSecond,
        "knot": UnitSpeed.knots,
        // Area
        "m^2": UnitArea.squareMeters, "km^2": UnitArea.squareKilometers, "cm^2": UnitArea.squareCentimeters,
        "ft^2": UnitArea.squareFeet, "in^2": UnitArea.squareInches, "mi^2": UnitArea.squareMiles,
        "yd^2": UnitArea.squareYards, "ac": UnitArea.acres, "ha": UnitArea.hectares, "a": UnitArea.ares,
        // Energy and power
        "J": UnitEnergy.joules, "kJ": UnitEnergy.kilojoules, "cal": UnitEnergy.calories,
        "kCal": UnitEnergy.kilocalories, "kWh": UnitEnergy.kilowattHours,
        "W": UnitPower.watts, "kW": UnitPower.kilowatts, "MW": UnitPower.megawatts, "GW": UnitPower.gigawatts,
        "mW": UnitPower.milliwatts, "hp": UnitPower.horsepower,
        // Pressure
        "Pa": UnitPressure.newtonsPerMetersSquared, "hPa": UnitPressure.hectopascals, "kPa": UnitPressure.kilopascals,
        "MPa": UnitPressure.megapascals, "GPa": UnitPressure.gigapascals, "bar": UnitPressure.bars,
        "mbar": UnitPressure.millibars, "mmhg": UnitPressure.millimetersOfMercury,
        "inhg": UnitPressure.inchesOfMercury, "lbf/in^2": UnitPressure.poundsForcePerSquareInch,
        // Angle and frequency
        "deg": UnitAngle.degrees, "rad": UnitAngle.radians, "rev": UnitAngle.revolutions,
        "Hz": UnitFrequency.hertz, "kHz": UnitFrequency.kilohertz, "MHz": UnitFrequency.megahertz,
        "GHz": UnitFrequency.gigahertz,
    ]
}
