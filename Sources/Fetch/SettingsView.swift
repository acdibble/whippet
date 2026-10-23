import AppKit
import ServiceManagement
import SwiftUI

/// Owns the single Settings window and brings it to the front, since an accessory app has no app menu to do it.
@MainActor
final class SettingsWindow {
    private let cloudSync: CloudSync
    private let clipboard: ClipboardHistory
    private(set) var window: NSWindow?

    init(cloudSync: CloudSync, clipboard: ClipboardHistory) {
        self.cloudSync = cloudSync
        self.clipboard = clipboard
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // While Fetch is not the active app, ordering front only reorders its own windows, so raise it above other apps too.
        window.orderFrontRegardless()
    }

    /// A full-size, transparent-titlebar window with a toolbar, which lets the split view's sidebar run under the
    /// traffic lights as a floating glass panel. It is a non-activating panel so it can take keyboard focus even when
    /// macOS refuses to activate Fetch, which it does since macOS 14 when the request comes from the search panel.
    private func makeWindow() -> NSWindow {
        let window = SettingsPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let controller = NSHostingController(rootView: SettingsView(cloudSync: cloudSync, clipboard: clipboard))
        controller.sceneBridgingOptions = [.toolbars, .title]
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 760, height: 520))
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbar = NSToolbar()
        window.toolbarStyle = .unified
        window.isFloatingPanel = false
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = false
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}

private final class SettingsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case cloudSync
    case usage
    case about

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .general: "General"
        case .cloudSync: "Cloud Sync"
        case .usage: "Usage"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .cloudSync: "icloud.fill"
        case .usage: "chart.bar.fill"
        case .about: "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: .gray
        case .cloudSync: .blue
        case .usage: .green
        case .about: .gray
        }
    }
}

struct SettingsView: View {
    let cloudSync: CloudSync
    let clipboard: ClipboardHistory
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
                case .cloudSync: CloudSyncPane(cloudSync: cloudSync)
                case .usage: UsagePane(clipboard: clipboard)
                case .about: AboutPane()
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .navigationTitle(Text((selection ?? .general).title))
        }
        .frame(minWidth: 680, minHeight: 440)
        .translucentWindowBackground()
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

    var body: some View {
        Form {
            Section {
                Toggle("Open at Login", isOn: Binding(get: { launchesAtLogin }, set: setLaunchAtLogin))
                LabeledContent("Fetch Hotkey") {
                    KeyChip(text: "⌥ Space")
                }
            }
        }
        .toggleStyle(.switch)
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
        .confirmationDialog("Delete Fetch data from iCloud?", isPresented: $isConfirmingDelete) {
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

/// A key combination drawn as a rounded chip, like a recorded shortcut.
private struct KeyChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }
}

private extension View {
    /// Lets the desktop show through the window behind the panes, where the system supports a material window background.
    @ViewBuilder
    func translucentWindowBackground() -> some View {
        if #available(macOS 15.0, *) {
            containerBackground(.thinMaterial, for: .window)
        } else {
            self
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
