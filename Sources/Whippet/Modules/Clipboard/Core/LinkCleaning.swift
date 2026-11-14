import Foundation

/// Cleans a copied link as it's pasted, leaving the stored link as it is.
enum LinkCleaning {
    /// The link without its query, where tracking parameters such as `utm_source` are:
    /// `https://example.com/page?utm_source=x#top` becomes `https://example.com/page#top`. The fragment stays, since
    /// it names a place in the page. The rest is left exactly as it was copied rather than parsed and written out
    /// again, which could change its encoding.
    static func clean(_ link: String) -> String {
        // A `?` after the `#` is part of the fragment.
        let fragmentStart = link.firstIndex(of: "#") ?? link.endIndex
        guard let queryStart = link[..<fragmentStart].firstIndex(of: "?") else { return link }
        return String(link[..<queryStart] + link[fragmentStart...])
    }
}
