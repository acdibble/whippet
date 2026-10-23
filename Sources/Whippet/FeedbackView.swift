import AppKit
import SwiftUI

/// The window for sending feedback, opened from the menu bar menu, the Send Feedback command and Settings › About.
struct FeedbackView: View {
    static let windowID = "feedback"

    let store: FeedbackStore
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var message = ""
    @State private var email = ""
    @State private var canSend: Bool?
    @State private var isSending = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("What's on your mind?") {
                    TextEditor(text: $message)
                        .font(.body)
                        .frame(minHeight: 140)
                }
                Section {
                    TextField("Email", text: $email, prompt: Text("Optional, if you'd like a reply"))
                }
                Section("Sent with your feedback") {
                    Text(SystemDetails.summary)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if canSend == false {
                    Section {
                        Text("Sign in to iCloud to send feedback from Whippet, or open an issue on GitHub instead.")
                    }
                }
                if let error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Open GitHub Issue…") {
                    GitHubIssue.open(title: "", body: issueBody)
                }
                Spacer()
                Button("Send", action: send)
                    .keyboardShortcut(.defaultAction)
                    .disabled(canSend != true || isSending || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 480)
        .task { canSend = await store.canSend }
        .onAppear { DockIcon.update() }
        .onDisappear { DockIcon.update() }
    }

    private var issueBody: String {
        "\(message)\n\n---\n\(SystemDetails.summary)"
    }

    private func send() {
        isSending = true
        error = nil
        Task {
            do {
                try await store.send(message: message, email: email)
                Toast.shared.show(String(localized: "Thanks for the feedback"), symbol: "checkmark.circle.fill")
                message = ""
                email = ""
                dismissWindow(id: Self.windowID)
            } catch {
                self.error = error.localizedDescription
            }
            isSending = false
        }
    }
}

/// The admin-only Settings pane for reading feedback. CloudKit only returns feedback to accounts with the Admin role.
struct FeedbackAdminPane: View {
    let store: FeedbackStore
    @State private var entries: [FeedbackStore.Entry] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var pendingDeletion: FeedbackStore.Entry?

    var body: some View {
        Form {
            if let error {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
            if entries.isEmpty, !isLoading {
                Section {
                    Text("No feedback yet")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(entries) { entry in
                Section {
                    Text(entry.message)
                        .textSelection(.enabled)
                    LabeledContent("From", value: entry.email ?? String(localized: "No email"))
                    LabeledContent("Sent", value: entry.sentAt.formatted(date: .abbreviated, time: .shortened))
                    Text(entry.details)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    HStack {
                        if entry.isHandled {
                            Label("Issue created", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let email = entry.email {
                            Button("Reply…") { reply(to: email, about: entry) }
                        }
                        Button("Create Issue…") { createIssue(from: entry) }
                        Button("Delete…", role: .destructive) { pendingDeletion = entry }
                    }
                }
            }
        }
        .toolbar {
            Button {
                Task { await load() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .confirmationDialog(
            "Delete this feedback?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
        ) {
            Button("Delete", role: .destructive) {
                guard let entry = pendingDeletion else { return }
                perform { try await store.delete(entry) }
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        do {
            entries = try await store.fetchAll()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    /// The reply email stays out of the issue, since issues are public.
    private func createIssue(from entry: FeedbackStore.Entry) {
        let title = entry.message.split(whereSeparator: \.isNewline).first.map { String($0.prefix(80)) } ?? ""
        GitHubIssue.open(title: title, body: "\(entry.message)\n\n---\nFrom in-app feedback\n\(entry.details)")
        perform { try await store.markHandled(entry) }
    }

    private func reply(to email: String, about entry: FeedbackStore.Entry) {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        let quoted = entry.message.split(separator: "\n", omittingEmptySubsequences: false).map { "> \($0)" }.joined(separator: "\n")
        components.queryItems = [
            URLQueryItem(name: "subject", value: String(localized: "Your Whippet feedback")),
            URLQueryItem(name: "body", value: "\n\n\(quoted)"),
        ]
        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }

    private func perform(_ change: @escaping () async throws -> Void) {
        Task {
            do {
                try await change()
            } catch {
                self.error = error.localizedDescription
            }
            await load()
        }
    }
}

/// Whippet shows a Dock icon only while one of its windows is open, such as Settings or Send Feedback.
enum DockIcon {
    static func update() {
        // Runs on the next pass, so a window that is closing no longer counts as visible.
        DispatchQueue.main.async {
            let hasWindow = NSApp.windows.contains { window in
                window.isVisible && [SettingsView.windowID, FeedbackView.windowID].contains { window.identifier?.rawValue.hasPrefix($0) == true }
            }
            NSApp.setActivationPolicy(hasWindow ? .regular : .accessory)
        }
    }
}
