import Foundation
import Testing

struct PageImageTests {
    private let page = URL(string: "https://github.com/acdibble/whippet/releases/tag/v0.10.0")!

    @Test func findsTheOpenGraphImage() {
        let html = """
            <head><meta name="twitter:image" content="https://example.com/twitter.png" />
            <meta property="og:image" content="https://opengraph.githubassets.com/abc/acdibble/whippet" /></head>
            """
        #expect(PageImage.url(inHTML: html, baseURL: page)?.absoluteString == "https://opengraph.githubassets.com/abc/acdibble/whippet")
    }

    @Test func fallsBackToTheTwitterImage() {
        let html = #"<meta content='https://example.com/card.png?a=1&amp;b=2' name='twitter:image'>"#
        #expect(PageImage.url(inHTML: html, baseURL: page)?.absoluteString == "https://example.com/card.png?a=1&b=2")
    }

    @Test func resolvesARelativeImageAgainstThePage() {
        let html = #"<META PROPERTY="og:image" CONTENT="/images/card.png">"#
        #expect(PageImage.url(inHTML: html, baseURL: page)?.absoluteString == "https://github.com/images/card.png")
    }

    @Test func readsQuotedValuesAndEntitiesLikeABrowser() {
        let html = #"<meta data-note="a > b" property="og:image" content="https://example.com/a.png?q=1&#x26;r=2&amp;quot;">"#
        #expect(PageImage.url(inHTML: html, baseURL: page)?.absoluteString == "https://example.com/a.png?q=1&r=2&quot;")
    }

    @Test func readsAHeadCutOffBeforeTheBody() {
        let html = #"<!DOCTYPE html><html><head><title>Whippet</title><meta property="og:image" content="https://example.com/a.png"></head>"#
        #expect(PageImage.url(inHTML: html, baseURL: page)?.absoluteString == "https://example.com/a.png")
    }

    @Test func ignoresPagesWithoutOneAndOtherSchemes() {
        #expect(PageImage.url(inHTML: #"<meta property="og:title" content="Whippet">"#, baseURL: page) == nil)
        #expect(PageImage.url(inHTML: #"<meta property="og:image" content="javascript:alert(1)">"#, baseURL: page) == nil)
        #expect(PageImage.url(inHTML: #"<meta property="og:image" content="">"#, baseURL: page) == nil)
    }
}
