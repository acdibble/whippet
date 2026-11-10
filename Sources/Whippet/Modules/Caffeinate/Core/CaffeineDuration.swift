import Foundation

/// Turns the Hours, Minutes and Seconds typed for "Caffeinate for…" into a number of seconds.
enum CaffeineDuration {
    /// A week. Anything longer is almost certainly a typo, and the limit keeps the arithmetic far from overflowing.
    static let maximumSeconds = 7 * 24 * 60 * 60

    /// Empty fields count as zero. Returns nil when a field isn't a whole number, or the total is zero or over the limit.
    static func seconds(hours: String, minutes: String, seconds: String) -> Int? {
        var total = 0
        for (field, unit) in [(hours, 3600), (minutes, 60), (seconds, 1)] {
            let text = field.trimmingCharacters(in: .whitespaces)
            if text.isEmpty { continue }
            // Checked before multiplying, so no field can overflow.
            guard let value = Int(text), value >= 0, value <= maximumSeconds / unit else { return nil }
            total += value * unit
        }
        guard total > 0, total <= maximumSeconds else { return nil }
        return total
    }
}
