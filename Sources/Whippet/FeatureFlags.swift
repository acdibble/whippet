import Foundation
import Observation

/// A feature that's still being tried out. It ships switched off, and is turned on under Settings › General › Beta
/// Features, so it can be released before it's finished without changing Whippet for everyone.
enum FeatureFlag: String, CaseIterable, Identifiable {
    case extensions

    var id: Self { self }

    var title: String {
        switch self {
        case .extensions: String(localized: "Extensions")
        }
    }

    var summary: String {
        switch self {
        case .extensions:
            String(localized: "Commands written in JavaScript with React, installed in Settings › Extensions.")
        }
    }

    var defaultsKey: String {
        "featureFlag.\(rawValue)"
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
