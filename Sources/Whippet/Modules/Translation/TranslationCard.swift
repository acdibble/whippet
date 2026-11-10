import SwiftUI
import Translation

/// Text and its translation, each over its language. The target language is a menu, and typing `in <language>` after
/// the text picks it too. Translations run from here, since a session lasts only as long as the view it belongs to.
struct TranslationCard: View {
    let module: TranslationModule
    let isSelected: Bool

    var body: some View {
        let translator = module.translator
        ResultCard(isSelected: isSelected) {
            value(translator.text, isPending: false)
        } inputLabel: {
            // Text in a language that can't be translated is sometimes taken for another, such as Farsi for Urdu, so
            // it isn't named.
            let source = translator.state == .unsupported ? nil : translator.source
            CardLabel(source.map(TranslationLanguages.name(of:)) ?? String(localized: "Detect Language"))
        } output: {
            output(translator)
        } outputLabel: {
            Menu {
                ForEach(translator.languages, id: \.minimalIdentifier) { language in
                    Button(TranslationLanguages.name(of: language)) { module.translate(into: language) }
                }
            } label: {
                CardLabel(TranslationLanguages.name(of: translator.target))
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .fixedSize()
        }
        .translationTask(translator.configuration) { @Sendable session in
            await translator.translate(using: session)
        }
    }

    @ViewBuilder
    private func output(_ translator: Translator) -> some View {
        switch translator.state {
        case .empty:
            message("Type or paste text to translate")
        case .translating, .translated:
            if let translation = translator.translation {
                value(translation, isPending: translator.state == .translating)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        case .needsDownload:
            VStack(spacing: 8) {
                message("Download these languages to translate on this Mac")
                Button("Download…") { module.downloadLanguages() }
                    .controlSize(.small)
            }
        case .unsupported:
            message("This language can't be translated on this Mac yet")
        case .sameLanguage:
            message("The text is already in this language")
        case .failed:
            message("The text couldn't be translated")
        }
    }

    private func value(_ text: String, isPending: Bool) -> some View {
        Text(text)
            .font(.system(size: 22, weight: .semibold))
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .minimumScaleFactor(0.5)
            .textSelection(.enabled)
            .opacity(isPending ? 0.5 : 1)
    }

    private func message(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Color.launcherSecondary)
            .multilineTextAlignment(.center)
    }
}

/// Downloads the languages for a translation from an invisible window. The system asks first, in a window of its own
/// that takes focus, which would close the launcher and end a session it started, so the session lives here instead.
struct TranslationDownloadView: View {
    let configuration: TranslationSession.Configuration
    let onFinish: @MainActor @Sendable () -> Void

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .translationTask(configuration) { @Sendable session in
                // Finished, or cancelled at the prompt: either way the launcher comes back.
                try? await session.prepareTranslation()
                await onFinish()
            }
    }
}
