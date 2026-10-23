import AppKit
import Observation

struct AppEntry: Identifiable, Hashable {
    let url: URL
    let name: String

    var id: URL { url }
}

@MainActor
@Observable
final class AppIndex {
    private(set) var apps: [AppEntry] = []

    private static let searchDirectories = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities",
        NSHomeDirectory() + "/Applications",
    ]

    func refresh() {
        apps = Self.searchDirectories
            .flatMap { directory in
                let contents = try? FileManager.default.contentsOfDirectory(
                    at: URL(filePath: directory),
                    includingPropertiesForKeys: nil
                )
                return contents ?? []
            }
            .filter { $0.pathExtension == "app" }
            .map { AppEntry(url: $0, name: $0.deletingPathExtension().lastPathComponent) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func open(_ app: AppEntry) {
        NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration())
    }
}
