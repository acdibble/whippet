import Foundation
import Observation
import Translation

/// Translates the Translate view's text on this Mac with Apple's Translation framework. A session only lasts as long
/// as the view showing it, so `TranslationCard` runs each translation from its `.translationTask`, whenever
/// `configuration` changes or is invalidated, and hands the session to `translate(using:)`.
@MainActor
@Observable
final class Translator {
    enum State: Equatable {
        case empty
        case translating
        case translated
        /// The languages can be translated between once they're downloaded, which `TranslationDownloadView` does.
        case needsDownload
        /// The text's language can't be translated, such as Farsi.
        case unsupported
        /// The text is already in the language it would be translated into.
        case sameLanguage
        case failed
    }

    static let targetKey = "translateTarget"
    private static let lastTargetKey = "translateLastTarget"
    /// How long typing pauses before the text is translated.
    private static let pause = Duration.milliseconds(250)

    private(set) var state = State.empty
    /// The latest translation, shown dimmed while the next one is worked out.
    private(set) var translation: String?
    private(set) var source: Locale.Language?
    private(set) var target: Locale.Language
    /// The languages that can be translated into, by name.
    private(set) var languages: [Locale.Language] = []
    /// Read by `TranslationCard`'s translation task.
    var configuration: TranslationSession.Configuration?
    /// Off while the Translation beta feature is: nothing offers translation, and no languages are looked up.
    private(set) var isEnabled = false

    /// The text being translated, empty when there's none.
    private(set) var text = ""
    /// The language typed after the text, as in `hola in english`, which wins over any other.
    @ObservationIgnored private var typedTarget: Locale.Language?
    /// Set once a language is picked in the view, which then stays until it closes.
    @ObservationIgnored private var isTargetChosen = false
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        target = Locale.Language(identifier: "en")
        target = preferredTarget
    }

    /// Turned on and off with the Translation beta feature.
    func setEnabled(_ isEnabled: Bool) {
        guard isEnabled != self.isEnabled else { return }
        self.isEnabled = isEnabled
        guard isEnabled else {
            reset()
            languages = []
            configuration = nil
            return
        }
        Task {
            languages = await Self.supportedLanguages()
            if !isTargetChosen {
                target = preferredTarget
            }
        }
    }

    /// The language set in Settings, or the Mac's preferred language that can be translated into.
    var preferredTarget: Locale.Language {
        if let identifier = defaults.string(forKey: Self.targetKey), !identifier.isEmpty {
            return Locale.Language(identifier: identifier)
        }
        return TranslationLanguages.defaultTarget(preferred: Locale.preferredLanguages, supported: languages)
    }

    private var lastTarget: Locale.Language? {
        defaults.string(forKey: Self.lastTargetKey).map(Locale.Language.init(identifier:))
    }

    /// Starts afresh as the view opens.
    func reset() {
        pending?.cancel()
        text = ""
        typedTarget = nil
        isTargetChosen = false
        target = preferredTarget
        source = nil
        translation = nil
        state = .empty
    }

    /// Translates `text` once typing pauses, into `target` when one was typed after it.
    func setText(_ text: String, target: Locale.Language? = nil) {
        guard text != self.text || target != typedTarget else { return }
        if text.isEmpty {
            // Text that comes back later, such as another `… in english`, starts without the last translation.
            translation = nil
        }
        self.text = text
        typedTarget = target
        pending?.cancel()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            source = nil
            translation = nil
            state = .empty
            return
        }
        state = .translating
        pending = Task {
            try? await Task.sleep(for: Self.pause)
            guard !Task.isCancelled else { return }
            await prepare()
        }
    }

    /// Translates into `language` until the view closes, and remembers it for text already in the usual language.
    func choose(_ language: Locale.Language) {
        isTargetChosen = true
        typedTarget = nil
        target = language
        if !TranslationLanguages.isSame(language, preferredTarget) {
            defaults.set(language.minimalIdentifier, forKey: Self.lastTargetKey)
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        state = .translating
        pending?.cancel()
        pending = Task { await prepare() }
    }

    /// Works out the languages and whether they can be translated, then asks the view's task to translate.
    private func prepare() async {
        let text = text
        let detected = TranslationLanguages.detect(text)
        source = detected
        guard
            let target = TranslationLanguages.target(
                source: detected, chosen: typedTarget ?? (isTargetChosen ? target : nil), preferred: preferredTarget,
                last: lastTarget),
            detected.map({ !TranslationLanguages.isSame($0, target) }) ?? true
        else {
            state = .sameLanguage
            return
        }
        self.target = target
        if let detected {
            let status = await Self.status(from: detected, to: target)
            guard text == self.text else { return }
            switch status {
            case .unsupported:
                state = .unsupported
                return
            case .supported:
                state = .needsDownload
                return
            case .installed:
                break
            @unknown default:
                break
            }
        }
        request()
    }

    /// The languages that can be translated into, sorted by name.
    nonisolated static func supportedLanguages() async -> [Locale.Language] {
        await LanguageAvailability().supportedLanguages.sorted {
            TranslationLanguages.name(of: $0).localizedStandardCompare(TranslationLanguages.name(of: $1))
                == .orderedAscending
        }
    }

    nonisolated private static func status(
        from source: Locale.Language, to target: Locale.Language
    ) async -> LanguageAvailability.Status {
        await LanguageAvailability().status(from: source, to: target)
    }

    private func request() {
        if configuration?.source == source, configuration?.target == target {
            configuration?.invalidate()
        } else {
            configuration = TranslationSession.Configuration(source: source, target: target)
        }
    }

    /// Run by the view's translation task with a session for `configuration`'s languages. The session isn't
    /// `Sendable`, so it's used off the main actor, and only its results come back.
    nonisolated func translate(using session: TranslationSession) async {
        let text = await text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let translation = try? await session.translate(text).targetText
        await MainActor.run { self.finish(translation, for: text) }
    }

    /// Shows a translation, or that it failed, unless the text has changed since.
    private func finish(_ translation: String?, for text: String) {
        guard text == self.text else { return }
        if let translation {
            self.translation = translation
            state = .translated
        } else {
            state = .failed
        }
    }
}
