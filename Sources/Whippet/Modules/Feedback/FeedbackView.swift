import AppKit
import CloudKit
import SwiftUI
import UniformTypeIdentifiers

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
    @State private var images: [AttachedImage] = []
    @State private var isChoosingImages = false
    @State private var pasteMonitor: Any?

    private struct AttachedImage: Identifiable {
        let id = UUID()
        let data: Data
        let thumbnail: CGImage
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("What's on your mind?") {
                    TextEditor(text: $message)
                        .font(.body)
                        .frame(minHeight: 140)
                }
                imagesSection
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
            // Sized to its sections, so the window grows with them instead of scrolling them under the buttons.
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Open GitHub Issue…") {
                    GitHubIssue.open(title: "", body: issueBody)
                }
                Spacer()
                Button("Send", action: send)
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        canSend != true || isSending || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 480)
        .onDrop(of: [.fileURL, .image], isTargeted: nil, perform: drop)
        .fileImporter(isPresented: $isChoosingImages, allowedContentTypes: [.image], allowsMultipleSelection: true) {
            result in
            guard case .success(let urls) = result else { return }
            attach(
                urls.compactMap { url in
                    let isAccessing = url.startAccessingSecurityScopedResource()
                    defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }
                    return try? Data(contentsOf: url)
                })
        }
        .task { canSend = await store.canSend }
        .onAppear {
            DockIcon.update()
            startCatchingPastedImages()
        }
        // The window keeps its state while closed, so closing it starts the next feedback afresh.
        .onDisappear {
            DockIcon.update()
            pasteMonitor.map(NSEvent.removeMonitor)
            pasteMonitor = nil
            message = ""
            email = ""
            images = []
            error = nil
        }
    }

    private var imagesSection: some View {
        Section {
            if !images.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(images) { image in
                            Image(decorative: image.thumbnail, scale: 1)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 64, height: 64)
                                .clipShape(.rect(cornerRadius: 6))
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        images.removeAll { $0.id == image.id }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.6))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Remove Image")
                                    .padding(2)
                                }
                        }
                    }
                }
                .scrollIndicators(.never)
            }
            HStack {
                Text(images.isEmpty ? "Paste or drop screenshots here" : "\(images.count) of \(FeedbackImage.limit)")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Add Images…") { isChoosingImages = true }
                    .disabled(images.count >= FeedbackImage.limit)
            }
        } header: {
            Text("Images")
        } footer: {
            if !images.isEmpty {
                Text("Images are sent without their location or other details from the camera.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// GitHub can't take images in a link, so the issue asks for them to be dragged in.
    private var issueBody: String {
        let note = images.isEmpty ? "" : "\n\n(Drag the \(images.count) attached images here.)"
        return "\(message)\(note)\n\n---\n\(SystemDetails.summary)"
    }

    /// The text box only takes text, so ⌘V with an image on the pasteboard attaches it instead.
    private func startCatchingPastedImages() {
        guard pasteMonitor == nil else { return }
        pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard
                event.window?.identifier?.rawValue.hasPrefix(Self.windowID) == true,
                event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                event.charactersIgnoringModifiers == "v",
                let pasted = FeedbackImage.images(on: .general)
            else { return event }
            attach(pasted)
            return nil
        }
    }

    private func drop(_ providers: [NSItemProvider]) -> Bool {
        let providers = providers.filter {
            $0.canLoadObject(ofClass: URL.self) || $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
        }
        guard !providers.isEmpty else { return false }
        Task {
            var dropped: [Data] = []
            for provider in providers {
                if let data = await Self.imageData(from: provider) { dropped.append(data) }
            }
            attach(dropped)
        }
        return true
    }

    private static func imageData(from provider: NSItemProvider) async -> Data? {
        if provider.canLoadObject(ofClass: URL.self) {
            let url = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
            }
            guard let url, url.isFileURL, UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
            else { return nil }
            return try? Data(contentsOf: url)
        }
        return await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    /// Strips metadata off the main thread, then adds what fits under the limit, beeping for anything left over or
    /// unreadable.
    private func attach(_ datas: [Data]) {
        guard !datas.isEmpty else { return }
        Task {
            let prepared = await Task.detached(priority: .userInitiated) {
                datas.map { data -> (Data, CGImage)? in
                    guard
                        let image = FeedbackImage.prepare(data),
                        let thumbnail = FeedbackImage.thumbnail(of: image, maxPixelSize: 128)
                    else { return nil }
                    return (image, thumbnail)
                }
            }.value
            let room = FeedbackImage.limit - images.count
            let readable = prepared.compactMap { $0 }
            images += readable.prefix(max(0, room)).map { AttachedImage(data: $0.0, thumbnail: $0.1) }
            if readable.count != datas.count || readable.count > room {
                NSSound.beep()
            }
        }
    }

    private func send() {
        isSending = true
        error = nil
        Task {
            do {
                try await store.send(message: message, email: email, images: images.map(\.data))
                Toast.shared.show(String(localized: "Thanks for the feedback"), symbol: "checkmark.circle.fill")
                message = ""
                email = ""
                images = []
                dismissWindow(id: Self.windowID)
            } catch {
                self.error = error.localizedDescription
            }
            isSending = false
        }
    }
}

/// The admin-only Settings pane for reading feedback, a page at a time. CloudKit only returns feedback to accounts with
/// the Admin role, and only the admin's key opens it.
struct FeedbackAdminPane: View {
    let store: FeedbackStore
    @State private var entries: [FeedbackStore.Entry] = []
    @State private var cursor: CKQueryOperation.Cursor?
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
                    if entry.imageCount > 0 {
                        FeedbackImagesRow(store: store, entry: entry)
                    }
                    HStack {
                        if entry.isHandled {
                            Label("Handled", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let email = entry.email {
                            Button("Reply…") { reply(to: email, about: entry) }
                        }
                        Button("Create Issue…") { createIssue(from: entry) }
                        Button(entry.isHandled ? "Mark as Not Handled" : "Mark as Handled") {
                            perform { try await store.setHandled(!entry.isHandled, for: entry) }
                        }
                        Button("Delete…", role: .destructive) { pendingDeletion = entry }
                    }
                }
            }
            if cursor != nil {
                Section {
                    Button("Load More") {
                        Task { await loadNextPage() }
                    }
                    .disabled(isLoading)
                }
            }
        }
        .toolbar {
            Button {
                Task { await reload() }
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
        .task { await reload() }
    }

    private func reload() async {
        await load { try await store.fetchPage() }
    }

    private func loadNextPage() async {
        guard let cursor else { return }
        await load(appending: true) { try await store.fetchPage(after: cursor) }
    }

    private func load(appending: Bool = false, _ fetch: () async throws -> FeedbackStore.Page) async {
        isLoading = true
        do {
            let page = try await fetch()
            entries = appending ? entries + page.entries : page.entries
            cursor = page.cursor
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    /// The reply email stays out of the issue, since issues are public. Opening the issue page doesn't mean it was
    /// submitted, so marking the feedback handled is a separate step.
    private func createIssue(from entry: FeedbackStore.Entry) {
        let title = entry.message.split(whereSeparator: \.isNewline).first.map { String($0.prefix(80)) } ?? ""
        let note = entry.imageCount > 0 ? "\n\n(\(entry.imageCount) images attached in Whippet.)" : ""
        GitHubIssue.open(title: title, body: "\(entry.message)\(note)\n\n---\nFrom in-app feedback\n\(entry.details)")
    }

    private func reply(to email: String, about entry: FeedbackStore.Entry) {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        let quoted = entry.message.split(separator: "\n", omittingEmptySubsequences: false).map { "> \($0)" }.joined(
            separator: "\n")
        components.queryItems = [
            URLQueryItem(name: "subject", value: String(localized: "Your Whippet feedback")),
            URLQueryItem(name: "body", value: "\n\n\(quoted)"),
        ]
        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }

    /// Runs a change, then reloads from the first page so the list matches CloudKit.
    private func perform(_ change: @escaping () async throws -> Void) {
        Task {
            do {
                try await change()
            } catch {
                self.error = error.localizedDescription
            }
            await reload()
        }
    }
}

/// A feedback's images, fetched and opened when its section is shown. Clicking one opens it in the default viewer.
private struct FeedbackImagesRow: View {
    let store: FeedbackStore
    let entry: FeedbackStore.Entry
    @State private var images: [(data: Data, thumbnail: CGImage)]?
    @State private var error: String?

    var body: some View {
        Group {
            if let images {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(images.indices, id: \.self) { index in
                            Button {
                                open(images[index].data, index: index)
                            } label: {
                                Image(decorative: images[index].thumbnail, scale: 1)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 80, height: 80)
                                    .clipShape(.rect(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                            .help("Open Image")
                        }
                    }
                }
                .scrollIndicators(.never)
            } else if let error {
                Text(error)
                    .foregroundStyle(.red)
            } else {
                LabeledContent("Images") {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .task(id: entry.id) {
            do {
                let datas = try await store.images(of: entry)
                images = datas.compactMap { data in
                    FeedbackImage.thumbnail(of: data, maxPixelSize: 160).map { (data, $0) }
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func open(_ data: Data, index: Int) {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "Whippet Feedback \(entry.id.recordName.prefix(8)) \(index + 1)")
            .appendingPathExtension(FeedbackImage.fileExtension(of: data))
        guard (try? data.write(to: url)) != nil else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Whippet shows a Dock icon only while one of its windows is open, such as Settings or Send Feedback.
enum DockIcon {
    static func update() {
        // Runs on the next pass, so a window that is closing no longer counts as visible.
        DispatchQueue.main.async {
            let hasWindow = NSApp.windows.contains { window in
                window.isVisible
                    && [SettingsView.windowID, FeedbackView.windowID].contains {
                        window.identifier?.rawValue.hasPrefix($0) == true
                    }
            }
            NSApp.setActivationPolicy(hasWindow ? .regular : .accessory)
        }
    }
}
