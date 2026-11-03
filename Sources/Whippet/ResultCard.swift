import SwiftUI

/// Two sides with an arrow between them, each a value over a label: a calculation and its answer, or text and its
/// translation.
struct ResultCard<Input: View, InputLabel: View, Output: View, OutputLabel: View>: View {
    let isSelected: Bool
    @ViewBuilder let input: Input
    @ViewBuilder let inputLabel: InputLabel
    @ViewBuilder let output: Output
    @ViewBuilder let outputLabel: OutputLabel

    var body: some View {
        HStack(spacing: 0) {
            side(input, inputLabel)
            VStack(spacing: 8) {
                Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 1)
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 1)
            }
            side(output, outputLabel)
        }
        .frame(height: 130)
        .background(Color.primary.opacity(isSelected ? 0.1 : 0.05), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
    }

    private func side(_ value: some View, _ label: some View) -> some View {
        VStack(spacing: 14) {
            value
            label
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }
}

/// A short label under a card's value, such as the kind of calculation or a language.
struct CardLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
    }
}
