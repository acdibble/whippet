import Foundation

/// Something a command or feature needs from the Mac or the network. Each module declares what its commands and
/// features need in its manifest, and extensions in theirs, so Settings › Commands can show it beside the switch that
/// turns it off.
public enum Permission: Hashable, Sendable {
    /// Connecting to hosts given as patterns, as in an extension's manifest: `api.github.com`, `*.example.com`, or
    /// `*` for any website.
    case network([String])
    /// Reading what's copied, including what other apps copy.
    case clipboardRead
    /// Accessibility, which lets Whippet send ⌘V to the app it opened over, or move other apps' windows.
    case accessibility(AccessibilityUse)
    /// Screen Recording, to read text on the screen.
    case screenRecording
    /// Asking other apps to do things with Apple Events, which macOS confirms once for each app.
    case automation([AutomationTarget])
    case notifications
    case iCloud(CloudDatabase)
    /// Downloads macOS makes on Whippet's behalf, such as translation languages, which come from Apple.
    case systemDownloads

    public enum AccessibilityUse: Hashable, Sendable {
        case paste
        case windows
    }

    public enum CloudDatabase: Hashable, Sendable {
        /// The user's own database, for sync.
        case privateDatabase
        /// The app's shared database, for feedback.
        case publicDatabase
    }

    /// Kinds of permission, for grouping in Settings: every `network` permission is listed under one heading.
    public enum Kind: Int, CaseIterable, Comparable, Sendable {
        case network
        case clipboardRead
        case accessibility
        case screenRecording
        case automation
        case notifications
        case iCloud
        case systemDownloads

        public static func < (lhs: Kind, rhs: Kind) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        public var title: String {
            switch self {
            case .network: String(localized: "Network", bundle: .module)
            case .clipboardRead: String(localized: "Clipboard", bundle: .module)
            case .accessibility: String(localized: "Accessibility", bundle: .module)
            case .screenRecording: String(localized: "Screen Recording", bundle: .module)
            case .automation: String(localized: "Automation", bundle: .module)
            case .notifications: String(localized: "Notifications", bundle: .module)
            case .iCloud: String(localized: "iCloud", bundle: .module)
            case .systemDownloads: String(localized: "Downloads from Apple", bundle: .module)
            }
        }

        /// An SF Symbol for the kind.
        public var symbol: String {
            switch self {
            case .network: "network"
            case .clipboardRead: "list.clipboard"
            case .accessibility: "accessibility"
            case .screenRecording: "rectangle.dashed.badge.record"
            case .automation: "gearshape.2"
            case .notifications: "bell.badge"
            case .iCloud: "icloud"
            case .systemDownloads: "arrow.down.circle"
            }
        }
    }

    public var kind: Kind {
        switch self {
        case .network: .network
        case .clipboardRead: .clipboardRead
        case .accessibility: .accessibility
        case .screenRecording: .screenRecording
        case .automation: .automation
        case .notifications: .notifications
        case .iCloud: .iCloud
        case .systemDownloads: .systemDownloads
        }
    }

    /// A sentence saying what it allows, such as “Connects to www.ecb.europa.eu”.
    public var detail: String {
        switch self {
        case .network(let hosts) where hosts.contains("*"):
            String(localized: "Connects to any website", bundle: .module)
        case .network(let hosts):
            String(localized: "Connects to \(hosts.formatted(.list(type: .and)))", bundle: .module)
        case .clipboardRead:
            String(localized: "Reads what you copy, in any app", bundle: .module)
        case .accessibility(.paste):
            String(localized: "Pastes into the app Whippet opened over, by sending ⌘V", bundle: .module)
        case .accessibility(.windows):
            String(localized: "Moves and resizes other apps' windows", bundle: .module)
        case .screenRecording:
            String(localized: "Reads text in an area of the screen you choose", bundle: .module)
        case .automation(let targets):
            String(
                localized: "Asks \(targets.map(\.name).formatted(.list(type: .and))) to carry out commands",
                bundle: .module)
        case .notifications:
            String(localized: "Shows notifications", bundle: .module)
        case .iCloud(.privateDatabase):
            String(localized: "Stores end-to-end encrypted data in your iCloud account", bundle: .module)
        case .iCloud(.publicDatabase):
            String(localized: "Sends what you write to the developer through iCloud", bundle: .module)
        case .systemDownloads:
            String(localized: "macOS downloads translation languages from Apple", bundle: .module)
        }
    }

    /// A few words for a badge, such as the host for one site or “Accessibility”.
    public var shortTitle: String {
        switch self {
        case .network(let hosts) where hosts.count == 1 && hosts[0] != "*": hosts[0]
        case .network(let hosts) where hosts.contains("*"): String(localized: "Any website", bundle: .module)
        case .network(let hosts): String(localized: "\(hosts.count) sites", bundle: .module)
        case .automation(let targets): targets.map(\.name).formatted(.list(type: .and))
        default: kind.title
        }
    }
}

/// An app asked to do things with Apple Events, such as Finder to empty the Trash.
public struct AutomationTarget: Hashable, Sendable {
    public let bundleIdentifier: String
    /// The app's name, which isn't translated.
    public let name: String

    public init(bundleIdentifier: String, name: String) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
    }

    public static let systemEvents = AutomationTarget(bundleIdentifier: "com.apple.systemevents", name: "System Events")
    public static let finder = AutomationTarget(bundleIdentifier: "com.apple.finder", name: "Finder")
}

extension Permission {
    /// Whether declaring this permits `other`: the same kind and use, with every host `other` connects to matching one
    /// of these patterns, and every app it asks being one of these. Whippet checks what a command or feature does
    /// against what it declared with this.
    public func covers(_ other: Permission) -> Bool {
        switch (self, other) {
        case (.network(let patterns), .network(let hosts)):
            hosts.allSatisfy { Self.host($0, matchesAnyOf: patterns) }
        case (.automation(let targets), .automation(let others)):
            others.allSatisfy { other in targets.contains { $0.bundleIdentifier == other.bundleIdentifier } }
        default:
            self == other
        }
    }

    /// Whether a host matches a pattern as extensions write them: `*` matches any host, `*.example.com` any host under
    /// example.com, and anything else only itself, ignoring case.
    public static func host(_ host: String, matchesAnyOf patterns: [String]) -> Bool {
        let host = host.lowercased()
        return patterns.contains { pattern in
            let pattern = pattern.lowercased()
            if pattern == "*" { return true }
            if pattern.hasPrefix("*.") { return host.hasSuffix(pattern.dropFirst(1)) }
            return host == pattern
        }
    }
}

extension Array where Element == Permission {
    /// Whether any of these permits `permission`.
    public func covers(_ permission: Permission) -> Bool {
        contains { $0.covers(permission) }
    }

    /// The host patterns in every `network` permission.
    public var hosts: [String] {
        flatMap { permission -> [String] in
            if case .network(let hosts) = permission { return hosts }
            return []
        }
    }

    /// The permissions without repeats, in the order of their kinds, with network hosts gathered into one: what a
    /// module needs, from what each of its commands and features needs.
    public var combined: [Permission] {
        var hosts: [String] = []
        var targets: [AutomationTarget] = []
        var others: [Permission] = []
        for permission in self {
            switch permission {
            case .network(let more):
                hosts += more.filter { !hosts.contains($0) }
            case .automation(let more):
                targets += more.filter { !targets.contains($0) }
            default:
                if !others.contains(permission) {
                    others.append(permission)
                }
            }
        }
        if hosts.contains("*") {
            hosts = ["*"]
        }
        var all = others
        if !hosts.isEmpty {
            all.append(.network(hosts))
        }
        if !targets.isEmpty {
            all.append(.automation(targets))
        }
        return all.enumerated().sorted { lhs, rhs in
            lhs.element.kind != rhs.element.kind ? lhs.element.kind < rhs.element.kind : lhs.offset < rhs.offset
        }.map(\.element)
    }
}

extension ExtensionPermissions {
    /// What the extension's manifest asks for, in the terms built-in modules use.
    public var permissions: [Permission] {
        var permissions: [Permission] = []
        if !network.isEmpty {
            permissions.append(.network(network))
        }
        if clipboard {
            permissions.append(.clipboardRead)
        }
        return permissions
    }
}
