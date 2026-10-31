import Foundation

/// The share image a web page declares in its `og:image` or `twitter:image` tags. LinkPresentation finds it for most
/// pages but returns none for some sites, such as GitHub, which leaves only the site's icon.
enum PageImage {
    /// The tags to look for, best first.
    private static let properties = [
        "og:image:secure_url", "og:image", "og:image:url", "twitter:image", "twitter:image:src",
    ]
    /// Reading stops at `</head>`, or here for a page without one.
    private static let maxPageBytes = 1_000_000
    private static let maxImageBytes = 20_000_000
    private static let endOfHead = Array("</head>".utf8)

    /// Fetched without cookies, so it sees the page as anyone would.
    private static let session = URLSession(configuration: .ephemeral)

    enum Outcome {
        case image(Data)
        case none
        /// The site asked for a pause, as GitHub's image service does after 100 images.
        case rateLimited(retryAfter: TimeInterval)
    }

    static func fetch(for pageURL: URL, timeout: TimeInterval) async -> Outcome {
        var pageRequest = URLRequest(url: pageURL, timeoutInterval: timeout)
        pageRequest.setValue("text/html", forHTTPHeaderField: "Accept")
        guard let (pageBytes, response) = try? await session.bytes(for: pageRequest) else { return .none }
        defer { pageBytes.task.cancel() }
        if let pause = rateLimit(response) { return .rateLimited(retryAfter: pause) }
        guard response.mimeType == "text/html", let head = try? await readHead(pageBytes) else { return .none }
        guard
            let imageURL = url(inHTML: String(decoding: head, as: UTF8.self), baseURL: response.url ?? pageURL),
            let (imageBytes, imageResponse) = try? await session.bytes(
                for: URLRequest(url: imageURL, timeoutInterval: timeout))
        else { return .none }
        defer { imageBytes.task.cancel() }
        if let pause = rateLimit(imageResponse) { return .rateLimited(retryAfter: pause) }
        guard
            (imageResponse as? HTTPURLResponse)?.statusCode == 200,
            imageResponse.expectedContentLength <= maxImageBytes,
            let image = try? await read(imageBytes, upTo: maxImageBytes)
        else { return .none }
        return .image(image)
    }

    /// How long a 429 response asks to wait, a minute when it doesn't say.
    static func rateLimit(_ response: URLResponse) -> TimeInterval? {
        guard let response = response as? HTTPURLResponse, response.statusCode == 429 else { return nil }
        let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init) ?? 60
        return min(max(retryAfter, 10), 3600)
    }

    /// The page up to the end of its `<head>`, where meta tags are, so the rest isn't downloaded.
    private static func readHead(_ bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if byte == UInt8(ascii: ">"), data.count >= endOfHead.count,
                data.suffix(endOfHead.count).map({ $0 | 0x20 }) == endOfHead.map({ $0 | 0x20 })
            {
                break
            }
            if data.count >= maxPageBytes { break }
        }
        return data
    }

    /// The whole response, or nil once it's longer than the limit.
    private static func read(_ bytes: URLSession.AsyncBytes, upTo limit: Int) async throws -> Data? {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > limit { return nil }
        }
        return data
    }

    /// The image URL from the page's meta tags, resolved against the page's address. Only web addresses count.
    /// The HTML is read with libxml2's forgiving HTML parser, which handles quoting, entities and unclosed tags.
    static func url(inHTML html: String, baseURL: URL) -> URL? {
        guard
            let document = try? XMLDocument(xmlString: html, options: [.documentTidyHTML]),
            let metas = try? document.nodes(forXPath: "//meta") as? [XMLElement]
        else { return nil }
        var found: [String: String] = [:]
        for meta in metas {
            guard
                let name = (meta.attribute(forName: "property") ?? meta.attribute(forName: "name"))?.stringValue?
                    .lowercased(),
                properties.contains(name),
                found[name] == nil,
                let content = meta.attribute(forName: "content")?.stringValue?.trimmingCharacters(in: .whitespaces),
                !content.isEmpty
            else { continue }
            found[name] = content
        }
        for property in properties {
            guard
                let content = found[property],
                let url = URL(string: content, relativeTo: baseURL)?.absoluteURL,
                ["http", "https"].contains(url.scheme?.lowercased())
            else { continue }
            return url
        }
        return nil
    }
}
