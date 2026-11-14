import Testing

struct LinkCleaningTests {
    @Test func removesTheQuery() {
        #expect(LinkCleaning.clean("https://example.com/page?utm_source=x&id=1") == "https://example.com/page")
        #expect(LinkCleaning.clean("https://example.com?a=1") == "https://example.com")
        #expect(LinkCleaning.clean("https://example.com/page?") == "https://example.com/page")
    }

    @Test func keepsTheFragment() {
        #expect(LinkCleaning.clean("https://example.com/page?utm_source=x#top") == "https://example.com/page#top")
        // A `?` in the fragment isn't a query.
        #expect(LinkCleaning.clean("https://example.com/#/route?tab=1") == "https://example.com/#/route?tab=1")
    }

    /// Nothing else is rewritten, so a link is pasted as it was copied.
    @Test func leavesTheRestAsItWas() {
        #expect(LinkCleaning.clean("https://example.com/a%20b/ü") == "https://example.com/a%20b/ü")
        #expect(LinkCleaning.clean("https://user@example.com:8080/p?q=1") == "https://user@example.com:8080/p")
    }
}
