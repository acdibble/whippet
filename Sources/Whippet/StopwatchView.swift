import SwiftUI

/// A stopwatch filling the launcher panel: the elapsed time, the current lap, every lap so far, and its controls.
struct StopwatchView: View {
    let model: LauncherModel

    var body: some View {
        VStack(spacing: 0) {
            if let stopwatch = model.currentStopwatch {
                // Ticks in tenths of a second, as the clock shows them.
                TimelineView(.periodic(from: .now, by: 0.1)) { context in
                    VStack(spacing: 0) {
                        Clock(stopwatch: stopwatch, now: context.date)
                        Divider()
                        LapList(stopwatch: stopwatch, now: context.date)
                    }
                }
                Footer(model: model, stopwatch: stopwatch)
            } else {
                // Ready at zero; nothing is created until it starts.
                VStack(spacing: 6) {
                    Text(TimerNaming.stopwatchClock(0).leftToRightIsolated)
                        .font(.system(size: 64, weight: .light))
                        .monospacedDigit()
                        .opacity(0.6)
                    Text("Press Return or Space to start")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.launcherSecondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 150)
                Divider()
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        model.activate()
                    } label: {
                        HStack(spacing: 8) {
                            Text("Start")
                            KeyCap(symbol: "return")
                        }
                    }
                    .launcherButtonStyle()
                }
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 10)
                .frame(height: 44)
            }
        }
    }
}

private struct Clock: View {
    let stopwatch: TimerItem
    let now: Date

    var body: some View {
        VStack(spacing: 6) {
            Text(TimerNaming.stopwatchClock(stopwatch.value(at: now)).leftToRightIsolated)
                .font(.system(size: 64, weight: .light))
                .monospacedDigit()
                .opacity(stopwatch.isPaused ? 0.6 : 1)
            if !stopwatch.laps.isEmpty {
                Text("Lap \(stopwatch.laps.count + 1)  \(TimerNaming.stopwatchClock(stopwatch.currentLap(at: now)).leftToRightIsolated)")
                    .font(.system(size: 15))
                    .monospacedDigit()
                    .foregroundStyle(Color.launcherSecondary)
            } else if stopwatch.isPaused {
                Text("Paused")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.launcherSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
    }
}

/// Newest first, with the lap still running on top. With two or more finished laps, the fastest and slowest are marked
/// green and red.
private struct LapList: View {
    let stopwatch: TimerItem
    let now: Date

    var body: some View {
        let laps = Self.durations(stopwatch.laps)
        let fastest = laps.count > 1 ? laps.indices.min { laps[$0] < laps[$1] } : nil
        let slowest = laps.count > 1 ? laps.indices.max { laps[$0] < laps[$1] } : nil

        ScrollView {
            LazyVStack(spacing: 0) {
                if !laps.isEmpty {
                    LapRow(
                        number: laps.count + 1,
                        lap: stopwatch.currentLap(at: now),
                        total: stopwatch.value(at: now),
                        mark: nil
                    )
                }
                ForEach(laps.indices.reversed(), id: \.self) { index in
                    LapRow(
                        number: index + 1,
                        lap: laps[index],
                        total: stopwatch.laps[index],
                        mark: index == fastest ? .fastest : index == slowest ? .slowest : nil
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .overlay {
            if laps.isEmpty {
                Text("Press L to take a lap")
                    .foregroundStyle(Color.launcherSecondary)
            }
        }
        .frame(maxHeight: .infinity)
    }

    /// Each lap's own length, from the elapsed time at each lap.
    private static func durations(_ laps: [TimeInterval]) -> [TimeInterval] {
        laps.enumerated().map { index, total in total - (index > 0 ? laps[index - 1] : 0) }
    }
}

private struct LapRow: View {
    enum Mark {
        case fastest
        case slowest
    }

    let number: Int
    let lap: TimeInterval
    let total: TimeInterval
    let mark: Mark?

    var body: some View {
        HStack {
            Text("Lap \(number)")
            Spacer()
            Text(TimerNaming.stopwatchClock(lap).leftToRightIsolated)
                .foregroundStyle(color)
                .frame(width: 110, alignment: .trailing)
            Text(TimerNaming.stopwatchClock(total).leftToRightIsolated)
                .foregroundStyle(Color.launcherSecondary)
                .frame(width: 110, alignment: .trailing)
        }
        .font(.system(size: 14))
        .monospacedDigit()
        .frame(height: 32)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var color: Color {
        switch mark {
        case .fastest: .green
        case .slowest: .red
        case nil: .primary
        }
    }
}

private struct Footer: View {
    let model: LauncherModel
    let stopwatch: TimerItem

    var body: some View {
        HStack(spacing: 4) {
            Spacer()
            Button {
                model.perform(.lap)
            } label: {
                HStack(spacing: 4) {
                    Text("Lap")
                        .padding(.trailing, 4)
                    KeyCap("L")
                }
            }
            .launcherButtonStyle()
            .disabled(stopwatch.isPaused)
            Button {
                model.perform(.restart)
            } label: {
                HStack(spacing: 4) {
                    Text("Reset")
                        .padding(.trailing, 4)
                    KeyCap("R")
                }
            }
            .launcherButtonStyle()
            Divider()
                .frame(height: 16)
            Button {
                model.activate()
            } label: {
                HStack(spacing: 8) {
                    stopwatch.isPaused ? Text("Start") : Text("Pause")
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
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 10)
        .frame(height: 44)
    }
}

/// "‹ 1 of 2 ›" beside the name when more than one stopwatch is running; ← and → do the same.
struct StopwatchSwitcher: View {
    let model: LauncherModel

    var body: some View {
        let stopwatches = model.stopwatches
        if stopwatches.count > 1, let index = stopwatches.firstIndex(where: { $0.id == model.currentStopwatch?.id }) {
            HStack(spacing: 2) {
                Button {
                    _ = model.switchStopwatch(by: -1)
                } label: {
                    Image(systemName: "chevron.backward")
                }
                .buttonStyle(.launcher)
                Text("\(index + 1) of \(stopwatches.count)")
                    .monospacedDigit()
                    .foregroundStyle(Color.launcherSecondary)
                    .fixedSize()
                Button {
                    _ = model.switchStopwatch(by: 1)
                } label: {
                    Image(systemName: "chevron.forward")
                }
                .buttonStyle(.launcher)
            }
            .font(.system(size: 13, weight: .medium))
        }
    }
}
