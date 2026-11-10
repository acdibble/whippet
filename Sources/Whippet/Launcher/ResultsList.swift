import KeyboardShortcuts
import SwiftUI
import WhippetCore

/// The top screen's items as a list: rows pinned above the scrolling ones, headings where the section changes, and
/// each row the screen's own or the standard one.
struct ResultsList: View {
    @Environment(LauncherModel.self) private var host

    var body: some View {
        let results = host.results
        let pinned = min(host.pinnedCount(), results.count)

        VStack(spacing: 0) {
            // A translation stays at the top while what its text can be used with scrolls under it.
            if pinned > 0 {
                VStack(alignment: .leading, spacing: 2) {
                    rows(listItems(of: results, in: 0..<pinned))
                }
                .padding(.horizontal, 8)
                .padding(.top, 6)
            }
            // One flat list of headers and rows, each with its own identity. Rows nested in a ForEach per section
            // left stale selection highlights on the wrong rows as the selection moved.
            SelectableList(ids: results.map(\.id), selection: host.selection) {
                rows(listItems(of: results, in: pinned..<results.count))
            }
        }
    }

    /// Consecutive items under a heading, keeping each item's position in `results` for selection.
    private enum ListItem: Identifiable {
        case header(String)
        case row(index: Int, item: LauncherItem)

        var id: String {
            switch self {
            case .header(let title): "header:\(title)"
            case .row(_, let item): item.id
            }
        }
    }

    private func rows(_ items: [ListItem]) -> some View {
        ForEach(items) { item in
            switch item {
            case .header(let title):
                SectionHeader(title: title)
            case .row(let index, let item):
                Group {
                    if let row = host.activeScreen.rowView(for: item, index: index, isSelected: index == host.selection)
                    {
                        row
                    } else {
                        ResultRow(item: item, isSelected: index == host.selection)
                    }
                }
                .onTapGesture {
                    host.selection = index
                    host.activate()
                }
            }
        }
    }

    private func listItems(of results: [LauncherItem], in range: Range<Int>) -> [ListItem] {
        var items: [ListItem] = []
        var currentTitle: String?
        for index in range {
            if let title = host.sectionTitle(at: index), title != currentTitle {
                items.append(.header(title))
                currentTitle = title
            }
            items.append(.row(index: index, item: results[index]))
        }
        return items
    }
}

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.launcherSecondary)
            .padding(.horizontal, 8)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }
}

/// An item's row: its icon and title, an Admin badge, its hotkey, and its subtitle or what the module shows in its
/// place, such as a timer counting down.
struct ResultRow<Trailing: View>: View {
    let item: LauncherItem
    let isSelected: Bool
    let trailing: Trailing?

    init(item: LauncherItem, isSelected: Bool, @ViewBuilder trailing: () -> Trailing) {
        self.item = item
        self.isSelected = isSelected
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            item.icon.view
                .frame(width: 22, height: 22)
            Text(item.title)
                .lineLimit(1)
            if item.subtitleBesideTitle, !item.subtitle.isEmpty {
                Text(item.subtitle)
                    .foregroundStyle(Color.launcherSecondary)
                    .lineLimit(1)
            }
            Spacer()
            if item.isAdminOnly {
                AdminBadge()
            }
            if let name = item.hotkey, let hotkey = KeyboardShortcuts.getShortcut(for: name) {
                HotkeyLabel(shortcut: hotkey)
            }
            Group {
                if let trailing {
                    trailing
                } else if !item.subtitleBesideTitle {
                    Text(item.subtitle)
                }
            }
            .foregroundStyle(Color.launcherSecondary)
        }
        .listRow(isSelected: isSelected)
    }
}

extension ResultRow where Trailing == EmptyView {
    init(item: LauncherItem, isSelected: Bool) {
        self.item = item
        self.isSelected = isSelected
        trailing = nil
    }
}

/// The footer's main action, what Return runs, drawn with `primaryKeys`, and the ⌘K menu with the rest.
struct ResultActions: View {
    @Environment(LauncherModel.self) private var host
    var primaryKeys = ["return"]

    var body: some View {
        if let title = host.primaryTitle {
            HStack(spacing: 4) {
                FooterButton(Text(title), keys: primaryKeys.map { KeyCap(symbol: $0) }) {
                    host.activate()
                }
                FooterDivider()
                ActionsButton()
            }
        }
    }
}

/// Opens the ⌘K menu with the rest of the actions.
struct ActionsButton: View {
    @Environment(LauncherModel.self) private var host

    var body: some View {
        FooterButton("Actions", keys: [KeyCap(symbol: "command"), KeyCap("K")]) {
            host.showActions()
        }
    }
}

/// The standard footer: the icon and name of the command a screen belongs to, such as `Clipboard History`, if any,
/// and the selected item's actions.
struct ActionsFooter: View {
    let badge: CommandBadge?
    let primaryKeys: [String]

    var body: some View {
        FooterBar {
            if let badge {
                HStack(spacing: 8) {
                    Image(systemName: badge.symbol)
                        .font(.system(size: 11))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(badge.tint, in: RoundedRectangle(cornerRadius: 5))
                    Text(badge.title)
                }
                .padding(.leading, 6)
                .padding(.trailing, 12)
                .padding(.vertical, 4)
                .background(.primary.opacity(0.08), in: Capsule())
            }

            Spacer()

            ResultActions(primaryKeys: primaryKeys)
        }
    }
}

/// An item under the empty search bar while the list is hidden, such as What's New, with the keys that run its
/// actions.
struct BannerRow: View {
    @Environment(LauncherModel.self) private var host
    let item: LauncherItem

    var body: some View {
        let actions = host.actions(for: item)
        HStack(spacing: 10) {
            item.icon.view
                .foregroundStyle(.indigo)
                .frame(width: 18, height: 18)
            Text(item.title)
            Text(item.subtitle)
                .foregroundStyle(Color.launcherSecondary)
            Spacer()
            HStack(spacing: 4) {
                if let primary = actions.first {
                    Text(primary.title)
                    KeyCap(symbol: "return")
                }
                if let dismiss = actions.first(where: { $0.shortcut == .delete }) {
                    Text(dismiss.title)
                        .padding(.leading, 8)
                    KeyCap("⌃")
                    KeyCap("X")
                }
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.launcherSecondary)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 16)
        .frame(height: 40)
        .contentShape(Rectangle())
        .onTapGesture { host.activate() }
    }
}

extension ItemIcon {
    /// The icon drawn at the size of a result row.
    @ViewBuilder
    var view: some View {
        switch self {
        case .none: EmptyView()
        case .symbol(let name): Image(systemName: name).resizable().scaledToFit()
        case .assetSymbol(let name): Image(name).resizable().scaledToFit()
        case .file(let url): Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit()
        case .extension(let name, let directory): ExtensionIcon(name: name, directory: directory)
        case .image(let box): Image(nsImage: box.image).resizable().scaledToFit()
        }
    }
}
