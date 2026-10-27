import Foundation
import IOKit.pwr_mgt
import Observation

/// Keeps the Mac and its display awake with a power assertion, the mechanism behind the `caffeinate` command.
/// macOS releases the assertion if Whippet quits. The session is saved, and picked up again at the next launch, so
/// restarting Whippet or installing an update doesn't end it; a timed session that ran out in the meantime isn't.
@MainActor
@Observable
final class Caffeine {
    private(set) var isActive = false
    /// When a timed session ends; nil while inactive or until turned off.
    private(set) var endsAt: Date?

    /// Whether the Caffeinate menu bar item is shown. The search command, Settings and the menu bar item all read and write
    /// this one property, so SwiftUI sees every change wherever it comes from.
    var showsInMenuBar = UserDefaults.standard.bool(forKey: "showsCaffeinateInMenuBar") {
        didSet { UserDefaults.standard.set(showsInMenuBar, forKey: "showsCaffeinateInMenuBar") }
    }

    private enum Keys {
        static let isActive = "caffeinateActive"
        static let endsAt = "caffeinateEndsAt"
    }

    @ObservationIgnored private var assertionID = IOPMAssertionID(0)
    @ObservationIgnored private var expiry: Task<Void, Never>?

    init() {
        guard UserDefaults.standard.bool(forKey: Keys.isActive) else { return }
        let endsAt = UserDefaults.standard.object(forKey: Keys.endsAt) as? Date
        if let endsAt, endsAt <= .now {
            save()
            return
        }
        begin(until: endsAt, announces: false)
    }

    /// Keeps the Mac awake for `seconds`, or until `stop()` when nil, replacing any session already running.
    func start(seconds: Int?) {
        begin(until: seconds.map { .now.addingTimeInterval(TimeInterval($0)) }, announces: true)
    }

    private func begin(until endsAt: Date?, announces: Bool) {
        release()
        let result = IOPMAssertionCreateWithName(
            "PreventUserIdleDisplaySleep" as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Whippet is keeping this Mac awake" as CFString,
            &assertionID
        )
        guard result == kIOReturnSuccess else {
            NSLog("Failed to keep the Mac awake: \(result)")
            return
        }
        isActive = true
        self.endsAt = endsAt
        save()
        if announces {
            Toast.shared.show(untilDescription, symbol: "cup.and.heat.waves.fill")
        }

        guard let endsAt else { return }
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(endsAt.timeIntervalSinceNow))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    func stop() {
        guard isActive else { return }
        release()
        Toast.shared.show(String(localized: "Decaffeinated"), symbol: "cup.and.heat.waves")
    }

    private func release() {
        expiry?.cancel()
        expiry = nil
        if isActive {
            IOPMAssertionRelease(assertionID)
        }
        isActive = false
        endsAt = nil
        save()
    }

    private func save() {
        UserDefaults.standard.set(isActive, forKey: Keys.isActive)
        UserDefaults.standard.set(endsAt, forKey: Keys.endsAt)
    }

    func toggle() {
        if isActive {
            stop()
            return
        }
        start(seconds: nil)
    }

    /// Until turned off, then the timed sessions offered in the menu bar item, in minutes.
    nonisolated static let durations: [Int?] = [nil, 30, 60, 120]

    nonisolated static func title(minutes: Int?) -> String {
        switch minutes {
        case nil: String(localized: "Caffeinate")
        case 30?: String(localized: "Caffeinate for 30 Minutes")
        case 60?: String(localized: "Caffeinate for 1 Hour")
        case 120?: String(localized: "Caffeinate for 2 Hours")
        case let minutes?: String(localized: "Caffeinate for \(minutes) Minutes")
        }
    }

    /// When the current session ends, for the menu bar and the Decaffeinate command.
    var untilDescription: String {
        guard let endsAt else { return String(localized: "Awake until turned off") }
        return String(localized: "Awake until \(endsAt.formatted(date: .omitted, time: .shortened))")
    }
}
