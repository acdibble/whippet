import AppKit
import Observation

/// The optional timers menu bar item, shown while a timer or stopwatch is running. It counts down the timer due
/// soonest, and its menu has every timer and stopwatch with their actions.
@MainActor
final class TimersStatusItem: NSObject, NSMenuDelegate {
    var onStartTimer: () -> Void = {}
    var onStartStopwatch: () -> Void = {}
    var onOpenTimers: () -> Void = {}
    var onOpenStopwatch: (UUID) -> Void = { _ in }
    /// Copies a timer's time the way the launcher does.
    var onCopyTime: (TimerItem) -> Void = { _ in }
    /// Renaming happens in the launcher's search bar.
    var onRename: (TimerItem) -> Void = { _ in }

    private let timers: Timers
    private var statusItem: NSStatusItem?
    private var visibility: NSKeyValueObservation?
    private var ticker: Timer?

    init(timers: Timers) {
        self.timers = timers
        super.init()
        observe()
    }

    /// Re-runs whenever the setting or the timers change, adding, removing or updating the item.
    private func observe() {
        withObservationTracking {
            update(isShown: timers.showsInMenuBar && timers.hasAny)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    private func update(isShown: Bool) {
        guard isShown else {
            remove()
            return
        }
        if statusItem == nil {
            statusItem = makeStatusItem()
        }
        refreshTitle()
        // A stopped clock needs no ticking.
        let isCounting = !timers.ringing.isEmpty || timers.items.contains { !$0.isPaused }
        if isCounting, ticker == nil {
            let ticker = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshTitle() }
            }
            RunLoop.main.add(ticker, forMode: .common)
            self.ticker = ticker
        } else if !isCounting {
            ticker?.invalidate()
            ticker = nil
        }
    }

    private func refreshTitle() {
        guard let button = statusItem?.button else { return }
        let others = timers.items.count + timers.ringing.count - 1
        let main: String
        if !timers.ringing.isEmpty {
            main = String(localized: "Done")
        } else if let next = Self.featured(timers.items) {
            main = next.kind == .stopwatch ? TimerNaming.clock(next.value().rounded(.down)) : TimerNaming.clock(next.value())
        } else {
            main = ""
        }
        let title = others > 0 ? "\(main) +\(others)" : main
        button.attributedTitle = NSAttributedString(
            string: " " + title,
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)]
        )
    }

    /// The running timer due soonest, then a running stopwatch, then whatever is paused.
    private static func featured(_ items: [TimerItem]) -> TimerItem? {
        let soonest = items.compactMap { item in item.endsAt.map { (item: item, endsAt: $0) } }.min { $0.endsAt < $1.endsAt }
        return soonest?.item
            ?? items.first { $0.kind == .stopwatch && !$0.isPaused }
            ?? items.first
    }

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.behavior = .removalAllowed
        // As with Caffeinate, an item ⌘-dragged out stays hidden when recreated unless made visible first.
        item.isVisible = true
        item.button?.image = NSImage(systemSymbolName: "timer", accessibilityDescription: String(localized: "Timers"))
        item.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        // ⌘-dragging the item out of the menu bar hides it, which turns the setting off too.
        visibility = item.observe(\.isVisible) { [weak self] item, _ in
            guard !item.isVisible else { return }
            Task { @MainActor in self?.timers.showsInMenuBar = false }
        }
        return item
    }

    private func remove() {
        ticker?.invalidate()
        ticker = nil
        visibility = nil
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for item in timers.ringing {
            let entry = NSMenuItem(title: String(localized: "\(item.name) · Done"), action: nil, keyEquivalent: "")
            entry.image = NSImage(systemSymbolName: "bell.and.waves.left.and.right", accessibilityDescription: nil)
            entry.submenu = submenu([
                action(String(localized: "Stop"), symbol: "stop") { [timers] in timers.stop(item.id) },
                action(String(localized: "Snooze"), symbol: "zzz") { [timers] in timers.snooze(item.id) },
            ])
            menu.addItem(entry)
        }
        for item in timers.items {
            let entry = NSMenuItem(title: "\(item.name) · \(status(of: item))", action: nil, keyEquivalent: "")
            entry.image = NSImage(systemSymbolName: item.kind == .timer ? "timer" : "stopwatch", accessibilityDescription: nil)
            entry.submenu = submenu(actions(for: item))
            menu.addItem(entry)
        }
        if timers.hasAny {
            menu.addItem(.separator())
        }
        menu.addItem(action(String(localized: "Start Timer…"), symbol: "timer") { [weak self] in self?.onStartTimer() })
        menu.addItem(action(String(localized: "Open Timers"), symbol: "list.bullet") { [weak self] in self?.onOpenTimers() })
        menu.addItem(action(String(localized: "Start Stopwatch"), symbol: "stopwatch") { [weak self] in
            self?.onStartStopwatch()
        })
    }

    private func status(of item: TimerItem) -> String {
        let time = item.kind == .timer
            ? String(localized: "\(TimerNaming.clock(item.value())) left")
            : TimerNaming.stopwatchClock(item.value())
        return item.isPaused ? String(localized: "Paused · \(time)") : time
    }

    private func actions(for item: TimerItem) -> [NSMenuItem] {
        let id = item.id
        var items = [
            item.isPaused
                ? action(String(localized: "Resume"), symbol: "play") { [timers] in timers.togglePause(id) }
                : action(String(localized: "Pause"), symbol: "pause") { [timers] in timers.togglePause(id) },
        ]
        switch item.kind {
        case .timer:
            items.append(action(String(localized: "Add 1 Minute"), symbol: "plus") { [timers] in timers.add(60, to: id) })
            items.append(action(String(localized: "Add 5 Minutes"), symbol: "goforward.5") { [timers] in timers.add(300, to: id) })
            items.append(action(String(localized: "Restart"), symbol: "arrow.counterclockwise") { [timers] in timers.restart(id) })
        case .stopwatch:
            items.insert(action(String(localized: "Open Stopwatch"), symbol: "stopwatch") { [weak self] in
                self?.onOpenStopwatch(id)
            }, at: 0)
            if !item.isPaused {
                items.append(action(String(localized: "Lap"), symbol: "flag") { [timers] in timers.lap(id) })
            }
            items.append(action(String(localized: "Reset"), symbol: "arrow.counterclockwise") { [timers] in timers.restart(id) })
            items.append(action(String(localized: "Copy Elapsed Time"), symbol: "doc.on.doc") { [weak self, timers] in
                guard let item = timers.item(id) else { return }
                self?.onCopyTime(item)
            })
        }
        items.append(action(String(localized: "Rename…"), symbol: "pencil") { [weak self, timers] in
            guard let item = timers.item(id) else { return }
            self?.onRename(item)
        })
        if !item.laps.isEmpty {
            items.append(.separator())
            for (index, lap) in item.laps.enumerated() {
                let previous = index > 0 ? item.laps[index - 1] : 0
                let entry = NSMenuItem(
                    title: String(localized: "Lap \(index + 1): \(TimerNaming.stopwatchClock(lap - previous))"),
                    action: nil,
                    keyEquivalent: ""
                )
                entry.isEnabled = false
                items.append(entry)
            }
        }
        items.append(.separator())
        items.append(action(
            item.kind == .timer ? String(localized: "Cancel Timer") : String(localized: "Stop Stopwatch"),
            symbol: "xmark"
        ) { [timers] in timers.remove(id) })
        return items
    }

    private func submenu(_ items: [NSMenuItem]) -> NSMenu {
        let menu = NSMenu()
        items.forEach(menu.addItem)
        return menu
    }

    private func action(_ title: String, symbol: String, handler: @escaping () -> Void) -> NSMenuItem {
        let item = ActionMenuItem(title: title, handler: handler)
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return item
    }
}
