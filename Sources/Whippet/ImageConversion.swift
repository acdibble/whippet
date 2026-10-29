import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Converts a stored image to another format as it's pasted, leaving the stored image as it is.
enum ImageConversion {
    /// High enough that the loss is hard to see, while the file stays a fraction of the PNG's size.
    static let jpegQuality = 0.85

    /// JPEG has no transparency, so transparent areas become white rather than black.
    static func jpeg(from data: Data) -> Data? {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        // Grey and indexed images are drawn into RGB, which JPEG encoders handle everywhere.
        let colorSpace = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)
        guard
            let colorSpace,
            let context = CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(bounds)
        context.draw(image, in: bounds)
        guard let flattened = context.makeImage() else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        let options = [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary
        CGImageDestinationAddImage(destination, flattened, options)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
