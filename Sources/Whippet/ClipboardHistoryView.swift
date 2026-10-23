import AppKit
import SwiftUI

struct ClipboardKindMenu: View {
    let model: LauncherModel

    var body: some View {
        HoverHighlight(isPressed: false) {
            Menu {
                Button("All Types") { model.clipboardKind = nil }
                ForEach(ClipboardKind.allCases) { kind in
                    Button(kind.pluralTitle) { model.clipboardKind = kind }
                }
            } label: {
                Label(model.clipboardKind?.pluralTitle ?? String(localized: "All Types"), systemImage: "list.bullet")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
}

struct ClipboardHistoryView: View {
    let model: LauncherModel

    var body: some View {
        let items = model.clipboardItems

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ItemList(model: model, items: items)
                    .frame(width: 300)
                Divider()
                if items.indices.contains(model.selection) {
                    let item = items[model.selection]
                    ItemDetail(item: item, imageURL: model.imageURL(for: item))
                } else {
                    EmptyDetail()
                }
            }
            .frame(maxHeight: .infinity)
            Divider()
            footer(selected: items.indices.contains(model.selection) ? items[model.selection] : nil)
        }
    }

    private func footer(selected: ClipboardItem?) -> some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "list.clipboard.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(.orange, in: RoundedRectangle(cornerRadius: 5))
                Text("Clipboard History")
            }
            .padding(.leading, 6)
            .padding(.trailing, 12)
            .padding(.vertical, 4)
            .background(.primary.opacity(0.08), in: Capsule())

            Spacer()

            if let selected {
                ResultActions(model: model, result: .clipboard(selected))
            }
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 10)
        .frame(height: 44)
    }
}

private struct ItemList: View {
    let model: LauncherModel
    let items: [ClipboardItem]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(sections, id: \.title) { section in
                        SectionHeader(title: section.title)
                        ForEach(section.rows, id: \.item.id) { row in
                            ItemRow(
                                item: row.item,
                                imageURL: model.imageURL(for: row.item),
                                isSelected: row.index == model.selection
                            )
                                .id(row.item.id)
                                .onTapGesture { model.selection = row.index }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .onChange(of: model.selection) { _, selection in
                guard items.indices.contains(selection) else { return }
                proxy.scrollTo(items[selection].id)
            }
        }
    }

    /// Groups pinned items, then the newest-first rest by day, keeping each item's position in `items` for selection.
    private var sections: [(title: String, rows: [(index: Int, item: ClipboardItem)])] {
        var sections: [(title: String, rows: [(index: Int, item: ClipboardItem)])] = []
        for (index, item) in items.enumerated() {
            let title = item.pinnedAt == nil ? Self.dayTitle(for: item.copiedAt) : String(localized: "Pinned")
            if sections.last?.title == title {
                sections[sections.count - 1].rows.append((index, item))
                continue
            }
            sections.append((title, [(index, item)]))
        }
        return sections
    }

    private static func dayTitle(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return String(localized: "Today") }
        if calendar.isDateInYesterday(date) { return String(localized: "Yesterday") }
        return date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }
}

private struct ItemRow: View {
    let item: ClipboardItem
    let imageURL: URL?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: 18, height: 18)
            Text(item.title)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 8)
        .frame(height: 32)
        .background(isSelected ? Color.primary.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var icon: some View {
        if let imageURL, let image = NSImage(contentsOf: imageURL) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 18, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        } else {
            Image(systemName: item.kind.symbolName)
                .foregroundStyle(Color.launcherSecondary)
        }
    }
}

private struct ItemDetail: View {
    let item: ClipboardItem
    let imageURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            preview
                .frame(maxHeight: .infinity)
            InformationList(title: "Information", rows: information)
                .padding(8)
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let imageURL, let image = NSImage(contentsOf: imageURL) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(16)
                .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                Text(item.text ?? "")
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }
    }

    private var information: [InformationRow] {
        let source = SourceApp(bundleID: item.sourceBundleID)
        var rows = [
            InformationRow("Source", source.name, icon: source.icon),
            InformationRow("Type", item.kind.title),
        ]
        if item.kind == .image {
            rows += [
                InformationRow("Dimensions", "\(item.imageWidth ?? 0)×\(item.imageHeight ?? 0)"),
                InformationRow("Size", Int64(item.imageBytes ?? 0).formatted(.byteCount(style: .file))),
                InformationRow("Recognized words", recognizedWords),
            ]
        } else {
            let text = item.text ?? ""
            rows += [
                InformationRow("Characters", text.count.formatted()),
                InformationRow("Words", text.split(whereSeparator: \.isWhitespace).count.formatted()),
            ]
        }
        return rows + [
            InformationRow("Times copied", item.timesCopied.formatted()),
            InformationRow("Last copied", item.copiedAt.formatted(date: .abbreviated, time: .shortened)),
        ]
    }

    private var recognizedWords: String {
        guard let ocrText = item.ocrText else { return String(localized: "Processing…") }
        return ocrText.split(whereSeparator: \.isWhitespace).count.formatted()
    }
}

struct InformationRow {
    let label: String
    let value: String
    let icon: NSImage?

    init(_ label: LocalizedStringResource, _ value: String, icon: NSImage? = nil) {
        self.init(verbatim: String(localized: label), value, icon: icon)
    }

    /// For a label that is already localized, such as a clipboard type name.
    init(verbatim label: String, _ value: String, icon: NSImage? = nil) {
        self.label = label
        self.value = value
        self.icon = icon
    }
}

/// A titled list of label and value rows with alternating shading.
struct InformationList: View {
    let title: String
    let rows: [InformationRow]

    init(title: LocalizedStringResource, rows: [InformationRow]) {
        self.title = String(localized: title)
        self.rows = rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.launcherSecondary)
                .padding(.horizontal, 8)
                .padding(.bottom, 6)

            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 6) {
                    Text(row.label)
                        .foregroundStyle(Color.launcherSecondary)
                    Spacer()
                    if let icon = row.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 16, height: 16)
                    }
                    Text(row.value)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.system(size: 12))
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(
                    index.isMultiple(of: 2) ? Color.primary.opacity(0.05) : .clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
            }
        }
    }
}

private struct EmptyDetail: View {
    var body: some View {
        Text("No clipboard history")
            .foregroundStyle(Color.launcherSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct KeyCap: View {
    private let label: Text

    init(symbol: String) {
        label = Text(Image(systemName: symbol))
    }

    init(_ key: String) {
        label = Text(key)
    }

    var body: some View {
        label
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.launcherSecondary)
            .frame(width: 20, height: 20)
            .background(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.launcherSecondary.opacity(0.5)))
    }
}

private struct SourceApp {
    let name: String
    let icon: NSImage?

    init(bundleID: String?) {
        guard let bundleID else {
            name = String(localized: "Unknown")
            icon = nil
            return
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            name = bundleID
            icon = nil
            return
        }
        name = AppIndex.displayName(of: url)
        icon = NSWorkspace.shared.icon(forFile: url.path)
    }
}
