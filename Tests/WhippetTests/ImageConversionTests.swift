import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

struct ImageConversionTests {
    /// A 4×2 PNG whose left half is opaque red and right half fully transparent.
    private func halfTransparentPNG() throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: 4, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    /// The RGB of each pixel in the top row, read back in sRGB.
    private func topRow(of data: Data) throws -> [[UInt8]] {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try #require(CGContext(
            data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return (0..<image.width).map { Array(pixels[$0 * 4..<$0 * 4 + 3]) }
    }

    @Test func convertsToJPEGAtTheSameSize() throws {
        let jpeg = try #require(ImageConversion.jpeg(from: try halfTransparentPNG()))
        let source = try #require(CGImageSourceCreateWithData(jpeg as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 4)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == 2)
    }

    @Test func transparencyBecomesWhite() throws {
        let jpeg = try #require(ImageConversion.jpeg(from: try halfTransparentPNG()))
        let row = try topRow(of: jpeg)
        // JPEG is lossy, and a 4×2 image blurs across its halves, so the colors are checked loosely.
        #expect(row[0][0] > 200 && row[0][1] < 80 && row[0][2] < 80)
        #expect(row[3].allSatisfy { $0 > 200 })
    }

    @Test func dataThatIsNotAnImageFails() {
        #expect(ImageConversion.jpeg(from: Data("not an image".utf8)) == nil)
    }
}
