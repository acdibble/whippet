import Foundation
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

struct PermissionCoverageTests {
    @Test func hostsMatchTheirPatterns() {
        #expect(Permission.network(["www.ecb.europa.eu"]).covers(.network(["WWW.ECB.EUROPA.EU"])))
        #expect(!Permission.network(["www.ecb.europa.eu"]).covers(.network(["ecb.europa.eu"])))
        #expect(Permission.network(["*.githubusercontent.com"]).covers(.network(["objects.githubusercontent.com"])))
        #expect(!Permission.network(["*.githubusercontent.com"]).covers(.network(["githubusercontent.com.evil.com"])))
        #expect(Permission.network(["*"]).covers(.network(["anything.example"])))
        #expect(!Permission.network(["a.com"]).covers(.network(["a.com", "b.com"])))
    }

    @Test func appsAndUsesMustMatch() {
        #expect(Permission.automation([.systemEvents, .finder]).covers(.automation([.finder])))
        #expect(!Permission.automation([.systemEvents]).covers(.automation([.finder])))
        #expect(!Permission.accessibility(.paste).covers(.accessibility(.windows)))
        #expect(!Permission.network(["*"]).covers(.clipboardRead))
        #expect([Permission.clipboardRead, .network(["*"])].covers(.network(["example.com"])))
    }
}

struct ScopedSessionTests {
    @Test func onlyDeclaredWebHostsAreAllowed() async {
        let session = ScopedSession(hosts: ["www.ecb.europa.eu", "*.example.com"])
        #expect(await session.permits(URL(string: "https://www.ecb.europa.eu/stats/eurofxref-daily.xml")!))
        #expect(await session.permits(URL(string: "http://api.example.com/")!))
        #expect(!(await session.permits(URL(string: "https://example.org/")!)))
        #expect(!(await session.permits(URL(string: "file:///etc/hosts")!)))
        #expect(!(await session.permits(URL(string: "ftp://www.ecb.europa.eu/")!)))
    }

    @Test func nothingIsRequestedWhileTurnedOff() async {
        let session = ScopedSession(hosts: ["*"]) { false }
        #expect(!(await session.permits(URL(string: "https://example.com/")!)))
        await #expect(throws: ScopedSession.Blocked.self) {
            _ = try await session.data(for: URLRequest(url: URL(string: "https://example.com/")!))
        }
    }

    @Test func undeclaredHostsAreBlockedBeforeConnecting() async {
        let session = ScopedSession(hosts: ["www.ecb.europa.eu"])
        await #expect(throws: ScopedSession.Blocked.self) {
            _ = try await session.data(for: URLRequest(url: URL(string: "https://example.com/")!))
        }
    }
}
