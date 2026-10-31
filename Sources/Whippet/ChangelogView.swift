import SwiftUI

/// Versions on the left, newest first, and the selected version's changes on the right. Opened from What's New, the
/// versions since the update come first, gathered into one.
struct ChangelogView: View {
    let model: LauncherModel

    var body: some View {
        let results = model.results
        let releases = results.compactMap { if case .release(let release) = $0 { release } else { nil } }
        let selected = releases.indices.contains(model.selection) ? releases[model.selection] : nil

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ReleaseList(model: model, releases: releases)
                    .frame(width: 300)
                Divider()
                if let selected {
                    ReleaseDetail(release: selected)
                        .id(selected.id)
                } else {
                    Text("No matching changes")
                        .foregroundStyle(Color.launcherSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxHeight: .infinity)
            Divider()
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet.rectangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(.indigo, in: RoundedRectangle(cornerRadius: 5))
                    Text("Changelog")
                }
                .padding(.leading, 6)
                .padding(.trailing, 12)
                .padding(.vertical, 4)
                .background(.primary.opacity(0.08), in: Capsule())

                Spacer()

                if let selected {
                    ResultActions(model: model, result: .release(selected))
                }
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 10)
            .frame(height: 44)
        }
    }
}

private struct ReleaseList: View {
    let model: LauncherModel
    let releases: [Release]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(releases.enumerated()), id: \.element.id) { index, release in
                        ReleaseRow(release: release, isSelected: index == model.selection)
                            .id(release.id)
                            .onTapGesture { model.selection = index }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .onChange(of: model.selection) { _, selection in
                guard releases.indices.contains(selection) else { return }
                proxy.scrollTo(releases[selection].id)
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
            Text(LauncherResult.release(release).title)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(LauncherResult.release(release).subtitle)
                .lineLimit(1)
                .foregroundStyle(Color.launcherSecondary)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 8)
        .frame(height: 32)
        .background(isSelected ? Color.primary.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
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
                    Text(LauncherResult.release(release).subtitle)
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
