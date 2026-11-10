import AppKit
import CloudKit
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

    /// Set first thing at launch. Until then nothing is allowed, so a use that comes too early is refused rather than
    /// let through unchecked.
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
        return isOn(ref)
    }

    private func isOn(_ ref: ModuleRef) -> Bool {
        modules?.isEnabled(ref) ?? false
    }

    private func declares(_ permission: Permission, for ref: ModuleRef) -> Bool {
        if ref.isExtension {
            // An extension's network and clipboard use is checked by its runtime, against its manifest.json, before it
            // asks Whippet for either. Pasting with its Paste action pastes what it shows.
            return permission == .accessibility(.paste) || permission == .clipboardRead
        }
        return ModuleRegistry.declares(permission, for: ref)
    }

    // MARK: - Network

    /// A session allowed only the hosts `ref` declares, and only while it's turned on.
    func network(for ref: ModuleRef, timeout: TimeInterval? = nil) -> ScopedSession {
        let hosts = ModuleRegistry.permissions(of: ref).hosts
        assert(!hosts.isEmpty, "\(ref) declares no network hosts")
        return ScopedSession(hosts: hosts, timeout: timeout) { [weak self] in
            self?.isOn(ref) ?? false
        }
    }

    // MARK: - Clipboard

    /// The pasteboard, to read what was copied in any app, for `ref`. Nil when `ref` may not. Writing to it needs
    /// nothing.
    func clipboard(for ref: ModuleRef) -> NSPasteboard? {
        allows(.clipboardRead, for: ref) ? .general : nil
    }

    // MARK: - iCloud

    private static let container = CKContainer(identifier: "iCloud.codes.dibble.whippet")

    /// The public database feedback is sent to and read from, for `ref`. Cloud Sync's private database is opened by
    /// `CloudSync` in WhippetCore, which its module allows only while it's on.
    func publicDatabase(for ref: ModuleRef) throws -> CKDatabase {
        guard allows(.iCloud(.publicDatabase), for: ref) else { throw PermissionError.turnedOff }
        return Self.container.publicCloudDatabase
    }

    /// Whether this Mac is signed in to iCloud, which sending to the public database needs, for `ref`.
    func hasCloudAccount(for ref: ModuleRef) async -> Bool {
        guard allows(.iCloud(.publicDatabase), for: ref) else { return false }
        return (try? await Self.container.accountStatus()) == .available
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

/// Thrown when something is asked of a command or feature that's turned off.
enum PermissionError: LocalizedError {
    case turnedOff

    var errorDescription: String? {
        String(localized: "This is turned off in Settings › Commands.")
    }
}
