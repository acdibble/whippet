import AppKit
import CoreServices
import Observation
import Security
import WhippetCore

/// An extension folder whose manifest loaded.
struct InstalledExtension: Identifiable, Hashable {
    let manifest: ExtensionManifest
    let directory: URL
    /// Changes when `manifest.json` or `index.js` does, so a rebuilt extension reloads.
    let signature: String

    var id: String { manifest.id }
}

/// A folder in the Extensions folder that couldn't be loaded, and why.
struct ExtensionProblem: Identifiable, Hashable {
    let folder: String
    let message: String

    var id: String { folder }
}

/// A command of an enabled extension, as the launcher lists it.
struct ExtensionCommandInfo: Hashable {
    let extensionID: String
    let extensionName: String
    let command: ExtensionCommand
    /// The command's own icon, or the extension's.
    let icon: String?
    let directory: URL

    var title: String { command.title }
    /// Unique across extensions, and stable, so launches and hotkeys survive a reload.
    var key: String { "\(extensionID)/\(command.name)" }
}

struct ExtensionLogLine: Identifiable, Hashable {
    let id: Int
    let date: Date
    let level: String
    let message: String
}

/// Finds the extensions in `~/Library/Application Support/Whippet/Extensions`, watches the folder so a rebuilt or added
/// extension reloads straight away, and runs each enabled one in its own `ExtensionRuntime` once a command is used.
///
/// An extension is enabled when the permissions its manifest asks for were approved. An update asking for more stops
/// it until they're approved again.
///
/// Extensions are a beta feature: until `setActive(true)`, from the feature flag, the manager reads nothing and runs
/// nothing.
@MainActor
@Observable
final class ExtensionManager {
    static let directory = ClipboardStore.defaultDirectory.appending(path: "Extensions")
    static let dataDirectory = ClipboardStore.defaultDirectory.appending(path: "Extension Data")
    private static let approvalsKey = "extensionApprovals"
    private static let logLimit = 500

    enum Status {
        case enabled
        case disabled
        /// Updated, and asking for more than was approved.
        case needsApproval
    }

    /// Whether the Extensions beta feature is on.
    private(set) var isActive = false
    private(set) var installed: [InstalledExtension] = []
    private(set) var problems: [ExtensionProblem] = []
    private(set) var approvals: [String: ExtensionPermissions] = [:]
    private(set) var logs: [String: [ExtensionLogLine]] = [:]
    /// Every enabled extension's commands, for the launcher.
    private(set) var commands: [ExtensionCommandInfo] = []
    /// Bumped when a preference changes, so Settings redraws values kept outside Observation, in the Keychain.
    private(set) var preferencesRevision = 0

    /// Called with each event from an extension's runtime, after the manager has logged it.
    @ObservationIgnored var onEvent: (_ extensionID: String, ExtensionRuntime.Event) -> Void = { _, _ in }
    /// Does what an extension asks of Whippet, such as copying text or closing the panel.
    @ObservationIgnored var host: (ExtensionRuntime.HostRequest) async throws -> JSONValue = { _ in .null }
    /// Called with the extensions whose files changed and were reloaded.
    @ObservationIgnored var onReload: (Set<String>) -> Void = { _ in }
    /// Called after the commands change, so their hotkeys can be registered.
    @ObservationIgnored var onCommandsChange: () -> Void = {}

    @ObservationIgnored private var runtimes: [String: ExtensionRuntime] = [:]
    @ObservationIgnored private var stream: FSEventStreamRef?
    @ObservationIgnored private var nextLogID = 0

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.approvalsKey),
            let approvals = try? JSONDecoder().decode([String: ExtensionPermissions].self, from: data)
        {
            self.approvals = approvals
        }
    }

    /// Starts finding and watching extensions when the feature is turned on. Turning it off stops every runtime and
    /// empties the lists, which closes any extension command that's open.
    func setActive(_ isActive: Bool) {
        guard isActive != self.isActive else { return }
        self.isActive = isActive
        if isActive {
            startWatching()
            reload()
            return
        }
        stopWatching()
        for runtime in runtimes.values {
            runtime.shutdown()
        }
        runtimes.removeAll()
        let ids = Set(installed.map(\.id))
        installed = []
        problems = []
        refreshCommands()
        onReload(ids)
    }

    // MARK: - Finding extensions

    /// Reads every manifest again, restarting the runtimes of extensions whose files changed.
    func reload() {
        guard isActive else { return }
        let previous = Dictionary(installed.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var found: [InstalledExtension] = []
        var problems: [ExtensionProblem] = []
        let folders =
            (try? FileManager.default.contentsOfDirectory(
                at: Self.directory, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? []
        for folder in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            do {
                let manifest = try ExtensionManifest.load(from: folder.appending(path: "manifest.json"))
                if found.contains(where: { $0.id == manifest.id }) {
                    problems.append(
                        ExtensionProblem(
                            folder: folder.lastPathComponent,
                            message: String(localized: "Another folder has an extension with the id \(manifest.id).")))
                    continue
                }
                found.append(
                    InstalledExtension(manifest: manifest, directory: folder, signature: Self.signature(of: folder)))
            } catch {
                problems.append(ExtensionProblem(folder: folder.lastPathComponent, message: error.localizedDescription))
            }
        }

        let current = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var changed = Set<String>()
        for (id, old) in previous where current[id]?.signature != old.signature {
            changed.insert(id)
            runtimes.removeValue(forKey: id)?.shutdown()
        }
        installed = found
        self.problems = problems
        refreshCommands()
        if !changed.isEmpty {
            onReload(changed)
        }
    }

    private static func signature(of folder: URL) -> String {
        ["manifest.json", "index.js"].map { name in
            let date = (try? folder.appending(path: name).resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            return date.map { "\($0.timeIntervalSince1970)" } ?? "-"
        }.joined(separator: "|")
    }

    private func refreshCommands() {
        commands = installed.filter { status(of: $0) == .enabled }.flatMap { installed in
            installed.manifest.commands.map { command in
                ExtensionCommandInfo(
                    extensionID: installed.id,
                    extensionName: installed.manifest.name,
                    command: command,
                    icon: command.icon ?? installed.manifest.icon,
                    directory: installed.directory)
            }
        }
        onCommandsChange()
    }

    func installed(id: String) -> InstalledExtension? {
        installed.first { $0.id == id }
    }

    /// Watches the Extensions folder, creating it if needed, so changes are picked up as they're saved.
    private func startWatching() {
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        guard stream == nil else { return }
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil,
            copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let manager = Unmanaged<ExtensionManager>.fromOpaque(info).takeUnretainedValue()
            MainActor.assumeIsolated { manager.reload() }
        }
        guard
            let stream = FSEventStreamCreate(
                nil, callback, &context, [Self.directory.path] as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3,
                FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer))
        else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    private func stopWatching() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    /// Copies an extension's folder into the Extensions folder, replacing an earlier version of it.
    @discardableResult
    func install(from folder: URL) throws -> InstalledExtension {
        let manifest = try ExtensionManifest.load(from: folder.appending(path: "manifest.json"))
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        let destination = Self.directory.appending(path: manifest.id)
        if folder.standardizedFileURL != destination.standardizedFileURL {
            if let existing = installed(id: manifest.id) {
                try FileManager.default.trashItem(at: existing.directory, resultingItemURL: nil)
            }
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.trashItem(at: destination, resultingItemURL: nil)
            }
            try FileManager.default.copyItem(at: folder, to: destination)
        }
        reload()
        guard let installed = installed(id: manifest.id) else { throw ExtensionManifestError.missing }
        return installed
    }

    /// Moves the extension's folder to the Trash. What it stored and its preferences stay, for a reinstall.
    func uninstall(_ installed: InstalledExtension) {
        disable(installed)
        do {
            try FileManager.default.trashItem(at: installed.directory, resultingItemURL: nil)
        } catch {
            NSLog("Failed to remove extension: \(error)")
        }
        reload()
    }

    // MARK: - Permissions

    func status(of installed: InstalledExtension) -> Status {
        guard let approved = approvals[installed.id] else { return .disabled }
        return approved.covers(installed.manifest.permissions) ? .enabled : .needsApproval
    }

    /// Approves what the extension's manifest asks for now.
    func enable(_ installed: InstalledExtension) {
        approvals[installed.id] = installed.manifest.permissions
        saveApprovals()
        refreshCommands()
    }

    func disable(_ installed: InstalledExtension) {
        approvals[installed.id] = nil
        saveApprovals()
        runtimes.removeValue(forKey: installed.id)?.shutdown()
        refreshCommands()
    }

    private func saveApprovals() {
        UserDefaults.standard.set(try? JSONEncoder().encode(approvals), forKey: Self.approvalsKey)
    }

    // MARK: - Runtimes

    /// The extension's runtime, started the first time one of its commands is used and kept for the next.
    func runtime(for extensionID: String) -> ExtensionRuntime? {
        if let runtime = runtimes[extensionID] { return runtime }
        guard isActive, let installed = installed(id: extensionID), status(of: installed) == .enabled else {
            return nil
        }
        let environment: [String: JSONValue] = [
            "extensionID": .string(installed.id),
            "extensionName": .string(installed.manifest.name),
            "whippetVersion": .string(WhippetModule.currentVersion),
        ]
        let runtime = ExtensionRuntime(
            manifest: installed.manifest,
            directory: installed.directory,
            dataDirectory: Self.dataDirectory.appending(path: installed.id),
            environment: environment,
            preferences: preferenceValues(for: installed),
            host: { [weak self] request in
                guard let self else { return .null }
                return try await handle(request)
            },
            onEvent: { [weak self] event in
                // In order, on the main queue, so renders and their sessions' ends arrive as they were sent.
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.receive(event, from: extensionID) }
                }
            })
        runtimes[extensionID] = runtime
        return runtime
    }

    private func handle(_ request: ExtensionRuntime.HostRequest) async throws -> JSONValue {
        try await host(request)
    }

    private func receive(_ event: ExtensionRuntime.Event, from extensionID: String) {
        switch event {
        case .log(let level, let message):
            log(message, level: level, for: extensionID)
        case .failed(_, let message, let stack):
            log([message, stack].compactMap { $0 }.joined(separator: "\n"), level: "error", for: extensionID)
        default:
            break
        }
        onEvent(extensionID, event)
    }

    private func log(_ message: String, level: String, for extensionID: String) {
        #if DEBUG
            NSLog("[\(extensionID)] \(level): \(message)")
        #endif
        var lines = logs[extensionID] ?? []
        lines.append(ExtensionLogLine(id: nextLogID, date: .now, level: level, message: message))
        nextLogID += 1
        logs[extensionID] = Array(lines.suffix(Self.logLimit))
    }

    func clearLog(for extensionID: String) {
        logs[extensionID] = nil
    }

    // MARK: - Preferences

    /// Every preference's value: what the user set, or the manifest's default.
    func preferenceValues(for installed: InstalledExtension) -> [String: JSONValue] {
        var values: [String: JSONValue] = [:]
        let stored = storedPreferences(for: installed.id)
        for preference in installed.manifest.preferences {
            let value: JSONValue? =
                switch preference.type {
                case .secret:
                    Keychain.read(service: keychainService(for: installed.id), account: preference.name)
                        .map(JSONValue.string)
                case .text, .checkbox: stored[preference.name]
                }
            values[preference.name] =
                value ?? preference.defaultValue ?? (preference.type == .checkbox ? .bool(false) : .string(""))
        }
        return values
    }

    func setPreference(_ value: JSONValue, named name: String, for installed: InstalledExtension) {
        guard let preference = installed.manifest.preferences.first(where: { $0.name == name }) else { return }
        if preference.type == .secret {
            let service = keychainService(for: installed.id)
            if let text = value.string, !text.isEmpty {
                Keychain.write(text, service: service, account: name)
            } else {
                Keychain.delete(service: service, account: name)
            }
        } else {
            var stored = storedPreferences(for: installed.id)
            stored[name] = value
            UserDefaults.standard.set(try? JSONEncoder().encode(stored), forKey: preferencesKey(for: installed.id))
        }
        preferencesRevision += 1
        runtimes[installed.id]?.updatePreferences(preferenceValues(for: installed))
    }

    /// Required preferences that are still empty, which stop the extension's commands until they're set.
    func missingPreferences(for installed: InstalledExtension) -> [ExtensionPreference] {
        let values = preferenceValues(for: installed)
        return installed.manifest.preferences.filter { preference in
            preference.required && preference.type != .checkbox && (values[preference.name]?.string ?? "").isEmpty
        }
    }

    private func storedPreferences(for extensionID: String) -> [String: JSONValue] {
        UserDefaults.standard.data(forKey: preferencesKey(for: extensionID))
            .flatMap { try? JSONDecoder().decode([String: JSONValue].self, from: $0) } ?? [:]
    }

    private func preferencesKey(for extensionID: String) -> String {
        "extensionPreferences.\(extensionID)"
    }

    private func keychainService(for extensionID: String) -> String {
        "\(Bundle.main.bundleIdentifier ?? "codes.dibble.whippet").extension.\(extensionID)"
    }
}

/// Generic passwords in the login keychain, for extension preferences marked secret, such as API tokens.
private enum Keychain {
    static func read(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String, service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let data = Data(value.utf8)
        if SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            SecItemAdd(item as CFDictionary, nil)
        }
    }

    static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
