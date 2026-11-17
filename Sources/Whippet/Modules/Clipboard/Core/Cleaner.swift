import Foundation
import WhippetCore

/// Cleans a copied link as it's pasted, leaving the stored link as it is.
struct Cleaner {
    let shouldClean: Bool
    /// The link without its query, where tracking parameters such as `utm_source` are:
    /// `https://example.com/page?utm_source=x#top` becomes `https://example.com/page#top`. The fragment stays, since
    /// it names a place in the page. The rest is left exactly as it was copied rather than parsed and written out
    /// again, which could change its encoding.
    func clean(_ text: String, type: ClipboardKind) -> String {
        if !self.shouldClean { return text }
        switch type {
        case .link:
            // A `?` after the `#` is part of the fragment.
            let fragmentStart = text.firstIndex(of: "#") ?? text.endIndex
            guard let queryStart = text[..<fragmentStart].firstIndex(of: "?") else { return text }
            return String(text[..<queryStart] + text[fragmentStart...])
        case .text:
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        default:
            return text
        }
    }
}
