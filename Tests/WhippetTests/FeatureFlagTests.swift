import Foundation
import Testing

@MainActor
final class FeatureFlagTests {
    let suiteName = "WhippetFeatureFlags-\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    @Test func flagsStartOff() {
        let flags = FeatureFlags(defaults: defaults)
        #expect(!flags.isEnabled(.extensions))
        #expect(flags.enabled.isEmpty)
    }

    @Test func turningAFlagOnIsRememberedAndReported() {
        let flags = FeatureFlags(defaults: defaults)
        var changes: [(FeatureFlag, Bool)] = []
        flags.onChange = { changes.append(($0, $1)) }

        flags.setEnabled(.extensions, true)
        flags.setEnabled(.extensions, true)

        #expect(flags.isEnabled(.extensions))
        #expect(changes.count == 1)
        #expect(FeatureFlags(defaults: defaults).isEnabled(.extensions))

        flags.setEnabled(.extensions, false)
        #expect(changes.last.map { $0.1 } == false)
        #expect(!FeatureFlags(defaults: defaults).isEnabled(.extensions))
    }
}
