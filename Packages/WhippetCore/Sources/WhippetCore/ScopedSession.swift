import Foundation

/// The only way Whippet connects to the network: a session allowed only the hosts a command, feature or extension
/// declares, redirects included, and only while it's turned on. Currency conversion gets one for
/// `www.ecb.europa.eu`, so it can't reach anywhere else, and turning it off in Settings › Commands stops it at once,
/// even mid-refresh.
public final class ScopedSession: Sendable {
    /// Host patterns, as in an extension's manifest: `api.github.com`, `*.example.com`, or `*` for any website.
    public let hosts: [String]
    private let isAllowed: @MainActor @Sendable () -> Bool
    private let session: URLSession

    /// A request to a host that wasn't declared, or made while what declared it is turned off.
    public struct Blocked: LocalizedError {
        public let host: String?

        public var errorDescription: String? {
            guard let host else {
                return String(
                    localized: "Whippet blocked a request made while its feature is turned off.", bundle: .module)
            }
            return String(localized: "Whippet blocked a request to \(host), which isn't declared.", bundle: .module)
        }
    }

    /// `isAllowed` is asked before each request, such as whether the feature is still turned on.
    public init(
        hosts: [String], timeout: TimeInterval? = nil, isAllowed: @escaping @MainActor @Sendable () -> Bool = { true }
    ) {
        self.hosts = hosts
        self.isAllowed = isAllowed
        // Without cookies or a cache on disk, so each request sees the site as anyone would and leaves nothing behind.
        let configuration = URLSessionConfiguration.ephemeral
        if let timeout {
            configuration.timeoutIntervalForRequest = timeout
        }
        session = URLSession(configuration: configuration)
    }

    /// Whether a request to `url` would be made now: it's a web address on a declared host, and what declared it is on.
    public func permits(_ url: URL) async -> Bool {
        (try? await check(url)) != nil
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await check(request.url)
        return try await session.data(for: request, delegate: RedirectGuard(hosts: hosts))
    }

    public func bytes(for request: URLRequest) async throws -> (URLSession.AsyncBytes, URLResponse) {
        try await check(request.url)
        return try await session.bytes(for: request, delegate: RedirectGuard(hosts: hosts))
    }

    /// Cancels what's in flight. The session can't be used afterwards.
    public func invalidate() {
        session.invalidateAndCancel()
    }

    private func check(_ url: URL?) async throws {
        guard let url, let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
            let host = url.host(), Permission.host(host, matchesAnyOf: hosts)
        else { throw Blocked(host: url?.host()) }
        guard await isAllowed() else { throw Blocked(host: nil) }
    }

    /// Stops a redirect to a host that wasn't declared, which would otherwise get round the check on the first
    /// request.
    private final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
        let hosts: [String]

        init(hosts: [String]) {
            self.hosts = hosts
        }

        func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest
        ) async -> URLRequest? {
            guard let host = request.url?.host(), Permission.host(host, matchesAnyOf: hosts) else { return nil }
            return request
        }
    }
}
