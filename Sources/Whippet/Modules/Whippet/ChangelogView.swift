import SwiftUI

/// Versions on the left, newest first, and the selected version's changes on the right. Opened from What's New, the
/// versions since the update come first, gathered into one.
struct ChangelogView: View {
    @Environment(LauncherModel.self) private var host

    var body: some View {
        let releases = host.results.compactMap { $0.payload(as: Release.self) }
        let selected = releases.indices.contains(host.selection) ? releases[host.selection] : nil

        SplitPane {
            ReleaseList(releases: releases)
        } detail: {
            if let selected {
                ReleaseDetail(release: selected)
                    .id(selected.id)
            } else {
                Text("No matching changes")
                    .foregroundStyle(Color.launcherSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct ReleaseList: View {
    @Environment(LauncherModel.self) private var host
    let releases: [Release]

    var body: some View {
        SelectableList(ids: releases.map(\.id), selection: host.selection) {
            ForEach(Array(releases.enumerated()), id: \.element.id) { index, release in
                ReleaseRow(release: release, isSelected: index == host.selection)
                    .id(release.id)
                    .onTapGesture { host.selection = index }
            }
        }
    }
}

private struct ReleaseRow: View {
    let release: Release
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: release.since == nil ? "tag" : "sparkles")
                .foregroundStyle(Color.launcherSecondary)
                .frame(width: 18, height: 18)
            Text(ChangelogScreen.title(of: release))
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(ChangelogScreen.subtitle(of: release))
                .lineLimit(1)
                .foregroundStyle(Color.launcherSecondary)
        }
        .listRow(isSelected: isSelected, compact: true)
    }
}

/// A version's note and its sections of changes. Gathered versions tag each change with the version it came in.
private struct ReleaseDetail: View {
    let release: Release

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        release.since == nil
                            ? String(localized: "Whippet \(release.version)")
                            : String(localized: "What's New in \(release.version)")
                    )
                    .font(.system(size: 17, weight: .semibold))
                    Text(ChangelogScreen.subtitle(of: release))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.launcherSecondary)
                }
                if let note = release.note {
                    Text(Self.markdown(note))
                        .foregroundStyle(Color.launcherSecondary)
                }
                ForEach(release.sections, id: \.title) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Self.sectionTitle(section.title))
                            .font(.system(size: 13, weight: .semibold))
                        ForEach(Array(section.changes.enumerated()), id: \.offset) { _, change in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(verbatim: "•")
                                    .foregroundStyle(Color.launcherSecondary)
                                Text(Self.markdown(change.text))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if release.since != nil {
                                    Text(verbatim: change.version)
                                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                                        .foregroundStyle(Color.launcherSecondary)
                                }
                            }
                        }
                    }
                }
            }
            .font(.system(size: 13))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    /// The changelog's own headings, translated where Whippet knows them.
    private static func sectionTitle(_ title: String) -> String {
        switch title {
        case "Added": String(localized: "Added")
        case "Changed": String(localized: "Changed")
        case "Fixed": String(localized: "Fixed")
        case "Removed": String(localized: "Removed")
        case "Deprecated": String(localized: "Deprecated")
        case "Security": String(localized: "Security")
        default: title
        }
    }

    /// Bold, code and links within a change; anything else shows as written.
    private static func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
