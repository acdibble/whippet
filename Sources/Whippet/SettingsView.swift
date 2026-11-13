import AppKit
import CryptoKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI
import WhippetCore

/// The pane Settings shows, shared so commands can open Settings on a particular pane.
@MainActor
@Observable
final class SettingsNavigation {
    var pane: SettingsPane? = .general
    /// Set by the Create Quicklink command, so the Quicklinks pane opens its editor.
    var isCreatingQuicklink = false
    /// Counts the times Settings has closed. The window's content is identified by it, so every pane's own state,
    /// such as a search, a pushed page or an open editor, starts afresh the next time Settings opens.
    private(set) var session = 0

    /// Puts Settings back as it first opens, on General, once its window closes.
    func reset() {
        pane = .general
        isCreatingQuicklink = false
        session += 1
    }
}

struct SettingsView: View {
    static let windowID = "settings"

    let cloudSync: CloudSync
    let clipboard: ClipboardHistory
    let feedbackStore: FeedbackStore
    @Bindable var navigation: SettingsNavigation
    let extensions: ExtensionManager
    let featureFlags: FeatureFlags
    let moduleSettings: ModuleSettings
    /// Where the modules are. Each supplies its own pane and what it adds to the others, so Settings needs none of
    /// their services.
    let launcher: LauncherModel
    /// The Developer pane is for accounts with the CloudKit Admin role, and always shows in development builds.
    @State private var hasAdminRole = false

    var body: some View {
        let modulePanes = modulePanes
        NavigationSplitView {
            List(selection: $navigation.pane) {
                ForEach([SettingsPane.general, .commands, .shortcuts]) { row($0) }
                ForEach(modulePanes.filter { !$0.pane.isAdminOnly }, id: \.id) { modulePane in
                    row(.module(modulePane.id), pane: modulePane.pane)
                }
                row(.usage)
                ForEach(modulePanes.filter(\.pane.isAdminOnly), id: \.id) { modulePane in
                    row(.module(modulePane.id), pane: modulePane.pane)
                }
                if isDeveloperShown {
                    row(.developer, isAdminOnly: true)
                }
                row(.about)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            Group {
                switch navigation.pane ?? .general {
                case .module(let id):
                    if let pane = modulePanes.first(where: { $0.id == id })?.pane {
                        pane.view()
                    }
                case .general:
                    GeneralPane(
                        featureFlags: featureFlags, modules: moduleSettings, launcherModules: launcher.launcherModules)
                case .commands:
                    CommandsPane(
                        modules: moduleSettings, launcherModules: launcher.launcherModules, extensions: extensions,
                        navigation: navigation, showsAdminCommands: hasAdminRole)
                case .shortcuts:
                    ShortcutsPane(modules: moduleSettings, launcherModules: launcher.launcherModules)
                case .usage: UsagePane(clipboard: clipboard)
                case .developer: DeveloperPane(cloudSync: cloudSync)
                case .about: AboutPane(clipboard: clipboard)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(title(of: navigation.pane ?? .general, in: modulePanes))
        }
        .background(InitialFocusClearer())
        .id(navigation.session)
        .frame(minWidth: 680, minHeight: 440)
        // Turning off a beta feature or a module hides its pane, so the window doesn't stay on it.
        .onChange(of: featureFlags.enabled) { leaveHiddenPane() }
        .onChange(of: moduleSettings.revision) { leaveHiddenPane() }
        .onAppear { DockIcon.update() }
        .onDisappear {
            DockIcon.update()
            navigation.reset()
        }
        .task { hasAdminRole = await feedbackStore.hasAdminRole }
    }

    private func row(_ pane: SettingsPane, pane modulePane: ModuleSettingsPane? = nil, isAdminOnly: Bool = false)
        -> some View
    {
        Label {
            HStack {
                Text(modulePane?.title ?? pane.title)
                if isAdminOnly || modulePane?.isAdminOnly == true {
                    Spacer()
                    AdminBadge()
                }
            }
        } icon: {
            PaneIcon(symbol: modulePane?.symbol ?? pane.symbol, tint: modulePane?.tint ?? pane.tint)
        }
        .tag(pane)
    }

    /// The panes of the modules that are on, each by its module's id.
    private var modulePanes: [(id: String, pane: ModuleSettingsPane)] {
        launcher.launcherModules.compactMap { module in
            guard let pane = module.settingsPane, moduleSettings.isEnabled(pane.ref ?? module.manifest.ref),
                pane.isShown()
            else { return nil }
            return (module.id, pane)
        }
    }

    private func title(of pane: SettingsPane, in modulePanes: [(id: String, pane: ModuleSettingsPane)]) -> String {
        guard case .module(let id) = pane else { return pane.title }
        return modulePanes.first { $0.id == id }?.pane.title ?? ""
    }

    private var isDeveloperShown: Bool {
        #if DEBUG
            true
        #else
            hasAdminRole
        #endif
    }

    private func leaveHiddenPane() {
        switch navigation.pane {
        case .module(let id)? where !modulePanes.contains(where: { $0.id == id }):
            navigation.pane = .general
        case .developer? where !isDeveloperShown:
            navigation.pane = .general
        default:
            break
        }
    }
}

/// Leaves nothing focused when Settings opens. The window would otherwise give the keyboard to the pane's first
/// control, so General could open with the Whippet Hotkey recorder waiting for a shortcut and the next key pressed
/// would replace the hotkey. It acts once, the first time its window becomes key, so coming back to Settings from
/// another app keeps the focus where it was; `SettingsView` makes a new one each time Settings closes.
private struct InitialFocusClearer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ClearingView() }

    func updateNSView(_ view: NSView, context: Context) {}

    private final class ClearingView: NSView {
        private var observer: (any NSObjectProtocol)?
        private var hasCleared = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopObserving()
            guard let window, !hasCleared else { return }
            if window.isKeyWindow {
                clear(window)
            } else {
                observer = NotificationCenter.default.addObserver(
                    forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.clear(window) }
                }
            }
        }

        /// Waits a turn of the run loop, since the window picks its first responder as it becomes key.
        private func clear(_ window: NSWindow) {
            stopObserving()
            hasCleared = true
            DispatchQueue.main.async { window.makeFirstResponder(nil) }
        }

        private func stopObserving() {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
            observer = nil
        }
    }
}

/// A white symbol on a coloured rounded square, as System Settings draws its sidebar icons.
struct PaneIcon: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: size * 0.27))
    }
}

private struct GeneralPane: View {
    let featureFlags: FeatureFlags
    let modules: ModuleSettings
    let launcherModules: [any LauncherModule]
    @State private var launchesAtLogin = LaunchAtLogin.isEnabled
    @State private var canPaste = Paster.isTrusted
    @State private var canCaptureScreen = ScreenCapture.isAllowed
    @AppStorage(TextRecognition.keepsLineBreaksKey) private var keepsLineBreaks = true
    @State private var language = AppLanguage.current
    @State private var appearance = AppAppearance.current
    @State private var needsRelaunch = false

    var body: some View {
        Form {
            Section {
                Toggle("Open at Login", isOn: Binding(get: { launchesAtLogin }, set: { setLaunchAtLogin($0) }))
                KeyboardShortcuts.Recorder("Whippet Hotkey", name: .togglePanel)
                ForEach(moduleRows, id: \.id) { $0.view() }
            }

            Section {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .onChange(of: appearance) { _, newAppearance in newAppearance.apply() }
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
                    Text("Paste and Move Windows")
                    Text(
                        "Needs Accessibility permission to send ⌘V and move other apps' windows; without it, Return only copies"
                    )
                }
                LabeledContent {
                    if canCaptureScreen {
                        Text("Allowed")
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Allow…") {
                            ScreenCapture.requestAccess()
                        }
                    }
                } label: {
                    Text("Capture Text")
                    Text("Needs Screen Recording permission to read text on the screen")
                }
                Toggle(isOn: $keepsLineBreaks) {
                    Text("Keep Line Breaks")
                    Text("In text copied from the screen or an image")
                }
            }

            ForEach(moduleSections, id: \.id) { $0.view() }

            Section {
                ForEach(FeatureFlag.allCases) { flag in
                    Toggle(
                        isOn: Binding(
                            get: { featureFlags.isEnabled(flag) }, set: { featureFlags.setEnabled(flag, $0) })
                    ) {
                        Text(flag.title)
                        Text(flag.summary)
                    }
                }
            } header: {
                Text("Beta Features")
            } footer: {
                Text("Features still being tried out. They may change or go away.")
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            canPaste = Paster.isTrusted
            canCaptureScreen = ScreenCapture.isAllowed
        }
        .onAppear {
            canPaste = Paster.isTrusted
            canCaptureScreen = ScreenCapture.isAllowed
        }
    }

    /// The switches of the modules that are on, in the order their panes are listed.
    private var moduleRows: [(id: String, view: () -> AnyView)] {
        launcherModules.compactMap { module in
            guard modules.isEnabled(module.manifest.ref), let rows = module.generalSettings?.rows else { return nil }
            return (module.id, rows)
        }
    }

    /// The sections of the modules that are on, in the order Settings › Commands lists modules.
    private var moduleSections: [(id: String, view: () -> AnyView)] {
        ModuleRegistry.all.compactMap { manifest in
            guard modules.isEnabled(manifest.ref),
                let section = launcherModules.first(where: { $0.id == manifest.id })?.generalSettings?.section
            else { return nil }
            return (manifest.id, section)
        }
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

/// A hotkey recorder for each command, by module, and each quicklink and installed application; recorded hotkeys are live
/// immediately. The search filters every list, and a list with nothing matching is left out.
private struct ShortcutsPane: View {
    let modules: ModuleSettings
    let launcherModules: [any LauncherModule]
    @State private var search = ""

    var body: some View {
        // Every command can have a hotkey, listed under its module. What's turned off in Settings › Commands isn't
        // listed.
        let sections = ModuleRegistry.all.map { manifest in
            (
                manifest,
                manifest.commands.filter { command in
                    !command.isAdminOnly && modules.isEnabled(manifest.ref(command.id)) && matches(command.title)
                }
            )
        }.filter { !$0.1.isEmpty }
        // Then the rows that come and go, by module in the order the search lists them: quicklinks, extensions' commands
        // and apps.
        let dynamic = launcherModules.map { module in
            (
                module.manifest,
                module.dynamicRows.filter { row in
                    modules.isEnabled(row.ref) && (matches(row.title) || row.searchText.map(matches) == true)
                }
            )
        }.filter { !$0.1.isEmpty }

        Form {
            ForEach(sections, id: \.0.id) { manifest, commands in
                Section(manifest.title) {
                    ForEach(commands) { command in
                        KeyboardShortcuts.Recorder(for: KeyboardShortcuts.Name(for: manifest.ref(command.id))) {
                            Label(command.title, systemImage: command.icon)
                        }
                    }
                }
            }
            ForEach(dynamic, id: \.0.id) { manifest, rows in
                Section(manifest.title) {
                    ForEach(rows) { row in
                        KeyboardShortcuts.Recorder(for: row.hotkey) { label(for: row) }
                    }
                }
            }
        }
        .overlay {
            if sections.isEmpty, dynamic.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .searchable(text: $search, prompt: "Search shortcuts")
    }

    @ViewBuilder
    private func label(for row: DynamicRow) -> some View {
        if case .symbol(let name) = row.icon {
            Label(row.title, systemImage: name)
        } else {
            Label {
                Text(row.title)
            } icon: {
                row.icon.view.frame(width: 18, height: 18)
            }
        }
    }

    private func matches(_ name: String) -> Bool {
        search.isEmpty || name.localizedCaseInsensitiveContains(search)
    }
}

/// Details for developing and administering Whippet, such as the CloudKit user record to give the Admin role.
private struct DeveloperPane: View {
    let cloudSync: CloudSync
    @State private var userRecordName: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("iCloud User") {
                    HStack {
                        Text(userRecordName ?? String(localized: "Not signed in"))
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let userRecordName {
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(userRecordName, forType: .string)
                            }
                        }
                    }
                }
            } footer: {
                Text(
                    "The CloudKit user record for the Apple Account signed into iCloud on this Mac. Give it a role, such as Admin, in the CloudKit Console."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            FeedbackKeySection()
        }
        .task { userRecordName = await cloudSync.userRecordName() }
    }
}

/// Creates, backs up and restores the admin key that feedback is sealed to.
private struct FeedbackKeySection: View {
    @State private var storedKey = FeedbackKey.storedPrivateKey
    @State private var isConfirmingCreate = false
    @State private var isImporting = false
    @State private var importedKey = ""

    var body: some View {
        Section {
            LabeledContent("Feedback Key", value: status)
            if let storedKey {
                LabeledContent("Public Key") {
                    HStack {
                        Text(storedKey.publicKey.rawRepresentation.base64EncodedString())
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Copy") {
                            copy(storedKey.publicKey.rawRepresentation.base64EncodedString(), concealed: false)
                        }
                    }
                }
            }
            HStack {
                Button("Create Key…") {
                    if storedKey == nil { create() } else { isConfirmingCreate = true }
                }
                Button("Import Key…") { isImporting = true }
                Spacer()
                if let storedKey {
                    Button("Copy Private Key") {
                        copy(storedKey.rawRepresentation.base64EncodedString(), concealed: true)
                    }
                }
            }
        } header: {
            Text("Feedback")
        } footer: {
            Text(
                "Feedback is sealed to this key. Its public key goes in WhippetFeedbackPublicKey in project.yml. The private key syncs through iCloud Keychain; back it up too, since feedback sealed to a lost key can't be read."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .confirmationDialog("Replace the feedback key?", isPresented: $isConfirmingCreate) {
            Button("Replace Key", role: .destructive, action: create)
        } message: {
            Text("Feedback sealed to the current key can't be read without it.")
        }
        .alert("Import Feedback Key", isPresented: $isImporting) {
            SecureField("Private key", text: $importedKey)
            Button("Import", action: importKey)
            Button("Cancel", role: .cancel) { importedKey = "" }
        } message: {
            Text("Paste the private key from your backup.")
        }
    }

    private var status: String {
        guard storedKey != nil else { return String(localized: "Not on this Mac") }
        return FeedbackKey.matchingPrivateKey == nil
            ? String(localized: "On this Mac, but this version uses a different key")
            : String(localized: "On this Mac")
    }

    private func create() {
        do {
            storedKey = try FeedbackKey.create()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func importKey() {
        defer { importedKey = "" }
        do {
            guard let data = Data(base64Encoded: importedKey.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw CocoaError(.coderInvalidValue)
            }
            let key = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
            try FeedbackKey.store(key)
            storedKey = key
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    /// The private key is marked concealed, so clipboard managers, Whippet's own history included, don't keep it.
    private func copy(_ text: String, concealed: Bool) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if concealed {
            pasteboard.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        }
        pasteboard.setString(text, forType: .string)
    }
}

private struct AboutPane: View {
    let clipboard: ClipboardHistory
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
            Section {
                LabeledContent("Developer", value: "Dibble Codes")
                LabeledContent(
                    "Version",
                    value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                LabeledContent("Data Folder") {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([ClipboardStore.defaultDirectory])
                    }
                }
                LabeledContent("Feedback") {
                    Button("Send Feedback…") {
                        openWindow(id: FeedbackView.windowID)
                    }
                }
                LabeledContent("Share with a Friend") {
                    Button("Copy Download Link") {
                        ShareLink.copy(using: clipboard)
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

/// Light or dark for every Whippet window and panel, or the system's choice.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: Self { self }

    static var current: AppAppearance {
        AppAppearance(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .system
    }

    var title: String {
        switch self {
        case .system: String(localized: "System")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }

    /// Saves the choice and applies it to the whole app at once.
    @MainActor
    func apply() {
        UserDefaults.standard.set(rawValue, forKey: "appearance")
        NSApp.appearance =
            switch self {
            case .system: nil
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
            }
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
