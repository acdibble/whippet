import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WhippetCore

/// Settings for clipboard history: how long it's kept, which apps it ignores, and what it holds.
struct ClipboardPane: View {
    @Bindable var clipboard: ClipboardHistory
    @State private var usage: ClipboardUsage?
    @State private var isConfirmingClear = false

    var body: some View {
        Form {
            Section {
                Picker("Keep Items", selection: $clipboard.retention) {
                    ForEach(ClipboardRetention.allCases) { retention in
                        Text(retention.title).tag(retention)
                    }
                }
            } footer: {
                Text(
                    "Pinned items are always kept. With iCloud sync on, removed items are also removed from your other Macs."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                Toggle(isOn: $clipboard.fetchesLinkPreviews) {
                    Text("Fetch Link Previews")
                    Text("Shows each copied link's page title and image, and makes them searchable")
                }
                .toggleStyle(.switch)
            } footer: {
                Text(
                    "Fetching opens the link from this Mac. A single-use link, such as a sign-in or password reset link, may stop working once it's opened."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                ForEach(clipboard.ignoredApps, id: \.self) { bundleID in
                    IgnoredAppRow(bundleID: bundleID) {
                        clipboard.ignoredApps.removeAll { $0 == bundleID }
                    }
                }
                Button("Add App…", action: chooseApps)
            } header: {
                Text("Ignored Apps")
            } footer: {
                Text(
                    "Copies made in these apps aren't saved. Copies that password managers mark as concealed are always skipped."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                if let usage {
                    LabeledContent("Items", value: usage.counts.values.reduce(0, +).formatted())
                    ForEach(ClipboardKind.allCases) { kind in
                        LabeledContent(kind.pluralTitle, value: (usage.counts[kind] ?? 0).formatted())
                    }
                    LabeledContent(
                        "Images Awaiting Text Recognition", value: usage.imagesAwaitingRecognition.formatted())
                    LabeledContent("Calculations", value: usage.calculations.formatted())
                }
                LabeledContent("Clear History") {
                    Button("Clear History…", role: .destructive) { isConfirmingClear = true }
                }
            } header: {
                Text("History")
            } footer: {
                Text(
                    "Text copies larger than \(Int64(ClipboardHistory.maximumTextBytes).formatted(.byteCount(style: .file))) aren't saved."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .confirmationDialog("Clear clipboard history?", isPresented: $isConfirmingClear) {
            Button("Clear Unpinned Items", role: .destructive) { clipboard.clear(includingPinned: false) }
            Button("Clear All Items", role: .destructive) { clipboard.clear(includingPinned: true) }
        } message: {
            Text(
                "Items are removed from this Mac, and from your other Macs when iCloud sync is on. Calculations are kept."
            )
        }
        .task(id: clipboard.revision) { usage = clipboard.usage() }
    }

    private func chooseApps() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(filePath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Ignore")
        panel.begin { response in
            guard response == .OK else { return }
            let bundleIDs = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
            clipboard.ignoredApps += bundleIDs.filter { !clipboard.ignoredApps.contains($0) }
        }
    }
}

private struct IgnoredAppRow: View {
    let bundleID: String
    let remove: () -> Void

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        LabeledContent {
            Button("Remove", action: remove)
        } label: {
            Label {
                Text(url.map { FileManager.default.displayName(atPath: $0.path) } ?? bundleID)
            } icon: {
                if let url {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .frame(width: 18, height: 18)
                }
            }
        }
    }
}
