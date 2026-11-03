import AppKit
import CoreImage
import Testing

@testable import WhippetCore

struct TextRecognitionTests {
    /// Black text on white, as a Retina screenshot of a page would show it, with loose line spacing of 1.6.
    private func image(lines: [String]) throws -> CGImage {
        let size = CGSize(width: 1200, height: 90 * lines.count + 80)
        let image = NSImage(size: size, flipped: true) { bounds in
            NSColor.white.setFill()
            bounds.fill()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 56), .foregroundColor: NSColor.black,
            ]
            for (index, line) in lines.enumerated() {
                (line as NSString).draw(at: CGPoint(x: 40, y: 40 + index * 90), withAttributes: attributes)
            }
            return true
        }
        return try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
    }

    private func qrCode(_ message: String) throws -> CGImage {
        let filter = try #require(CIFilter(name: "CIQRCodeGenerator"))
        filter.setValue(Data(message.utf8), forKey: "inputMessage")
        let output = try #require(filter.outputImage).transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        // A quiet zone of white around the code, which readers need to find it.
        let padded = output.composited(
            over: CIImage(color: .white).cropped(to: output.extent.insetBy(dx: -60, dy: -60)))
        return try #require(CIContext().createCGImage(padded, from: padded.extent))
    }

    @Test func readsLinesInOrder() throws {
        let recognized = TextRecognition.recognize(
            in: try image(lines: ["Whippet launcher", "Capture some text"]))
        #expect(recognized.text == "Whippet launcher\nCapture some text")
        #expect(recognized.payloads.isEmpty)
    }

    @Test func readsWhatAQRCodeEncodes() throws {
        let recognized = TextRecognition.recognize(in: try qrCode("https://example.com/whippet"))
        #expect(recognized.payloads == ["https://example.com/whippet"])
        #expect(recognized.isLink)
        #expect(recognized.content == "https://example.com/whippet")
    }
}
