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
            .map { AppEntry(url: $0, name: Self.displayName(of: $0)) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The name Finder shows, which is localized for apps such as System Settings and drops the `.app` extension.
    nonisolated static func displayName(of app: URL) -> String {
        let name = FileManager.default.displayName(atPath: app.path)
        guard name.hasSuffix(".app") else { return name }
        return String(name.dropLast(4))
    }

    func open(_ app: AppEntry) {
        NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration())
    }
}
