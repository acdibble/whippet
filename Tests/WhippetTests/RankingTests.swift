import Foundation
import Testing

struct RankingTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func recentLaunchesWeighMore() {
        let today = Ranking.frecency(count: 4, lastOpened: now.addingTimeInterval(-3600), now: now)
        let lastMonth = Ranking.frecency(count: 4, lastOpened: now.addingTimeInterval(-20 * 86_400), now: now)
        let undated = Ranking.frecency(count: 4, lastOpened: nil, now: now)
        #expect(today > lastMonth)
        #expect(lastMonth > undated)
        #expect(Ranking.frecency(count: 0, lastOpened: now, now: now) == 0)
    }

    @Test func theUsageBonusIsCapped() {
        #expect(Ranking.usageBonus(0) == 0)
        #expect(Ranking.usageBonus(1) > 0)
        #expect(Ranking.usageBonus(10_000) == 8)
    }

    @Test func usageLiftsAnAppAmongSimilarMatches() {
        let use: [String: Double] = ["Mail": 0, "Maps": 12]
        let ranked = Ranking.rank(["Mail", "Maps"], query: "ma", title: { $0 }, frecency: { use[$0] ?? 0 })
        #expect(ranked == ["Maps", "Mail"])
    }

    @Test func aClearlyBetterMatchBeatsHeavyUse() {
        let use: [String: Double] = ["Terminal": 0, "Telegram": 500]
        let ranked = Ranking.rank(["Telegram", "Terminal"], query: "term", title: { $0 }, frecency: { use[$0] ?? 0 })
        #expect(ranked.first == "Terminal")
    }

    @Test func nonMatchesAreDropped() {
        #expect(Ranking.rank(["Safari", "Notes"], query: "saf", title: { $0 }, frecency: { _ in 0 }) == ["Safari"])
    }

    @Test func suggestionsAreTheMostUsedInOrder() {
        let use: [String: Double] = ["Safari": 3, "Notes": 0, "Mail": 9, "Maps": 3]
        let suggestions = Ranking.suggestions(["Safari", "Notes", "Mail", "Maps"], limit: 2, frecency: { use[$0] ?? 0 })
        #expect(suggestions == ["Mail", "Safari"])
    }

    @MainActor
    @Test func historyPersists() throws {
        let suite = "WhippetTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["com.apple.Safari": 7], forKey: "appLaunchCounts")

        let history = LaunchHistory(defaults: defaults)
        #expect(history.counts["com.apple.Safari"] == 7)
        history.record("command:calculator", at: now)

        let reloaded = LaunchHistory(defaults: defaults)
        #expect(reloaded.counts["command:calculator"] == 1)
        #expect(reloaded.lastOpened["command:calculator"] == now)
        #expect(reloaded.frecency(of: "command:calculator", now: now) == 1)
    }
}
