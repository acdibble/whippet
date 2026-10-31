import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Images attached to feedback: kept at full size, but decoded and encoded again so location, camera and other
/// metadata never leave the Mac.
enum FeedbackImage {
    static let limit = 10

    /// Lossless formats stay lossless as PNG, and photos become HEIC, which keeps them close to their original size.
    /// Rotation from the metadata is applied to the pixels, so the image still looks the same without it.
    static func prepare(_ data: Data) -> Data? {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        let options =
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(width, height),
            ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }

        let sourceType = CGImageSourceGetType(source).flatMap { UTType($0 as String) }
        let isPhoto =
            sourceType.map { $0.conforms(to: .jpeg) || $0.conforms(to: .heic) || $0.conforms(to: .heif) } ?? false
        let type: UTType = isPhoto ? .heic : .png
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else {
            return nil
        }
        let encoding = isPhoto ? [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary : nil
        CGImageDestinationAddImage(destination, image, encoding)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// The image data on the pasteboard: image files copied in Finder, or an image copied from an app, such as a
    /// screenshot. Nil when it holds neither, or holds text too, as apps such as Word add a picture of copied text, so
    /// text pastes as usual.
    static func images(on pasteboard: NSPasteboard) -> [Data]? {
        let fileURLs =
            pasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true, .urlReadingContentsConformToTypes: [UTType.image.identifier]]
            ) as? [URL] ?? []
        if !fileURLs.isEmpty {
            return fileURLs.compactMap { try? Data(contentsOf: $0) }
        }
        guard pasteboard.availableType(from: [.string]) == nil else { return nil }
        let types = [
            NSPasteboard.PasteboardType.png, .tiff, NSPasteboard.PasteboardType(UTType.heic.identifier),
            NSPasteboard.PasteboardType(UTType.jpeg.identifier),
        ]
        guard let type = pasteboard.availableType(from: types), let data = pasteboard.data(forType: type) else {
            return nil
        }
        return [data]
    }

    /// A small copy for showing in a list.
    static func thumbnail(of data: Data, maxPixelSize: Int) -> CGImage? {
        let options =
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            ] as CFDictionary
        return CGImageSourceCreateWithData(data as CFData, nil).flatMap {
            CGImageSourceCreateThumbnailAtIndex($0, 0, options)
        }
    }

    /// The extension the image's format uses, for opening it in another app.
    static func fileExtension(of data: Data) -> String {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let type = CGImageSourceGetType(source).flatMap({ UTType($0 as String) })
        else { return "png" }
        return type.preferredFilenameExtension ?? "png"
    }
}
