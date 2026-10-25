import Foundation
import Testing

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
        "5 km", "5 km to kg", "5 to km", "km to mi", "5 apples to pears", "5 km to", "to mi", "72 f to",
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
        let record = CalculationRecord(id: 1, expression: "5 km to mi", answer: "3.106855961", mode: "standard", calculatedAt: .now)
        #expect(record.displayAnswer.contains("mi"))
        #expect(record.answer == "3.106855961")
        let sum = CalculationRecord(id: 2, expression: "2+2", answer: "4", mode: "standard", calculatedAt: .now)
        #expect(sum.displayAnswer == "4")
    }

    @Test(arguments: [
        "5 km t", "5 km to", "5 km to m", "5km to", "5 km i", "72 f in", "12 in to", "12 in to c", "1.5 light years to p",
        "5 km to light y",
    ])
    func recognisesConversionsBeingTyped(_ input: String) {
        #expect(UnitConversion.looksLikeConversion(input))
    }

    @Test(arguments: [
        "1p", "1password", "5k", "5 k", "5 km", "2 apples", "km", "safari", "3 d", "2 f", "1 pa", "5 km to kg",
        "5 km to banana",
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
