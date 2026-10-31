import Foundation
import Testing

struct ChangelogTests {
    private let sample = """
        # Changelog

        All notable changes. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

        ## [Unreleased]

        ### Added

        - Not shipped yet.

        ## [0.3.0] - 2026-10-29

        ### Added

        - **Bold** feature with `code`, which wraps
          onto a second line.
        - Another.

        ### Fixed

        - A fix in 0.3.0.

        ## [0.2.0] - 2026-10-20

        ### Fixed

        - A fix in 0.2.0.

        ## [0.1.0] - 2026-10-10

        Tagged but never published.

        ### Added

        - The first version.

        [Unreleased]: https://example.com/compare/v0.3.0...HEAD
        [0.3.0]: https://example.com/compare/v0.2.0...v0.3.0
        """

    @Test func parsesVersionsNewestFirstWithoutUnreleased() throws {
        let releases = Changelog.parse(sample)
        #expect(releases.map(\.version) == ["0.3.0", "0.2.0", "0.1.0"])
        let date = try #require(releases[0].date)
        #expect(
            Calendar.current.dateComponents([.year, .month, .day], from: date)
                == DateComponents(year: 2026, month: 10, day: 29))
    }

    @Test func joinsWrappedLinesAndKeepsSections() {
        let release = Changelog.parse(sample)[0]
        #expect(release.sections.map(\.title) == ["Added", "Fixed"])
        #expect(
            release.sections[0].changes.map(\.text) == [
                "**Bold** feature with `code`, which wraps onto a second line.",
                "Another.",
            ])
        #expect(release.note == nil)
    }

    @Test func keepsANoteAndIgnoresTheLinks() {
        let first = Changelog.parse(sample)[2]
        #expect(first.note == "Tagged but never published.")
        #expect(first.sections.flatMap(\.changes).map(\.text) == ["The first version."])
    }

    @Test func gathersTheVersionsSinceAnUpdate() throws {
        let releases = Changelog.parse(sample)
        let gathered = try #require(Changelog.changes(after: "0.1.0", upTo: "0.3.0", in: releases))
        #expect(gathered.version == "0.3.0")
        #expect(gathered.since == "0.1.0")
        #expect(gathered.sections.map(\.title) == ["Added", "Fixed"])
        #expect(gathered.sections[1].changes.map(\.version) == ["0.3.0", "0.2.0"])
        #expect(gathered.id != releases[0].id)

        #expect(Changelog.changes(after: "0.2.0", upTo: "0.2.0", in: releases) == nil)
        #expect(Changelog.changes(after: "0.1.0", upTo: "0.2.0", in: releases)?.sections.flatMap(\.changes).count == 1)
    }

    @Test func comparesVersionsAsNumbers() {
        #expect(Changelog.isVersion("0.10.0", newerThan: "0.9.9"))
        #expect(Changelog.isVersion("1.0", newerThan: "0.99.0"))
        #expect(!Changelog.isVersion("0.11.0", newerThan: "0.11"))
        #expect(!Changelog.isVersion("0.2.0", newerThan: "0.2.1"))
    }

    @Test func theRealChangelogParses() throws {
        let url = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../CHANGELOG.md")
        let markdown = try String(contentsOf: url, encoding: .utf8)
        let releases = Changelog.parse(markdown)
        let headings = markdown.split(separator: "\n").filter {
            $0.hasPrefix("## [") && !$0.hasPrefix("## [Unreleased]")
        }
        #expect(releases.count == headings.count)
        #expect(releases.allSatisfy { $0.date != nil && !$0.sections.isEmpty })
    }

    // MARK: - What's New

    private func whatsNew() -> WhatsNew {
        let name = "WhippetTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return WhatsNew(defaults: defaults)
    }

    @Test func aFirstLaunchHasNothingNew() {
        let whatsNew = whatsNew()
        whatsNew.recordLaunch(of: "0.3.0")
        #expect(whatsNew.pending() == nil)
    }

    @Test func anUpdateOffersWhatsNewForAWeek() {
        let whatsNew = whatsNew()
        let start = Date(timeIntervalSince1970: 1_000_000)
        whatsNew.recordLaunch(of: "0.1.0", at: start)
        whatsNew.recordLaunch(of: "0.1.0", at: start)
        #expect(whatsNew.pending(at: start) == nil)

        whatsNew.recordLaunch(of: "0.2.0", at: start)
        #expect(whatsNew.pending(at: start.addingTimeInterval(6 * 24 * 60 * 60)) == "0.1.0")
        #expect(whatsNew.pending(at: start.addingTimeInterval(WhatsNew.duration)) == nil)
    }

    @Test func updatesBeforeItsSeenAreShownTogether() {
        let whatsNew = whatsNew()
        let start = Date(timeIntervalSince1970: 1_000_000)
        whatsNew.recordLaunch(of: "0.1.0", at: start)
        whatsNew.recordLaunch(of: "0.2.0", at: start)
        whatsNew.recordLaunch(of: "0.3.0", at: start.addingTimeInterval(60))
        #expect(whatsNew.pending(at: start.addingTimeInterval(120)) == "0.1.0")

        whatsNew.dismiss()
        #expect(whatsNew.pending(at: start.addingTimeInterval(120)) == nil)
        whatsNew.recordLaunch(of: "0.3.0", at: start.addingTimeInterval(180))
        #expect(whatsNew.pending(at: start.addingTimeInterval(180)) == nil)
    }
}
