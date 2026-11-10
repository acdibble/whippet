import AppKit
import KeyboardShortcuts
import SwiftUI
import WhippetCore

/// The launcher shell: the search bar, what's under it while the panel is collapsed, and the top screen's content. The
/// search field stays mounted across screens so it keeps keyboard focus when switching between them.
struct SearchView: View {
    @Bindable var model: LauncherModel
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case search
        case input(Int)
    }

    var body: some View {
        let screen = model.activeScreen
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if !model.isRoot {
                    Button(action: model.back) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.launcherSecondary)
                    }
                    .launcherButtonStyle()
                }

                if let input = model.input {
                    Text("\(input.label) ›")
                        .font(.system(size: 15, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                        .fixedSize()
                    ForEach(Array(input.fields.enumerated()), id: \.offset) { index, field in
                        if model.inputValues.indices.contains(index) {
                            inputField(field, index: index)
                        }
                    }
                    if input.fields.allSatisfy(\.isNarrow) {
                        Spacer()
                    }
                } else {
                    switch screen.searchBar {
                    case .field(let placeholder):
                        TextField(placeholder, text: $model.query)
                            .textFieldStyle(.plain)
                            .font(.system(size: 20))
                            .focused($focus, equals: .search)
                            .onSubmit { model.activate() }
                    case .title(let title, let isDimmed):
                        // A label, not a field, so plain keys reach the screen.
                        Text(title)
                            .font(.system(size: 20))
                            .foregroundStyle(isDimmed ? Color.launcherSecondary : .primary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let accessory = screen.accessory() {
                        accessory
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 56)

            if let banner = model.banner {
                Divider()
                BannerRow(item: banner)
            }

            // The bar and the footer keep their heights, and the content gets what's left between them, clipped to
            // it, so nothing a screen shows can push the footer out of the panel.
            if model.isExpanded {
                Group {
                    switch screen.content {
                    case .list: ResultsList()
                    case .custom(let view): view
                    }
                }
                .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
                .clipped()

                switch screen.footer {
                case .actions(let badge, let primaryKeys): ActionsFooter(badge: badge, primaryKeys: primaryKeys)
                case .custom(let view): view
                }
            }
        }
        .frame(width: LauncherPanel.contentSize.width)
        .frame(height: model.isExpanded ? LauncherPanel.contentSize.height : nil)
        .modifier(PanelBackground())
        .padding(LauncherPanel.shadowInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(model)
        .onAppear { focus = .search }
        // The field takes focus again as screens open and close and as text is asked for. It's new in this update, so
        // focusing it waits until it's in the window.
        .onChange(of: model.focusRevision) {
            DispatchQueue.main.async { focus = model.input != nil ? .input(0) : .search }
        }
    }

    @ViewBuilder
    private func inputField(_ field: InputRequest.Field, index: Int) -> some View {
        if field.isNarrow {
            TextField(field.placeholder, text: $model.inputValues[index])
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .frame(width: 64)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                .focused($focus, equals: .input(index))
                .onSubmit { model.activate() }
        } else {
            TextField(field.placeholder, text: $model.inputValues[index])
                .textFieldStyle(.plain)
                .font(.system(size: 20))
                .focused($focus, equals: .input(index))
                .onSubmit { model.activate() }
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
struct HotkeyLabel: View {
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
