import SwiftUI
import WhippetCore

/// Every timer in one list, managed in place: ringing timers first, then running and paused ones, then recent timers to
/// start again. Keys act on the selected row, and each row has buttons for the mouse.
struct TimersView: View {
    let model: LauncherModel

    var body: some View {
        let results = model.results

        VStack(spacing: 0) {
            SelectableList(ids: results.map(\.id), selection: model.selection) {
                if !results.contains(where: \.isTimerRow) {
                    SectionHeader(title: String(localized: "Timers"))
                    Text("No timers running. Press N to start one.")
                        .foregroundStyle(Color.launcherSecondary)
                        .padding(.horizontal, 10)
                        .frame(height: 40)
                }
                ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                    if index == 0 || model.sectionTitle(at: index) != model.sectionTitle(at: index - 1) {
                        SectionHeader(title: model.sectionTitle(at: index))
                    }
                    TimerRow(model: model, result: result, index: index)
                        .id(result.id)
                }
            }
            .frame(maxHeight: .infinity)

            FooterBar {
                Spacer()
                if let result = model.selectedResult {
                    ResultActions(model: model, result: result)
                }
            }
        }
    }
}

private struct TimerRow: View {
    let model: LauncherModel
    let result: LauncherResult
    let index: Int

    var body: some View {
        HStack(spacing: 10) {
            icon
                .font(.system(size: 17))
                .frame(width: 22)
            Text(result.title)
                .lineLimit(1)
                .frame(width: 170, alignment: .leading)
            content
        }
        .listRow(isSelected: index == model.selection)
        .onTapGesture { model.selection = index }
    }

    @ViewBuilder
    private var icon: some View {
        switch result {
        case .ringingTimer: Image(systemName: "bell.and.waves.left.and.right").foregroundStyle(.red)
        case .timer(let item) where item.isPaused:
            Image(systemName: "pause.circle").foregroundStyle(Color.launcherSecondary)
        default: Image(systemName: "timer")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch result {
        case .timer(let item):
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let left = item.value(at: context.date)
                HStack(spacing: 10) {
                    ProgressView(value: item.duration > 0 ? left / item.duration : 0)
                        .progressViewStyle(.linear)
                        .tint(item.isPaused ? .secondary : .accentColor)
                    Text(TimerNaming.clock(left).leftToRightIsolated)
                        .monospacedDigit()
                        .foregroundStyle(item.isPaused ? Color.launcherSecondary : .primary)
                        .frame(width: 70, alignment: .trailing)
                }
            }
            RowButton(symbol: item.isPaused ? "play.fill" : "pause.fill", help: item.isPaused ? "Resume" : "Pause") {
                model.selection = index
                model.activate()
            }
            RowButton(symbol: "plus", help: "Add 1 Minute") {
                model.selection = index
                model.perform(.addMinute)
            }
            RowButton(symbol: "xmark", help: "Cancel Timer") {
                model.selection = index
                model.perform(.delete)
            }
        case .ringingTimer:
            Text("Done")
                .foregroundStyle(.red)
            Spacer()
            RowButton(title: "Stop") {
                model.selection = index
                model.activate()
            }
            RowButton(title: "Snooze") {
                model.selection = index
                model.perform(.snooze)
            }
        default:
            Spacer()
            RowButton(title: "Start") {
                model.selection = index
                model.activate()
            }
        }
    }
}

private struct RowButton: View {
    private let label: Text
    private let help: LocalizedStringKey?
    private let action: () -> Void

    init(symbol: String, help: LocalizedStringKey, action: @escaping () -> Void) {
        label = Text(Image(systemName: symbol))
        self.help = help
        self.action = action
    }

    init(title: LocalizedStringKey, action: @escaping () -> Void) {
        label = Text(title)
        help = nil
        self.action = action
    }

    var body: some View {
        let button = Button(action: action) {
            label
                .font(.system(size: 12, weight: .medium))
        }
        .buttonStyle(.launcher)
        if let help {
            button.help(help)
        } else {
            button
        }
    }
}

extension LauncherResult {
    /// A running, paused or ringing timer, as opposed to a recent one.
    var isTimerRow: Bool {
        switch self {
        case .timer, .ringingTimer: true
        default: false
        }
    }
}
