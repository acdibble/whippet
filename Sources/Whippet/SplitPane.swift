import SwiftUI

/// A list on the left and the selected item's detail on the right, filling the panel between the search bar and the
/// footer. The dividers close the split on every side, so the line between the panes never starts in midair.
struct SplitPane<List: View, Detail: View>: View {
    @ViewBuilder let list: List
    @ViewBuilder let detail: Detail

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                list
                    .frame(width: 300)
                Divider()
                detail
            }
            .frame(maxHeight: .infinity)
            Divider()
        }
    }
}

/// The footer of a view opened from a command: the command's icon and name, such as `Clipboard History`, and the
/// actions of the selected result, if there is one.
struct CommandFooter: View {
    let model: LauncherModel
    let title: LocalizedStringKey
    let symbol: String
    let tint: Color
    let result: LauncherResult?

    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(tint, in: RoundedRectangle(cornerRadius: 5))
                Text(title)
            }
            .padding(.leading, 6)
            .padding(.trailing, 12)
            .padding(.vertical, 4)
            .background(.primary.opacity(0.08), in: Capsule())

            Spacer()

            if let result {
                ResultActions(model: model, result: result)
            }
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 10)
        .frame(height: 44)
    }
}
