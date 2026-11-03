import CoreGraphics
import Testing

@testable import WhippetCore

struct TextLayoutTests {
    /// A run of text on a page measured in lines of height 10, starting at `x` along `line`.
    private func fragment(_ text: String, line: CGFloat, x: CGFloat = 0, width: CGFloat = 100) -> TextLayout.Fragment {
        .init(text: text, bounds: CGRect(x: x, y: line * 14, width: width, height: 10))
    }

    @Test func ordersLinesFromTopToBottom() {
        let text = TextLayout.text(from: [
            fragment("third", line: 2), fragment("first", line: 0), fragment("second", line: 1),
        ])
        #expect(text == "first\nsecond\nthird")
    }

    @Test func joinsRunsOnOneLineFromLeftToRight() {
        let slightlyLower = TextLayout.Fragment(text: "Price", bounds: CGRect(x: 200, y: 2, width: 50, height: 10))
        let text = TextLayout.text(from: [slightlyLower, fragment("Name", line: 0, width: 50)])
        #expect(text == "Name Price")
    }

    @Test func joinsRightToLeftRunsFromRightToLeft() {
        let text = TextLayout.text(from: [
            fragment("سلام", line: 0, x: 200, width: 50), fragment("دنیا", line: 0, x: 0, width: 50),
        ])
        #expect(text == "سلام دنیا")
    }

    @Test func startsParagraphsAtLargerGaps() {
        let text = TextLayout.text(from: [
            fragment("one", line: 0), fragment("two", line: 1), fragment("three", line: 3), fragment("four", line: 4),
        ])
        #expect(text == "one\ntwo\n\nthree\nfour")
    }

    @Test func looselySetLinesStayOneParagraph() {
        let loose = [0, 18, 36, 54, 100].enumerated().map { index, top in
            TextLayout.Fragment(text: "line \(index)", bounds: CGRect(x: 0, y: top, width: 100, height: 10))
        }
        #expect(TextLayout.text(from: loose) == "line 0\nline 1\nline 2\nline 3\n\nline 4")
    }

    @Test func joinsWordsHyphenatedAcrossLines() {
        let text = TextLayout.text(from: [
            fragment("text recog-", line: 0), fragment("nition works", line: 1), fragment("well-", line: 2),
            fragment("done", line: 3),
        ])
        #expect(text == "text recognition\nworks\nwelldone")
    }

    @Test func leavesDashesAndCapitalizedLinesAlone() {
        let text = TextLayout.text(from: [
            fragment("Wait -", line: 0), fragment("then go", line: 1), fragment("Item-", line: 2),
            fragment("Next", line: 3),
        ])
        #expect(text == "Wait -\nthen go\nItem-\nNext")
    }

    @Test func dropsALineLeftEmptyByAHyphenatedWord() {
        let text = TextLayout.text(from: [fragment("recog-", line: 0), fragment("nition", line: 1)])
        #expect(text == "recognition")
    }

    @Test func joiningLinesKeepsParagraphs() {
        #expect(TextLayout.joiningLines("one\ntwo\n\nthree\nfour") == "one two\n\nthree four")
        #expect(TextLayout.joiningLines("") == "")
    }

    @Test func emptyWithoutText() {
        #expect(TextLayout.text(from: []) == "")
        #expect(TextLayout.text(from: [fragment("  ", line: 0)]) == "")
    }

    // MARK: - Recognized text

    @Test func codeWithACaptionIsItsContents() {
        let recognized = ImageText(text: "Scan to visit", payloads: ["https://example.com"])
        #expect(recognized.isCode)
        #expect(recognized.isLink)
        #expect(recognized.content == "https://example.com")
    }

    @Test func codeBesideLotsOfTextIsTheText() {
        let text = (1...20).map { "word\($0)" }.joined(separator: " ")
        let recognized = ImageText(text: text, payloads: ["https://example.com"])
        #expect(!recognized.isCode)
        #expect(recognized.content == text)
    }

    @Test func codesAreListedOnce() {
        let recognized = ImageText(text: "", payloads: ["WIFI:S:Home;;", "", "WIFI:S:Home;;", "other"])
        #expect(recognized.content == "WIFI:S:Home;;\nother")
        #expect(!recognized.isLink)
    }

    @Test func textWithoutCodes() {
        let recognized = ImageText(text: "hello", payloads: [])
        #expect(!recognized.isCode)
        #expect(recognized.content == "hello")
    }
}
