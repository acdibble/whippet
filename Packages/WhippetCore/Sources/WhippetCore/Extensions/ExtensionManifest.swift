import Foundation

/// An extension's `manifest.json`: what it's called, the commands it adds to the launcher, the preferences it asks for
/// and the access it needs beyond its own code.
public struct ExtensionManifest: Codable, Hashable, Sendable {
    /// The API version this Whippet runs. A manifest asking for another is refused rather than run against an API it
    /// wasn't written for.
    public static let supportedAPIVersion = 1

    /// Reverse-DNS, such as `com.example.github`, so extensions from different authors don't collide.
    public let id: String
    public let name: String
    public let version: String
    public let apiVersion: Int
    public let description: String?
    public let author: String?
    /// An SF Symbol name, an emoji or an image file in the extension's folder.
    public let icon: String?
    public let permissions: ExtensionPermissions
    public let preferences: [ExtensionPreference]
    public let commands: [ExtensionCommand]

    public init(
        id: String, name: String, version: String, apiVersion: Int = ExtensionManifest.supportedAPIVersion,
        description: String? = nil, author: String? = nil, icon: String? = nil,
        permissions: ExtensionPermissions = ExtensionPermissions(), preferences: [ExtensionPreference] = [],
        commands: [ExtensionCommand]
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.apiVersion = apiVersion
        self.description = description
        self.author = author
        self.icon = icon
        self.permissions = permissions
        self.preferences = preferences
        self.commands = commands
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, version, apiVersion, description, author, icon, permissions, preferences, commands
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        version = try container.decode(String.self, forKey: .version)
        apiVersion = try container.decode(Int.self, forKey: .apiVersion)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        permissions = try container.decodeIfPresent(ExtensionPermissions.self, forKey: .permissions) ?? .init()
        preferences = try container.decodeIfPresent([ExtensionPreference].self, forKey: .preferences) ?? []
        commands = try container.decode([ExtensionCommand].self, forKey: .commands)
    }

    /// Reads and checks a manifest.
    public static func load(from url: URL) throws -> ExtensionManifest {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ExtensionManifestError.missing
        }
        let manifest: ExtensionManifest
        do {
            manifest = try JSONDecoder().decode(ExtensionManifest.self, from: data)
        } catch let error as DecodingError {
            throw ExtensionManifestError.invalid(error.summary)
        }
        try manifest.validate()
        return manifest
    }

    public func validate() throws {
        guard apiVersion == Self.supportedAPIVersion else {
            throw ExtensionManifestError.unsupportedAPIVersion(apiVersion)
        }
        guard id.wholeMatch(of: /[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)+/) != nil else {
            throw ExtensionManifestError.invalidID(id)
        }
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { throw ExtensionManifestError.missingName }
        guard !commands.isEmpty else { throw ExtensionManifestError.noCommands }
        var names = Set<String>()
        for command in commands {
            // Command names are JavaScript export names and part of hotkey names, so they're kept to identifiers.
            guard command.name.wholeMatch(of: /[a-zA-Z_][a-zA-Z0-9_]*/) != nil else {
                throw ExtensionManifestError.invalidCommandName(command.name)
            }
            guard names.insert(command.name).inserted else {
                throw ExtensionManifestError.duplicateCommand(command.name)
            }
        }
        for host in permissions.network where !ExtensionPermissions.isValidHostPattern(host) {
            throw ExtensionManifestError.invalidHost(host)
        }
    }
}

/// What a manifest asks for. A bare JavaScript context reaches nothing outside the extension's own code, so these are
/// the only ways out, and Whippet asks before granting them.
public struct ExtensionPermissions: Codable, Hashable, Sendable {
    /// Hosts the extension may fetch from, such as `api.github.com` or `*.example.com`. `*` allows any host.
    public var network: [String]
    /// Reading what's on the clipboard. Copying and pasting what the extension supplies needs no permission.
    public var clipboard: Bool

    public init(network: [String] = [], clipboard: Bool = false) {
        self.network = network
        self.clipboard = clipboard
    }

    private enum CodingKeys: String, CodingKey {
        case network, clipboard
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        network = try container.decodeIfPresent([String].self, forKey: .network) ?? []
        clipboard = try container.decodeIfPresent(Bool.self, forKey: .clipboard) ?? false
    }

    public var isEmpty: Bool {
        network.isEmpty && !clipboard
    }

    /// Whether everything in `other` was already granted here, so an update asking for nothing new keeps running.
    public func covers(_ other: ExtensionPermissions) -> Bool {
        (!other.clipboard || clipboard)
            && other.network.allSatisfy { requested in
                network.contains { $0 == "*" || $0.lowercased() == requested.lowercased() }
            }
    }

    public func allowsHost(_ host: String) -> Bool {
        let host = host.lowercased()
        return network.contains { pattern in
            let pattern = pattern.lowercased()
            if pattern == "*" { return true }
            if pattern.hasPrefix("*.") { return host.hasSuffix(pattern.dropFirst(1)) }
            return host == pattern
        }
    }

    static func isValidHostPattern(_ pattern: String) -> Bool {
        pattern == "*" || pattern.wholeMatch(of: /(\*\.)?[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)*/) != nil
    }

    /// One line per permission, for the prompt before an extension runs and for Settings.
    public var descriptions: [String] {
        var lines: [String] = []
        if network.contains("*") {
            lines.append(String(localized: "Connect to any website", bundle: .module))
        } else if !network.isEmpty {
            let hosts = network.formatted(.list(type: .and))
            lines.append(String(localized: "Connect to \(hosts)", bundle: .module))
        }
        if clipboard {
            lines.append(String(localized: "Read the clipboard", bundle: .module))
        }
        return lines
    }
}

/// A setting the user fills in under Settings › Extensions, such as an API token.
public struct ExtensionPreference: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case text
        /// Kept in the Keychain.
        case secret
        case checkbox
    }

    public let name: String
    public let title: String
    public let type: Kind
    public let description: String?
    public let placeholder: String?
    public let required: Bool
    public let defaultValue: JSONValue?

    public init(
        name: String, title: String, type: Kind = .text, description: String? = nil, placeholder: String? = nil,
        required: Bool = false, defaultValue: JSONValue? = nil
    ) {
        self.name = name
        self.title = title
        self.type = type
        self.description = description
        self.placeholder = placeholder
        self.required = required
        self.defaultValue = defaultValue
    }

    private enum CodingKeys: String, CodingKey {
        case name, title, type, description, placeholder, required
        case defaultValue = "default"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        title = try container.decode(String.self, forKey: .title)
        type = try container.decodeIfPresent(Kind.self, forKey: .type) ?? .text
        description = try container.decodeIfPresent(String.self, forKey: .description)
        placeholder = try container.decodeIfPresent(String.self, forKey: .placeholder)
        required = try container.decodeIfPresent(Bool.self, forKey: .required) ?? false
        defaultValue = try container.decodeIfPresent(JSONValue.self, forKey: .defaultValue)
    }
}

/// A command the extension adds to the launcher.
public struct ExtensionCommand: Codable, Hashable, Sendable {
    public enum Mode: String, Codable, Sendable {
        /// Shows a list, detail or form in the panel.
        case view
        /// Runs and closes the panel, as for copying a generated value.
        case noView = "no-view"
    }

    /// The name the extension's bundle exports the command under.
    public let name: String
    public let title: String
    public let subtitle: String?
    public let icon: String?
    public let mode: Mode
    /// Text typed after Tab, or asked for when the command is chosen, passed to it as `arguments[name]`.
    public let argument: ExtensionArgument?
    /// Offers the command for whatever is typed in the search bar, under "Use … with". It gets the text as its argument,
    /// or else as `fallbackText`, with a list starting out searched for it.
    public let fallback: Bool

    public init(
        name: String, title: String, subtitle: String? = nil, icon: String? = nil, mode: Mode = .view,
        argument: ExtensionArgument? = nil, fallback: Bool = false
    ) {
        self.name = name
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.mode = mode
        self.argument = argument
        self.fallback = fallback
    }

    private enum CodingKeys: String, CodingKey {
        case name, title, subtitle, icon, mode, argument, fallback
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        mode = try container.decodeIfPresent(Mode.self, forKey: .mode) ?? .view
        argument = try container.decodeIfPresent(ExtensionArgument.self, forKey: .argument)
        fallback = try container.decodeIfPresent(Bool.self, forKey: .fallback) ?? false
    }
}

public struct ExtensionArgument: Codable, Hashable, Sendable {
    public let name: String
    public let placeholder: String?

    public init(name: String, placeholder: String? = nil) {
        self.name = name
        self.placeholder = placeholder
    }
}

public enum ExtensionManifestError: LocalizedError, Equatable {
    case missing
    case invalid(String)
    case unsupportedAPIVersion(Int)
    case invalidID(String)
    case missingName
    case noCommands
    case invalidCommandName(String)
    case duplicateCommand(String)
    case invalidHost(String)

    public var errorDescription: String? {
        switch self {
        case .missing:
            String(localized: "There's no manifest.json in the folder.", bundle: .module)
        case .invalid(let reason):
            String(localized: "manifest.json isn't valid: \(reason)", bundle: .module)
        case .unsupportedAPIVersion(let version):
            String(
                localized: "The extension needs API version \(version), and this Whippet supports version 1.",
                bundle: .module)
        case .invalidID(let id):
            String(localized: "The id “\(id)” should be reverse-DNS, such as com.example.github.", bundle: .module)
        case .missingName:
            String(localized: "The extension has no name.", bundle: .module)
        case .noCommands:
            String(localized: "The extension has no commands.", bundle: .module)
        case .invalidCommandName(let name):
            String(
                localized: "The command name “\(name)” should be letters, digits and underscores.", bundle: .module)
        case .duplicateCommand(let name):
            String(localized: "There's more than one command named “\(name)”.", bundle: .module)
        case .invalidHost(let host):
            String(localized: "“\(host)” isn't a host name, such as api.example.com.", bundle: .module)
        }
    }
}

extension DecodingError {
    /// The missing or mistyped key, rather than the full debug description.
    fileprivate var summary: String {
        switch self {
        case .keyNotFound(let key, _): "missing \(key.stringValue)"
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            context.codingPath.map(\.stringValue).joined(separator: ".").nilIfEmpty ?? context.debugDescription
        @unknown default: localizedDescription
        }
    }
}

extension String {
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
