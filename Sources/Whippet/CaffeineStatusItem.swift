import AppKit
import Observation

/// The optional Caffeinate menu bar item. It is an AppKit status item rather than a SwiftUI `MenuBarExtra`, because
/// `MenuBarExtra(isInserted:)` wrote its old state back when the setting changed outside SwiftUI and never hid.
@MainActor
final class CaffeineStatusItem: NSObject, NSMenuDelegate {
    private let caffeine: Caffeine
    private var statusItem: NSStatusItem?
    private var visibility: NSKeyValueObservation?

    init(caffeine: Caffeine) {
        self.caffeine = caffeine
        super.init()
        observe()
    }

    /// Re-runs whenever `showsInMenuBar` or `isActive` changes, adding, removing or updating the item.
    private func observe() {
        withObservationTracking {
            update(isShown: caffeine.showsInMenuBar, isActive: caffeine.isActive)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    private func update(isShown: Bool, isActive: Bool) {
        guard isShown else {
            remove()
            return
        }
        let item = statusItem ?? makeStatusItem()
        item.button?.image = NSImage(
            systemSymbolName: isActive ? "cup.and.heat.waves.fill" : "cup.and.heat.waves",
            accessibilityDescription: String(localized: "Caffeinate")
        )
    }

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.behavior = .removalAllowed
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        // ⌘-dragging the item out of the menu bar hides it, which should turn the setting off too.
        visibility = item.observe(\.isVisible) { [weak self] item, _ in
            guard !item.isVisible else { return }
            Task { @MainActor in self?.caffeine.showsInMenuBar = false }
        }
        statusItem = item
        return item
    }

    private func remove() {
        visibility = nil
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if caffeine.isActive {
            let status = NSMenuItem(title: caffeine.untilDescription, action: nil, keyEquivalent: "")
            status.isEnabled = false
            menu.addItem(status)
            menu.addItem(item(String(localized: "Decaffeinate"), symbol: "cup.and.heat.waves") { [caffeine] in
                caffeine.stop()
            })
            menu.addItem(.separator())
        }
        for minutes in Caffeine.durations {
            menu.addItem(item(Caffeine.title(minutes: minutes), symbol: "cup.and.heat.waves.fill") { [caffeine] in
                caffeine.start(seconds: minutes.map { $0 * 60 })
            })
        }
    }

    private func item(_ title: String, symbol: String, action: @escaping () -> Void) -> NSMenuItem {
        let item = ActionMenuItem(title: title, handler: action)
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return item
    }
}
