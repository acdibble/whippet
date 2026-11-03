import Foundation
import Testing

struct TranslationLanguagesTests {
    private let supported = ["en-GB", "en", "es", "fr", "de", "zh", "zh-TW"].map { Locale.Language(identifier: $0) }

    private func language(_ identifier: String) -> Locale.Language {
        Locale.Language(identifier: identifier)
    }

    @Test func defaultTargetIsTheFirstPreferredLanguageThatCanBeTranslatedInto() {
        let target = TranslationLanguages.defaultTarget(preferred: ["fa-IR", "de-DE", "en-US"], supported: supported)
        #expect(target.minimalIdentifier == "de")
    }

    @Test func defaultTargetKeepsThePreferredRegion() {
        let british = TranslationLanguages.defaultTarget(preferred: ["en-GB"], supported: supported)
        #expect(british.minimalIdentifier == "en-GB")
        let american = TranslationLanguages.defaultTarget(preferred: ["en-US"], supported: supported)
        #expect(american.minimalIdentifier == "en")
    }

    @Test func defaultTargetFallsBackToEnglish() {
        let target = TranslationLanguages.defaultTarget(preferred: ["fa-IR"], supported: supported)
        #expect(target.minimalIdentifier == "en")
    }

    @Test func chosenTargetWins() {
        let target = TranslationLanguages.target(
            source: language("es"), chosen: language("fr"), preferred: language("en"), last: language("de"))
        #expect(target.map { TranslationLanguages.isSame($0, language("fr")) } == true)
    }

    @Test func textInAnotherLanguageGoesToThePreferredLanguage() {
        let target = TranslationLanguages.target(
            source: language("es"), chosen: nil, preferred: language("en"), last: language("de"))
        #expect(target.map { TranslationLanguages.isSame($0, language("en")) } == true)
    }

    @Test func textAlreadyInThePreferredLanguageGoesToTheLastChosen() {
        let target = TranslationLanguages.target(
            source: language("en-GB"), chosen: nil, preferred: language("en"), last: language("de"))
        #expect(target.map { TranslationLanguages.isSame($0, language("de")) } == true)
    }

    @Test func textAlreadyInEveryLanguageHasNoTarget() {
        #expect(
            TranslationLanguages.target(source: language("en"), chosen: nil, preferred: language("en"), last: nil)
                == nil)
    }

    @Test func undetectedTextGoesToThePreferredLanguage() {
        let target = TranslationLanguages.target(source: nil, chosen: nil, preferred: language("en"), last: nil)
        #expect(target.map { TranslationLanguages.isSame($0, language("en")) } == true)
    }

    @Test func regionsAreTheSameLanguageButScriptsArent() {
        #expect(TranslationLanguages.isSame(language("en"), language("en-GB")))
        #expect(!TranslationLanguages.isSame(language("zh"), language("zh-TW")))
        #expect(!TranslationLanguages.isSame(language("en"), language("es")))
    }

    @Test(arguments: [
        ("hola in english", "hola", "en"),
        ("\"翻訳者は言葉の魔術師である\" in english", "翻訳者は言葉の魔術師である", "en"),
        ("“bonjour” to German", "bonjour", "de"),
        ("where is the station into spanish", "where is the station", "es"),
        ("bread in a box to français", "bread in a box", "fr"),
        ("hello in Chinese", "hello", "zh"),
        ("hello in English (United Kingdom)", "hello", "en-GB"),
    ])
    func parsesTextWithALanguage(_ query: String, _ text: String, _ target: String) throws {
        let parsed = try #require(TranslationLanguages.parse(query, languages: supported))
        #expect(parsed.text == text)
        #expect(parsed.target.minimalIdentifier == target)
    }

    @Test(arguments: ["hola", "5 km in miles", "3pm in london", "in english", "\"\" in english", "hola in klingon"])
    func leavesOtherTextAlone(_ query: String) {
        #expect(TranslationLanguages.parse(query, languages: supported) == nil)
    }

    @Test func detectsTheTextsLanguage() {
        let detected = TranslationLanguages.detect("¿Dónde está la biblioteca? Necesito un libro.")
        #expect(detected.map { TranslationLanguages.isSame($0, language("es")) } == true)
        #expect(TranslationLanguages.detect("") == nil)
    }
}
