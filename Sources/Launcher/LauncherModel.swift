import AppKit
import Observation

enum LauncherResult: Identifiable, Hashable {
    case clipboardHistory
    case usageStats
    case app(AppEntry)
    case clipboard(ClipboardItem)

    var id: String {
        switch self {
        case .clipboardHistory: "command:clipboard-history"
        case .usageStats: "command:usage-stats"
        case .app(let app): "app:\(app.url.path)"
        case .clipboard(let item): "clipboard:\(item.id)"
        }
    }

    var title: String {
        switch self {
        case .clipboardHistory: "Clipboard History"
        case .usageStats: "Usage Stats"
        case .app(let app): app.name
        case .clipboard(let item): item.title
        }
    }

    var subtitle: String {
        switch self {
        case .clipboardHistory, .usageStats: "Command"
        case .app: "Application"
        case .clipboard(let item): item.copiedAt.formatted(.relative(presentation: .named))
        }
    }
}

@MainActor
@Observable
final class LauncherModel {
    enum Mode {
        case root
        case clipboard
        case usage
    }

    var query = "" {
        didSet { resetSelection() }
    }
    var selection = 0
    var clipboardKind: ClipboardKind? {
        didSet { resetSelection() }
    }
    private(set) var mode = Mode.root

    @ObservationIgnored var onDismiss: () -> Void = {}

    private let appIndex: AppIndex
    private let clipboard: ClipboardHistory

    init(appIndex: AppIndex, clipboard: ClipboardHistory) {
        self.appIndex = appIndex
        self.clipboard = clipboard
    }

    var isExpanded: Bool {
        mode != .root || !query.isEmpty
    }

    var results: [LauncherResult] {
        switch mode {
        case .root:
            ranked([.clipboardHistory, .usageStats] + appIndex.apps.map(LauncherResult.app))
        case .clipboard:
            clipboardItems.map(LauncherResult.clipboard)
        case .usage:
            []
        }
    }

    var clipboardItems: [ClipboardItem] {
        clipboard.search(query, kind: clipboardKind)
    }

    func imageURL(for item: ClipboardItem) -> URL? {
        clipboard.imageURL(for: item)
    }

    func usage() -> ClipboardUsage? {
        clipboard.usage()
    }

    func reset() {
        mode = .root
        query = ""
        clipboardKind = nil
    }

    func moveSelection(by offset: Int) {
        let count = results.count
        guard count > 0 else { return }
        selection = min(max(selection + offset, 0), count - 1)
    }

    func togglePinnedSelection() {
        guard mode == .clipboard else { return }
        let items = clipboardItems
        guard items.indices.contains(selection) else { return }

        let item = items[selection]
        clipboard.setPinned(item.pinnedAt == nil, item: item)
        selection = clipboardItems.firstIndex { $0.id == item.id } ?? 0
    }

    /// Clipboard history opens on the most recent copy rather than the pinned items above it.
    private func resetSelection() {
        if mode == .clipboard {
            selection = clipboardItems.firstIndex { $0.pinnedAt == nil } ?? 0
            return
        }
        selection = 0
    }

    func activate() {
        let results = results
        guard results.indices.contains(selection) else { return }

        switch results[selection] {
        case .clipboardHistory:
            mode = .clipboard
            query = ""
        case .usageStats:
            mode = .usage
            query = ""
        case .app(let app):
            appIndex.open(app)
            onDismiss()
        case .clipboard(let item):
            clipboard.copy(item)
            onDismiss()
        }
    }

    func back() {
        if mode != .root {
            reset()
            return
        }
        onDismiss()
    }

    private func ranked(_ candidates: [LauncherResult]) -> [LauncherResult] {
        if query.isEmpty { return candidates }
        return candidates
            .compactMap { result in FuzzyMatch.score(query, in: result.title).map { (result, $0) } }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }
}
