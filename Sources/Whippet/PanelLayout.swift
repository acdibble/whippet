import SwiftUI

/// The scrolling list of a launcher view, which keeps the selected row in view as the selection moves. `ids` are the
/// selectable rows' ids in selection order, so headers and other rows in `content` don't count toward it.
struct SelectableList<ID: Hashable, Content: View>: View {
    let ids: [ID]
    let selection: Int
    @ViewBuilder let content: Content

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    content
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .onChange(of: selection) { _, selection in
                guard ids.indices.contains(selection) else { return }
                proxy.scrollTo(ids[selection])
            }
        }
    }
}

extension View {
    /// A row of a `SelectableList`, highlighted while selected. Compact rows fit the narrower list of a `SplitPane`.
    func listRow(isSelected: Bool, compact: Bool = false) -> some View {
        font(.system(size: compact ? 13 : 14))
            .padding(.horizontal, compact ? 8 : 10)
            .frame(height: compact ? 32 : 40)
            .background(isSelected ? Color.primary.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
    }
}

/// A list on the left and the selected item's detail on the right, filling the panel between the search bar and the
/// footer. The dividers close the split on every side, so the line between the panes never starts in midair.
struct SplitPane<List: View, Detail: View>: View {
    @ViewBuilder let list: List
    @ViewBuilder let detail: Detail

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                list
                    .frame(width: 300)
                Divider()
                detail
            }
            .frame(maxHeight: .infinity)
            Divider()
        }
    }
}

/// The bar along the bottom of the panel, with a view's actions at its trailing end.
struct FooterBar<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 4) {
            content
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 10)
        .frame(height: 44)
    }
}

/// A footer action and the keys that run it, such as `Lap L`.
struct FooterButton: View {
    private let title: Text
    private let keys: [KeyCap]
    private let action: () -> Void

    init(_ title: Text, keys: [KeyCap], action: @escaping () -> Void) {
        self.title = title
        self.keys = keys
        self.action = action
    }

    init(_ title: LocalizedStringKey, keys: [KeyCap], action: @escaping () -> Void) {
        self.init(Text(title), keys: keys, action: action)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                title
                HStack(spacing: 4) {
                    ForEach(keys.indices, id: \.self) { keys[$0] }
                }
            }
        }
        .launcherButtonStyle()
    }
}

/// Opens the ⌘K menu with the rest of the actions.
struct ActionsButton: View {
    let model: LauncherModel

    var body: some View {
        FooterButton("Actions", keys: [KeyCap(symbol: "command"), KeyCap("K")]) {
            model.onShowActions()
        }
    }
}

/// Separates groups of footer buttons.
struct FooterDivider: View {
    var body: some View {
        Divider()
            .frame(height: 16)
    }
}

/// The footer's main action for the selected result, and the ⌘K menu with the rest.
struct ResultActions: View {
    let model: LauncherModel
    let result: LauncherResult

    var body: some View {
        HStack(spacing: 4) {
            FooterButton(Text(model.actionTitle(for: result)), keys: [KeyCap(symbol: "return")]) {
                model.activate()
            }
            FooterDivider()
            ActionsButton(model: model)
        }
    }
}

/// The footer of a view opened from a command: the command's icon and name, such as `Clipboard History`, and the
/// actions of the selected result, if there is one.
struct CommandFooter: View {
    let model: LauncherModel
    let title: LocalizedStringKey
    let symbol: String
    let tint: Color
    let result: LauncherResult?

    var body: some View {
        FooterBar {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(tint, in: RoundedRectangle(cornerRadius: 5))
                Text(title)
            }
            .padding(.leading, 6)
            .padding(.trailing, 12)
            .padding(.vertical, 4)
            .background(.primary.opacity(0.08), in: Capsule())

            Spacer()

            if let result {
                ResultActions(model: model, result: result)
            }
        }
    }
}

/// A key drawn as a key cap, by its symbol, such as `return`, or its label, such as `K`.
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
