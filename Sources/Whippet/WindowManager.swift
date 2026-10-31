import AppKit
import ApplicationServices
import SwiftUI

extension WindowCommand {
    /// Center Third's symbol is Whippet's own, in the asset catalog: SF Symbols fills a first or last third but not the
    /// middle one.
    var image: Image {
        self == .centerThird ? Image(symbol) : Image(systemName: symbol)
    }
}

/// Moves and resizes another app's focused window with the Accessibility API, which needs the same permission as
/// pasting.
@MainActor
enum WindowManager {
    /// Where each window was before Whippet first moved it, for Restore. Kept for a handful of recent windows.
    private static var originalFrames: [(window: AXUIElement, frame: CGRect)] = []
    private static let originalFrameLimit = 30

    static func perform(_ command: WindowCommand, in app: NSRunningApplication?) {
        guard Paster.isTrusted else {
            Paster.requestTrust()
            return
        }
        guard
            let app,
            let window = focusedWindow(of: app),
            let current = frame(of: window),
            let mainScreen = NSScreen.screens.first
        else {
            NSSound.beep()
            return
        }
        let mainHeight = mainScreen.frame.height
        let windowFrame = WindowLayout.flipped(current, mainScreenHeight: mainHeight)
        let target: CGRect?
        if command == .restore {
            target = originalFrames.firstIndex { CFEqual($0.window, window) }.map {
                originalFrames.remove(at: $0).frame
            }
        } else {
            let screens = NSScreen.screens.map(\.visibleFrame)
            guard let index = WindowLayout.screenIndex(for: windowFrame, in: screens) else { return NSSound.beep() }
            let next = WindowLayout.nextScreenIndex(after: index, in: screens).map { screens[$0] }
            target = WindowLayout.frame(for: command, window: windowFrame, screen: screens[index], nextScreen: next)
            if target != nil, !originalFrames.contains(where: { CFEqual($0.window, window) }) {
                originalFrames.append((window, windowFrame))
                if originalFrames.count > originalFrameLimit { originalFrames.removeFirst() }
            }
        }
        guard let target else { return NSSound.beep() }
        setFrame(of: window, to: WindowLayout.flipped(target, mainScreenHeight: mainHeight))
    }

    private static func focusedWindow(of app: NSRunningApplication) -> AXUIElement? {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value {
                // The attribute's value is always a UI element.
                return (value as! AXUIElement)
            }
        }
        return nil
    }

    /// In Accessibility coordinates, from the top left of the main display.
    private static func frame(of window: AXUIElement) -> CGRect? {
        var position = CGPoint.zero
        var size = CGSize.zero
        guard
            let positionValue = attribute(kAXPositionAttribute, of: window),
            let sizeValue = attribute(kAXSizeAttribute, of: window),
            AXValueGetValue(positionValue, .cgPoint, &position),
            AXValueGetValue(sizeValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: position, size: size)
    }

    /// Size, then position, then size again: a window too big to move fully onto a screen is resized first, and one
    /// that couldn't take its size at the old position gets it at the new one.
    private static func setFrame(of window: AXUIElement, to frame: CGRect) {
        var position = frame.origin
        var size = frame.size
        guard
            let positionValue = AXValueCreate(.cgPoint, &position),
            let sizeValue = AXValueCreate(.cgSize, &size)
        else { return }
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
    }

    private static func attribute(_ name: String, of element: AXUIElement) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let value else {
            return nil
        }
        return (value as! AXValue)
    }
}
