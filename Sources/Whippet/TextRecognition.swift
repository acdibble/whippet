import CoreGraphics
import Foundation
import Vision
import WhippetCore

/// Reads the text, and any QR codes or barcodes, in an image: one copied to clipboard history, or an area of the screen
/// picked with Capture Text. It's slow enough to keep off the main thread.
enum TextRecognition {
    /// Whether text copied from the screen or an image keeps the breaks where its lines wrapped.
    static let keepsLineBreaksKey = "textKeepsLineBreaks"

    nonisolated static func recognize(in file: URL) -> ImageText {
        recognize(with: VNImageRequestHandler(url: file))
    }

    nonisolated static func recognize(in image: CGImage) -> ImageText {
        recognize(with: VNImageRequestHandler(cgImage: image))
    }

    /// Text as it's copied: with or without line breaks, as set in Settings. A code's contents are copied as they are.
    @MainActor
    static func forCopying(_ text: String, isCode: Bool = false) -> String {
        let keepsLineBreaks = UserDefaults.standard.object(forKey: keepsLineBreaksKey) as? Bool ?? true
        return keepsLineBreaks || isCode ? text : TextLayout.joiningLines(text)
    }

    nonisolated private static func recognize(with handler: VNImageRequestHandler) -> ImageText {
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.automaticallyDetectsLanguage = true
        textRequest.usesLanguageCorrection = true
        let codeRequest = VNDetectBarcodesRequest()
        try? handler.perform([textRequest, codeRequest])
        // Vision measures from the bottom left, as fractions of the image's size.
        let fragments = (textRequest.results ?? []).compactMap { observation -> TextLayout.Fragment? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let box = observation.boundingBox
            return TextLayout.Fragment(
                text: text, bounds: CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height))
        }
        return ImageText(
            text: TextLayout.text(from: fragments),
            payloads: (codeRequest.results ?? []).compactMap(\.payloadStringValue)
        )
    }
}
