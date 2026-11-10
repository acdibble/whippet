import AppKit
import SwiftUI
import Translation

/// Translating text on this Mac, with Apple's translation: typed with a language after it in the main search, or in
/// the Translate screen.
@MainActor
final class TranslationModule: LauncherModule {
    let manifest = ModuleManifest.translation
    let translator = Translator()
    private var isDownloading = false
    /// Holds the session downloading translation languages while the system asks to.
    private var downloadWindow: NSWindow?
    private weak var host: (any ModuleHost)?

    func attach(to host: any ModuleHost) {
        self.host = host
    }

    func update(_ modules: ModuleSettings) {
        translator.setEnabled(modules.isEnabled(manifest.ref))
    }

    var activity: [ActivityLock] {
        guard isDownloading else { return [] }
        return [
            ActivityLock(
                module: manifest.id, rows: ["translate", "card"],
                reason: String(localized: "Downloading translation languages"))
        ]
    }

    var revision: AnyHashable {
        [AnyHashable(translator.isEnabled), AnyHashable(translator.text)]
    }

    /// Text typed as `<text> in <language>` is translated in the main search.
    func searchTextChanged(_ query: String) {
        guard translator.isEnabled, host?.modules.isEnabled(.translationCard) ?? true else {
            if translator.isEnabled { translator.setText("", target: nil) }
            return
        }
        let typed = TranslationLanguages.parse(query, languages: translator.languages)
        translator.setText(typed?.text ?? "", target: typed?.target)
    }

    func contributions(for query: String) -> [Contribution] {
        guard translator.isEnabled, !query.isEmpty else { return [] }
        var contributions: [Contribution] = []
        if !translator.text.isEmpty {
            // The card translates the text already, so the Translate screen isn't offered for it as well.
            contributions.append(.pinned(cardItem(ref: .translationCard)))
        } else {
            let item = LauncherItem(
                id: "with:translate", module: manifest.id, title: String(localized: "Translate"),
                subtitle: String(localized: "Command"), icon: .symbol("translate"), launchKey: "command:translate",
                refs: [.translate, .translationFallback])
            contributions.append(.fallback(item, tier: 1))
        }
        return contributions
    }

    var generalSettings: GeneralSettings? {
        GeneralSettings(section: { AnyView(TranslationSettings()) })
    }

    func cardItem(ref: ModuleRef) -> LauncherItem {
        LauncherItem(
            id: "translation", module: manifest.id, title: String(localized: "Translation"), icon: .symbol("translate"),
            section: String(localized: "Translate"), refs: [ref], payload: Card(ref: ref))
    }

    /// The translation of what's typed, for `ref`: the card in the main search, or the Translate screen.
    struct Card: Hashable {
        let ref: ModuleRef
    }

    func rowView(for item: LauncherItem, isSelected: Bool) -> AnyView? {
        guard item.payload(as: Card.self) != nil else { return nil }
        return AnyView(TranslationCard(module: self, isSelected: isSelected))
    }

    func actions(for item: LauncherItem) -> [ItemAction] {
        if let card = item.payload(as: Card.self) {
            return cardActions(for: card.ref)
        }
        if item.id == "with:translate" {
            return [
                ItemAction(
                    id: "translate.text", title: String(localized: "Translate"), icon: "return",
                    owner: .translationFallback, recordsLaunch: true
                ) { [weak self] in
                    guard let self, let host else { return .stay }
                    let text = host.query
                    host.push(screen())
                    host.query = text
                    return .stay
                }
            ]
        }
        return [.open(owner: .translate) { [weak self] in self.map { .push($0.screen()) } ?? .stay }]
    }

    private func cardActions(for ref: ModuleRef) -> [ItemAction] {
        guard let host else { return [] }
        let paste = { [translator] (copyOnly: Bool) -> ActionOutcome in
            guard translator.state == .translated, let translation = translator.translation else { return .fail() }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(translation, forType: .string)
            return host.dismissAndPaste(copyOnly: copyOnly, for: ref)
        }
        return [
            ItemAction(
                id: "translation.paste",
                title: host.targetApp == nil
                    ? String(localized: "Copy to Clipboard") : String(localized: "Paste Translation"),
                icon: "return"
            ) { paste(false) },
            ItemAction(
                id: "translation.copy", title: String(localized: "Copy"), icon: "doc.on.doc",
                shortcut: .commandReturn
            ) { paste(true) },
            ItemAction(id: "translation.copy-original", title: String(localized: "Copy Original"), icon: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(host.query, forType: .string)
                return host.dismissAndPaste(copyOnly: true, for: ref)
            },
            ItemAction(
                id: "translation.swap", title: String(localized: "Swap Languages"), icon: "arrow.left.arrow.right",
                shortcut: KeyShortcut("s", [.command, .shift])
            ) { [weak self] in
                self?.swapLanguages() ?? .stay
            },
        ]
    }

    func screen() -> TranslateScreen {
        TranslateScreen(module: self, host: host)
    }

    /// Translates into `language`, rewriting the language typed after the text, if there's one, so the two agree.
    func translate(into language: Locale.Language) {
        guard let host else { return }
        if let typed = TranslationLanguages.parse(host.query, languages: translator.languages) {
            host.query = "\(typed.text) in \(TranslationLanguages.name(of: language))"
        } else {
            translator.choose(language)
        }
    }

    /// Translates the translation back: its language becomes the one translated into, and it becomes the text.
    private func swapLanguages() -> ActionOutcome {
        guard let host, translator.state == .translated, let translation = translator.translation,
            let source = translator.source
        else { return .fail() }
        if TranslationLanguages.parse(host.query, languages: translator.languages) != nil {
            host.query = "\(translation) in \(TranslationLanguages.name(of: source))"
        } else {
            translator.choose(source)
            host.query = translation
        }
        return .stay
    }

    /// Downloads the languages the text is translated between, then opens the launcher again where it was, so the
    /// text is translated straight away.
    func downloadLanguages() {
        guard let host else { return }
        let query = host.query
        let inScreen = host.isTranslateScreenOpen
        // Opening the launcher again puts Whippet in front, so the app to paste into is remembered.
        let targetApp = host.targetApp
        isDownloading = true
        download(TranslationSession.Configuration(source: translator.source, target: translator.target)) {
            [weak self] in
            guard let self else { return }
            isDownloading = false
            host.openDirectly {
                if inScreen { host.push(self.screen()) }
            }
            host.query = query
            host.restoreTarget(targetApp)
        }
    }

    /// Downloads languages, which the system confirms in a window of its own, calling back once it's done or
    /// cancelled. The panel closes for it, and the session lives in a window that can't be seen or clicked.
    private func download(_ configuration: TranslationSession.Configuration, onFinish: @escaping () -> Void) {
        host?.closePanelForWindow()
        let view = TranslationDownloadView(configuration: configuration) { [weak self] in
            self?.downloadWindow?.close()
            self?.downloadWindow = nil
            onFinish()
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1), styleMask: [.borderless], backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.contentView = NSHostingView(rootView: view)
        downloadWindow = window
        window.orderFrontRegardless()
    }

}

extension ModuleHost {
    fileprivate var isTranslateScreenOpen: Bool {
        activeScreen is TranslateScreen
    }
}

/// Text to translate, typed or pasted, with its translation, and what else it can be used with.
@MainActor
final class TranslateScreen: LauncherScreen {
    private let module: TranslationModule
    private weak var host: (any ModuleHost)?

    init(module: TranslationModule, host: (any ModuleHost)?) {
        self.module = module
        self.host = host
        module.translator.reset()
    }

    let id = "translate"

    var searchBar: SearchBar {
        .field(placeholder: String(localized: "Text to translate"))
    }

    var revision: AnyHashable { module.translator.text }

    func items(for query: String) -> [LauncherItem] {
        // What the text can be used with too, as in the main search, except this screen.
        let fallbacks = query.isEmpty ? [] : host?.fallbacks(for: query, excluding: module.id) ?? []
        return [module.cardItem(ref: .translate)] + fallbacks
    }

    func actions(for item: LauncherItem) -> [ItemAction] {
        if item.module == module.id {
            return module.actions(for: item)
        }
        return host?.ownActions(for: item) ?? []
    }

    func sectionTitle(at index: Int, in items: [LauncherItem]) -> String? {
        index == 0 ? String(localized: "Translate") : String(localized: "Use “\(host?.query ?? "")” with…")
    }

    /// The card stays put while what its text can be used with scrolls under it.
    func pinnedCount(in items: [LauncherItem]) -> Int {
        min(items.count, 1)
    }

    func rowView(for item: LauncherItem, index: Int, isSelected: Bool) -> AnyView? {
        module.rowView(for: item, isSelected: isSelected)
    }

    func queryChanged(_ query: String) {
        let typed = TranslationLanguages.parse(query, languages: module.translator.languages)
        module.translator.setText(typed?.text ?? query, target: typed?.target)
    }
}

/// Translate in Settings › General: the language to translate into, and where downloaded languages are managed.
private struct TranslationSettings: View {
    /// Empty for Automatic, the Mac's preferred language.
    @AppStorage(Translator.targetKey) private var translateTarget = ""
    @State private var translationLanguages: [Locale.Language] = []

    var body: some View {
        Section("Translate") {
            Picker("Translate To", selection: $translateTarget) {
                Text("Automatic").tag("")
                ForEach(translationLanguages, id: \.minimalIdentifier) { language in
                    Text(TranslationLanguages.name(of: language)).tag(language.minimalIdentifier)
                }
            }
            LabeledContent {
                Button("Manage Languages…") {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension")!)
                }
            } label: {
                Text("Downloaded Languages")
                Text("Managed in System Settings › General › Language & Region › Translation Languages")
            }
        }
        .task { translationLanguages = await Translator.supportedLanguages() }
    }
}
