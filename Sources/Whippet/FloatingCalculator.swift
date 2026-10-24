import AppKit
import SwiftUI

/// A small calculator window that floats above other apps, so you can do sums while reading a page. It doesn't
/// activate Whippet, so the app you were using stays in front, and it keeps its place across launches and Spaces.
@MainActor
final class FloatingCalculator {
    @Observable
    final class State {
        var expression = ""
        /// Bumped to move focus to the input, since the window is reused rather than recreated.
        var focusRequest = 0
    }

    private let state = State()
    private let clipboard: ClipboardHistory
    private lazy var panel = makePanel()

    init(clipboard: ClipboardHistory) {
        self.clipboard = clipboard
    }

    var isVisible: Bool {
        panel.isVisible
    }

    /// Opens the calculator, with `expression` in the input when given.
    func show(expression: String? = nil) {
        if let expression {
            state.expression = expression
        }
        state.focusRequest += 1
        panel.makeKeyAndOrderFront(nil)
    }

    func toggle() {
        if panel.isVisible {
            panel.orderOut(nil)
            return
        }
        show()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 380),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.title = String(localized: "Calculator")
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 240, height: 220)
        panel.contentView = NSHostingView(
            rootView: FloatingCalculatorView(state: state, clipboard: clipboard) { [weak panel] in panel?.performClose(nil) }
        )
        panel.center()
        panel.setFrameAutosaveName("FloatingCalculator")
        return panel
    }
}

private struct FloatingCalculatorView: View {
    @Bindable var state: FloatingCalculator.State
    let clipboard: ClipboardHistory
    let close: () -> Void
    @FocusState private var isInputFocused: Bool

    var body: some View {
        let calculation = Calculator.evaluate(state.expression) ?? Calculator.evaluateNumber(state.expression)

        VStack(spacing: 0) {
            VStack(alignment: .trailing, spacing: 4) {
                TextField("Type a calculation…", text: $state.expression)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .focused($isInputFocused)
                    .onSubmit { record(calculation) }
                    .onExitCommand(perform: close)
                Text(calculation.map { "= \($0.answer)".leftToRightIsolated } ?? " ")
                    .font(.system(size: 24, weight: .semibold))
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .padding(12)

            Divider()

            List {
                ForEach(clipboard.recentCalculations(limit: 50)) { record in
                    Button {
                        copy(record.answer)
                    } label: {
                        HStack {
                            Text(record.expression.leftToRightIsolated)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Text(record.answer.leftToRightIsolated)
                                .fontWeight(.medium)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .overlay {
                if clipboard.recentCalculations(limit: 1).isEmpty {
                    Text("Answers you copy appear here")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { isInputFocused = true }
        .onChange(of: state.focusRequest) { isInputFocused = true }
    }

    /// Return keeps the calculation in history, shared with the launcher, and copies the answer.
    private func record(_ calculation: Calculation?) {
        guard let calculation else {
            NSSound.beep()
            return
        }
        if !calculation.isPlainNumber {
            clipboard.recordCalculation(
                expression: state.expression.trimmingCharacters(in: .whitespaces),
                answer: calculation.answer,
                isRPN: calculation.isRPN
            )
        }
        copy(calculation.answer)
        state.expression = ""
    }

    private func copy(_ answer: String) {
        clipboard.copy(text: answer)
        Toast.shared.show(String(localized: "Copied to Clipboard"), symbol: "doc.on.doc")
    }
}
