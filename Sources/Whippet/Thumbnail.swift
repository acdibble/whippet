import ImageIO
import SwiftUI

/// Downsampled copies of clipboard image files, decoded off the main thread with ImageIO and kept in memory. Decoding
/// each full screenshot on every render made long histories slow to scroll.
enum Thumbnail {
    /// NSCache is thread-safe, and evicts entries under memory pressure as well as past the cost limit.
    nonisolated(unsafe) private static let cache: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    static func cached(_ url: URL, maxPixelSize: Int) -> CGImage? {
        cache.object(forKey: key(url, maxPixelSize))
    }

    /// The image scaled so its longer side is at most `maxPixelSize`, or nil when the file can't be read.
    static func load(_ url: URL, maxPixelSize: Int) async -> CGImage? {
        if let image = cached(url, maxPixelSize: maxPixelSize) {
            return image
        }
        return await Task.detached(priority: .userInitiated) {
            let options =
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                ] as CFDictionary
            guard
                let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options)
            else { return nil }
            cache.setObject(image, forKey: key(url, maxPixelSize), cost: image.bytesPerRow * image.height)
            return image
        }.value
    }

    private static func key(_ url: URL, _ maxPixelSize: Int) -> NSString {
        "\(maxPixelSize)@\(url.path)" as NSString
    }
}

/// An image file shown from a downsampled copy: straight from memory when it's cached, otherwise loaded in the
/// background with the placeholder shown meanwhile, or for good when the file can't be read.
struct ThumbnailView<Placeholder: View>: View {
    let url: URL
    let maxPixelSize: Int
    var contentMode = ContentMode.fit
    @ViewBuilder let placeholder: Placeholder
    @State private var image: CGImage?

    init(url: URL, maxPixelSize: Int, contentMode: ContentMode = .fit, @ViewBuilder placeholder: () -> Placeholder) {
        self.url = url
        self.maxPixelSize = maxPixelSize
        self.contentMode = contentMode
        self.placeholder = placeholder()
        _image = State(initialValue: Thumbnail.cached(url, maxPixelSize: maxPixelSize))
    }

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder
            }
        }
        .task(id: url) {
            image = await Thumbnail.load(url, maxPixelSize: maxPixelSize)
        }
    }
}
