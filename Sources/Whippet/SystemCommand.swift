import AppKit
import IOKit.pwr_mgt

/// Commands that act on the Mac itself. Sleep uses IOKit; restarting, shutting down and switching appearance ask System
/// Events, and emptying the Trash asks Finder, so they behave as if chosen from the menu bar, and macOS asks once for
/// permission to control each. Locking has no public API, so it uses the private function the lock menu item calls.
enum SystemCommand: String, CaseIterable, Identifiable {
    case lockScreen
    case sleep
    case restart
    case shutDown
    case emptyTrash
    case toggleDarkMode

    var id: Self { self }

    var title: String {
        switch self {
        case .lockScreen: String(localized: "Lock Screen")
        case .sleep: String(localized: "Sleep")
        case .restart: String(localized: "Restart")
        case .shutDown: String(localized: "Shut Down")
        case .emptyTrash: String(localized: "Empty Trash")
        case .toggleDarkMode: String(localized: "Toggle Dark Mode")
        }
    }

    var symbol: String {
        switch self {
        case .lockScreen: "lock.fill"
        case .sleep: "moon.fill"
        case .restart: "arrow.clockwise"
        case .shutDown: "power"
        case .emptyTrash: "trash"
        case .toggleDarkMode: "circle.lefthalf.filled"
        }
    }

    /// The alert's title and button for commands that can't be undone, or nil for those that run straight away.
    var confirmation: (title: String, message: String, button: String)? {
        switch self {
        case .restart:
            (
                String(localized: "Restart this Mac?"), String(localized: "Apps will be asked to quit first."),
                String(localized: "Restart")
            )
        case .shutDown:
            (
                String(localized: "Shut down this Mac?"), String(localized: "Apps will be asked to quit first."),
                String(localized: "Shut Down")
            )
        case .emptyTrash:
            (
                String(localized: "Empty the Trash?"),
                String(localized: "Items in the Trash will be deleted permanently."), String(localized: "Empty Trash")
            )
        default:
            nil
        }
    }

    func run() throws {
        switch self {
        case .lockScreen: try Self.lockScreen()
        case .sleep: try Self.sleep()
        case .restart: try Self.runAppleScript(#"tell application "System Events" to restart"#)
        case .shutDown: try Self.runAppleScript(#"tell application "System Events" to shut down"#)
        case .emptyTrash: try Self.runAppleScript(#"tell application "Finder" to empty trash"#)
        case .toggleDarkMode:
            try Self.runAppleScript(
                #"tell application "System Events" to tell appearance preferences to set dark mode to not dark mode"#
            )
        }
    }

    private static func sleep() throws {
        let port = IOPMFindPowerManagement(kIOMainPortDefault)
        guard port != 0 else { throw SystemCommandError.failed }
        defer { IOServiceClose(port) }
        guard IOPMSleepSystem(port) == kIOReturnSuccess else { throw SystemCommandError.failed }
    }

    private static func lockScreen() throws {
        guard
            let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
            let symbol = dlsym(handle, "SACLockScreenImmediate")
        else { throw SystemCommandError.failed }
        typealias LockScreen = @convention(c) () -> Int32
        _ = unsafeBitCast(symbol, to: LockScreen.self)()
    }

    private static func runAppleScript(_ source: String) throws {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            throw SystemCommandError.script(error[NSAppleScript.errorMessage] as? String)
        }
    }
}

enum SystemCommandError: LocalizedError {
    case failed
    case script(String?)

    var errorDescription: String? {
        switch self {
        case .failed: String(localized: "macOS didn't carry out the command.")
        case .script(let message): message ?? String(localized: "macOS didn't carry out the command.")
        }
    }
}
