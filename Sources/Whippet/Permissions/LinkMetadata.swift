import Foundation
import LinkPresentation
import WhippetCore

/// A page's title and images from LinkPresentation, for link previews. macOS makes the request itself rather than
/// through a `ScopedSession`, so the session it would have used is asked first: the page has to be on a host it
/// allows, while what it's for is turned on.
enum LinkMetadata {
    static func fetch(for url: URL, timeout: TimeInterval, session: ScopedSession) async -> LPLinkMetadata? {
        guard await session.permits(url) else { return nil }
        let provider = LPMetadataProvider()
        provider.timeout = timeout
        return try? await provider.startFetchingMetadata(for: url)
    }
}
