import AppKit
import SwiftUI

/// Disk and memory figures, read fresh each time the pane appears. Item counts are in the Clipboard History pane.
struct UsagePane: View {
    let clipboard: ClipboardHistory
    @State private var usage: ClipboardUsage?

    var body: some View {
        Form {
            if let usage {
                Section("Disk") {
                    LabeledContent("Database", value: Self.bytes(usage.databaseBytes))
                    LabeledContent(
                        "Images",
                        value: String(localized: "\(Self.bytes(usage.imageBytes)) in \(usage.imageFiles) files")
                    )
                    LabeledContent("Total", value: Self.bytes(usage.databaseBytes + usage.imageBytes))
                }

                Section("App") {
                    LabeledContent("Memory", value: Self.memoryFootprint().map(Self.bytes) ?? String(localized: "Unknown"))
                    LabeledContent("Data Folder") {
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([usage.directory])
                        }
                    }
                }
            } else {
                Text("Usage is unavailable because clipboard history could not be opened.")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { usage = clipboard.usage() }
    }

    private static func bytes(_ count: Int) -> String {
        Int64(count).formatted(.byteCount(style: .file))
    }

    /// The figure Activity Monitor shows in its Memory column.
    private static func memoryFootprint() -> Int? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Int(info.phys_footprint)
    }
}
