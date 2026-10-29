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

/// A whippet's head in profile, from the MenuBarIcon asset: a template image that macOS tints to match the menu bar.
enum WhippetIcon {
    static let menuBarImage: NSImage = {
        let template = NSImage(resource: .menuBarIcon)
        #if DEBUG
        // Development builds draw the whippet in construction yellow, to tell them apart from the installed release.
        let image = NSImage(size: template.size, flipped: false) { rect in
            template.draw(in: rect)
            NSColor.systemYellow.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        image.isTemplate = false
        return image
        #else
        return template
        #endif
    }()
}

extension NSApplication {
    /// The standard About panel titled with the full display name instead of the short bundle name.
    func showAboutPanel() {
        activate()
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        orderFrontStandardAboutPanel(options: name.map { [.applicationName: $0] } ?? [:])
    }
}
