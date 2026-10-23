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

        statusItem.button?.image = Self.boneImage()
        statusItem.button?.setAccessibilityLabel(String(localized: "Fetch"))

        let openItem = menuItem(String(localized: "Open Fetch"), symbol: "magnifyingglass", action: #selector(open), key: " ")
        openItem.keyEquivalentModifierMask = .option

        let menu = NSMenu()
        menu.items = [
            openItem,
            .separator(),
            menuItem(String(localized: "About Fetch"), symbol: "info.circle", action: #selector(showAbout)),
            menuItem(String(localized: "Settings…"), symbol: "gearshape", action: #selector(showSettings), key: ","),
            .separator(),
            menuItem(String(localized: "Show Data Folder"), symbol: "folder", action: #selector(showDataFolder)),
            .separator(),
            menuItem(String(localized: "Quit Fetch"), action: #selector(quit), key: "q"),
        ]
        statusItem.menu = menu
    }

    /// A dog bone outline drawn as a template image, since SF Symbols has no bone; macOS tints it to match the menu bar.
    private static func boneImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.addPath(bonePath())
            context.setLineWidth(1.4)
            context.setLineJoin(.round)
            context.setStrokeColor(NSColor.black.cgColor)
            context.strokePath()
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Two knobs at each end of a shaft, merged into one outline and turned 45 degrees within the 18-point canvas.
    private static func bonePath() -> CGPath {
        let radius: CGFloat = 1.8
        let knobs: [(x: CGFloat, y: CGFloat)] = [(3.6, 7.4), (3.6, 10.6), (14.4, 7.4), (14.4, 10.6)]
        let shaft = CGPath(rect: CGRect(x: 3.6, y: 7.6, width: 10.8, height: 2.8), transform: nil)
        let outline = knobs.reduce(shaft) { path, knob in
            let knobRect = CGRect(x: knob.x - radius, y: knob.y - radius, width: radius * 2, height: radius * 2)
            return path.union(CGPath(ellipseIn: knobRect, transform: nil))
        }
        var rotation = CGAffineTransform(translationX: 9, y: 9).rotated(by: .pi / 4).translatedBy(x: -9, y: -9)
        return outline.copy(using: &rotation) ?? outline
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
    /// The standard About panel titled with the full display name, Fetch Launcher, instead of the short bundle name.
    func showAboutPanel() {
        activate()
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        orderFrontStandardAboutPanel(options: name.map { [.applicationName: $0] } ?? [:])
    }
}
