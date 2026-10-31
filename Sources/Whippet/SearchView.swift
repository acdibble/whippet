import AppKit
import KeyboardShortcuts
import SwiftUI
import WhippetCore

/// The launcher shell. The search field stays mounted across every mode so it keeps keyboard focus when switching views.
struct SearchView: View {
    @Bindable var model: LauncherModel
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case search
        case duration(Int)
        case argument
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if model.mode != .root {
                    Button(action: model.back) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.launcherSecondary)
                    }
                    .launcherButtonStyle()
                }

                if let target = model.argumentTarget {
                    Text("\(target.label) ›")
                        .font(.system(size: 15, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                        .fixedSize()
                    TextField(target.placeholder, text: $model.argument)
                        .textFieldStyle(.plain)
                        .font(.system(size: 20))
                        .focused($focus, equals: .argument)
                        .onSubmit { model.activate() }
                        // The field is new in this update, so focusing it waits until it's in the window.
                        .onAppear { DispatchQueue.main.async { focus = .argument } }
                } else if model.mode == .stopwatch {
                    // A label, not a field, so plain keys control the stopwatch; ⌘K › Rename… renames it.
                    Text(model.currentStopwatch?.name ?? TimerNaming.defaultStopwatchName)
                        .font(.system(size: 20))
                        .foregroundStyle(model.currentStopwatch == nil ? Color.launcherSecondary : .primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    StopwatchSwitcher(model: model)
                } else if model.mode == .timers {
                    Text("Timers")
                        .font(.system(size: 20))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 4) {
                        Text("New Timer")
                            .padding(.trailing, 4)
                        KeyCap("N")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.launcherSecondary)
                } else {
                    TextField(placeholder, text: $model.query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 20))
                        .focused($focus, equals: .search)
                        .fixedSize(horizontal: model.isEnteringDuration, vertical: false)
                        .onSubmit { model.activate() }
                }

                if model.isEnteringDuration {
                    ForEach(Array(Self.durationPlaceholders.enumerated()), id: \.offset) { index, placeholder in
                        TextField(placeholder, text: $model.durationFields[index])
                            .textFieldStyle(.plain)
                            .font(.system(size: 15))
                            .frame(width: 64)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                            .focused($focus, equals: .duration(index))
                            .onSubmit { model.startTimedCaffeinate() }
                    }
                    Spacer()
                }

                // While the next part is typed, the previous answer stays, dimmed.
                if model.isCalculatingInline, let calculation = model.inlineCalculation ?? model.lastInlineCalculation {
                    Text("= \(calculation.displayAnswer)".leftToRightIsolated)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color.launcherSecondary)
                        .opacity(model.inlineCalculation == nil ? 0.5 : 1)
                        .lineLimit(1)
                        .fixedSize()
                }

                if model.mode == .clipboard {
                    ClipboardKindMenu(model: model)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 56)

            if let release = model.collapsedWhatsNew {
                Divider()
                WhatsNewRow(release: release) { model.activate() }
            }

            if model.isExpanded {
                switch model.mode {
                case .root, .calculator: RootResults(model: model)
                case .clipboard: ClipboardHistoryView(model: model)
                case .stopwatch: StopwatchView(model: model)
                case .timers: TimersView(model: model)
                case .changelog: ChangelogView(model: model)
                }
            }
        }
        .frame(width: LauncherPanel.contentSize.width)
        .frame(height: model.isExpanded ? LauncherPanel.contentSize.height : nil)
        .modifier(PanelBackground())
        .padding(LauncherPanel.shadowInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { focus = .search }
        .onChange(of: model.isEnteringDuration) { _, isEntering in
            focus = isEntering ? .duration(0) : .search
        }
        .onChange(of: model.mode) { _, mode in
            guard mode != .stopwatch else { return }
            DispatchQueue.main.async { focus = .search }
        }
        .onChange(of: model.argumentTarget) { _, target in
            guard target == nil else { return }
            DispatchQueue.main.async { focus = .search }
        }
    }

    private static let durationPlaceholders = [
        String(localized: "Hours"),
        String(localized: "Minutes"),
        String(localized: "Seconds"),
    ]

    private var placeholder: String {
        switch model.mode {
        case .root: String(localized: "Search apps and commands")
        case .calculator: String(localized: "Type a calculation…")
        case .clipboard: String(localized: "Type to filter entries…")
        case .changelog: String(localized: "Type to filter changes…")
        case .stopwatch, .timers: ""
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
                            // One flat list of headers and rows, each with its own identity. Rows nested in a ForEach
                            // per section left stale selection highlights on the wrong rows as the selection moved.
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(listItems(of: results)) { item in
                                    switch item {
                                    case .header(let title):
                                        SectionHeader(title: title)
                                    case .row(let index, let result):
                                        ResultRow(result: result, isSelected: index == model.selection)
                                            .onTapGesture {
                                                model.selection = index
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
                    ResultActions(model: model, result: results[model.selection])
                }
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 10)
            .frame(height: 44)
        }
    }

    /// Groups consecutive results under a heading, keeping each result's position in `results` for selection.
    private enum ListItem: Identifiable {
        case header(String)
        case row(index: Int, result: LauncherResult)

        var id: String {
            switch self {
            case .header(let title): "header:\(title)"
            case .row(_, let result): result.id
            }
        }
    }

    /// The results with a header wherever the section changes.
    private func listItems(of results: [LauncherResult]) -> [ListItem] {
        var items: [ListItem] = []
        var currentTitle: String?
        for (index, result) in results.enumerated() {
            let title = model.sectionTitle(at: index)
            if title != currentTitle {
                items.append(.header(title))
                currentTitle = title
            }
            items.append(.row(index: index, result: result))
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
            if result.isAdminOnly {
                AdminBadge()
            }
            if let hotkey = result.hotkey {
                HotkeyLabel(shortcut: hotkey)
            }
            ResultSubtitle(result: result)
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
        case .calculator: Image(systemName: "plus.forwardslash.minus")
        case .floatingCalculator: Image(systemName: "macwindow.on.rectangle")
        case .settings: Image(systemName: "gearshape")
        case .sendFeedback: Image(systemName: "bubble.left")
        case .readFeedback: Image(systemName: "tray.full")
        case .changelog: Image(systemName: "list.bullet.rectangle")
        case .whatsNew: Image(systemName: "sparkles")
        case .release(let release): Image(systemName: release.since == nil ? "tag" : "sparkles")
        case .shareWhippet: Image(systemName: "square.and.arrow.up")
        case .system(let command): Image(systemName: command.symbol)
        case .window(let command): command.image
        case .quicklink(let quicklink):
            if let icon = Quicklinks.icon(for: quicklink) { Image(nsImage: icon) } else { Image(systemName: "link") }
        case .createQuicklink: Image(systemName: "link.badge.plus")
        case .searchWithQuicklink(let quicklink):
            if let icon = Quicklinks.icon(for: quicklink) { Image(nsImage: icon) } else { Image(systemName: "link") }
        case .searchClipboard: Image(systemName: "list.clipboard")
        case .quit: Image(systemName: "power")
        case .caffeinate, .caffeinateFor: Image(systemName: "cup.and.heat.waves.fill")
        case .caffeinateMenuBar: Image(systemName: "menubar.rectangle")
        case .decaffeinate: Image(systemName: "cup.and.heat.waves")
        case .calculation: Image(systemName: "equal.square")
        case .pastCalculation: Image(systemName: "clock.arrow.circlepath")
        case .clipboard(let item): Image(systemName: item.kind.symbolName)
        case .startTimer, .newTimer, .timerPreset: Image(systemName: "timer")
        case .newStopwatch, .stopwatch: Image(systemName: "stopwatch")
        case .timersView: Image(systemName: "list.bullet")
        case .timer(let item):
            switch (item.kind, item.isPaused) {
            case (_, true): Image(systemName: "pause.circle")
            case (.timer, false): Image(systemName: "timer")
            case (.stopwatch, false): Image(systemName: "stopwatch")
            }
        case .ringingTimer: Image(systemName: "bell.and.waves.left.and.right")
        }
    }
}

/// A result's subtitle. A running timer or stopwatch counts in place.
private struct ResultSubtitle: View {
    let result: LauncherResult

    var body: some View {
        if case .timer(let item) = result {
            if item.isPaused {
                Text("Paused · \(time(of: item, at: .now))")
                    .monospacedDigit()
            } else {
                // A stopwatch shows tenths of a second, so it ticks faster.
                TimelineView(.periodic(from: .now, by: item.kind == .stopwatch ? 0.1 : 1)) { context in
                    Text(time(of: item, at: context.date))
                        .monospacedDigit()
                }
            }
        } else {
            Text(result.subtitle)
        }
    }

    private func time(of item: TimerItem, at date: Date) -> String {
        switch item.kind {
        case .timer:
            return String(localized: "\(TimerNaming.clock(item.value(at: date))) left")
        case .stopwatch:
            let total = TimerNaming.stopwatchClock(item.value(at: date))
            guard !item.laps.isEmpty else { return total }
            return String(
                localized:
                    "Lap \(item.laps.count + 1) \(TimerNaming.stopwatchClock(item.currentLap(at: date))) · \(total)")
        }
    }
}

extension Color {
    /// Hierarchical `.secondary` turns vibrant over the panel's material and washes out, so secondary text uses a fixed opacity.
    static let launcherSecondary = Color.primary.opacity(0.6)
    /// Glass also takes on what's behind it, so over a white page it turned light even in Dark mode. A tint of the
    /// window background keeps the panel and toasts following the appearance.
    static let launcherGlassTint = Color(nsColor: .windowBackgroundColor).opacity(0.8)
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

extension View {
    /// Glass buttons on macOS 26, which sit naturally on the panel's glass, and highlight-on-hover buttons before it.
    @ViewBuilder
    func launcherButtonStyle() -> some View {
        if #available(macOS 26, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.launcher)
        }
    }
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

/// The footer's main action for the selected result, and the ⌘K menu with the rest.
struct ResultActions: View {
    let model: LauncherModel
    let result: LauncherResult

    var body: some View {
        HStack(spacing: 4) {
            Button {
                model.activate()
            } label: {
                HStack(spacing: 8) {
                    Text(model.actionTitle(for: result))
                    KeyCap(symbol: "return")
                }
            }
            .launcherButtonStyle()
            Divider()
                .frame(height: 16)
            Button {
                model.onShowActions()
            } label: {
                HStack(spacing: 4) {
                    Text("Actions")
                        .padding(.trailing, 4)
                    KeyCap(symbol: "command")
                    KeyCap("K")
                }
            }
            .launcherButtonStyle()
        }
    }
}

/// Liquid Glass on macOS 26, which refracts what's behind the panel and draws its own depth. Earlier versions get a
/// mostly opaque material with a shadow.
private struct PanelBackground: ViewModifier {
    private static let shape = RoundedRectangle(cornerRadius: 14)
    /// Whippet's own appearance, read outside the glass.
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        // Glass lightens toward what's behind it, so in Dark mode it turned mid grey over a bright page and light text
        // lost its contrast. Dark mode uses a blurred material with a dark wash instead, which stays dark whatever is
        // behind the panel; Light mode keeps the glass.
        if #available(macOS 26, *), colorScheme == .light {
            content.glassEffect(.regular.tint(.launcherGlassTint), in: Self.shape)
        } else if colorScheme == .dark {
            content
                .background {
                    Self.shape
                        .fill(.ultraThinMaterial)
                        .overlay(Self.shape.fill(Color.black.opacity(0.4)))
                        .overlay(Self.shape.strokeBorder(Color.white.opacity(0.12)))
                }
                .shadow(color: .black.opacity(0.35), radius: 20, y: 8)
        } else {
            content
                .background {
                    Self.shape
                        .fill(.regularMaterial)
                        .overlay(Self.shape.fill(Color(nsColor: .windowBackgroundColor).opacity(0.75)))
                }
                .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
        }
    }
}

/// A result's global hotkey, drawn like the footer's key caps but sized to fit the whole shortcut.
private struct HotkeyLabel: View {
    let shortcut: KeyboardShortcuts.Shortcut

    var body: some View {
        // Kept left to right, so the modifiers stay before the key in right-to-left languages.
        Text(shortcut.description.leftToRightIsolated)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.launcherSecondary)
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.launcherSecondary.opacity(0.5)))
    }
}

/// Marks commands and settings only CloudKit Admin accounts can see.
struct AdminBadge: View {
    var body: some View {
        Text("Admin")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(.orange.opacity(0.15), in: Capsule())
    }
}

/// What's New under the empty search bar, with the keys that open and dismiss it.
private struct WhatsNewRow: View {
    let release: Release
    let open: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(.indigo)
                .frame(width: 18)
            Text(LauncherResult.whatsNew(release).title)
            Text(LauncherResult.whatsNew(release).subtitle)
                .foregroundStyle(Color.launcherSecondary)
            Spacer()
            HStack(spacing: 4) {
                Text("Open")
                KeyCap(symbol: "return")
                Text("Dismiss")
                    .padding(.leading, 8)
                KeyCap("⌃")
                KeyCap("X")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.launcherSecondary)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 16)
        .frame(height: 40)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
    }
}
