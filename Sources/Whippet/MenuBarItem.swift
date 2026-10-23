import AppKit

/// The menu bar icon, which keeps the app reachable without the hotkey.
@MainActor
final class MenuBarItem: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let onOpen: () -> Void
    private let onSettings: () -> Void

    init(onOpen: @escaping () -> Void, onSettings: @escaping () -> Void) {
        self.onOpen = onOpen
        self.onSettings = onSettings
        super.init()

        statusItem.button?.image = Self.whippetImage()
        statusItem.button?.setAccessibilityLabel(String(localized: "Whippet"))

        let openItem = menuItem(String(localized: "Open Whippet"), symbol: "magnifyingglass", action: #selector(open), key: " ")
        openItem.keyEquivalentModifierMask = .option

        let menu = NSMenu()
        menu.items = [
            openItem,
            .separator(),
            menuItem(String(localized: "About Whippet"), symbol: "info.circle", action: #selector(showAbout)),
            menuItem(String(localized: "Settings…"), symbol: "gearshape", action: #selector(showSettings), key: ","),
            .separator(),
            menuItem(String(localized: "Show Data Folder"), symbol: "folder", action: #selector(showDataFolder)),
            .separator(),
            menuItem(String(localized: "Quit Whippet"), action: #selector(quit), key: "q"),
        ]
        statusItem.menu = menu
    }

    /// A whippet's head in profile, drawn as a template image since SF Symbols has no whippet; macOS tints it to match the menu bar.
    private static func whippetImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.addPath(headPath())
            context.setLineWidth(1.4)
            context.setLineJoin(.round)
            context.setLineCap(.round)
            context.setStrokeColor(NSColor.black.cgColor)
            context.strokePath()
            context.setFillColor(NSColor.black.cgColor)
            context.fillEllipse(in: CGRect(x: 7.1, y: 8.6, width: 1.3, height: 1.3))
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Facing left in an 18-point canvas: the head and neck outline, the underside of the jaw and neck, and a rose ear.
    private static func headPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 1.7, y: 7.4))
        path.addCurve(to: CGPoint(x: 1.5, y: 9.0), control1: CGPoint(x: 1.0, y: 7.7), control2: CGPoint(x: 1.0, y: 8.7))
        path.addCurve(to: CGPoint(x: 6.8, y: 10.6), control1: CGPoint(x: 3.4, y: 9.6), control2: CGPoint(x: 5.4, y: 10.0))
        path.addCurve(to: CGPoint(x: 12.0, y: 12.0), control1: CGPoint(x: 8.2, y: 12.0), control2: CGPoint(x: 10.6, y: 12.6))
        path.addCurve(to: CGPoint(x: 15.8, y: 3.0), control1: CGPoint(x: 14.2, y: 10.4), control2: CGPoint(x: 15.4, y: 6.6))

        path.move(to: CGPoint(x: 1.7, y: 7.4))
        path.addCurve(to: CGPoint(x: 8.8, y: 6.2), control1: CGPoint(x: 4.0, y: 6.8), control2: CGPoint(x: 6.6, y: 6.4))
        path.addCurve(to: CGPoint(x: 10.8, y: 3.0), control1: CGPoint(x: 10.0, y: 5.4), control2: CGPoint(x: 10.6, y: 4.2))

        path.move(to: CGPoint(x: 10.0, y: 12.2))
        path.addCurve(to: CGPoint(x: 14.6, y: 13.6), control1: CGPoint(x: 11.4, y: 14.0), control2: CGPoint(x: 13.4, y: 14.4))
        path.addCurve(to: CGPoint(x: 12.6, y: 11.2), control1: CGPoint(x: 14.4, y: 12.6), control2: CGPoint(x: 13.4, y: 11.8))
        return path
    }

    private func menuItem(_ title: String, symbol: String? = nil, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        item.target = self
        return item
    }

    @objc private func open() {
        onOpen()
    }

    @objc private func showAbout() {
        NSApp.showAboutPanel()
    }

    @objc private func showSettings() {
        onSettings()
    }

    @objc private func showDataFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([ClipboardStore.defaultDirectory])
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

extension NSApplication {
    /// The standard About panel titled with the full display name instead of the short bundle name.
    func showAboutPanel() {
        activate()
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        orderFrontStandardAboutPanel(options: name.map { [.applicationName: $0] } ?? [:])
    }
}
