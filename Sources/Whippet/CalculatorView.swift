import SwiftUI

/// The calculator layout: the current calculation as a card, with past calculations and numeric clipboard items in two columns below.
struct CalculatorResults: View {
    let model: LauncherModel
    let results: [LauncherResult]

    var body: some View {
        let rows = Array(results.enumerated()).map { (index: $0.offset, result: $0.element) }
        let current = rows.first { if case .calculation = $0.result { return true }; return false }
        let history = rows.filter { if case .pastCalculation = $0.result { return true }; return false }
        let numbers = rows.filter { if case .clipboard = $0.result { return true }; return false }

        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    SectionHeader(title: String(localized: "Calculator"))
                    if let current, case .calculation(let calculation) = current.result {
                        CalculationCard(calculation: calculation, isSelected: current.index == model.selection)
                            .id(current.result.id)
                            .onTapGesture {
                                model.selection = current.index
                                model.activate()
                            }
                    } else {
                        Text("Type a calculation")
                            .foregroundStyle(Color.launcherSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 130)
                            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                    }

                    HStack(alignment: .top, spacing: 8) {
                        column(title: "History", rows: history, emptyText: "Answers you copy appear here")
                        column(title: "Numbers", rows: numbers, emptyText: "Numbers you copy appear here")
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

    private func column(
        title: LocalizedStringResource,
        rows: [(index: Int, result: LauncherResult)],
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
            ForEach(rows, id: \.result.id) { row in
                ResultRow(result: row.result, isSelected: row.index == model.selection)
                    .id(row.result.id)
                    .onTapGesture {
                        model.selection = row.index
                        model.activate()
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct CalculationCard: View {
    let calculation: Calculation
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 0) {
            side(Text(expression), label: calculation.operationName)
            VStack(spacing: 8) {
                Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 1)
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 1)
            }
            side(Text(calculation.answer.leftToRightIsolated), label: calculation.spelledAnswer)
        }
        .frame(height: 130)
        .background(Color.primary.opacity(isSelected ? 0.1 : 0.05), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
    }

    private func side(_ value: Text, label: String) -> some View {
        VStack(spacing: 14) {
            value
                .font(.system(size: 30, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
    }

    /// The input re-spaced with typographic operators, which are dimmed so the numbers stand out, kept left to right in right-to-left languages.
    private var expression: AttributedString {
        var expression = AttributedString()
        var previous: Calculator.Token?
        for token in calculation.tokens {
            if previous != nil, previous != .open, token != .close {
                expression += AttributedString(" ")
            }
            switch token {
            case .number(_, let literal):
                expression += AttributedString(literal)
            case .operation(let operation):
                var symbol = AttributedString(Self.symbol(for: operation))
                symbol.foregroundColor = Color.launcherSecondary
                expression += symbol
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

