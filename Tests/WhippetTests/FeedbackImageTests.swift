import CryptoKit
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

struct FeedbackImageTests {
    /// A 300 × 200 image with a location and an orientation that turns it on its side.
    private func image(type: UTType, orientation: Int = 1) throws -> Data {
        let context = try #require(
            CGContext(
                data: nil, width: 300, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 300, height: 200))
        let cgImage = try #require(context.makeImage())
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil))
        let properties =
            [
                kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 52.5, kCGImagePropertyGPSLongitude: 13.4],
                kCGImagePropertyOrientation: orientation,
            ] as CFDictionary
        CGImageDestinationAddImage(destination, cgImage, properties)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func properties(of data: Data) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    @Test func removesTheLocationAndKeepsTheSize() throws {
        let original = try image(type: .jpeg)
        #expect(try properties(of: original)[kCGImagePropertyGPSDictionary] != nil)

        let prepared = try #require(FeedbackImage.prepare(original))
        let properties = try properties(of: prepared)
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 300)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == 200)
    }

    @Test func appliesTheRotationToThePixels() throws {
        // Orientation 6 shows the image turned a quarter, so it's 200 wide once applied.
        let prepared = try #require(FeedbackImage.prepare(try image(type: .jpeg, orientation: 6)))
        let properties = try properties(of: prepared)
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 200)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == 300)
        #expect((properties[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
    }

    @Test func photosBecomeHEICAndScreenshotsStayLossless() throws {
        #expect(FeedbackImage.fileExtension(of: try #require(FeedbackImage.prepare(try image(type: .jpeg)))) == "heic")
        #expect(FeedbackImage.fileExtension(of: try #require(FeedbackImage.prepare(try image(type: .png)))) == "png")
        #expect(FeedbackImage.fileExtension(of: try #require(FeedbackImage.prepare(try image(type: .tiff)))) == "png")
    }

    @Test func rejectsWhatIsntAnImage() {
        #expect(FeedbackImage.prepare(Data("not an image".utf8)) == nil)
    }

    @Test func theAdminKeyOpensASealedImage() throws {
        let adminKey = Curve25519.KeyAgreement.PrivateKey()
        let original = try image(type: .png)
        let sealed = try SealedFeedback.sealImage(original, to: adminKey.publicKey)
        #expect(sealed != original)
        #expect(try SealedFeedback.openImage(sealed, with: adminKey) == original)
        #expect(throws: (any Error).self) {
            try SealedFeedback.openImage(sealed, with: Curve25519.KeyAgreement.PrivateKey())
        }
    }
}
