import AppKit
import SwiftUI

/// A short confirmation at the bottom of the screen after a command runs.
/// It ignores the mouse and never takes focus, so it can't get in the way of the app underneath.
@MainActor
final class Toast {
    static let shared = Toast()

    private let panel: NSPanel
    private var dismissal: Task<Void, Never>?

    private init() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    func show(_ message: String, symbol: String) {
        let content = NSHostingView(rootView: ToastView(message: message, symbol: symbol))
        panel.contentView = content
        let size = content.fittingSize
        let screen = NSScreen.main?.visibleFrame ?? .zero
        panel.setFrame(
            NSRect(x: screen.midX - size.width / 2, y: screen.minY + 96, width: size.width, height: size.height),
            display: true
        )

        panel.alphaValue = 1
        panel.orderFrontRegardless()
        dismissal?.cancel()
        dismissal = Task { [panel] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                panel.animator().alphaValue = 0
            }
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
        }
    }
}

private struct ToastView: View {
    let message: String
    let symbol: String

    var body: some View {
        Label(message, systemImage: symbol)
            .font(.system(size: 14, weight: .medium))
            .fixedSize()
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .modifier(ToastBackground())
            .padding(12)
    }
}

/// Liquid Glass on macOS 26, like the system's own HUDs, and a material capsule before it.
private struct ToastBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content.background(.regularMaterial, in: Capsule())
        }
    }
}
