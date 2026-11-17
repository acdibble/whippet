import Testing

let cleaner = Cleaner(shouldClean: true)

struct LinkCleaningTests {
    @Test func removesTheQuery() {
        #expect(cleaner.clean("https://example.com/page?utm_source=x&id=1", type: .link) == "https://example.com/page")
        #expect(cleaner.clean("https://example.com?a=1", type: .link) == "https://example.com")
        #expect(cleaner.clean("https://example.com/page?", type: .link) == "https://example.com/page")
    }

    @Test func keepsTheFragment() {
        #expect(
            cleaner.clean("https://example.com/page?utm_source=x#top", type: .link) == "https://example.com/page#top")
        // A `?` in the fragment isn't a query.
        #expect(cleaner.clean("https://example.com/#/route?tab=1", type: .link) == "https://example.com/#/route?tab=1")
    }

    /// Nothing else is rewritten, so a link is pasted as it was copied.
    @Test func leavesTheRestAsItWas() {
        #expect(cleaner.clean("https://example.com/a%20b/ü", type: .link) == "https://example.com/a%20b/ü")
        #expect(cleaner.clean("https://user@example.com:8080/p?q=1", type: .link) == "https://user@example.com:8080/p")
    }

    @Test func trimsStrings() {
        #expect(cleaner.clean("   hello  world    ", type: .text) == "hello  world")
    }
}
