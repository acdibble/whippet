import AppKit
import KeyboardShortcuts
import SwiftUI
import UniformTypeIdentifiers
import WhippetCore

/// Settings › Quicklinks: the saved links, with an editor for adding and changing them.
struct QuicklinksPane: View {
    let quicklinks: Quicklinks
    @Bindable var navigation: SettingsNavigation
    @State private var editing: Quicklink?
    @State private var pendingDeletion: Quicklink?

    var body: some View {
        Form {
            Section {
                ForEach(quicklinks.items) { quicklink in
                    LabeledContent {
                        HStack {
                            Button("Edit…") { editing = quicklink }
                            Button("Delete…", role: .destructive) { pendingDeletion = quicklink }
                        }
                    } label: {
                        Label {
                            Text(quicklink.name)
                            Text(quicklink.template)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } icon: {
                            QuicklinkIcon(quicklink: quicklink)
                        }
                    }
                }
                Button("Add Quicklink…") { editing = Self.newQuicklink }
            } footer: {
                Text(
                    "Search for a quicklink in Whippet and press Tab to type the text that replaces {query} in its link."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .sheet(item: $editing) { quicklink in
            QuicklinkEditor(quicklink: quicklink, quicklinks: quicklinks)
        }
        .confirmationDialog(
            "Delete this quicklink?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
        ) {
            Button("Delete", role: .destructive) {
                guard let quicklink = pendingDeletion else { return }
                KeyboardShortcuts.reset(quicklink.shortcutName)
                quicklinks.delete(quicklink)
            }
        } message: {
            Text("It's also removed from your other Macs when iCloud sync is on.")
        }
        .onAppear(perform: openRequestedEditor)
        .onChange(of: navigation.isCreatingQuicklink) { openRequestedEditor() }
    }

    private static var newQuicklink: Quicklink {
        Quicklink(uuid: UUID().uuidString, name: "", keyword: nil, template: "https://")
    }

    /// The Create Quicklink command opens this pane with a new quicklink in the editor.
    private func openRequestedEditor() {
        guard navigation.isCreatingQuicklink else { return }
        navigation.isCreatingQuicklink = false
        editing = Self.newQuicklink
    }
}

private struct QuicklinkIcon: View {
    let quicklink: Quicklink

    var body: some View {
        if let icon = Quicklinks.icon(for: quicklink) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 18, height: 18)
        } else {
            Image(systemName: "link")
        }
    }
}

private struct QuicklinkEditor: View {
    let quicklinks: Quicklinks
    private let uuid: String
    @State private var name: String
    @State private var keyword: String
    @State private var template: String
    @State private var appBundleID: String?
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(quicklink: Quicklink, quicklinks: Quicklinks) {
        self.quicklinks = quicklinks
        uuid = quicklink.uuid
        _name = State(initialValue: quicklink.name)
        _keyword = State(initialValue: quicklink.keyword ?? "")
        _template = State(initialValue: quicklink.template)
        _appBundleID = State(initialValue: quicklink.appBundleID)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Name", text: $name, prompt: Text("Search GitHub"))
                TextField("Keyword", text: $keyword, prompt: Text("Optional, such as gh"))
                TextField("Link", text: $template, prompt: Text("https://github.com/search?q={query}"))
                    .font(.body.monospaced())
                LabeledContent("Open With") {
                    HStack {
                        Text(appName)
                        Button("Choose…", action: chooseApp)
                        if appBundleID != nil {
                            Button("Use Default") { appBundleID = nil }
                        }
                    }
                }
                Section {
                    Text(
                        "Put {query} where the text you type should go. It's encoded for a link; {query:raw} inserts it as typed."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if let problem {
                        Text(problem)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    if let error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(problem != nil)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 480)
    }

    private var trimmedKeyword: String {
        keyword.trimmingCharacters(in: .whitespaces)
    }

    /// Why the quicklink can't be saved yet, or nil when it can.
    private var problem: String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            return String(localized: "Give the quicklink a name.")
        }
        if !QuicklinkTemplate.isValid(template) {
            return String(localized: "The link needs to be a full URL, such as https://example.com/?q={query}.")
        }
        if trimmedKeyword.contains(where: \.isWhitespace) {
            return String(localized: "The keyword can't contain spaces.")
        }
        if !trimmedKeyword.isEmpty, quicklinks.isKeywordTaken(trimmedKeyword, except: uuid) {
            return String(localized: "Another quicklink already uses this keyword.")
        }
        return nil
    }

    private var appName: String {
        guard let appBundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appBundleID) else {
            return String(localized: "Default App")
        }
        return FileManager.default.displayName(atPath: url.path)
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(filePath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            appBundleID = Bundle(url: url)?.bundleIdentifier
        }
    }

    private func save() {
        let quicklink = Quicklink(
            uuid: uuid,
            name: name.trimmingCharacters(in: .whitespaces),
            keyword: trimmedKeyword.isEmpty ? nil : trimmedKeyword,
            template: template.trimmingCharacters(in: .whitespaces),
            appBundleID: appBundleID
        )
        do {
            try quicklinks.save(quicklink)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
