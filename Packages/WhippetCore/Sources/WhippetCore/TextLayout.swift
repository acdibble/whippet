import CoreGraphics
import Foundation

/// Puts text recognized in an image back together in reading order. Recognition finds each run of text on its own,
/// in no particular order, so the runs are gathered into lines from top to bottom, and the lines into paragraphs
/// wherever the space between them grows.
public enum TextLayout {
    /// A run of text and where it is, measured from the image's top left. Positions are only compared along the same
    /// axis, so the two axes may use different units, as recognition's fractions of the image's width and height do.
    public struct Fragment: Sendable, Equatable {
        public var text: String
        public var bounds: CGRect

        public init(text: String, bounds: CGRect) {
            self.text = text
            self.bounds = bounds
        }
    }

    /// Two runs are on the same line when they overlap by more than this much of the shorter one's height.
    private static let sameLineOverlap = 0.5
    /// A space between lines starts a new paragraph when it's taller than a typical run of text, and, with enough
    /// lines to tell how far apart they usually are, this much larger than the usual space. Text set loosely, with
    /// line spacing of 1.6 or more, then still reads as one paragraph.
    private static let paragraphGap = 1.5
    /// How many spaces between lines it takes to tell the usual one.
    private static let gapsForUsualGap = 3

    /// Lines separated by `\n` and paragraphs by `\n\n`, with words hyphenated across a line joined up again.
    public static func text(from fragments: [Fragment]) -> String {
        let fragments =
            fragments
            .map { Fragment(text: $0.text.trimmingCharacters(in: .whitespaces), bounds: $0.bounds) }
            .filter { !$0.text.isEmpty }
            .sorted { $0.bounds.minY < $1.bounds.minY }
        guard !fragments.isEmpty else { return "" }

        var lines: [Line] = []
        for fragment in fragments {
            if let last = lines.indices.last, lines[last].contains(fragment) {
                lines[last].add(fragment)
            } else {
                lines.append(Line(fragment))
            }
        }

        let gaps = zip(lines, lines.dropFirst()).map { previous, line in line.top - previous.bottom }
        let threshold = max(
            median(fragments.map(\.bounds.height)),
            gaps.count >= gapsForUsualGap ? median(gaps) * paragraphGap : 0
        )
        var paragraphs: [[String]] = [[lines[0].text]]
        for (line, gap) in zip(lines.dropFirst(), gaps) {
            if gap > threshold {
                paragraphs.append([line.text])
            } else {
                paragraphs[paragraphs.count - 1].append(line.text)
            }
        }
        return paragraphs.map { joinHyphenatedWords($0).joined(separator: "\n") }.joined(separator: "\n\n")
    }

    private static func median(_ values: [CGFloat]) -> CGFloat {
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    /// The text with each paragraph's lines joined by spaces, for copying text without the breaks where its lines
    /// happened to wrap.
    public static func joiningLines(_ text: String) -> String {
        text.components(separatedBy: "\n\n")
            .map { paragraph in
                paragraph.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                    .joined(separator: " ")
            }
            .joined(separator: "\n\n")
    }

    /// Moves the end of a word broken with a hyphen, such as `recog-` and `nition`, up to the line it began on.
    /// Only a hyphen after a letter and before a lowercase letter counts, so a dash or a list of items stays as it is.
    private static func joinHyphenatedWords(_ lines: [String]) -> [String] {
        var lines = lines
        var index = 0
        while index < lines.count - 1 {
            let line = lines[index]
            let next = lines[index + 1]
            if line.hasSuffix("-"), line.dropLast().last?.isLetter == true, next.first?.isLowercase == true {
                let rest = next.drop { !$0.isWhitespace }
                lines[index] = String(line.dropLast()) + next.prefix(next.count - rest.count)
                lines[index + 1] = rest.trimmingCharacters(in: .whitespaces)
                if lines[index + 1].isEmpty {
                    lines.remove(at: index + 1)
                    continue
                }
            }
            index += 1
        }
        return lines
    }

    private struct Line {
        var fragments: [Fragment]
        var top: CGFloat
        var bottom: CGFloat
        /// The shortest run's height, so a tall run such as a heading doesn't pull in the line below it.
        var height: CGFloat

        init(_ fragment: Fragment) {
            fragments = [fragment]
            top = fragment.bounds.minY
            bottom = fragment.bounds.maxY
            height = fragment.bounds.height
        }

        func contains(_ fragment: Fragment) -> Bool {
            let overlap = min(bottom, fragment.bounds.maxY) - max(top, fragment.bounds.minY)
            return overlap > min(height, fragment.bounds.height) * TextLayout.sameLineOverlap
        }

        mutating func add(_ fragment: Fragment) {
            fragments.append(fragment)
            top = min(top, fragment.bounds.minY)
            bottom = max(bottom, fragment.bounds.maxY)
            height = min(height, fragment.bounds.height)
        }

        /// Runs from left to right, or right to left when most of the line's letters are in a right-to-left script
        /// such as Farsi.
        var text: String {
            let ordered = fragments.sorted { $0.bounds.minX < $1.bounds.minX }
            let isRightToLeft = TextLayout.isRightToLeft(fragments.map(\.text).joined())
            return (isRightToLeft ? ordered.reversed() : ordered).map(\.text).joined(separator: " ")
        }
    }

    static func isRightToLeft(_ text: String) -> Bool {
        var rightToLeft = 0
        var leftToRight = 0
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            switch scalar.value {
            // Hebrew, Arabic, Syriac, Thaana, NKo, Samaritan and their presentation forms.
            case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF: rightToLeft += 1
            default: leftToRight += 1
            }
        }
        return rightToLeft > leftToRight
    }
}

/// What recognition found in an image: its text, laid out by `TextLayout`, and what any QR codes or barcodes in it
/// encode.
public struct ImageText: Sendable, Equatable {
    public var text: String
    /// Each code's contents, once, in the order they were found.
    public var payloads: [String]

    /// A code with no more than this many words beside it, such as a caption, is what the image is of.
    private static let captionWords = 12

    public init(text: String, payloads: [String]) {
        self.text = text
        var seen = Set<String>()
        self.payloads = payloads.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// True when the image is mostly a code, such as a QR code with a caption, so what it encodes is what's wanted.
    public var isCode: Bool {
        !payloads.isEmpty && text.split(whereSeparator: \.isWhitespace).count <= Self.captionWords
    }

    /// What's saved as the image's text and copied from it: the codes' contents when the image is mostly a code,
    /// otherwise the text.
    public var content: String {
        isCode ? payloads.joined(separator: "\n") : text
    }

    /// True when the content is a single web link, such as a QR code for a page.
    public var isLink: Bool {
        guard isCode, payloads.count == 1, let url = URL(string: payloads[0]) else { return false }
        return url.scheme == "http" || url.scheme == "https"
    }
}
