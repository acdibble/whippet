import Foundation
import Testing

struct ClipboardRetentionTests {
    @Test func cutoffs() throws {
        let now = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 31, hour: 12)))
        let calendar = Calendar.current
        #expect(ClipboardRetention.forever.cutoff(from: now) == nil)
        #expect(ClipboardRetention.day.cutoff(from: now) == calendar.date(byAdding: .day, value: -1, to: now))
        #expect(ClipboardRetention.week.cutoff(from: now) == calendar.date(byAdding: .day, value: -7, to: now))
        // Month arithmetic clamps to the end of a shorter month.
        #expect(ClipboardRetention.month.cutoff(from: now).map { calendar.component(.day, from: $0) } == 28)
        #expect(ClipboardRetention.threeMonths.cutoff(from: now).map { calendar.component(.month, from: $0) } == 12)
        #expect(ClipboardRetention.year.cutoff(from: now).map { calendar.component(.year, from: $0) } == 2025)
    }
}
