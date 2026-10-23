import AppKit
import Observation

struct AppEntry: Identifiable, Hashable {
    let url: URL
    let name: String
    let bundleIdentifier: String?

    var id: URL { url }

    /// Stable across moves when the app has a bundle identifier, which keys hotkeys and usage counts.
    var stableID: String {
        bundleIdentifier ?? url.path
    }
}

@MainActor
@Observable
final class AppIndex {
    private(set) var apps: [AppEntry] = []
    /// Called after a rescan triggered by an application folder changing.
    @ObservationIgnored var onChange: () -> Void = {}

    @ObservationIgnored private var launchCounts = UserDefaults.standard.dictionary(forKey: "appLaunchCounts") as? [String: Int] ?? [:]
    @ObservationIgnored private var watchers: [DispatchSourceFileSystemObject] = []
    @ObservationIgnored private var pendingRefresh: Task<Void, Never>?

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
            .map { AppEntry(url: $0, name: Self.displayName(of: $0), bundleIdentifier: Bundle(url: $0)?.bundleIdentifier) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Rescans a second after an application folder changes, so installs and removals appear without a relaunch.
    /// The delay lets a burst of changes, such as an app being copied in, settle into one rescan.
    func startWatching() {
        for directory in Self.searchDirectories {
            let descriptor = Darwin.open(directory, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let watcher = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .rename, .delete],
                queue: .main
            )
            watcher.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.scheduleRefresh() }
            }
            watcher.setCancelHandler { close(descriptor) }
            watcher.resume()
            watchers.append(watcher)
        }
    }

    func launchCount(of app: AppEntry) -> Int {
        launchCounts[app.stableID] ?? 0
    }

    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        pendingRefresh = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            refresh()
            onChange()
        }
    }

    /// The name Finder shows, which is localized for apps such as System Settings and drops the `.app` extension.
    nonisolated static func displayName(of app: URL) -> String {
        let name = FileManager.default.displayName(atPath: app.path)
        guard name.hasSuffix(".app") else { return name }
        return String(name.dropLast(4))
    }

    func open(_ app: AppEntry) {
        NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration())
        launchCounts[app.stableID, default: 0] += 1
        UserDefaults.standard.set(launchCounts, forKey: "appLaunchCounts")
    }
}
