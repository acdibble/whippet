import Foundation
import Testing

@testable import WhippetCore

struct CurrencyTests {
    /// Round numbers, so answers are easy to check: a euro buys 2 dollars, half a pound or 100 yen.
    private let rates = ExchangeRates(date: "2026-10-29", perEuro: ["EUR": 1, "USD": 2, "GBP": 0.5, "JPY": 100])

    private func answer(_ input: String) -> String? {
        Calculator.calculate(input, rates: rates)?.answer
    }

    @Test(arguments: [
        ("10 usd to eur", "5.00"),
        ("10 USD in EUR", "5.00"),
        ("10usd to eur", "5.00"),
        ("$10 to €", "5.00"),
        ("10$ to euros", "5.00"),
        ("USD 10 to EUR", "5.00"),
        ("€1,000 to dollars", "2000.00"),
        ("2 * 3 euros as pounds", "3.00"),
        ("1 pound to yen", "200"),
        ("3 usd to jpy", "150"),
        ("1 usd to gbp", "0.25"),
        ("-4 eur to usd", "-8.00"),
    ])
    func converts(_ input: String, _ expected: String) {
        #expect(answer(input) == expected, "got \(answer(input) ?? "nil")")
    }

    @Test(arguments: [
        ("US$10 to eur", "5.00", "€5.00", "5.00 euros"),
        ("$30/hour to €", "15.00", "€15.00/h", "15.00 euros per hour"),
        ("$30/h to euros per day", "360.00", "€360.00/d", "360.00 euros per d"),
        ("30 dollars/hour to €/min", "0.25", "€0.25/m", "0.25 euros per minute"),
        ("US$30/h in £/m", "0.12", "£0.12/m", "0.12 British pounds per minute"),
        ("$30/h * 8 h in gbp", "60.00", "£60.00", "60.00 British pounds"),
        ("€5 + €5 to yen", "1000", "¥1,000", "1,000 Japanese yen"),
    ])
    func convertsMoneyWorkedOutLikeAUnit(_ input: String, _ expected: String, _ output: String, _ outputLong: String)
        throws
    {
        let conversion = try #require(Calculator.calculate(input, rates: rates)?.conversion, "\(input)")
        #expect(conversion.answer == expected)
        #expect(conversion.output == output)
        #expect(conversion.outputLong == outputLong)
        #expect(conversion.kind == "Currency")
    }

    @Test(arguments: ["$30/h to €/km", "$30 to €/day", "$30/h to chf", "5 km/h to €/day", "$30/h to €/banana"])
    func moneyThatDoesntConvert(_ input: String) {
        #expect(CurrencyConversion.convert(input, rates: rates) == nil)
    }

    @Test func unitsWinOverCurrencies() {
        // Pounds are a weight unless the other side is money.
        #expect(answer("1 pound to kg") == "0.45359237")
        #expect(answer("1 pound to usd") == "4.00")
    }

    @Test func needsRatesForBothCurrencies() {
        #expect(answer("10 usd to chf") == nil)
        #expect(Calculator.calculate("10 usd to eur") == nil)
    }

    @Test func showsWhenTheRatesWereUpdatedAndTheCurrencies() throws {
        var rates = rates
        #expect(Calculator.calculate("10 usd to eur", rates: rates)?.conversion?.kind == "Currency")
        let today = Date.now
        rates.fetchedAt = today
        let conversion = try #require(Calculator.calculate("10 usd to eur", rates: rates)?.conversion)
        #expect(conversion.kind == "Currency · Updated \(today.formatted(date: .omitted, time: .shortened))")
        // An older update names the day.
        let earlier = today.addingTimeInterval(-3 * 86400)
        rates.fetchedAt = earlier
        #expect(rates.kind == "Currency · Updated \(earlier.formatted(date: .abbreviated, time: .shortened))")
        #expect(conversion.output.contains("5"))
        #expect(conversion.output.contains("€") || conversion.output.contains("EUR"))
    }

    @Test func historyShowsTheTargetCurrency() {
        #expect(CurrencyConversion.displayAnswer(5, of: "$10 to eur") == "€5.00")
        #expect(CurrencyConversion.displayAnswer(1000, of: "5 pounds in yen") == "¥1,000")
        #expect(CurrencyConversion.displayAnswer(5, of: "5 pounds in kg") == nil)
        #expect(CurrencyConversion.displayAnswer(360, of: "$30/h to euros per day") == "€360.00/d")
        #expect(CurrencyConversion.displayAnswer(15, of: "$30/h to €") == "€15.00/h")
    }

    @Test(arguments: ["$5 t", "5 usd to", "5 usd to e", "€20 in dol", "5 pounds to $"])
    func recognisesAConversionBeingTyped(_ input: String) {
        #expect(CurrencyConversion.looksLikeConversion(input))
    }

    @Test(arguments: ["$5", "5 usd", "5 usd to xq", "0xff to usd", "safari", "5 cats to"])
    func leavesOtherTextAlone(_ input: String) {
        #expect(!CurrencyConversion.looksLikeConversion(input))
    }

    @Test func readsTheECBFile() throws {
        let xml = """
            <gesmes:Envelope>
                <Cube>
                    <Cube time='2026-10-29'>
                        <Cube currency='USD' rate='1.1130'/>
                        <Cube currency='JPY' rate='175.92'/>
                    </Cube>
                </Cube>
            </gesmes:Envelope>
            """
        let rates = try #require(ExchangeRates(ecbXML: xml))
        #expect(rates.date == "2026-10-29")
        #expect(rates.perEuro == ["EUR": 1, "USD": 1.1130, "JPY": 175.92])
        #expect(ExchangeRates(ecbXML: "<html>Maintenance</html>") == nil)
    }
}
