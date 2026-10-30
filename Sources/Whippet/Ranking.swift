import Foundation
import Observation
import WhippetCore

/// How often and how recently each app and command was opened from Whippet, which ranks search results and fills the
/// Suggestions section. Apps are keyed by bundle identifier, commands by their result identifier.
@MainActor
@Observable
final class LaunchHistory {
    private(set) var counts: [String: Int]
    private(set) var lastOpened: [String: Date]
    /// Bumped on every launch, so cached results know to rank again.
    private(set) var revision = 0

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Counts kept the name they had when only apps were counted.
        counts = defaults.dictionary(forKey: "appLaunchCounts") as? [String: Int] ?? [:]
        lastOpened = defaults.dictionary(forKey: "launchDates") as? [String: Date] ?? [:]
    }

    func record(_ key: String, at date: Date = .now) {
        counts[key, default: 0] += 1
        lastOpened[key] = date
        revision += 1
        defaults.set(counts, forKey: "appLaunchCounts")
        defaults.set(lastOpened, forKey: "launchDates")
    }

    func frecency(of key: String, now: Date = .now) -> Double {
        Ranking.frecency(count: counts[key] ?? 0, lastOpened: lastOpened[key], now: now)
    }
}

enum Ranking {
    /// Launches weighted by how recently the last one was, so a newly favourite app overtakes an old habit. Launches
    /// counted before dates were kept count as old.
    static func frecency(count: Int, lastOpened: Date?, now: Date) -> Double {
        guard count > 0 else { return 0 }
        let days = lastOpened.map { now.timeIntervalSince($0) / 86_400 } ?? .infinity
        let recency: Double = switch days {
        case ..<1: 1
        case ..<7: 0.8
        case ..<30: 0.5
        default: 0.25
        }
        return Double(count) * recency
    }

    /// Added to a match score. It grows slowly and stays below the 10 points a word start is worth in `FuzzyMatch`, so
    /// heavy use lifts an app among similar matches without beating a clearly better match.
    static func usageBonus(_ frecency: Double) -> Int {
        min(8, Int((log2(1 + frecency) * 2).rounded()))
    }

    /// Matching candidates, best first: match score plus usage bonus, then more use, then the original order.
    static func rank<Candidate>(
        _ candidates: [Candidate],
        query: String,
        title: (Candidate) -> String,
        frecency: (Candidate) -> Double
    ) -> [Candidate] {
        candidates.enumerated()
            .compactMap { offset, candidate -> (offset: Int, candidate: Candidate, score: Int, frecency: Double)? in
                guard let match = FuzzyMatch.score(query, in: title(candidate)) else { return nil }
                let use = frecency(candidate)
                return (offset, candidate, match + usageBonus(use), use)
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.frecency != rhs.frecency { return lhs.frecency > rhs.frecency }
                return lhs.offset < rhs.offset
            }
            .map(\.candidate)
    }

    /// The most used candidates, weighted toward recent use, for the Suggestions section of an empty search.
    static func suggestions<Candidate>(_ candidates: [Candidate], limit: Int, frecency: (Candidate) -> Double) -> [Candidate] {
        let used: [(offset: Int, candidate: Candidate, frecency: Double)] = candidates.enumerated().compactMap { offset, candidate in
            let use = frecency(candidate)
            return use > 0 ? (offset, candidate, use) : nil
        }
        let sorted = used.sorted { lhs, rhs in
            lhs.frecency != rhs.frecency ? lhs.frecency > rhs.frecency : lhs.offset < rhs.offset
        }
        return sorted.prefix(limit).map(\.candidate)
    }
}
