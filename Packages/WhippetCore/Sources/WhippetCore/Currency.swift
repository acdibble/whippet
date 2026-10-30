import Foundation

/// The European Central Bank's euro reference rates, which it publishes once each working day at about 16:00 CET for
/// around 30 currencies. They're free, need no key, and are fetched as a whole, so nothing reveals what's converted.
public struct ExchangeRates: Codable, Hashable, Sendable {
    /// The day the rates are for, such as `2026-10-29`.
    let date: String
    /// How much of each currency one euro buys, by ISO code, with the euro itself as 1.
    let perEuro: [String: Double]
    /// When Whippet last fetched them, shown with a conversion.
    var fetchedAt: Date?

    static let sourceURL = URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml")!

    public init(date: String, perEuro: [String: Double], fetchedAt: Date? = nil) {
        self.date = date
        self.perEuro = perEuro
        self.fetchedAt = fetchedAt
    }

    /// Reads the ECB's daily file, whose rates are attributes such as `<Cube currency='USD' rate='1.1130'/>` inside a
    /// `<Cube time='2026-10-29'>`.
    init?(ecbXML xml: String) {
        guard let date = xml.firstMatch(of: /time=['"](\d{4}-\d{2}-\d{2})['"]/)?.1 else { return nil }
        var perEuro = ["EUR": 1.0]
        for match in xml.matches(of: /currency=['"]([A-Z]{3})['"]\s+rate=['"]([0-9.]+)['"]/) {
            if let rate = Double(match.2), rate > 0 {
                perEuro[String(match.1)] = rate
            }
        }
        guard perEuro.count > 1 else { return nil }
        self.init(date: String(date), perEuro: perEuro)
    }

    func convert(_ amount: Double, from source: String, to target: String) -> Double? {
        guard let sourceRate = perEuro[source], let targetRate = perEuro[target] else { return nil }
        return amount / sourceRate * targetRate
    }

    /// What a conversion is labelled with: when the rates were last fetched, as `Currency · Updated 14:10`, or with the
    /// day too when that wasn't today.
    var kind: String {
        guard let fetchedAt else { return String(localized: "Currency", bundle: .module) }
        let isToday = Calendar.current.isDateInToday(fetchedAt)
        let time = fetchedAt.formatted(date: isToday ? .omitted : .abbreviated, time: .shortened)
        return String(localized: "Currency · Updated \(time)", bundle: .module)
    }
}

/// Converts `<amount> <currency> to|in <currency>`, such as `5 usd to eur`, `$20 in €`, `€1,000 to pounds` or
/// `2 * 3 GBP as yen`. A currency is its ISO code, its symbol, or a name for it that's not shared with another one, so
/// `peso` and `krone` need their codes.
public enum CurrencyConversion {
    /// Pasted text is never a conversion, as for units.
    private static let maximumLength = 100
    /// The longest currency name or symbol, so an amount is only split near its ends.
    private static let maximumNameLength = 10

    static func convert(_ input: String, rates: ExchangeRates) -> Calculation? {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard text.count <= maximumLength else { return nil }
        for (amountText, targetText) in UnitConversion.splits(text) {
            guard
                let target = currency(named: targetText),
                let (amount, source) = amount(in: amountText),
                let converted = rates.convert(amount, from: source, to: target),
                converted.isFinite
            else { continue }
            let conversion = Conversion(
                input: amount.formatted(.currency(code: source)),
                output: converted.formatted(.currency(code: target)),
                outputLong: converted.formatted(.currency(code: target).presentation(.fullName)),
                kind: rates.kind,
                answer: Calculator.format(converted, fractionDigits: fractionDigits(of: target))
            )
            return Calculation(tokens: [], value: converted, isRPN: false, conversion: conversion)
        }
        return nil
    }

    /// True for a conversion on its way, such as `$5 t` or `5 usd to e`, so the launcher keeps the calculator showing
    /// while the target is typed.
    public static func looksLikeConversion(_ input: String) -> Bool {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard text.count <= maximumLength else { return false }

        // The keyword itself being typed: `$5 t`.
        if let space = text.lastIndex(where: \.isWhitespace) {
            let word = text[text.index(after: space)...].lowercased()
            if UnitConversion.keywords.contains(where: { $0.hasPrefix(word) }), amount(in: String(text[..<space])) != nil {
                return true
            }
        }
        // The target being typed: `$5 to` or `$5 to eu`.
        for (amountText, targetText) in UnitConversion.splits(text) where amount(in: amountText) != nil {
            let typed = targetText.lowercased()
            return typed.isEmpty || vocabulary.contains { $0.hasPrefix(typed) }
        }
        return false
    }

    /// The currency a conversion is into, such as `EUR` for `5 usd to eur`, for showing an answer kept in history.
    static func targetCurrency(of input: String) -> String? {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard text.count <= maximumLength else { return nil }
        return UnitConversion.splits(text).lazy
            .compactMap { amountText, targetText in
                amount(in: amountText) == nil ? nil : currency(named: targetText)
            }
            .first
    }

    // MARK: - Parsing

    /// A number or calculation with a currency before or after it: `$5`, `USD 5`, `5 usd`, `5€` or `2 * 3 euros`.
    private static func amount(in text: String) -> (Double, String)? {
        for length in 1...min(maximumNameLength, text.count) {
            let prefix = text.prefix(length)
            if let code = currency(named: String(prefix)), isBoundary(after: prefix, in: text),
               let value = Calculator.number(String(text.dropFirst(length))) {
                return (value, code)
            }
            let suffix = text.suffix(length)
            if let code = currency(named: String(suffix)), isBoundary(before: suffix, in: text),
               let value = Calculator.number(String(text.dropLast(length))) {
                return (value, code)
            }
        }
        return nil
    }

    /// A name or code can't run into the number's letters, so `usd5` is read but `0xff` isn't `0x` and `FF`.
    private static func isBoundary(after prefix: Substring, in text: String) -> Bool {
        guard let last = prefix.last, last.isLetter, prefix.endIndex < text.endIndex else { return true }
        return !text[prefix.endIndex].isLetter
    }

    private static func isBoundary(before suffix: Substring, in text: String) -> Bool {
        guard let first = suffix.first, first.isLetter, suffix.startIndex > text.startIndex else { return true }
        return !text[text.index(before: suffix.startIndex)].isLetter
    }

    /// The ISO code for a currency's code, symbol or name, in any case.
    static func currency(named rawText: String) -> String? {
        let text = rawText.trimmingCharacters(in: .whitespaces).lowercased()
        if let code = names[text] { return code }
        guard text.count == 3, isoCodes.contains(text.uppercased()) else { return nil }
        return text.uppercased()
    }

    private static let isoCodes = Set(Locale.commonISOCurrencyCodes)

    /// What people type for a currency besides its code, lowercased. A name two currencies share is left out, except
    /// `$` and `dollar` for the US dollar and `¥` for the yen.
    private static let names: [String: String] = {
        var names: [String: String] = [:]
        func add(_ keys: [String], _ code: String) {
            for key in keys { names[key] = code }
        }
        add(["$", "us$", "dollar", "dollars", "buck", "bucks"], "USD")
        add(["€", "euro", "euros"], "EUR")
        add(["£", "pound", "pounds", "quid", "sterling"], "GBP")
        add(["¥", "yen"], "JPY")
        add(["cn¥", "yuan", "rmb", "renminbi"], "CNY")
        add(["a$", "au$"], "AUD")
        add(["c$", "ca$"], "CAD")
        add(["nz$"], "NZD")
        add(["hk$"], "HKD")
        add(["s$"], "SGD")
        add(["r$", "real", "reais"], "BRL")
        add(["₹", "rupee", "rupees"], "INR")
        add(["rupiah"], "IDR")
        add(["₩", "won"], "KRW")
        add(["₺", "lira", "liras"], "TRY")
        add(["₪", "shekel", "shekels"], "ILS")
        add(["฿", "baht"], "THB")
        add(["₱"], "PHP")
        add(["ringgit"], "MYR")
        add(["rand"], "ZAR")
        add(["franc", "francs"], "CHF")
        add(["zł", "zloty", "zlotys", "złoty"], "PLN")
        add(["kč", "koruna"], "CZK")
        add(["forint", "forints"], "HUF")
        add(["leu", "lei"], "RON")
        add(["krona", "kronor"], "SEK")
        return names
    }()

    /// Every word a currency can be typed as, for recognising a target while it's typed.
    private static let vocabulary = Array(names.keys) + isoCodes.map { $0.lowercased() }

    /// Digits after the decimal point in the currency's usual amounts, such as 2 for the dollar and 0 for the yen.
    private static func fractionDigits(of code: String) -> Int {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        return formatter.maximumFractionDigits
    }
}

extension Calculator {
    /// Without grouping, to a fixed number of decimal places, as money is copied.
    public static func format(_ value: Double, fractionDigits: Int) -> String {
        value.formatted(
            .number.locale(Locale(identifier: "en_US_POSIX")).grouping(.never).precision(.fractionLength(fractionDigits))
        )
    }
}
