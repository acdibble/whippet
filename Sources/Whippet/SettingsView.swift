import AppKit
import ServiceManagement
import KeyboardShortcuts
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case shortcuts
    case cloudSync
    case usage
    case about

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .general: "General"
        case .shortcuts: "Shortcuts"
        case .cloudSync: "Cloud Sync"
        case .usage: "Usage"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .shortcuts: "command"
        case .cloudSync: "icloud.fill"
        case .usage: "chart.bar.fill"
        case .about: "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: .gray
        case .shortcuts: .purple
        case .cloudSync: .blue
        case .usage: .green
        case .about: .gray
        }
    }
}

struct SettingsView: View {
    static let windowID = "settings"

    let cloudSync: CloudSync
    let clipboard: ClipboardHistory
    let appIndex: AppIndex
    @State private var selection: SettingsPane? = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $selection) { pane in
                Label {
                    Text(pane.title)
                } icon: {
                    PaneIcon(symbol: pane.symbol, tint: pane.tint)
                }
                .tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            Group {
                switch selection ?? .general {
                case .general: GeneralPane()
                case .shortcuts: ShortcutsPane(appIndex: appIndex)
                case .cloudSync: CloudSyncPane(cloudSync: cloudSync)
                case .usage: UsagePane(clipboard: clipboard)
                case .about: AboutPane()
                }
            }
            .formStyle(.grouped)
            .navigationTitle(Text((selection ?? .general).title))
        }
        .frame(minWidth: 680, minHeight: 440)
        .onAppear { NSApp.setActivationPolicy(.regular) }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
    }
}

/// A white symbol on a coloured rounded square, as System Settings and Raycast draw their sidebar icons.
private struct PaneIcon: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct GeneralPane: View {
    @State private var launchesAtLogin = LaunchAtLogin.isEnabled
    @State private var canPaste = Paster.isTrusted
    @State private var language = AppLanguage.current
    @State private var needsRelaunch = false

    var body: some View {
        Form {
            Section {
                Toggle("Open at Login", isOn: Binding(get: { launchesAtLogin }, set: setLaunchAtLogin))
                KeyboardShortcuts.Recorder("Whippet Hotkey", name: .togglePanel)
            }

            Section {
                Picker("Language", selection: $language) {
                    Text("System").tag(String?.none)
                    ForEach(AppLanguage.available, id: \.self) { code in
                        Text(AppLanguage.name(of: code)).tag(Optional(code))
                    }
                }
                .onChange(of: language) { _, newLanguage in
                    AppLanguage.set(newLanguage)
                    needsRelaunch = true
                }
                if needsRelaunch {
                    LabeledContent("Relaunch Whippet to use the new language") {
                        Button("Relaunch", action: AppLanguage.relaunch)
                    }
                }
            }

            Section {
                LabeledContent {
                    if canPaste {
                        Text("Allowed")
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Allow…") {
                            Paster.requestTrust()
                        }
                    }
                } label: {
                    Text("Paste into Apps")
                    Text("Needs Accessibility permission to send ⌘V; without it, Return only copies")
                }
            }
        }
        .toggleStyle(.switch)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            canPaste = Paster.isTrusted
        }
        .onAppear { canPaste = Paster.isTrusted }
    }

    private func setLaunchAtLogin(_ isEnabled: Bool) {
        do {
            try LaunchAtLogin.set(isEnabled)
        } catch {
            NSAlert(error: error).runModal()
        }
        launchesAtLogin = LaunchAtLogin.isEnabled
    }
}

/// A hotkey recorder for each command and installed application; recorded hotkeys are live immediately.
private struct ShortcutsPane: View {
    let appIndex: AppIndex
    @State private var search = ""

    var body: some View {
        Form {
            Section("Commands") {
                ForEach(CommandShortcut.allCases) { command in
                    KeyboardShortcuts.Recorder(for: command.name) {
                        Label(command.title, systemImage: command.symbol)
                    }
                }
            }
            Section("Applications") {
                ForEach(filteredApps) { app in
                    KeyboardShortcuts.Recorder(for: app.shortcutName) {
                        Label {
                            Text(app.name)
                        } icon: {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                                .resizable()
                                .frame(width: 18, height: 18)
                        }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Search applications")
    }

    private var filteredApps: [AppEntry] {
        if search.isEmpty { return appIndex.apps }
        return appIndex.apps.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }
}

private struct CloudSyncPane: View {
    @Bindable var cloudSync: CloudSync
    @State private var isConfirmingDelete = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $cloudSync.isEnabled) {
                    Text("Sync with iCloud")
                    Text("Clipboard history, pins and calculations, across your Macs")
                }
                Toggle(isOn: $cloudSync.includesImages) {
                    Text("Include Images")
                    Text("Copied images and their recognized text")
                }
                .disabled(!cloudSync.isEnabled)
            } footer: {
                Text("Clipboard text and calculations are end-to-end encrypted. Images are stored like other iCloud data, and are end-to-end encrypted only with Advanced Data Protection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Status") {
                LabeledContent("Status", value: cloudSync.statusDescription)
                LabeledContent("Waiting to Upload", value: cloudSync.pendingChanges.formatted())
                HStack {
                    Button("Sync Now") {
                        Task { await cloudSync.syncNow() }
                    }
                    Spacer()
                    Button("Delete iCloud Data…", role: .destructive) {
                        isConfirmingDelete = true
                    }
                }
                .disabled(!cloudSync.isEnabled)
            }
        }
        .toggleStyle(.switch)
        .confirmationDialog("Delete Whippet data from iCloud?", isPresented: $isConfirmingDelete) {
            Button("Delete iCloud Data", role: .destructive) {
                Task { await cloudSync.deleteCloudData() }
            }
        } message: {
            Text("This removes the copy in iCloud and turns sync off. History on this Mac is kept.")
        }
    }
}

private struct AboutPane: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("Developer", value: "Dibble Codes")
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                LabeledContent("Data Folder") {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([ClipboardStore.defaultDirectory])
                    }
                }
            }
        }
    }
}

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Opens Login Items settings when macOS needs the user's approval to finish turning it on.
    static func set(_ isEnabled: Bool) throws {
        let service = SMAppService.mainApp
        if isEnabled {
            try service.register()
            if service.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
            return
        }
        try service.unregister()
    }
}

/// The window's material over the toolbar area, fading out just below it, so content scrolled under the pane title
/// blurs away instead of overlapping it. The system's own scroll edge effect does not appear over a material window.
private struct ToolbarFade: View {
    private static let fadeHeight: CGFloat = 16

    var body: some View {
        GeometryReader { proxy in
            let inset = proxy.safeAreaInsets.top
            Rectangle()
                .fill(.thinMaterial)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: inset / (inset + Self.fadeHeight)),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: inset + Self.fadeHeight)
                .offset(y: -inset)
        }
        .allowsHitTesting(false)
    }
}

/// The app's language, stored as the same per-app preference that System Settings › Language & Region › Applications sets.
enum AppLanguage {
    /// The languages Whippet ships, excluding the base localization.
    static let available = Bundle.main.localizations.filter { $0 != "Base" }.sorted()

    /// The chosen language, or nil to follow the system.
    static var current: String? {
        let domain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
        guard let preferred = (domain?["AppleLanguages"] as? [String])?.first else { return nil }
        return available.first { preferred == $0 || preferred.hasPrefix("\($0)-") }
    }

    /// The language's name in that language, such as فارسی for Farsi.
    static func name(of code: String) -> String {
        let locale = Locale(identifier: code)
        return locale.localizedString(forLanguageCode: code)?.capitalized(with: locale) ?? code
    }

    static func set(_ code: String?) {
        if let code {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
            return
        }
        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
    }

    /// Opens a fresh copy of the app before quitting, since the language is only read at launch.
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
