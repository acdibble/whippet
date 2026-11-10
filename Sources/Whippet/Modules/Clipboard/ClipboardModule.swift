import AppKit
import Observation
import SwiftUI
import WhippetCore

/// What's copied, kept to search and paste again, with previews of copied links.
@MainActor
final class ClipboardModule: LauncherModule {
    let manifest = ModuleManifest.clipboard
    let clipboard: ClipboardHistory
    /// Asks where to save an image, as PNG or JPEG.
    private let saveImage: (ClipboardItem) -> Void
    private weak var host: (any ModuleHost)?

    init(clipboard: ClipboardHistory, saveImage: @escaping (ClipboardItem) -> Void) {
        self.clipboard = clipboard
        self.saveImage = saveImage
    }

    func attach(to host: any ModuleHost) {
        self.host = host
    }

    func update(_ modules: ModuleSettings) {
        clipboard.isRecording = modules.isEnabled(.clipboardRecording)
        clipboard.allowsLinkPreviews = modules.isEnabled(manifest.ref)
    }

    func contributions(for query: String) -> [Contribution] {
        var contributions: [Contribution] = [
            .listed(
                .command(
                    .clipboardHistory, id: "command:clipboard-history",
                    title: String(localized: "Clipboard History"), icon: .symbol("list.clipboard")))
        ]
        if !query.isEmpty {
            // Counted as using Clipboard History itself; it's only there while text is typed, so not a favorite.
            let item = LauncherItem(
                id: "with:clipboard-history", module: manifest.id, title: String(localized: "Search Clipboard History"),
                subtitle: String(localized: "Command"), icon: .symbol("list.clipboard"),
                launchKey: "command:clipboard-history", refs: [.clipboardHistory, .clipboardSearchFallback])
            contributions.append(.fallback(item, tier: 2))
        }
        return contributions
    }

    func actions(for item: LauncherItem) -> [ItemAction] {
        if item.id == "with:clipboard-history" {
            return [
                ItemAction(
                    id: "clipboard.search", title: String(localized: "Search"), icon: "return",
                    owner: .clipboardSearchFallback, recordsLaunch: true
                ) { [weak self] in
                    guard let self, let host else { return .stay }
                    let text = host.query
                    host.push(screen())
                    host.query = text
                    return .stay
                }
            ]
        }
        return [.open(owner: .clipboardHistory) { [weak self] in self.map { .push($0.screen()) } ?? .stay }]
    }

    func screen() -> ClipboardScreen {
        ClipboardScreen(clipboard: clipboard, host: host, saveImage: saveImage)
    }

    func run(command: String) {
        host?.openDirectly { [weak self] in
            guard let self else { return }
            host?.push(screen())
        }
    }

    var settingsPane: ModuleSettingsPane? {
        ModuleSettingsPane(title: String(localized: "Clipboard History"), symbol: "list.clipboard.fill", tint: .teal) {
            [clipboard] in AnyView(ClipboardPane(clipboard: clipboard))
        }
    }
}

/// Clipboard history: copies newest first, pinned ones above them, beside the selected copy's preview, filtered by
/// what's typed and by kind.
@MainActor
@Observable
final class ClipboardScreen: LauncherScreen {
    var kind: ClipboardKind?
    @ObservationIgnored private let clipboard: ClipboardHistory
    @ObservationIgnored private weak var host: (any ModuleHost)?
    @ObservationIgnored private let saveImage: (ClipboardItem) -> Void

    init(clipboard: ClipboardHistory, host: (any ModuleHost)?, saveImage: @escaping (ClipboardItem) -> Void) {
        self.clipboard = clipboard
        self.host = host
        self.saveImage = saveImage
    }

    let id = "clipboard"

    var searchBar: SearchBar {
        .field(placeholder: String(localized: "Type to filter entries…"))
    }

    var revision: AnyHashable {
        [clipboard.revision, kind?.rawValue.hashValue ?? -1]
    }

    func accessory() -> AnyView? {
        AnyView(ClipboardKindMenu(screen: self))
    }

    var content: ScreenContent {
        .custom(AnyView(ClipboardHistoryView(clipboard: clipboard)))
    }

    var footer: ScreenFooter {
        .actions(
            badge: CommandBadge(
                title: String(localized: "Clipboard History"), symbol: "list.clipboard.fill", tint: .orange))
    }

    func items(for query: String) -> [LauncherItem] {
        clipboard.search(query, kind: kind).map { item in
            LauncherItem(
                id: "clipboard:\(item.id)", module: ModuleManifest.clipboard.id, title: item.title,
                icon: .symbol(item.kind.symbolName), payload: item)
        }
    }

    /// The newest copy rather than the pinned items above it.
    func initialSelection(in items: [LauncherItem]) -> Int {
        items.firstIndex { $0.payload(as: ClipboardItem.self)?.pinnedAt == nil } ?? 0
    }

    func back() -> Bool {
        guard kind != nil else { return false }
        kind = nil
        return true
    }

    func actions(for item: LauncherItem) -> [ItemAction] {
        guard let clip = item.payload(as: ClipboardItem.self), let host else { return [] }
        return Self.pasteActions(for: clip, clipboard: clipboard, host: host) + more(for: clip, host: host)
    }

    /// Paste and copy, for a copy wherever it's listed, such as the calculator's numbers.
    static func pasteActions(for item: ClipboardItem, clipboard: ClipboardHistory, host: any ModuleHost)
        -> [ItemAction]
    {
        let deliver = { (copyOnly: Bool) -> ActionOutcome in
            guard clipboard.copy(item) else { return .fail() }
            return host.dismissAndPaste(copyOnly: copyOnly, for: .clipboardHistory)
        }
        return [
            ItemAction(id: "clipboard.paste", title: pasteTitle(host), icon: "return") { deliver(false) },
            ItemAction(
                id: "clipboard.copy", title: String(localized: "Copy"), icon: "doc.on.doc",
                shortcut: .commandReturn
            ) { deliver(true) },
        ]
    }

    static func pasteTitle(_ host: any ModuleHost) -> String {
        host.targetApp?.localizedName.map { String(localized: "Paste to \($0)") }
            ?? String(localized: "Copy to Clipboard")
    }

    private func more(for item: ClipboardItem, host: any ModuleHost) -> [ItemAction] {
        var actions = [
            ItemAction(
                id: "clipboard.pin",
                title: item.pinnedAt == nil ? String(localized: "Pin") : String(localized: "Unpin"),
                icon: "pin", shortcut: KeyShortcut("p", [.command, .shift])
            ) { [clipboard] in
                clipboard.setPinned(item.pinnedAt == nil, item: item)
                return .keepSelection
            }
        ]
        if item.kind == .link {
            actions.append(
                ItemAction(
                    id: "clipboard.refresh-preview", title: String(localized: "Refresh Preview"),
                    icon: "arrow.clockwise"
                ) { [clipboard] in
                    clipboard.refreshPreview(item)
                    return .stay
                })
        }
        if item.mayHaveText {
            for copyOnly in [false, true] {
                actions.append(
                    ItemAction(
                        id: copyOnly ? "clipboard.copy-text" : "clipboard.paste-text",
                        title: copyOnly ? String(localized: "Copy Text") : String(localized: "Paste Text"),
                        icon: copyOnly ? "doc.on.doc" : "text.viewfinder"
                    ) { [clipboard] in
                        Task {
                            guard let text = await clipboard.text(in: item) else {
                                NSSound.beep()
                                Toast.shared.show(String(localized: "No Text Found"), symbol: "text.viewfinder")
                                return
                            }
                            clipboard.copy(text: TextRecognition.forCopying(text))
                            _ = host.dismissAndPaste(copyOnly: copyOnly, for: .clipboardHistory)
                        }
                        return .stay
                    })
            }
        }
        if item.kind == .image {
            for copyOnly in [false, true] {
                actions.append(
                    ItemAction(
                        id: copyOnly ? "clipboard.copy-jpeg" : "clipboard.paste-jpeg",
                        title: copyOnly ? String(localized: "Copy as JPEG") : String(localized: "Paste as JPEG"),
                        icon: copyOnly ? "photo.on.rectangle" : "photo"
                    ) { [clipboard] in
                        guard clipboard.copyAsJPEG(item) else { return .fail() }
                        return host.dismissAndPaste(copyOnly: copyOnly, for: .clipboardHistory)
                    })
            }
            actions.append(
                ItemAction(
                    id: "clipboard.save-image", title: String(localized: "Save Image…"),
                    icon: "square.and.arrow.down", shortcut: KeyShortcut("s", .command)
                ) { [saveImage] in
                    saveImage(item)
                    return .stay
                })
        }
        actions.append(
            ItemAction(
                id: "clipboard.delete", title: String(localized: "Delete"), icon: "trash", shortcut: .delete,
                isDestructive: true
            ) { [clipboard] in
                clipboard.delete(item)
                return .removed
            })
        return actions
    }
}
