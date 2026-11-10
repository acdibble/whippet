import AppKit
import IOKit.pwr_mgt
import WhippetCore

/// Running a system command, apart from `SystemCommand` itself so its tests needn't build `PermissionGate`.
extension SystemCommand {
    /// Asks first for commands that can't be undone. Whippet is hidden once the panel closes, so it comes forward to
    /// show the alert.
    @MainActor
    func confirmAndRun() {
        if let confirmation {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = confirmation.title
            alert.informativeText = confirmation.message
            alert.addButton(withTitle: confirmation.button)
            alert.addButton(withTitle: String(localized: "Cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        do {
            try run()
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            NSAlert(error: error).runModal()
        }
    }

    @MainActor
    func run() throws {
        switch self {
        case .lockScreen: try Self.lockScreen()
        case .sleep: try Self.sleep()
        case .restart: try Self.ask(.systemEvents, #"tell application "System Events" to restart"#, for: self)
        case .shutDown: try Self.ask(.systemEvents, #"tell application "System Events" to shut down"#, for: self)
        case .emptyTrash: try Self.ask(.finder, #"tell application "Finder" to empty trash"#, for: self)
        case .toggleDarkMode:
            try Self.ask(
                .systemEvents,
                #"tell application "System Events" to tell appearance preferences to set dark mode to not dark mode"#,
                for: self)
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

    /// Asks System Events or Finder to do something, through `PermissionGate`, which checks the command declares it.
    @MainActor
    private static func ask(_ target: AutomationTarget, _ source: String, for command: SystemCommand) throws {
        try PermissionGate.shared.runAppleScript(source, in: target, for: command.moduleRef)
    }
}
