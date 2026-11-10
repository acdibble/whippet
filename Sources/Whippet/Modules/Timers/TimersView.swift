import SwiftUI
import WhippetCore

/// Every timer in one list, managed in place: ringing timers first, then running and paused ones, then recent timers to
/// start again. Keys act on the selected row, and each row has buttons for the mouse.
struct TimersView: View {
    @Environment(LauncherModel.self) private var host
    let screen: TimersScreen

    var body: some View {
        let results = host.results

        VStack(spacing: 0) {
            SelectableList(ids: results.map(\.id), selection: host.selection) {
                if !results.contains(where: \.isTimerRow) {
                    SectionHeader(title: String(localized: "Timers"))
                    Text("No timers running. Press N to start one.")
                        .foregroundStyle(Color.launcherSecondary)
                        .padding(.horizontal, 10)
                        .frame(height: 40)
                }
                ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                    let title = host.sectionTitle(at: index) ?? ""
                    if index == 0 || title != host.sectionTitle(at: index - 1) {
                        SectionHeader(title: title)
                    }
                    TimerRow(item: result, row: result.payload(as: TimersModule.Row.self), index: index)
                        .id(result.id)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

private struct TimerRow: View {
    @Environment(LauncherModel.self) private var host
    let item: LauncherItem
    let row: TimersModule.Row?
    let index: Int

    var body: some View {
        HStack(spacing: 10) {
            icon
                .font(.system(size: 17))
                .frame(width: 22)
            Text(item.title)
                .lineLimit(1)
                .frame(width: 170, alignment: .leading)
            content
        }
        .listRow(isSelected: index == host.selection)
        .onTapGesture { host.selection = index }
    }

    @ViewBuilder
    private var icon: some View {
        switch row {
        case .ringing?: Image(systemName: "bell.and.waves.left.and.right").foregroundStyle(.red)
        case .running(let item)? where item.isPaused:
            Image(systemName: "pause.circle").foregroundStyle(Color.launcherSecondary)
        default: Image(systemName: "timer")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch row {
        case .running(let item)?:
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
                host.perform("timers.toggle", at: index)
            }
            RowButton(symbol: "plus", help: "Add 1 Minute") {
                host.perform("timers.add-minute", at: index)
            }
            RowButton(symbol: "xmark", help: "Cancel Timer") {
                host.perform("timers.remove", at: index)
            }
        case .ringing?:
            Text("Done")
                .foregroundStyle(.red)
            Spacer()
            RowButton(title: "Stop") {
                host.perform("timers.stop", at: index)
            }
            RowButton(title: "Snooze") {
                host.perform("timers.snooze", at: index)
            }
        default:
            Spacer()
            RowButton(title: "Start") {
                host.perform("timers.start", at: index)
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

extension LauncherItem {
    /// A running, paused or ringing timer, as opposed to a recent one.
    fileprivate var isTimerRow: Bool {
        switch payload(as: TimersModule.Row.self) {
        case .running?, .ringing?: true
        default: false
        }
    }
}
