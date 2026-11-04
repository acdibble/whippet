import Testing

@testable import WhippetCore

struct PermissionTests {
    @Test func combiningGathersHostsAndAppsAndDropsRepeats() {
        let permissions: [Permission] = [
            .accessibility(.paste), .network(["a.example.com"]), .automation([.finder]),
            .network(["b.example.com", "a.example.com"]), .accessibility(.paste), .automation([.systemEvents]),
        ]
        #expect(
            permissions.combined == [
                .network(["a.example.com", "b.example.com"]), .accessibility(.paste),
                .automation([.finder, .systemEvents]),
            ])
    }

    @Test func anyWebsiteCoversEveryHost() {
        let permissions: [Permission] = [.network(["www.ecb.europa.eu"]), .network(["*"])]
        #expect(permissions.combined == [.network(["*"])])
        #expect(Permission.network(["*"]).shortTitle == "Any website")
        #expect(Permission.network(["www.ecb.europa.eu"]).shortTitle == "www.ecb.europa.eu")
        #expect(Permission.network(["a.com", "b.com"]).shortTitle == "2 sites")
    }

    @Test func extensionsAskInTheSameTerms() {
        #expect(ExtensionPermissions().permissions.isEmpty)
        #expect(
            ExtensionPermissions(network: ["api.github.com"], clipboard: true).permissions == [
                .network(["api.github.com"]), .clipboardRead,
            ])
    }
}
