import AppKit
import SwiftUI

/// A transparent panel sized for the expanded launcher, so the search field never moves when results appear.
/// The SwiftUI view draws its own shadow inside `shadowInset`, because the window shadow would not track the content's height.
final class LauncherPanel: NSPanel {
    static let shadowInset: CGFloat = 32
    static let contentSize = CGSize(width: 760, height: 480)

    init(rootView: some View) {
        super.init(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: Self.contentSize.width + Self.shadowInset * 2,
                height: Self.contentSize.height + Self.shadowInset * 2
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        contentView = NSHostingView(rootView: rootView)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
