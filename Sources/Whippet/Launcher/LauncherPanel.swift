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

    /// Centres the panel on the screen with `app`'s front window, where you're working, then on the screen with the
    /// pointer. Read before Whippet activates: once it does, an open Settings window becomes the key window, and
    /// `center()` alone would follow it to its screen.
    func center(onScreenOf app: NSRunningApplication?) {
        let screen = app.flatMap(Self.screen(ofFrontWindowOf:)) ?? Self.screenWithPointer
        if let screen {
            // Moved onto the screen first, since `center()` centres on the screen the window is on.
            setFrameOrigin(screen.visibleFrame.origin)
        }
        center()
    }

    /// The screen showing most of the app's frontmost normal window. Window bounds are readable without any permission.
    private static func screen(ofFrontWindowOf app: NSRunningApplication) -> NSScreen? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        // Front to back, so the first of the app's windows at the normal level is its front window.
        let front = windows.first { window in
            window[kCGWindowOwnerPID as String] as? pid_t == app.processIdentifier
                && window[kCGWindowLayer as String] as? Int == 0
        }
        guard
            let bounds = front?[kCGWindowBounds as String] as? NSDictionary,
            let rect = CGRect(dictionaryRepresentation: bounds),
            let primary = NSScreen.screens.first
        else { return nil }
        // The window server measures from the top of the primary screen, AppKit from its bottom.
        let frame = NSRect(x: rect.minX, y: primary.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
        return NSScreen.screens.max { lhs, rhs in
            lhs.frame.intersection(frame).area < rhs.frame.intersection(frame).area
        }.flatMap { $0.frame.intersects(frame) ? $0 : nil }
    }

    private static var screenWithPointer: NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
    }
}

extension NSRect {
    fileprivate var area: CGFloat { isNull ? 0 : width * height }
}
