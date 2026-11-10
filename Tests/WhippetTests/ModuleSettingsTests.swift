import Foundation
import Testing

@MainActor
final class ModuleSettingsTests {
    let suiteName = "WhippetModuleSettings-\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    private func settings() -> ModuleSettings {
        ModuleSettings(defaults: defaults)
    }

    @Test func everythingStartsOn() {
        let settings = settings()
        for manifest in ModuleRegistry.all {
            #expect(settings.isEnabled(manifest.ref))
            for row in manifest.commands.map(\.id) + manifest.features.map(\.id) {
                #expect(settings.isEnabled(manifest.ref(row)))
            }
        }
        // Rows that come and go, and extensions, are on too.
        #expect(settings.isEnabled(.app("com.apple.Safari")))
        #expect(settings.isEnabled(.extension("com.example.hello", row: "BrowseFruit")))
    }

    @Test func aSwitchIsRememberedAndReported() {
        let settings = settings()
        var changes = 0
        settings.onChange = { changes += 1 }
        let revision = settings.revision

        #expect(settings.setOn(.currencyConversion, false))
        settings.setOn(.currencyConversion, false)

        #expect(!settings.isEnabled(.currencyConversion))
        #expect(changes == 1)
        #expect(settings.revision == revision + 1)
        #expect(!ModuleSettings(defaults: defaults).isEnabled(.currencyConversion))
        #expect(defaults.object(forKey: "module.calculator.currency.enabled") as? Bool == false)
    }

    @Test func turningOffAModuleTurnsOffItsRowsAndKeepsTheirSwitches() {
        let settings = settings()
        settings.setOn(.timersModule, false)

        #expect(!settings.isEnabled(.startTimer))
        #expect(settings.isOn(.startTimer))

        settings.setOn(.timersModule, true)
        #expect(settings.isEnabled(.startTimer))
    }

    /// A beta module does nothing until it's turned on under Beta Features, whatever its own switches say.
    @Test func aBetaModuleIsOffUntilItsFlagIsOn() {
        let flags = FeatureFlags(defaults: defaults)
        let settings = ModuleSettings(defaults: defaults, flags: flags)
        var changes = 0
        settings.onChange = { changes += 1 }
        let revision = settings.revision
        let command = ModuleRef.extension("com.example.hello", row: "BrowseFruit")

        #expect(!settings.isEnabled(.translate))
        #expect(!settings.isAvailable(.translationModule))
        #expect(settings.isOn(.translate))
        #expect(!settings.isEnabled(command))
        #expect(settings.isEnabled(.calculator))

        flags.setEnabled(.translation, true)
        #expect(settings.isEnabled(.translate))
        #expect(!settings.isEnabled(command))
        #expect(changes == 1)
        #expect(settings.revision == revision + 1)

        flags.setEnabled(.extensions, true)
        #expect(settings.isEnabled(command))
        #expect(settings.isEnabled(.extensionsModule))
    }

    @Test func settingsAndQuitStayOn() {
        let settings = settings()

        #expect(!settings.setOn(.settings, false))
        #expect(!settings.setOn(.quit, false))
        #expect(!settings.setOn(.whippetModule, false))
        #expect(settings.isEnabled(.settings))
        #expect(settings.setOn(.changelog, false))
    }

    @Test func whatsInUseStaysOn() {
        let settings = settings()
        settings.locks = {
            [ActivityLock(module: "timers", rows: ["timers", "stopwatch"], reason: "A timer is running")]
        }

        #expect(!settings.setOn(.timersModule, false))
        #expect(!settings.setOn(.timers, false))
        #expect(settings.lock(for: .stopwatch)?.reason == "A timer is running")
        #expect(settings.setOn(.startTimer, false))
        #expect(settings.isEnabled(.timersModule))

        settings.locks = { [] }
        #expect(settings.setOn(.timersModule, false))
    }
}

struct ModuleManifestTests {
    @Test func idsAreUnique() {
        let modules = ModuleRegistry.all.map(\.id)
        #expect(Set(modules).count == modules.count)
        for manifest in ModuleRegistry.all {
            let rows = manifest.commands.map(\.id) + manifest.features.map(\.id)
            #expect(Set(rows).count == rows.count, "\(manifest.id)")
        }
    }

    /// Hotkeys set before modules keep working.
    @Test func hotkeysKeepTheirNames() {
        let names = Set(ModuleRegistry.all.flatMap(\.commands).compactMap(\.legacyHotkey))
        let before = [
            "calculator", "floatingCalculator", "clipboardHistory", "captureText", "translate", "settings",
            "caffeinate", "startTimer", "timers", "startStopwatch", "stopwatch",
        ].map { "command.\($0)" }
        #expect(names == Set(before + WindowCommand.allCases.map { "window.\($0.rawValue)" }))
        #expect(ModuleRegistry.hotkeyName(for: .calculator) == "command.calculator")
        #expect(ModuleRegistry.hotkeyName(for: SystemCommand.sleep.moduleRef) == "command.system.sleep")
    }

    @Test func modulesGatherWhatTheirRowsUse() {
        #expect(ModuleManifest.calculator.permissions == [.network(["www.ecb.europa.eu"]), .accessibility(.paste)])
        #expect(ModuleManifest.system.permissions == [.automation([.systemEvents, .finder])])
        #expect(ModuleManifest.whippet.permissions.isEmpty)
    }
}
