import AppKit
import OSLog
import WhippetCore

/// The one way Whippet uses anything sensitive: the network, Accessibility, Screen Recording, Apple Events and
/// notifications. Each use names the command or feature it's for, and goes ahead only when that command or feature
/// declares it in its module's manifest and is turned on in Settings › Commands, so what Settings shows is what
/// Whippet does.
///
/// Using something undeclared is a bug, which stops a debug build at once; a release build refuses it and logs it.
/// `just lint` fails when the system APIs behind these are used outside `Permissions/`, so new code comes through here.
@MainActor
final class PermissionGate {
    static let shared = PermissionGate()

    /// Set at launch. Until then, and in tests, whatever is declared counts as on.
    var modules: ModuleSettings?

    private let log = Logger(subsystem: "codes.dibble.whippet", category: "permissions")

    /// Whether `ref` may use `permission` now: it declares it, and it's turned on.
    func allows(_ permission: Permission, for ref: ModuleRef) -> Bool {
        guard declares(permission, for: ref) else {
            log.fault(
                "Refused \(String(describing: permission), privacy: .public) for \(ref.defaultsKey, privacy: .public), which doesn't declare it"
            )
            assertionFailure("\(ref) uses \(permission) without declaring it in its module's manifest")
            return false
        }
        return modules?.isEnabled(ref) ?? true
    }

    private func declares(_ permission: Permission, for ref: ModuleRef) -> Bool {
        if ref.isExtension {
            // An extension's network and clipboard use is checked by its runtime, against its manifest.json. Pasting
            // with its Paste action is the one thing it does through Whippet, and it pastes what it shows.
            return permission == .accessibility(.paste)
        }
        return ModuleRegistry.declares(permission, for: ref)
    }

    // MARK: - Network

    /// A session allowed only the hosts `ref` declares, and only while it's turned on.
    func network(for ref: ModuleRef, timeout: TimeInterval? = nil) -> ScopedSession {
        let hosts = ModuleRegistry.permissions(of: ref).hosts
        assert(!hosts.isEmpty, "\(ref) declares no network hosts")
        return ScopedSession(hosts: hosts, timeout: timeout) { [weak self] in
            self?.modules?.isEnabled(ref) ?? true
        }
    }

    // MARK: - Accessibility

    /// Whether `ref` may use Accessibility now and macOS allows it. When macOS doesn't yet, it's asked to show its
    /// prompt, which leads to System Settings.
    func hasAccessibility(_ use: Permission.AccessibilityUse, for ref: ModuleRef) -> Bool {
        guard allows(.accessibility(use), for: ref) else { return false }
        guard Paster.isTrusted else {
            Paster.requestTrust()
            return false
        }
        return true
    }

    /// Brings back the app the panel opened over and sends it ⌘V, for `ref`. False when it couldn't, leaving what was
    /// copied on the clipboard.
    func paste(into app: NSRunningApplication, for ref: ModuleRef) -> Bool {
        guard hasAccessibility(.paste, for: ref) else { return false }
        // With a Whippet window open, closing the panel leaves Whippet in front, so the app is brought back for ⌘V.
        app.activate()
        Paster.pasteAfterPanelCloses()
        return true
    }

    // MARK: - Apple Events

    /// Runs an AppleScript that asks `target` to do something, for `ref`. macOS asks the user the first time for each
    /// app.
    func runAppleScript(_ source: String, in target: AutomationTarget, for ref: ModuleRef) throws {
        guard allows(.automation([target]), for: ref) else { throw SystemCommandError.failed }
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            throw SystemCommandError.script(error[NSAppleScript.errorMessage] as? String)
        }
    }
}
