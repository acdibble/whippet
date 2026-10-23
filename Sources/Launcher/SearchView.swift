import AppKit
import SwiftUI

/// The launcher shell. The search field stays mounted across every mode so it keeps keyboard focus when switching views.
struct SearchView: View {
    @Bindable var model: LauncherModel
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if model.mode != .root {
                    Button(action: model.back) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.launcherSecondary)
                    }
                    .buttonStyle(.launcher)
                }

                TextField(placeholder, text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20))
                    .focused($isSearchFocused)
                    .onSubmit { model.activate() }

                if model.mode == .clipboard {
                    ClipboardKindMenu(model: model)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 56)

            if model.isExpanded {
                switch model.mode {
                case .root: RootResults(model: model)
                case .clipboard: ClipboardHistoryView(model: model)
                case .usage: UsageStatsView(model: model)
                }
            }
        }
        .frame(width: LauncherPanel.contentSize.width)
        .frame(height: model.isExpanded ? LauncherPanel.contentSize.height : nil)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(.regularMaterial)
                .overlay(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .windowBackgroundColor).opacity(0.75)))
        }
        .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
        .padding(LauncherPanel.shadowInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { isSearchFocused = true }
    }

    private var placeholder: String {
        switch model.mode {
        case .root: "Search apps and commands"
        case .clipboard: "Type to filter entries…"
        case .usage: "Usage Stats"
        }
    }
}

private struct RootResults: View {
    let model: LauncherModel

    var body: some View {
        let results = model.results

        ScrollViewReader { proxy in
            List(Array(results.enumerated()), id: \.element.id) { index, result in
                ResultRow(result: result, isSelected: index == model.selection)
                    .id(result.id)
                    .listRowSeparator(.hidden)
                    .onTapGesture {
                        model.selection = index
                        model.activate()
                    }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(maxHeight: .infinity)
            .onChange(of: model.selection) { _, selection in
                guard results.indices.contains(selection) else { return }
                proxy.scrollTo(results[selection].id)
            }
        }
    }
}

private struct ResultRow: View {
    let result: LauncherResult
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            icon
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
            Text(result.title)
                .lineLimit(1)
            Spacer()
            Text(result.subtitle)
                .foregroundStyle(Color.launcherSecondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            isSelected ? Color.accentColor.opacity(0.25) : .clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .contentShape(Rectangle())
    }

    private var icon: Image {
        switch result {
        case .app(let app): Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
        case .clipboardHistory: Image(systemName: "list.clipboard")
        case .usageStats: Image(systemName: "chart.bar")
        case .clipboard: Image(systemName: "doc.on.clipboard")
        }
    }
}

extension Color {
    /// Hierarchical `.secondary` turns vibrant over the panel's material and washes out, so secondary text uses a fixed opacity.
    static let launcherSecondary = Color.primary.opacity(0.6)
}

/// A borderless button with a rounded highlight on hover and press.
struct LauncherButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverHighlight(isPressed: configuration.isPressed) {
            configuration.label
        }
    }
}

extension ButtonStyle where Self == LauncherButtonStyle {
    static var launcher: LauncherButtonStyle { LauncherButtonStyle() }
}

struct HoverHighlight<Label: View>: View {
    let isPressed: Bool
    @ViewBuilder let label: Label
    @State private var isHovered = false

    var body: some View {
        label
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(highlightOpacity), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.1), value: isHovered)
    }

    private var highlightOpacity: Double {
        if isPressed { return 0.16 }
        if isHovered { return 0.08 }
        return 0
    }
}
