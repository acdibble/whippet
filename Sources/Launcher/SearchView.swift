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
                case .root, .calculator: RootResults(model: model)
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
        case .calculator: "Type a calculation…"
        case .clipboard: "Type to filter entries…"
        case .usage: "Usage Stats"
        }
    }
}

private struct RootResults: View {
    let model: LauncherModel

    var body: some View {
        let results = model.results

        VStack(spacing: 0) {
            Group {
                if model.showsCalculatorLayout {
                    CalculatorResults(model: model, results: results)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(sections(of: results), id: \.title) { section in
                                    SectionHeader(title: section.title)
                                    ForEach(section.rows, id: \.result.id) { row in
                                        ResultRow(result: row.result, isSelected: row.index == model.selection)
                                            .id(row.result.id)
                                            .onTapGesture {
                                                model.selection = row.index
                                                model.activate()
                                            }
                                    }
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                        }
                        .onChange(of: model.selection) { _, selection in
                            guard results.indices.contains(selection) else { return }
                            proxy.scrollTo(results[selection].id)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)

            HStack {
                Spacer()
                if results.indices.contains(model.selection) {
                    Button(action: model.activate) {
                        HStack(spacing: 8) {
                            Text(results[model.selection].actionTitle)
                            KeyCap(symbol: "return")
                        }
                    }
                    .buttonStyle(.launcher)
                }
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 10)
            .frame(height: 44)
        }
    }

    /// Groups consecutive results under a heading, keeping each result's position in `results` for selection.
    private func sections(of results: [LauncherResult]) -> [(title: String, rows: [(index: Int, result: LauncherResult)])] {
        var sections: [(title: String, rows: [(index: Int, result: LauncherResult)])] = []
        for (index, result) in results.enumerated() {
            let title = Self.sectionTitle(for: result)
            if sections.last?.title == title {
                sections[sections.count - 1].rows.append((index, result))
                continue
            }
            sections.append((title, [(index, result)]))
        }
        return sections
    }

    private static func sectionTitle(for result: LauncherResult) -> String {
        switch result {
        case .clipboard: "Clipboard History"
        default: "Results"
        }
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

struct ResultRow: View {
    let result: LauncherResult
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            icon
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
            Text(result.title)
                .lineLimit(1)
            Spacer()
            Text(result.subtitle)
                .foregroundStyle(Color.launcherSecondary)
        }
        .font(.system(size: 14))
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(isSelected ? Color.primary.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }

    private var icon: Image {
        switch result {
        case .app(let app): Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
        case .clipboardHistory: Image(systemName: "list.clipboard")
        case .usageStats: Image(systemName: "chart.bar")
        case .calculator: Image(systemName: "plus.forwardslash.minus")
        case .quit: Image(systemName: "power")
        case .calculation: Image(systemName: "equal.square")
        case .pastCalculation: Image(systemName: "clock.arrow.circlepath")
        case .clipboard(let item): Image(systemName: item.kind.symbolName)
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
