import SwiftUI
import WhippetCore

/// The calculator layout: the current calculation as a card, with past calculations and numeric clipboard items in two columns below.
struct CalculatorResults: View {
    @Environment(LauncherModel.self) private var host
    let screen: CalculatorScreen

    var body: some View {
        let results = host.results
        let rows = Array(results.enumerated()).map { (index: $0.offset, item: $0.element) }
        let current = rows.first { $0.item.payload(as: Calculation.self) != nil }
        let history = rows.filter { $0.item.payload(as: CalculationRecord.self) != nil }
        let numbers = rows.filter { $0.item.payload(as: ClipboardItem.self) != nil }

        VStack(spacing: 0) {
            // The card stays at the top while the columns under it scroll.
            VStack(alignment: .leading, spacing: 2) {
                SectionHeader(title: String(localized: "Calculator"))
                if let current, let calculation = current.item.payload(as: Calculation.self) {
                    CalculationCard(calculation: calculation, isSelected: current.index == host.selection)
                        .id(current.item.id)
                        .onTapGesture {
                            host.selection = current.index
                            host.activate()
                        }
                    if !calculation.otherBases.isEmpty {
                        OtherBases(calculation: calculation) { base in
                            host.perform("calculator.copy-\(base)", at: current.index)
                        }
                    }
                } else {
                    Text("Type a calculation")
                        .foregroundStyle(Color.launcherSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 130)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)

            SelectableList(ids: results.map(\.id), selection: host.selection) {
                HStack(alignment: .top, spacing: 8) {
                    column(title: "History", rows: history, emptyText: "Answers you copy appear here")
                    column(title: "Numbers", rows: numbers, emptyText: "Numbers you copy appear here")
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func column(
        title: LocalizedStringResource,
        rows: [(index: Int, item: LauncherItem)],
        emptyText: LocalizedStringResource
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionHeader(title: String(localized: title))
            if rows.isEmpty {
                Text(emptyText)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.launcherSecondary)
                    .padding(.horizontal, 10)
            }
            ForEach(rows, id: \.item.id) { row in
                ResultRow(item: row.item, isSelected: row.index == host.selection)
                    .id(row.item.id)
                    .onTapGesture {
                        host.selection = row.index
                        host.activate()
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// A whole-number answer in each other base, such as hexadecimal and binary, which a click copies. ⌘K offers the same.
private struct OtherBases: View {
    let calculation: Calculation
    let copy: (NumberBase) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(calculation.otherBases, id: \.self) { base in
                if let answer = calculation.answer(in: base) {
                    Button {
                        copy(base)
                    } label: {
                        HStack(spacing: 6) {
                            Text(base.name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.launcherSecondary)
                            Text(answer.leftToRightIsolated)
                                .font(.system(size: 13, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Copy as \(base.name)"))
                }
            }
        }
    }
}

struct CalculationCard: View {
    let calculation: Calculation
    let isSelected: Bool

    var body: some View {
        ResultCard(isSelected: isSelected) {
            value(Text(calculation.conversion.map { AttributedString($0.input.leftToRightIsolated) } ?? expression))
        } inputLabel: {
            CardLabel(calculation.operationName)
        } output: {
            value(Text(calculation.displayAnswer.leftToRightIsolated))
        } outputLabel: {
            CardLabel(calculation.spelledAnswer)
        }
    }

    private func value(_ text: Text) -> some View {
        text
            .font(.system(size: 30, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.4)
    }

    /// The input re-spaced with typographic operators, which are dimmed so the numbers stand out, kept left to right in right-to-left languages.
    private var expression: AttributedString {
        var expression = AttributedString()
        var previous: Calculator.Token?
        for token in calculation.tokens {
            // A percentage keeps its `%` beside the number, as in `20%`, but in RPN it's the remainder.
            let isAttached = token == .close || (token == .percent && !calculation.isRPN)
            if previous != nil, previous != .open, !isAttached {
                expression += AttributedString(" ")
            }
            switch token {
            case .number(_, let literal):
                expression += AttributedString(literal)
            case .operation(let operation):
                var symbol = AttributedString(Self.symbol(for: operation))
                symbol.foregroundColor = Color.launcherSecondary
                expression += symbol
            case .percent:
                var symbol = AttributedString("%")
                symbol.foregroundColor = Color.launcherSecondary
                expression += symbol
            case .word(let word):
                var text = AttributedString(word)
                text.foregroundColor = Color.launcherSecondary
                expression += text
            case .open:
                expression += AttributedString("(")
            case .close:
                expression += AttributedString(")")
            }
            previous = token
        }
        return AttributedString("\u{2066}") + expression + AttributedString("\u{2069}")
    }

    private static func symbol(for operation: Character) -> String {
        switch operation {
        case "*": "×"
        case "/": "÷"
        case "-": "−"
        default: String(operation)
        }
    }
}
