import CoreGraphics
import Foundation

/// Commands that move and resize the front window, from the launcher or their own hotkeys.
enum WindowCommand: String, CaseIterable, Identifiable {
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case firstThird
    case centerThird
    case lastThird
    case firstTwoThirds
    case lastTwoThirds
    case maximize
    case center
    case nextDisplay
    case restore

    var id: Self { self }

    var title: String {
        switch self {
        case .leftHalf: String(localized: "Left Half")
        case .rightHalf: String(localized: "Right Half")
        case .topHalf: String(localized: "Top Half")
        case .bottomHalf: String(localized: "Bottom Half")
        case .firstThird: String(localized: "First Third")
        case .centerThird: String(localized: "Center Third")
        case .lastThird: String(localized: "Last Third")
        case .firstTwoThirds: String(localized: "First Two Thirds")
        case .lastTwoThirds: String(localized: "Last Two Thirds")
        case .maximize: String(localized: "Maximize")
        case .center: String(localized: "Center")
        case .nextDisplay: String(localized: "Next Display")
        case .restore: String(localized: "Restore")
        }
    }

    var symbol: String {
        switch self {
        case .leftHalf: "rectangle.lefthalf.filled"
        case .rightHalf: "rectangle.righthalf.filled"
        case .topHalf: "rectangle.tophalf.filled"
        case .bottomHalf: "rectangle.bottomhalf.filled"
        case .firstThird: "rectangle.leadingthird.inset.filled"
        case .centerThird: "rectangle.centerthird.inset.filled"
        case .lastThird: "rectangle.trailingthird.inset.filled"
        case .firstTwoThirds: "rectangle.leadinghalf.inset.filled"
        case .lastTwoThirds: "rectangle.trailinghalf.inset.filled"
        case .maximize: "arrow.up.left.and.arrow.down.right"
        case .center: "rectangle.center.inset.filled"
        case .nextDisplay: "display.2"
        case .restore: "arrow.uturn.backward"
        }
    }
}

/// The frame maths for window commands, in AppKit's global coordinates: origin at the bottom left of the main
/// display, y growing upwards. Screen rectangles are visible frames, without the menu bar and Dock.
enum WindowLayout {
    /// Where the command puts the window, or nil for Restore, which needs the window's earlier frame. Thirds run across
    /// a landscape screen and down a portrait one.
    static func frame(for command: WindowCommand, window: CGRect, screen: CGRect, nextScreen: CGRect?) -> CGRect? {
        let isPortrait = screen.height > screen.width
        let frame: CGRect
        switch command {
        case .leftHalf: frame = slice(screen, from: 0, to: 1 / 2, vertical: false)
        case .rightHalf: frame = slice(screen, from: 1 / 2, to: 1, vertical: false)
        case .topHalf: frame = slice(screen, from: 0, to: 1 / 2, vertical: true)
        case .bottomHalf: frame = slice(screen, from: 1 / 2, to: 1, vertical: true)
        case .firstThird: frame = slice(screen, from: 0, to: 1 / 3, vertical: isPortrait)
        case .centerThird: frame = slice(screen, from: 1 / 3, to: 2 / 3, vertical: isPortrait)
        case .lastThird: frame = slice(screen, from: 2 / 3, to: 1, vertical: isPortrait)
        case .firstTwoThirds: frame = slice(screen, from: 0, to: 2 / 3, vertical: isPortrait)
        case .lastTwoThirds: frame = slice(screen, from: 1 / 3, to: 1, vertical: isPortrait)
        case .maximize: frame = screen
        case .center:
            let size = CGSize(width: min(window.width, screen.width), height: min(window.height, screen.height))
            frame = CGRect(
                x: screen.midX - size.width / 2, y: screen.midY - size.height / 2, width: size.width,
                height: size.height)
        case .nextDisplay:
            guard let nextScreen else { return nil }
            frame = moved(window, from: screen, to: nextScreen)
        case .restore:
            return nil
        }
        return rounded(frame)
    }

    /// Edges on whole points, rounded rather than pushed outwards, so thirds don't gain a point from rounding errors.
    private static func rounded(_ rect: CGRect) -> CGRect {
        let minX = rect.minX.rounded()
        let minY = rect.minY.rounded()
        return CGRect(x: minX, y: minY, width: rect.maxX.rounded() - minX, height: rect.maxY.rounded() - minY)
    }

    /// Part of the screen, measured from the left, or from the top when vertical.
    private static func slice(_ screen: CGRect, from start: CGFloat, to end: CGFloat, vertical: Bool) -> CGRect {
        if vertical {
            return CGRect(
                x: screen.minX, y: screen.maxY - screen.height * end, width: screen.width,
                height: screen.height * (end - start))
        }
        return CGRect(
            x: screen.minX + screen.width * start, y: screen.minY, width: screen.width * (end - start),
            height: screen.height)
    }

    /// The window in the same place relative to the other screen, scaled to its size and kept on it.
    private static func moved(_ window: CGRect, from screen: CGRect, to next: CGRect) -> CGRect {
        let scaleX = next.width / screen.width
        let scaleY = next.height / screen.height
        let width = min(window.width * scaleX, next.width)
        let height = min(window.height * scaleY, next.height)
        let x = next.minX + (window.minX - screen.minX) * scaleX
        let y = next.minY + (window.minY - screen.minY) * scaleY
        return CGRect(
            x: min(max(x, next.minX), next.maxX - width),
            y: min(max(y, next.minY), next.maxY - height),
            width: width,
            height: height
        )
    }

    /// The screen holding most of the window, or the one nearest its centre when it's on none.
    static func screenIndex(for window: CGRect, in screens: [CGRect]) -> Int? {
        let overlaps = screens.map { screen -> CGFloat in
            let overlap = screen.intersection(window)
            return overlap.isNull ? 0 : overlap.width * overlap.height
        }
        if let best = overlaps.indices.max(by: { overlaps[$0] < overlaps[$1] }), overlaps[best] > 0 {
            return best
        }
        let center = CGPoint(x: window.midX, y: window.midY)
        return screens.indices.min { distance(center, to: screens[$0]) < distance(center, to: screens[$1]) }
    }

    /// The next screen from left to right, back to the first after the last.
    static func nextScreenIndex(after index: Int, in screens: [CGRect]) -> Int? {
        guard screens.count > 1 else { return nil }
        let order = screens.indices.sorted {
            (screens[$0].minX, screens[$0].minY) < (screens[$1].minX, screens[$1].minY)
        }
        guard let position = order.firstIndex(of: index) else { return nil }
        return order[(position + 1) % order.count]
    }

    /// Accessibility positions windows from the top left of the main display, with y growing downwards. Flipping
    /// against the main display's height converts either way.
    static func flipped(_ rect: CGRect, mainScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: mainScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    private static func distance(_ point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }
}
