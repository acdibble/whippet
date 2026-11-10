import SwiftUI
import WhippetCore

/// Turning sync on and off, and deleting what's in iCloud.
struct CloudSyncPane: View {
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
                Text(
                    "Everything that syncs is end-to-end encrypted, images included. Apple can see only how many items there are, their sizes and when they changed."
                )
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
