import Foundation
import Testing

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

    @Test func unitsWinOverCurrencies() {
        // Pounds are a weight unless the other side is money.
        #expect(answer("1 pound to kg") == "0.45359237")
        #expect(answer("1 pound to usd") == "4.00")
    }

    @Test func needsRatesForBothCurrencies() {
        #expect(answer("10 usd to chf") == nil)
        #expect(Calculator.calculate("10 usd to eur") == nil)
    }

    @Test func keepsTheRatesDateAndShowsCurrencies() throws {
        let conversion = try #require(Calculator.calculate("10 usd to eur", rates: rates)?.conversion)
        #expect(conversion.kind.hasPrefix("Currency · "))
        #expect(conversion.output.contains("5"))
        #expect(conversion.output.contains("€") || conversion.output.contains("EUR"))
    }

    @Test func historyShowsTheTargetCurrency() {
        #expect(CurrencyConversion.targetCurrency(of: "$10 to eur") == "EUR")
        #expect(CurrencyConversion.targetCurrency(of: "5 pounds in yen") == "JPY")
        #expect(CurrencyConversion.targetCurrency(of: "5 pounds in kg") == nil)
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
