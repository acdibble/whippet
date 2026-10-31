import Foundation
import Testing

@testable import WhippetCore

struct UnitConversionTests {
    private func answer(_ input: String) -> String? {
        UnitConversion.convert(input)?.answer
    }

    @Test(arguments: [
        ("5 km to mi", "3.106855961"),
        ("5km in mi", "3.106855961"),
        ("1 mile to km", "1.609344"),
        ("12 inches to cm", "30.48"),
        ("6 ft to m", "1.8288"),
        ("3 feet to in", "36"),
        ("1 lightyear to km", "9460730473000"),
        ("1 parsec to light years", "3.261563777"),
        ("1 furlong to yd", "220"),
        ("1 smoot to cm", "170.18"),
        ("1 league to miles", "3"),
    ])
    func length(_ input: String, _ expected: String) {
        #expect(answer(input) == expected, "got \(answer(input) ?? "nil")")
    }

    @Test(arguments: [
        ("1 kg to lb", "2.204622622"),
        ("16 oz to lb", "1"),
        ("1 stone to kg", "6.35029318"),
        ("1 tonne to kg", "1000"),
        ("1 ton to lbs", "2000"),
        ("1 hogshead to gal", "63"),
        ("1 hogshead to liters", "238.4809424"),
        ("1 gallon to litres", "3.785411784"),
        ("1 imp gal to l", "4.54609"),
        ("2 cups to ml", "473.176473"),
        ("8 fl oz to cups", "1"),
        ("1 barrel to gallons", "42"),
    ])
    func massAndVolume(_ input: String, _ expected: String) {
        #expect(answer(input) == expected, "got \(answer(input) ?? "nil")")
    }

    @Test(arguments: [
        ("72 f to c", "22.22222222"),
        ("100 °C to °F", "212"),
        ("0 celsius in kelvin", "273.15"),
        ("-40 c to f", "-40"),
        ("98.6 degrees fahrenheit to degrees celsius", "37"),
    ])
    func temperature(_ input: String, _ expected: String) {
        #expect(answer(input) == expected, "got \(answer(input) ?? "nil")")
    }

    @Test(arguments: [
        ("90 min to hours", "1.5"),
        ("2 fortnights to days", "28"),
        ("1 week in hrs", "168"),
        ("3600 sec to h", "1"),
        ("1 GB to MB", "1000"),
        ("1 GiB to MiB", "1024"),
        ("1 byte to bits", "8"),
        ("60 mph to kph", "96.56064"),
        ("10 m/s to km/h", "36"),
        ("1 acre to m2", "4046.856422"),
        ("1 kwh to kj", "3600"),
        ("180 deg to rad", "3.141592654"),
        ("90° to rad", "1.570796327"),
        ("1 rev to degrees", "360"),
    ])
    func otherKinds(_ input: String, _ expected: String) {
        #expect(answer(input) == expected, "got \(answer(input) ?? "nil")")
    }

    @Test(arguments: [
        ("90 min to h", 5400),
        ("1.5 h in minutes", 5400),
        ("2100 seconds / 3 in minutes", 700),
        ("1 day to h", 86400),
        ("1 h + 30 min", 5400),
        ("2100 s / 3", 700),
    ])
    func amountsOfTimeStartATimer(_ input: String, _ seconds: Int) throws {
        let calculation = try #require(Calculator.calculate(input))
        #expect(calculation.timerSeconds() == seconds)
    }

    @Test(arguments: ["5 km to mi", "100 km / 2 h to mph", "20 items / second", "60 per hour to per minute", "2 + 3"])
    func otherResultsDontStartATimer(_ input: String) throws {
        let calculation = try #require(Calculator.calculate(input))
        #expect(calculation.timerSeconds() == nil)
    }

    @Test func ambiguousUnitsTakeTheMeaningThatFits() {
        // m is metres or minutes, c is cups or Celsius, oz is weight or volume.
        #expect(answer("100 m to ft") == "328.0839895")
        #expect(answer("90 m to h") == "1.5")
        #expect(answer("2 c to ml") == "473.176473")
        #expect(answer("20 c to f") == "68")
        #expect(answer("8 oz to g") == "226.796185")
        #expect(answer("8 oz to ml") == "236.5882365")
        // dm is the decimetre, not the package's decametre.
        #expect(answer("1 dm to cm") == "10", "got \(answer("1 dm to cm") ?? "nil")")
    }

    @Test func theAmountCanBeACalculation() {
        #expect(answer("2 * 3 km to m") == "6000")
        #expect(answer("1,500 m to km") == "1.5")
        #expect(answer("(1 + 1) hogsheads to gallons") == "126")
        #expect(answer("0x10 GB to MB") == "16000")
    }

    @Test(arguments: [
        ("2100 seconds / 3 in minutes", "11.66666667"),
        ("2100 s / 3 in m", "11.66666667"),
        ("1 h + 30 min to min", "90"),
        ("1 h 30 min to min", "90"),
        ("5 ft 10 in to cm", "177.8"),
        ("5' 10\" to cm", "177.8"),
        ("1 + 1 hogsheads to gallons", "126"),
        ("2 km - 500 m in m", "1500"),
        ("(1 km + 1 mi) * 2 to m", "5218.688"),
        ("100 km / 2 h to mph", "31.06855961"),
        ("100 km / 2 h in minutes", "0.8333333333"),
        ("60 mph * 30 min to km", "48.28032"),
        ("6 m2 / 2 m to cm", "300"),
        ("(3 m)^2 to ft2", "96.87519375"),
        ("1 / 2 s to Hz", "0.5"),
        ("20 items / 2 seconds in minutes", "600"),
        ("10 items/s * 2 to per min", "1200"),
    ])
    func arithmeticWithUnits(_ input: String, _ expected: String) {
        #expect(answer(input) == expected, "got \(answer(input) ?? "nil")")
    }

    @Test(arguments: [
        "5 km + 2 kg", "5 km + 2 kg to g", "5 km + 2 apples", "5 items/s * 2 kg", "2 km ^ 1 m", "(2 km) m to m",
        "1 / 2 apples",
    ])
    func unitsThatDontFitTogether(_ input: String) {
        #expect(Calculator.calculate(input) == nil, "got \(Calculator.calculate(input)?.displayAnswer ?? "")")
    }

    @Test(arguments: [
        ("2100 seconds / 3", "700", "Time"),
        ("2100 seconds / 3 in", "700", "Time"),
        ("2100 seconds / 3 in mi", "700", "Time"),
        ("20 items / second", "20", "Rate"),
        ("20 items/s", "20", "Rate"),
        ("100 km / 2 h", "50", "Speed"),
        ("1 h + 30 min", "1.5", "Time"),
        ("20 items / second * 1 h", "72000", "Count"),
        ("2 apples * 3", "6", "Count"),
    ])
    func workedOutWithoutATarget(_ input: String, _ expected: String, _ kind: String) throws {
        let calculation = try #require(UnitConversion.workOut(input))
        #expect(calculation.answer == expected)
        #expect(calculation.conversion?.kind == kind)
        #expect(calculation.conversion?.input == input.replacing(/\s+in.*/, with: ""))
    }

    @Test func workedOutAmountsShowTheirUnit() throws {
        let rate = try #require(UnitConversion.workOut("20 items / second")?.conversion)
        #expect(rate.output.hasSuffix(" items/s"), "got \(rate.output)")
        let speed = try #require(UnitConversion.workOut("100 km / 2 h")?.conversion)
        #expect(speed.output.contains("km/h"), "got \(speed.output)")
        let count = try #require(UnitConversion.workOut("20 items / second * 1 h")?.conversion)
        #expect(count.output.hasSuffix(" items"), "got \(count.output)")
    }

    @Test(arguments: [
        "5 km", "-5 km", "2 f", "60 mph", "1 h 30 min", "2 apples", "10 min to feed", "3pm in london", "1password",
    ])
    func loneAmountsWaitForATarget(_ input: String) {
        #expect(UnitConversion.convert(input) == nil)
        #expect(UnitConversion.workOut(input) == nil, "got \(UnitConversion.workOut(input)?.displayAnswer ?? "")")
    }

    @Test func moneyIsntACount() {
        let rates = ExchangeRates(date: "2026-10-30", perEuro: ["EUR": 1, "GBP": 0.5])
        #expect(
            Calculator.calculate("2 * 3 euros as pounds", rates: rates)?.conversion?.kind.hasPrefix("Currency") == true)
    }

    @Test(arguments: [
        ("9.35 items per second in hours", "33660"),
        ("9.35 items per second to per hour", "33660"),
        ("9.35 items/s to items per hour", "33660"),
        ("120 page views per hour to minutes", "2"),
        ("60 km per hour to minutes", "1"),
        ("60 km/h to per min", "1"),
        ("10 m/s in minutes", "600"),
        ("5 km per hour to mph", "3.106855961"),
        ("2 cups per day to weeks", "14"),
        ("60 mph in minutes", "1"),
        ("60 mph to per min", "1"),
        ("36 kph to seconds", "0.01"),
        ("60 knots to minutes", "1"),
    ])
    func rates(_ input: String, _ expected: String) {
        #expect(answer(input) == expected, "got \(answer(input) ?? "nil")")
    }

    @Test func ratesShowWhatTheyCount() throws {
        let calculation = try #require(UnitConversion.convert("9.35 items per second in hours"))
        let conversion = try #require(calculation.conversion)
        #expect(conversion.kind == "Rate")
        #expect(conversion.input.hasSuffix(" items/s"), "got \(conversion.input)")
        #expect(conversion.output.hasSuffix(" items/h"), "got \(conversion.output)")
        #expect(conversion.outputLong.hasSuffix(" items per hour"), "got \(conversion.outputLong)")
    }

    @Test(arguments: [
        "5 km", "5 km to kg", "5 items per second to km", "5 items per second to requests per hour",
        "5 per second to h",
        "5 items per banana to h", "5 to km", "km to mi", "5 apples to pears", "5 km to", "to mi", "72 f to",
        String(repeating: "1", count: 200) + " m to ft",
    ])
    func notConversions(_ input: String) {
        #expect(UnitConversion.convert(input) == nil)
    }

    @Test func showsUnitsAndRecordsHistory() throws {
        let calculation = try #require(UnitConversion.convert("5 km to mi"))
        let conversion = try #require(calculation.conversion)
        #expect(conversion.kind == "Length")
        #expect(conversion.input.contains("km"))
        #expect(conversion.output.contains("mi"))
        #expect(calculation.displayAnswer == conversion.output)
        #expect(!calculation.isPlainNumber)
    }

    @Test func unitsWithoutAFoundationEquivalentShowTheirSymbol() throws {
        let conversion = try #require(UnitConversion.convert("126 gal to hogsheads")?.conversion)
        #expect(conversion.output.hasSuffix(" hogsheads"))
        let one = try #require(UnitConversion.convert("63 gal to hogsheads")?.conversion)
        #expect(one.output.hasSuffix(" hogshead"), "got \(one.output)")
    }

    @Test(arguments: [
        ("12 in to cm", "30.48"),
        ("5 in in cm", "12.7"),
        ("1 sq in to cm2", "6.4516"),
        ("3 ft in in", "36"),
        ("0xFF MB to kB", "255000"),
    ])
    func inchesAndKeywordsTogether(_ input: String, _ expected: String) {
        #expect(answer(input) == expected, "got \(answer(input) ?? "nil")")
    }

    @Test func negativeOneIsSingular() throws {
        let conversion = try #require(UnitConversion.convert("-63 gal to hogsheads")?.conversion)
        #expect(conversion.output.hasSuffix(" hogshead"), "got \(conversion.output)")
    }

    @Test func historyShowsTheUnitButKeepsTheNumber() {
        let record = CalculationRecord(
            id: 1, expression: "5 km to mi", answer: "3.106855961", mode: "standard", calculatedAt: .now)
        #expect(record.displayAnswer.contains("mi"))
        #expect(record.answer == "3.106855961")
        let sum = CalculationRecord(id: 2, expression: "2+2", answer: "4", mode: "standard", calculatedAt: .now)
        #expect(sum.displayAnswer == "4")
    }

    @Test(arguments: [
        "5 km t", "5 km to", "5 km to m", "5km to", "5 km i", "72 f in", "12 in to", "12 in to c",
        "1.5 light years to p",
        "5 km to light y", "9 items per second in h", "9 items per second to per", "9 items per second to per ho",
        "2100 seconds /", "2100 seconds / 3 i", "1 h + (",
    ])
    func recognisesConversionsBeingTyped(_ input: String) {
        #expect(UnitConversion.looksLikeConversion(input))
    }

    @Test(arguments: [
        "1p", "1password", "5k", "5 k", "5 km", "2 apples", "km", "safari", "3 d", "2 f", "1 pa", "5 km to kg",
        "5 km to banana", "5 km to per", "2 apples +", "5 apples t",
    ])
    func leavesOtherSearchesAlone(_ input: String) {
        #expect(!UnitConversion.looksLikeConversion(input))
    }

    @Test func aNamedTimerStaysATimerUntilAFittingUnitStarts() {
        #expect(!UnitConversion.looksLikeConversion("10 min to", requiresTarget: true))
        #expect(!UnitConversion.looksLikeConversion("10 min to feed", requiresTarget: true))
        #expect(UnitConversion.looksLikeConversion("10 min to s", requiresTarget: true))
    }
}
