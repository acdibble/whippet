import AppKit
import Foundation
import Testing

struct ThumbnailTests {
    /// Writes a PNG of the given size to a temporary file.
    private func png(width: Int, height: Int) throws -> URL {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        let url = FileManager.default.temporaryDirectory.appending(path: "WhippetThumbnail-\(UUID().uuidString).png")
        try data.write(to: url)
        return url
    }

    @Test func downsamplesToTheLongerSide() async throws {
        let url = try png(width: 3000, height: 1500)
        defer { try? FileManager.default.removeItem(at: url) }

        let image = try #require(await Thumbnail.load(url, maxPixelSize: 300))
        #expect(image.width == 300)
        #expect(image.height == 150)
    }

    @Test func keepsDecodedImagesInMemory() async throws {
        let url = try png(width: 400, height: 400)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(Thumbnail.cached(url, maxPixelSize: 36) == nil)
        let first = try #require(await Thumbnail.load(url, maxPixelSize: 36))
        try FileManager.default.removeItem(at: url)
        // Served from memory even though the file is gone.
        let second = try #require(await Thumbnail.load(url, maxPixelSize: 36))
        #expect(first === second)
        #expect(Thumbnail.cached(url, maxPixelSize: 72) == nil)
    }

    @Test func aMissingFileHasNoThumbnail() async {
        let url = FileManager.default.temporaryDirectory.appending(path: "WhippetMissing-\(UUID().uuidString).png")
        #expect(await Thumbnail.load(url, maxPixelSize: 36) == nil)
    }
}
