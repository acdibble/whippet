import Foundation

/// One version in the changelog, or for What's New, every version since an update gathered into one.
struct Release: Hashable, Identifiable {
    struct Section: Hashable {
        /// Added, Changed, Fixed and so on, as written in the changelog.
        let title: String
        let changes: [Change]
    }

    struct Change: Hashable {
        /// Markdown with inline formatting only.
        let text: String
        /// The version the change came in, shown beside it when versions are gathered together.
        let version: String
    }

    /// The version, such as `0.11.3`, or for gathered versions the newest of them.
    let version: String
    let date: Date?
    /// Text under the version heading before its first section, such as why it was never published.
    let note: String?
    let sections: [Section]
    /// For What's New, the version updated from, whose own changes aren't included; nil for a single version.
    let since: String?

    var id: String { since.map { "since:\($0)" } ?? version }

    /// Every change's text, for filtering the list.
    var searchText: String {
        ([version, note ?? ""] + sections.flatMap { $0.changes.map(\.text) }).joined(separator: "\n")
    }
}

/// Reads the CHANGELOG.md shipped in the app. It follows Keep a Changelog: `## [version] - date` headings, `###`
/// sections, and `- ` items that may wrap onto lines indented by two spaces.
enum Changelog {
    static func parse(_ markdown: String) -> [Release] {
        var releases: [Release] = []
        var version: String?
        var date: Date?
        var note: [String] = []
        var sections: [Release.Section] = []
        var sectionTitle: String?
        var changes: [String] = []

        func endSection() {
            if let version, let sectionTitle, !changes.isEmpty {
                sections.append(.init(title: sectionTitle, changes: changes.map { .init(text: $0, version: version) }))
            }
            sectionTitle = nil
            changes = []
        }
        func endRelease() {
            endSection()
            if let version {
                let note = note.joined(separator: " ")
                releases.append(
                    Release(
                        version: version, date: date, note: note.isEmpty ? nil : note, sections: sections, since: nil))
            }
            version = nil
            date = nil
            note = []
            sections = []
        }

        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("## [") {
                endRelease()
                let heading = line.dropFirst(4)
                guard let close = heading.firstIndex(of: "]") else { continue }
                let name = String(heading[..<close])
                // Unreleased changes aren't in any build anyone runs.
                guard name != "Unreleased" else { continue }
                version = name
                let rest = heading[heading.index(after: close)...].trimmingCharacters(
                    in: CharacterSet(charactersIn: " -"))
                date = day(from: rest)
            } else if version == nil {
                continue
            } else if line.hasPrefix("### ") {
                endSection()
                sectionTitle = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("- "), sectionTitle != nil {
                changes.append(String(line.dropFirst(2)))
            } else if line.hasPrefix("  "), !changes.isEmpty, !line.trimmingCharacters(in: .whitespaces).isEmpty {
                changes[changes.count - 1] += " " + line.trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("["), line.contains("]: ") {
                // The links at the end, which follow the last version.
                endRelease()
            } else if sectionTitle == nil, !line.trimmingCharacters(in: .whitespaces).isEmpty {
                note.append(line.trimmingCharacters(in: .whitespaces))
            }
        }
        endRelease()
        return releases
    }

    /// The versions after `version` up to and including `current`, newest first, gathered into one: each section keeps
    /// the order sections first appear in, with the newest changes first.
    static func changes(after version: String, upTo current: String, in releases: [Release]) -> Release? {
        let newer = releases.filter {
            isVersion($0.version, newerThan: version) && !isVersion($0.version, newerThan: current)
        }
        guard let newest = newer.first else { return nil }
        var titles: [String] = []
        var changes: [String: [Release.Change]] = [:]
        for section in newer.flatMap(\.sections) {
            if changes[section.title] == nil {
                titles.append(section.title)
            }
            changes[section.title, default: []] += section.changes
        }
        return Release(
            version: newest.version,
            date: newest.date,
            note: nil,
            sections: titles.map { .init(title: $0, changes: changes[$0] ?? []) },
            since: version
        )
    }

    /// A `2026-10-29` date as that day in this Mac's time zone, so it isn't shown as the day before west of UTC.
    private static func day(from text: String) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// Compares versions such as `0.11.3` and `0.12.0` part by part, as numbers; missing parts count as zero.
    static func isVersion(_ version: String, newerThan other: String) -> Bool {
        let parts = version.split(separator: ".").map { Int($0) ?? 0 }
        let otherParts = other.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(parts.count, otherParts.count) {
            let part = index < parts.count ? parts[index] : 0
            let otherPart = index < otherParts.count ? otherParts[index] : 0
            if part != otherPart { return part > otherPart }
        }
        return false
    }

    /// The changelog shipped in the app, newest version first.
    static let shipped: [Release] = {
        guard
            let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
            let markdown = try? String(contentsOf: url, encoding: .utf8)
        else { return [] }
        return parse(markdown)
    }()
}

/// Remembers the version last run, so that after an update the launcher can offer What's New for a week, until it's
/// opened or dismissed. Several updates before then are shown together, from the version first updated from.
struct WhatsNew {
    static let duration: TimeInterval = 7 * 24 * 60 * 60

    private enum Keys {
        static let lastRunVersion = "lastRunVersion"
        static let since = "whatsNewSince"
        static let until = "whatsNewUntil"
    }

    var defaults = UserDefaults.standard

    /// Called once at launch. A first launch has nothing to show, since everything is new.
    func recordLaunch(of version: String, at now: Date = .now) {
        if let last = defaults.string(forKey: Keys.lastRunVersion), Changelog.isVersion(version, newerThan: last) {
            if pending(at: now) == nil {
                defaults.set(last, forKey: Keys.since)
            }
            defaults.set(now.addingTimeInterval(Self.duration), forKey: Keys.until)
        }
        defaults.set(version, forKey: Keys.lastRunVersion)
    }

    /// The version updated from while What's New is still offered.
    func pending(at now: Date = .now) -> String? {
        guard
            let since = defaults.string(forKey: Keys.since),
            let until = defaults.object(forKey: Keys.until) as? Date,
            now < until
        else { return nil }
        return since
    }

    func dismiss() {
        defaults.removeObject(forKey: Keys.since)
        defaults.removeObject(forKey: Keys.until)
    }
}
