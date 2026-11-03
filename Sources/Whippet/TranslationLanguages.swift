import Foundation
import NaturalLanguage

/// Which language the Translate view translates from and into. Kept apart from the Translation framework, so the
/// choices can be tested.
enum TranslationLanguages {
    /// The text's language, or nil when there's too little to tell.
    static func detect(_ text: String) -> Locale.Language? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage, language != .undetermined else { return nil }
        return Locale.Language(identifier: language.rawValue)
    }

    /// True for the same language in any region, such as `en` and `en-GB`, but not for Chinese in its two scripts.
    static func isSame(_ lhs: Locale.Language, _ rhs: Locale.Language) -> Bool {
        let left = Locale.Language(identifier: lhs.maximalIdentifier)
        let right = Locale.Language(identifier: rhs.maximalIdentifier)
        return left.languageCode == right.languageCode && left.script == right.script
    }

    /// The first of `preferred`, the Mac's preferred languages, that can be translated into, in the same region where
    /// there's a choice, such as `en-GB` for British English; English when none can.
    static func defaultTarget(preferred: [String], supported: [Locale.Language]) -> Locale.Language {
        for identifier in preferred {
            let language = Locale.Language(identifier: identifier)
            let matches = supported.filter { isSame($0, language) }
            let region = Locale.Language(identifier: language.maximalIdentifier).region
            if let match = matches.first(where: { Locale.Language(identifier: $0.maximalIdentifier).region == region })
                ?? matches.first
            {
                return match
            }
        }
        return Locale.Language(identifier: "en")
    }

    /// The language to translate text in `source` into: `chosen` when one was picked in the view, otherwise `preferred`,
    /// unless the text is already in it, when it's `last`, the language picked last time. Nil when the text is
    /// already in each of them.
    static func target(
        source: Locale.Language?, chosen: Locale.Language?, preferred: Locale.Language, last: Locale.Language?
    ) -> Locale.Language? {
        if let chosen { return chosen }
        guard let source else { return preferred }
        return [preferred, last].compactMap { $0 }.first { !isSame($0, source) }
    }

    /// Text typed with the language to translate it into, such as `hola in english`, `"hola" to French` or
    /// `bonjour into Deutsch`: the text, without quotes around it, and the language. Nil unless what follows the last
    /// `in`, `to` or `into` names one of `languages`, in the app's language, in English or in its own.
    static func parse(_ query: String, languages: [Locale.Language]) -> (text: String, target: Locale.Language)? {
        guard
            let match = query.wholeMatch(of: /(?s)\s*(.+)\s+(?i:in|to|into)\s+(\S.*?)\s*/),
            let target = namedLanguages(languages)[match.2.lowercased()]
        else { return nil }
        let text = unquoted(String(match.1).trimmingCharacters(in: .whitespacesAndNewlines))
        return text.isEmpty ? nil : (text, target)
    }

    /// Each language by its names, lowercased. A name without a region, such as `english`, is the language without
    /// one, such as `en` rather than `en-GB`.
    private static func namedLanguages(_ languages: [Locale.Language]) -> [String: Locale.Language] {
        var named: [String: Locale.Language] = [:]
        let locales = [Locale.current, Locale(identifier: "en")]
        for language in languages.sorted(by: { $0.minimalIdentifier.count < $1.minimalIdentifier.count }) {
            let own = Locale(identifier: language.minimalIdentifier)
            let codes = [language.minimalIdentifier, language.languageCode?.identifier].compactMap { $0 }
            for locale in locales + [own] {
                for code in codes {
                    if let name = locale.localizedString(forIdentifier: code)?.lowercased(), named[name] == nil {
                        named[name] = language
                    }
                }
            }
        }
        return named
    }

    private static let quotes: [(Character, Character)] = [
        ("\"", "\""), ("“", "”"), ("„", "“"), ("'", "'"), ("‘", "’"), ("«", "»"), ("「", "」"), ("『", "』"),
    ]

    private static func unquoted(_ text: String) -> String {
        guard text.count >= 2, let first = text.first, let last = text.last,
            quotes.contains(where: { $0 == (first, last) })
        else { return text }
        return String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The language's name in the app's language, such as `Spanish`, with its region where the framework offers more
    /// than one, such as `English (United Kingdom)`.
    static func name(of language: Locale.Language) -> String {
        Locale.current.localizedString(forIdentifier: language.minimalIdentifier) ?? language.minimalIdentifier
    }
}
