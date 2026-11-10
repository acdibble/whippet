import AppKit
import SwiftUI
import WhippetCore

/// Installed extensions: turning each on, which approves what its manifest asks for, its preferences, and its log.
struct ExtensionsPane: View {
    let extensions: ExtensionManager
    @State private var installError: String?
    @State private var pendingApproval: InstalledExtension?
    @State private var shownLog: InstalledExtension?

    var body: some View {
        Form {
            Section {
                HStack {
                    Button("Install Extension…", action: chooseExtension)
                    Button("Open Extensions Folder") {
                        try? FileManager.default.createDirectory(
                            at: ExtensionManager.directory, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(ExtensionManager.directory)
                    }
                }
            } footer: {
                Text(
                    "An extension is a folder with a manifest.json and a built index.js. Extensions in the Extensions folder reload as they change."
                )
                .foregroundStyle(.secondary)
            }

            ForEach(extensions.installed) { installed in
                ExtensionSection(
                    installed: installed, extensions: extensions,
                    enable: { requestEnable(installed) },
                    showLog: { shownLog = installed })
            }

            if !extensions.problems.isEmpty {
                Section("Couldn't Load") {
                    ForEach(extensions.problems) { problem in
                        LabeledContent(problem.folder) {
                            Text(problem.message)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }
        }
        .overlay {
            if extensions.installed.isEmpty, extensions.problems.isEmpty {
                ContentUnavailableView(
                    "No Extensions", systemImage: "puzzlepiece.extension",
                    description: Text("Install an extension to add its commands to Whippet."))
            }
        }
        .alert(
            "Couldn't Install the Extension",
            isPresented: Binding(get: { installError != nil }, set: { _ in installError = nil })
        ) {
            Button("OK") {}
        } message: {
            Text(installError ?? "")
        }
        .alert(
            approvalTitle, isPresented: Binding(get: { pendingApproval != nil }, set: { _ in pendingApproval = nil }),
            presenting: pendingApproval
        ) { installed in
            Button("Turn On") { extensions.enable(installed) }
            Button("Cancel", role: .cancel) {}
        } message: { installed in
            Text(installed.manifest.permissions.descriptions.map { "• \($0)" }.joined(separator: "\n"))
        }
        .sheet(item: $shownLog) { installed in
            ExtensionLogView(installed: installed, extensions: extensions)
        }
    }

    private var approvalTitle: String {
        guard let pendingApproval else { return "" }
        return String(localized: "Allow “\(pendingApproval.manifest.name)” to:")
    }

    /// Asks before granting any permission. An extension that asks for none turns on straight away.
    private func requestEnable(_ installed: InstalledExtension) {
        if installed.manifest.permissions.isEmpty {
            extensions.enable(installed)
        } else {
            pendingApproval = installed
        }
    }

    private func chooseExtension() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Install")
        panel.message = String(localized: "Choose an extension's folder, with its manifest.json and index.js.")
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        do {
            requestEnable(try extensions.install(from: folder))
        } catch {
            installError = error.localizedDescription
        }
    }
}

private struct ExtensionSection: View {
    let installed: InstalledExtension
    let extensions: ExtensionManager
    let enable: () -> Void
    let showLog: () -> Void

    var body: some View {
        let manifest = installed.manifest
        let status = extensions.status(of: installed)
        Section {
            HStack(spacing: 12) {
                ExtensionIcon(name: manifest.icon, directory: installed.directory)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(manifest.name)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(
                    "Enabled",
                    isOn: Binding(
                        get: { status == .enabled },
                        set: { isOn in isOn ? enable() : extensions.disable(installed) })
                )
                .labelsHidden()
                .toggleStyle(.switch)
            }
            if let description = manifest.description {
                Text(description)
                    .foregroundStyle(.secondary)
            }
            if status == .needsApproval {
                Label(
                    "This version asks for more access. Turn it on again to allow it.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
            }
            LabeledContent("Commands") {
                Text(manifest.commands.map(\.title).formatted(.list(type: .and)))
                    .multilineTextAlignment(.trailing)
            }
            if !manifest.permissions.isEmpty {
                LabeledContent("Access") {
                    Text(manifest.permissions.descriptions.joined(separator: "\n"))
                        .multilineTextAlignment(.trailing)
                }
            }
            ForEach(manifest.preferences, id: \.name) { preference in
                PreferenceField(preference: preference, installed: installed, extensions: extensions)
            }
            HStack {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([installed.directory])
                }
                Button("View Log", action: showLog)
                Spacer()
                Button("Uninstall", role: .destructive) { extensions.uninstall(installed) }
            }
        }
    }

    private var subtitle: String {
        [installed.manifest.version, installed.manifest.author].compactMap { $0 }.joined(separator: " · ")
    }
}

/// One of the preferences an extension declares. Secrets are kept in the Keychain and saved as they're typed.
private struct PreferenceField: View {
    let preference: ExtensionPreference
    let installed: InstalledExtension
    let extensions: ExtensionManager

    var body: some View {
        // Read through the revision, since secrets live outside Observation, in the Keychain.
        let _ = extensions.preferencesRevision
        let value = extensions.preferenceValues(for: installed)[preference.name]
        Group {
            switch preference.type {
            case .checkbox:
                Toggle(
                    preference.title,
                    isOn: Binding(
                        get: { value?.bool ?? false },
                        set: { extensions.setPreference(.bool($0), named: preference.name, for: installed) }))
            case .secret:
                SecureField(preference.title, text: text(value), prompt: prompt)
            case .text:
                TextField(preference.title, text: text(value), prompt: prompt)
            }
        }
        .help(preference.description ?? "")
    }

    private var prompt: Text? {
        if let placeholder = preference.placeholder { return Text(placeholder) }
        return preference.required ? Text("Required") : nil
    }

    private func text(_ value: JSONValue?) -> Binding<String> {
        Binding(
            get: { value?.string ?? "" },
            set: { extensions.setPreference(.string($0), named: preference.name, for: installed) })
    }
}

/// What an extension logged with `console`, and its errors, since Whippet started.
private struct ExtensionLogView: View {
    let installed: InstalledExtension
    let extensions: ExtensionManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let lines = extensions.logs[installed.id] ?? []
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(lines) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(line.date.formatted(date: .omitted, time: .standard))
                                .foregroundStyle(.secondary)
                            Text(line.message)
                                .foregroundStyle(
                                    line.level == "error" ? .red : line.level == "warn" ? .orange : .primary)
                        }
                    }
                }
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            .overlay {
                if lines.isEmpty {
                    Text("Nothing logged yet")
                        .foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack {
                Button("Clear") { extensions.clearLog(for: installed.id) }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 620, height: 400)
        .navigationTitle(Text(installed.manifest.name))
    }
}
