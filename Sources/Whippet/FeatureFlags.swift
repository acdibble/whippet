import Foundation
import Observation

/// A module that's still being tried out, declared with `stage: .beta` in its manifest. It ships switched off, and is
/// turned on under Settings › General › Beta Features, so it can be released before it's finished without changing
/// Whippet for everyone. Until then it isn't listed in Settings › Commands, and does no work.
struct FeatureFlag: Hashable, Identifiable {
    /// The module's id, which names its switch in user defaults, such as `featureFlag.translation`.
    let id: String
    let title: String
    let summary: String

    init?(_ manifest: ModuleManifest) {
        guard case .beta(let summary) = manifest.stage else { return nil }
        id = manifest.id
        title = manifest.title
        self.summary = summary
    }

    /// Every beta module's, in the order Settings lists modules.
    static var allCases: [FeatureFlag] {
        ModuleRegistry.all.compactMap(FeatureFlag.init)
    }

    static let extensions = FeatureFlag(.extensions)!
    static let translation = FeatureFlag(.translation)!

    var defaultsKey: String {
        "featureFlag.\(id)"
    }
}

/// Which beta features are on, kept in user defaults.
@MainActor
@Observable
final class FeatureFlags {
    private(set) var enabled: Set<FeatureFlag>

    /// Called after a flag changes, so what it gates can start or stop.
    @ObservationIgnored var onChange: (FeatureFlag, Bool) -> Void = { _, _ in }
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = Set(FeatureFlag.allCases.filter { defaults.bool(forKey: $0.defaultsKey) })
    }

    func isEnabled(_ flag: FeatureFlag) -> Bool {
        enabled.contains(flag)
    }

    func setEnabled(_ flag: FeatureFlag, _ isEnabled: Bool) {
        guard isEnabled != self.isEnabled(flag) else { return }
        defaults.set(isEnabled, forKey: flag.defaultsKey)
        if isEnabled {
            enabled.insert(flag)
        } else {
            enabled.remove(flag)
        }
        onChange(flag, isEnabled)
    }
}
