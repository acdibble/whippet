import Foundation
import Testing
import WhippetCore

/// What modules declare matches what Whippet is signed with and what it does, so Settings › Commands is complete.
struct ManifestTests {
    private static let root = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../..")
        .standardizedFileURL

    /// The kind of permission each entitlement is for. An entitlement added to the app has to be added here, with the
    /// module that needs it declaring that kind, so the table in Settings stays complete.
    private static let entitlementKinds: [String: Permission.Kind] = [
        // Push notifications tell Cloud Sync when another Mac changed something.
        "com.apple.developer.aps-environment": .iCloud,
        "com.apple.developer.icloud-container-identifiers": .iCloud,
        "com.apple.developer.icloud-container-environment": .iCloud,
        "com.apple.developer.icloud-services": .iCloud,
        // Holds the key Read Feedback decrypts feedback with, shared with Whippet's other builds.
        "keychain-access-groups": .iCloud,
        "com.apple.security.automation.apple-events": .automation,
    ]

    /// The kind of permission each usage description in `project.yml` explains, which macOS shows when it asks.
    private static let usageDescriptionKinds: [String: Permission.Kind] = [
        "NSAppleEventsUsageDescription": .automation
    ]

    private var declaredKinds: Set<Permission.Kind> {
        Set(ModuleRegistry.builtIn.flatMap(\.permissions).map(\.kind))
    }

    @Test(arguments: ["Whippet.entitlements", "WhippetRelease.entitlements"])
    func everyEntitlementIsDeclared(file: String) throws {
        let data = try Data(contentsOf: Self.root.appending(path: "Resources/\(file)"))
        let entitlements = try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        // An entitlement set to false, such as turning off the sandbox, grants nothing.
        let granted = entitlements.filter { ($0.value as? Bool) != false }.keys
        for key in granted {
            let kind = try #require(Self.entitlementKinds[key], "\(key) in \(file) isn't claimed by any permission")
            #expect(declaredKinds.contains(kind), "\(key) is for \(kind), which no module declares")
        }
        // And what modules declare that needs an entitlement has one.
        for (key, kind) in Self.entitlementKinds where declaredKinds.contains(kind) && key.hasSuffix("services") {
            #expect(granted.contains(key), "\(kind) is declared, but \(file) lacks \(key)")
        }
        #expect(granted.contains("com.apple.security.automation.apple-events") == declaredKinds.contains(.automation))
    }

    @Test func everyUsageDescriptionIsDeclared() throws {
        let project = try String(contentsOf: Self.root.appending(path: "project.yml"), encoding: .utf8)
        let keys = Set(project.matches(of: /\b(NS\w+UsageDescription)\b/).map { String($0.output.1) })
        for key in keys {
            let kind = try #require(Self.usageDescriptionKinds[key], "\(key) isn't claimed by any permission")
            #expect(declaredKinds.contains(kind), "\(key) is for \(kind), which no module declares")
        }
        for (key, kind) in Self.usageDescriptionKinds where declaredKinds.contains(kind) {
            #expect(keys.contains(key), "\(kind) is declared, but project.yml has no \(key)")
        }
    }

    /// What `PermissionGate` checks each use against.
    @Test func declaredPermissionsAreLookedUpByRow() {
        #expect(ModuleRegistry.declares(.network(["www.ecb.europa.eu"]), for: .currencyConversion))
        #expect(!ModuleRegistry.declares(.network(["github.com"]), for: .currencyConversion))
        #expect(!ModuleRegistry.declares(.network(["www.ecb.europa.eu"]), for: .inlineCalculation))
        #expect(ModuleRegistry.declares(.accessibility(.paste), for: .calculator))
        #expect(ModuleRegistry.declares(.automation([.systemEvents]), for: SystemCommand.restart.moduleRef))
        #expect(!ModuleRegistry.declares(.automation([.finder]), for: SystemCommand.restart.moduleRef))
        #expect(!ModuleRegistry.declares(.automation([.systemEvents]), for: SystemCommand.sleep.moduleRef))
        // The module declares what any of its rows do.
        #expect(ModuleRegistry.declares(.notifications, for: .timersModule))
        #expect(ModuleRegistry.permissions(of: .linkPreviews).hosts == ["*"])
    }

    /// Settings › Commands shows every module's names and summaries, and they're translated.
    @Test func everyModuleStringIsTranslated() throws {
        let missing = try Self.untranslated(
            ModuleRegistry.builtIn.flatMap { manifest in
                [manifest.title, manifest.summary] + manifest.commands.map(\.title)
                    + manifest.features.flatMap { [$0.title, $0.summary] }
            },
            in: "Sources/Whippet/Localizable.xcstrings")
        #expect(missing.isEmpty, "No fa translation: \(missing)")
    }

    @Test func everyPermissionNameIsTranslated() throws {
        let missing = try Self.untranslated(
            Permission.Kind.allCases.map(\.title),
            in: "Packages/WhippetCore/Sources/WhippetCore/Localizable.xcstrings")
        #expect(missing.isEmpty, "No fa translation: \(missing)")
    }

    /// The strings with no `fa` translation in a catalog. Tests run in English, so each string is its own key.
    private static func untranslated(_ strings: [String], in catalog: String) throws -> [String] {
        let data = try Data(contentsOf: root.appending(path: catalog))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entries = try #require(json["strings"] as? [String: [String: Any]])
        return Set(strings).sorted().filter { string in
            let localizations = entries[string]?["localizations"] as? [String: Any]
            return localizations?["fa"] == nil && string != "Whippet"
        }
    }
}
