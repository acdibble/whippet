import AppKit
import KeyboardShortcuts
import SwiftUI

@main
struct WhippetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenu(appDelegate: appDelegate)
        } label: {
            MenuBarLabel(appDelegate: appDelegate)
        }

        Window("Whippet Settings", id: SettingsView.windowID) {
            SettingsView(
                cloudSync: appDelegate.cloudSync,
                clipboard: appDelegate.clipboard,
                appIndex: appDelegate.appIndex,
                caffeine: appDelegate.caffeine,
                timers: appDelegate.timers,
                feedbackStore: appDelegate.feedbackStore,
                navigation: appDelegate.settingsNavigation,
                updater: appDelegate.updater,
                quicklinks: appDelegate.quicklinks
            )
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 760, height: 520)
        .defaultLaunchBehavior(.suppressed)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Whippet") { NSApp.showAboutPanel() }
                Button("Check for Updates…") { appDelegate.updater.checkForUpdates() }
                    .disabled(!appDelegate.updater.canCheckForUpdates)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { appDelegate.showSettings() }
                    .keyboardShortcut(",")
            }
            CommandGroup(replacing: .appTermination) {
                CloseWindowButton()
            }
        }

        Window("Send Feedback", id: FeedbackView.windowID) {
            FeedbackView(store: appDelegate.feedbackStore)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }
}

/// The app menu only exists while one of Whippet's windows is open, so ⌘Q there closes that window and leaves Whippet
/// running in the menu bar.
private struct CloseWindowButton: View {
    var body: some View {
        Button("Close Window") { NSApp.keyWindow?.performClose(nil) }
            .keyboardShortcut("q")
    }
}

/// The menu bar icon; it also hands SwiftUI's `openWindow` to the app delegate, since the label is always on screen.
private struct MenuBarLabel: View {
    let appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(nsImage: WhippetIcon.menuBarImage)
            .onAppear {
                appDelegate.openSettingsWindow = { openWindow(id: SettingsView.windowID) }
                appDelegate.openFeedbackWindow = { openWindow(id: FeedbackView.windowID) }
            }
    }
}

private struct MenuBarMenu: View {
    let appDelegate: AppDelegate

    var body: some View {
        Button("Open Whippet", systemImage: "magnifyingglass") { appDelegate.showPanel() }
            // Follows the hotkey set in Settings; the global hotkey itself opens the panel.
            .globalKeyboardShortcut(.togglePanel)
        Divider()
        Button("About Whippet", systemImage: "info.circle") { NSApp.showAboutPanel() }
        Button("Check for Updates…", systemImage: "arrow.down.circle") { appDelegate.updater.checkForUpdates() }
            .disabled(!appDelegate.updater.canCheckForUpdates)
        Button("Settings…", systemImage: "gearshape") { appDelegate.showSettings() }
            .keyboardShortcut(",")
        Button("Send Feedback…", systemImage: "bubble.left") { appDelegate.showFeedback() }
        Divider()
        Button("Show Data Folder", systemImage: "folder") {
            NSWorkspace.shared.activateFileViewerSelecting([ClipboardStore.defaultDirectory])
        }
        Divider()
        Button("Quit Whippet") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// A whippet's head in profile, drawn as a template image since SF Symbols has no whippet; macOS tints it to match the menu bar.
enum WhippetIcon {
    static let menuBarImage: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.addPath(headPath())
            context.setLineWidth(1.4)
            context.setLineJoin(.round)
            context.setLineCap(.round)
            context.setStrokeColor(color.cgColor)
            context.strokePath()
            context.setFillColor(color.cgColor)
            context.fillEllipse(in: CGRect(x: 7.1, y: 8.6, width: 1.3, height: 1.3))
            return true
        }
        image.isTemplate = isTemplate
        return image
    }()

    /// Development builds draw the whippet in construction yellow, to tell them apart from the installed release, which
    /// uses a template image that macOS tints to match the menu bar.
    #if DEBUG
    private static let color = NSColor.systemYellow
    private static let isTemplate = false
    #else
    private static let color = NSColor.black
    private static let isTemplate = true
    #endif

    /// Facing left in an 18-point canvas: the head and neck outline, the underside of the jaw and neck, and a rose ear.
    private static func headPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 1.7, y: 7.4))
        path.addCurve(to: CGPoint(x: 1.5, y: 9.0), control1: CGPoint(x: 1.0, y: 7.7), control2: CGPoint(x: 1.0, y: 8.7))
        path.addCurve(to: CGPoint(x: 6.8, y: 10.6), control1: CGPoint(x: 3.4, y: 9.6), control2: CGPoint(x: 5.4, y: 10.0))
        path.addCurve(to: CGPoint(x: 12.0, y: 12.0), control1: CGPoint(x: 8.2, y: 12.0), control2: CGPoint(x: 10.6, y: 12.6))
        path.addCurve(to: CGPoint(x: 15.8, y: 3.0), control1: CGPoint(x: 14.2, y: 10.4), control2: CGPoint(x: 15.4, y: 6.6))

        path.move(to: CGPoint(x: 1.7, y: 7.4))
        path.addCurve(to: CGPoint(x: 8.8, y: 6.2), control1: CGPoint(x: 4.0, y: 6.8), control2: CGPoint(x: 6.6, y: 6.4))
        path.addCurve(to: CGPoint(x: 10.8, y: 3.0), control1: CGPoint(x: 10.0, y: 5.4), control2: CGPoint(x: 10.6, y: 4.2))

        path.move(to: CGPoint(x: 10.0, y: 12.2))
        path.addCurve(to: CGPoint(x: 14.6, y: 13.6), control1: CGPoint(x: 11.4, y: 14.0), control2: CGPoint(x: 13.4, y: 14.4))
        path.addCurve(to: CGPoint(x: 12.6, y: 11.2), control1: CGPoint(x: 14.4, y: 12.6), control2: CGPoint(x: 13.4, y: 11.8))
        return path
    }
}

extension NSApplication {
    /// The standard About panel titled with the full display name instead of the short bundle name.
    func showAboutPanel() {
        activate()
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        orderFrontStandardAboutPanel(options: name.map { [.applicationName: $0] } ?? [:])
    }
}
