import Foundation
import GRDB

/// A saved link, opened from the launcher. `{query}` in its template is replaced with what's typed after pressing Tab.
public struct Quicklink: Identifiable, Hashable, Codable, FetchableRecord, TableRecord, Sendable {
    public static let databaseTableName = "quicklink"

    public let uuid: String
    public var name: String
    /// An extra search term, such as `gh` for Search GitHub.
    public var keyword: String?
    public var template: String
    /// The app that opens the link, or nil for the default app for the URL.
    public var appBundleID: String?

    public init(uuid: String, name: String, keyword: String? = nil, template: String, appBundleID: String? = nil) {
        self.uuid = uuid
        self.name = name
        self.keyword = keyword
        self.template = template
        self.appBundleID = appBundleID
    }

    public var id: String { uuid }

    public var takesArgument: Bool {
        QuicklinkTemplate.takesArgument(template)
    }

    /// What search matches against: the name, then the keyword.
    public var searchText: String {
        [name, keyword].compactMap { $0 }.joined(separator: " ")
    }

    /// Starters are created once, with fixed UUIDs so two Macs creating them make the same records rather than
    /// duplicates.
    public static let starters = [
        Quicklink(uuid: "starter-google", name: "Search Google", keyword: "g", template: "https://www.google.com/search?q={query}"),
        Quicklink(uuid: "starter-github", name: "Search GitHub", keyword: "gh", template: "https://github.com/search?q={query}"),
        Quicklink(
            uuid: "starter-wikipedia",
            name: "Search Wikipedia",
            keyword: "wiki",
            template: "https://en.wikipedia.org/w/index.php?search={query}"
        ),
        Quicklink(uuid: "starter-maps", name: "Search Maps", keyword: "maps", template: "maps://?q={query}"),
    ]
}

public enum QuicklinkTemplate {
    static let queryPlaceholder = "{query}"
    static let rawQueryPlaceholder = "{query:raw}"

    public static func takesArgument(_ template: String) -> Bool {
        template.contains(queryPlaceholder) || template.contains(rawQueryPlaceholder)
    }

    /// The link with the argument filled in: percent-encoded for `{query}`, as typed for `{query:raw}`. Nil when the
    /// result isn't a URL with a scheme.
    public static func url(_ template: String, argument: String = "") -> URL? {
        let encoded = argument.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
        let filled = template
            .replacingOccurrences(of: rawQueryPlaceholder, with: argument)
            .replacingOccurrences(of: queryPlaceholder, with: encoded)
        guard let url = URL(string: filled), let scheme = url.scheme, !scheme.isEmpty else { return nil }
        return url
    }

    /// Whether a template makes a valid link, checked with a sample argument.
    public static func isValid(_ template: String) -> Bool {
        url(template, argument: "whippet test") != nil
    }

    /// RFC 3986's unreserved characters, so anything with meaning in a URL, such as `&`, `#` or a space, is encoded.
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )
}
