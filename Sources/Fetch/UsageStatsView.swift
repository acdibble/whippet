import AppKit
import SwiftUI

struct UsageStatsView: View {
    let model: LauncherModel
    @State private var usage: ClipboardUsage?

    var body: some View {
        ScrollView {
            if let usage {
                VStack(alignment: .leading, spacing: 16) {
                    InformationList(title: "Disk", rows: diskRows(usage))
                    InformationList(title: "Clipboard History", rows: historyRows(usage))
                    InformationList(title: "App", rows: appRows(usage))
                    Button("Show Data Folder in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([usage.directory])
                    }
                    .buttonStyle(.launcher)
                }
                .padding(16)
            } else {
                Text("Usage stats are unavailable because clipboard history could not be opened.")
                    .foregroundStyle(Color.launcherSecondary)
                    .padding(16)
            }
        }
        .frame(maxHeight: .infinity)
        .onAppear { usage = model.usage() }
    }

    private func diskRows(_ usage: ClipboardUsage) -> [InformationRow] {
        [
            InformationRow("Database", Self.bytes(usage.databaseBytes)),
            InformationRow("Images", String(localized: "\(Self.bytes(usage.imageBytes)) in \(usage.imageFiles) files")),
            InformationRow("Total", Self.bytes(usage.databaseBytes + usage.imageBytes)),
        ]
    }

    private func historyRows(_ usage: ClipboardUsage) -> [InformationRow] {
        let total = usage.counts.values.reduce(0, +)
        return [InformationRow("Items", total.formatted())]
            + ClipboardKind.allCases.map { InformationRow(verbatim: $0.pluralTitle, (usage.counts[$0] ?? 0).formatted()) }
            + [InformationRow("Images awaiting text recognition", usage.imagesAwaitingRecognition.formatted())]
            + [InformationRow("Calculations", usage.calculations.formatted())]
    }

    private func appRows(_ usage: ClipboardUsage) -> [InformationRow] {
        [
            InformationRow("Memory", Self.memoryFootprint().map(Self.bytes) ?? String(localized: "Unknown")),
            InformationRow("Data folder", usage.directory.path(percentEncoded: false)),
        ]
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
