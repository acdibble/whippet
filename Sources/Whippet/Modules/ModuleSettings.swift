import Foundation
import Observation

/// Which modules, commands and features are turned on in Settings › Commands, kept in user defaults. Everything is on
/// until it's turned off, so features added in an update start on, except a beta module, which is off until it's
/// turned on under Beta Features.
@MainActor
@Observable
final class ModuleSettings {
    /// Changes with every switch, so cached launcher results know to update.
    private(set) var revision = 0

    /// What's running, which keeps the switches it names on. Read when asked, from services that are observable
    /// themselves, so Settings updates as timers start and stop.
    @ObservationIgnored var locks: () -> [ActivityLock] = { [] }
    /// Called after a switch changes, so what it gates can start or stop.
    @ObservationIgnored var onChange: () -> Void = {}

    private var stored: [String: Bool]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let manifests: [String: ModuleManifest]
    /// Which beta modules are on. Without it, as in most tests, every beta module counts as on.
    @ObservationIgnored private let flags: FeatureFlags?

    init(
        defaults: UserDefaults = .standard, manifests: [ModuleManifest] = ModuleRegistry.all,
        flags: FeatureFlags? = nil
    ) {
        self.defaults = defaults
        self.flags = flags
        self.manifests = Dictionary(manifests.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        stored = defaults.dictionaryRepresentation().filter { key, _ in
            key.hasPrefix("module.") && key.hasSuffix(".enabled")
        }.compactMapValues { $0 as? Bool }
        // A beta feature turning on or off changes what may run just as a switch does.
        flags?.onChange = { [weak self] _, _ in
            guard let self else { return }
            revision += 1
            onChange()
        }
    }

    /// Where its own switch is, whatever the module it's in. Settings and Quit are always on.
    func isOn(_ ref: ModuleRef) -> Bool {
        isRequired(ref) || stored[ref.defaultsKey] ?? true
    }

    /// Whether it may run: its module is past beta or turned on under Beta Features, its module is on, and so is it.
    func isEnabled(_ ref: ModuleRef) -> Bool {
        isAvailable(ref) && isOn(ref.moduleRef) && (ref.row == nil || isOn(ref))
    }

    /// Whether its module is there to be turned on at all: a beta module is only once its beta feature is on, and an
    /// extension only while Extensions is.
    func isAvailable(_ ref: ModuleRef) -> Bool {
        guard let flags else { return true }
        let manifest = ref.isExtension ? ModuleManifest.extensions : manifests[ref.module]
        return manifest?.flag.map(flags.isEnabled) ?? true
    }

    /// Settings and Quit, and the Whippet module they're in.
    func isRequired(_ ref: ModuleRef) -> Bool {
        guard let manifest = manifests[ref.module] else { return false }
        guard let row = ref.row else { return manifest.isRequired }
        return manifest.command(row)?.isRequired ?? false
    }

    /// What's keeping it on, if anything is running that needs it.
    func lock(for ref: ModuleRef) -> ActivityLock? {
        locks().first { $0.locks(ref) }
    }

    /// Whether its switch can be turned off now.
    func canTurnOff(_ ref: ModuleRef) -> Bool {
        !isRequired(ref) && lock(for: ref) == nil
    }

    /// Turns a module, command or feature on or off. Something required or in use stays on, and this returns false.
    @discardableResult
    func setOn(_ ref: ModuleRef, _ isOn: Bool) -> Bool {
        guard isOn != self.isOn(ref) else { return true }
        guard isOn || canTurnOff(ref) else { return false }
        stored[ref.defaultsKey] = isOn
        defaults.set(isOn, forKey: ref.defaultsKey)
        revision += 1
        onChange()
        return true
    }
}
