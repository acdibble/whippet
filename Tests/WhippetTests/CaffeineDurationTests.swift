import Testing

struct CaffeineDurationTests {
    @Test(arguments: [
        ("1", "", "", 3600),
        ("", "90", "", 5400),
        ("", "", "45", 45),
        ("1", "2", "3", 3723),
        (" 2 ", "", "", 7200),
        ("168", "", "", 604_800),
        ("", "", "604800", 604_800),
    ])
    func validDurations(_ hours: String, _ minutes: String, _ seconds: String, _ expected: Int) {
        #expect(CaffeineDuration.seconds(hours: hours, minutes: minutes, seconds: seconds) == expected)
    }

    @Test(arguments: [
        ("", "", ""),
        ("0", "0", "0"),
        ("-1", "", ""),
        ("1.5", "", ""),
        ("one", "", ""),
        ("169", "", ""),
        ("168", "0", "1"),
        ("3000000000000000", "", ""),
        ("", "", "99999999999999999999"),
        ("100", "9999", "999999"),
    ])
    func invalidDurations(_ hours: String, _ minutes: String, _ seconds: String) {
        #expect(CaffeineDuration.seconds(hours: hours, minutes: minutes, seconds: seconds) == nil)
    }
}
