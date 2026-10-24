import AppKit
import Observation

enum LauncherResult: Identifiable, Hashable {
    case calculation(Calculation)
    case pastCalculation(CalculationRecord)
    case calculator
    case settings
    case sendFeedback
    case readFeedback
    case changelog
    case quit
    case clipboardHistory
    case caffeinate
    case caffeinateFor
    case decaffeinate(until: String)
    case caffeinateMenuBar(isShown: Bool)
    case app(AppEntry)
    case clipboard(ClipboardItem)

    var id: String {
        switch self {
        case .calculation: "calculation"
        case .pastCalculation(let record): "calculation:\(record.id)"
        case .calculator: "command:calculator"
        case .settings: "command:settings"
        case .sendFeedback: "command:send-feedback"
        case .readFeedback: "command:read-feedback"
        case .changelog: "command:changelog"
        case .quit: "command:quit"
        case .clipboardHistory: "command:clipboard-history"
        case .caffeinate: "command:caffeinate"
        case .caffeinateFor: "command:caffeinate-for"
        case .decaffeinate: "command:decaffeinate"
        case .caffeinateMenuBar: "command:caffeinate-menu-bar"
        case .app(let app): "app:\(app.url.path)"
        case .clipboard(let item): "clipboard:\(item.id)"
        }
    }

    var title: String {
        switch self {
        case .calculation(let calculation): calculation.answer
        case .pastCalculation(let record): "\(record.expression) = \(record.answer)".leftToRightIsolated
        case .calculator: String(localized: "Calculator")
        case .settings: String(localized: "Settings")
        case .sendFeedback: String(localized: "Send Feedback")
        case .readFeedback: String(localized: "Read Feedback")
        case .changelog: String(localized: "Changelog")
        case .quit: String(localized: "Quit Whippet")
        case .clipboardHistory: String(localized: "Clipboard History")
        case .caffeinate: String(localized: "Caffeinate")
        case .caffeinateFor: String(localized: "Caffeinate for…")
        case .decaffeinate: String(localized: "Decaffeinate")
        case .caffeinateMenuBar(let isShown):
            isShown ? String(localized: "Hide Caffeinate in Menu Bar") : String(localized: "Show Caffeinate in Menu Bar")
        case .app(let app): app.name
        case .clipboard(let item): item.title
        }
    }

    var subtitle: String {
        switch self {
        case .calculation: String(localized: "Calculator")
        case .pastCalculation(let record): record.calculatedAt.formatted(.relative(presentation: .named))
        case .calculator, .clipboardHistory, .settings, .sendFeedback, .readFeedback, .changelog, .quit: String(localized: "Command")
        case .caffeinate, .caffeinateFor: String(localized: "Keep this Mac awake")
        case .caffeinateMenuBar: String(localized: "Command")
        case .decaffeinate(let until): until
        case .app: String(localized: "Application")
        case .clipboard(let item): item.copiedAt.formatted(.relative(presentation: .named))
        }
    }

    /// Commands only an account with the CloudKit Admin role sees, shown with an Admin badge.
    var isAdminOnly: Bool {
        guard case .readFeedback = self else { return false }
        return true
    }

    var isApp: Bool {
        guard case .app = self else { return false }
        return true
    }

    var isPinned: Bool {
        guard case .clipboard(let item) = self else { return false }
        return item.pinnedAt != nil
    }

    var isCalculation: Bool {
        guard case .calculation = self else { return false }
        return true
    }

    /// Results whose action puts text or an image on the clipboard, which Return then pastes into the target app.
    var pastes: Bool {
        switch self {
        case .calculation, .pastCalculation, .clipboard: true
        default: false
        }
    }

    var actionTitle: String {
        switch self {
        case .calculation, .pastCalculation: String(localized: "Copy Answer")
        case .calculator, .clipboardHistory, .settings, .sendFeedback, .readFeedback: String(localized: "Open Command")
        case .caffeinate, .decaffeinate, .caffeinateMenuBar: String(localized: "Run Command")
        case .caffeinateFor: String(localized: "Choose Duration")
        case .changelog: String(localized: "Open in Browser")
        case .quit: String(localized: "Quit")
        case .app: String(localized: "Open Application")
        case .clipboard: String(localized: "Copy to Clipboard")
        }
    }
}

/// What can be done with a result, offered in the ⌘K menu and through each action's own shortcut.
enum ResultAction: CaseIterable {
    case primary
    case secondary
    case togglePin
    case copyPath
    case delete

    func isAvailable(for result: LauncherResult) -> Bool {
        switch (self, result) {
        case (.primary, _): true
        case (.secondary, .app): true
        case (.secondary, _): result.pastes
        case (.togglePin, .clipboard), (.delete, .clipboard), (.copyPath, .app): true
        default: false
        }
    }

    @MainActor
    func title(for result: LauncherResult, model: LauncherModel) -> String {
        switch self {
        case .primary: model.actionTitle(for: result)
        case .secondary: result.isApp ? String(localized: "Show in Finder") : String(localized: "Copy")
        case .togglePin: result.isPinned ? String(localized: "Unpin") : String(localized: "Pin")
        case .copyPath: String(localized: "Copy Path")
        case .delete: String(localized: "Delete")
        }
    }

    var symbol: String {
        switch self {
        case .primary: "return"
        case .secondary: "doc.on.doc"
        case .togglePin: "pin"
        case .copyPath: "link"
        case .delete: "trash"
        }
    }

    /// The key equivalent shown in the menu; the panel's key monitor handles the same keys outside the menu.
    var shortcut: (key: String, modifiers: NSEvent.ModifierFlags) {
        switch self {
        case .primary: ("\r", [])
        case .secondary: ("\r", [.command])
        case .togglePin: ("p", [.command, .shift])
        case .copyPath: ("c", [.command, .shift])
        case .delete: ("x", [.control])
        }
    }
}

@MainActor
@Observable
final class LauncherModel {
    enum Mode {
        case root
        case calculator
        case clipboard
    }

    var query = "" {
        didSet {
            guard query != oldValue else { return }
            resetSelection()
        }
    }
    var selection = 0
    var clipboardKind: ClipboardKind? {
        didSet {
            guard clipboardKind != oldValue else { return }
            resetSelection()
        }
    }
    private(set) var mode = Mode.root

    @ObservationIgnored var onDismiss: () -> Void = {}
    /// The app that was in front when the panel opened, which keeps keyboard focus underneath it and receives pastes.
    var targetApp: NSRunningApplication?
    @ObservationIgnored var onOpenSettings: () -> Void = {}
    @ObservationIgnored var onSendFeedback: () -> Void = {}
    @ObservationIgnored var onReadFeedback: () -> Void = {}
    /// Set at launch when this iCloud account has the CloudKit Admin role, which shows the Read Feedback command.
    var isFeedbackAdmin = false
    @ObservationIgnored var onShowActions: () -> Void = {}

    private static let calculatorColumnLength = 10
    private static let changelogURL = URL(string: "https://github.com/acdibble/whippet/blob/main/CHANGELOG.md")!

    /// The inputs `results` depends on. Reading them registers each with Observation, and comparing them tells whether
    /// the cached results still apply, so a keystroke computes them once however often views and key handling ask.
    private struct ResultsKey: Equatable {
        let mode: Mode
        let query: String
        let clipboardKind: ClipboardKind?
        let clipboardRevision: Int
        let isFeedbackAdmin: Bool
        let isCaffeinated: Bool
        let caffeinatedUntil: Date?
        let showsCaffeineInMenuBar: Bool
        /// Compared cheaply, since an unchanged array shares its storage.
        let apps: [AppEntry]
    }

    @ObservationIgnored private var cachedResults: (key: ResultsKey, results: [LauncherResult])?
    /// The calculator's history and number columns, which don't depend on the query, keyed by the clipboard revision.
    @ObservationIgnored private var cachedCalculatorColumns: (revision: Int, results: [LauncherResult])?

    private let appIndex: AppIndex
    private let clipboard: ClipboardHistory
    private let caffeine: Caffeine

    /// True while the Hours, Minutes and Seconds fields of "Caffeinate for…" are shown beside the search field.
    private(set) var isEnteringDuration = false
    /// Hours, minutes and seconds as typed into those fields.
    var durationFields = ["", "", ""]

    init(appIndex: AppIndex, clipboard: ClipboardHistory, caffeine: Caffeine) {
        self.caffeine = caffeine
        self.appIndex = appIndex
        self.clipboard = clipboard
    }

    var isExpanded: Bool {
        mode != .root || !query.isEmpty
    }

    var results: [LauncherResult] {
        let key = ResultsKey(
            mode: mode,
            query: query,
            clipboardKind: clipboardKind,
            clipboardRevision: clipboard.revision,
            isFeedbackAdmin: isFeedbackAdmin,
            isCaffeinated: caffeine.isActive,
            caffeinatedUntil: caffeine.endsAt,
            showsCaffeineInMenuBar: caffeine.showsInMenuBar,
            apps: appIndex.apps
        )
        if let cachedResults, cachedResults.key == key {
            return cachedResults.results
        }
        let results = computeResults()
        cachedResults = (key, results)
        return results
    }

    private func computeResults() -> [LauncherResult] {
        switch mode {
        case .root:
            if let calculation = Calculator.evaluate(query) {
                return calculatorResults(calculation)
            }
            let commands: [LauncherResult] = [.calculator, .clipboardHistory, .settings, .sendFeedback, .changelog, .quit]
                + (isFeedbackAdmin ? [.readFeedback] : [])
                + [.caffeinate, .caffeinateFor]
                + (caffeine.isActive ? [.decaffeinate(until: caffeine.untilDescription)] : [])
                + [.caffeinateMenuBar(isShown: caffeine.showsInMenuBar)]
            return ranked(commands + appIndex.apps.map(LauncherResult.app))
        case .calculator:
            return calculatorResults(Calculator.evaluate(query))
        case .clipboard:
            return clipboard.search(query, kind: clipboardKind).map(LauncherResult.clipboard)
        }
    }

    /// The current calculation, if any, followed by the calculator history and numeric clipboard items shown beside it.
    private func calculatorResults(_ calculation: Calculation?) -> [LauncherResult] {
        let current = calculation.map { [LauncherResult.calculation($0)] } ?? []
        return current + calculatorColumns
    }

    private var calculatorColumns: [LauncherResult] {
        if let cachedCalculatorColumns, cachedCalculatorColumns.revision == clipboard.revision {
            return cachedCalculatorColumns.results
        }
        let history = clipboard.recentCalculations(limit: Self.calculatorColumnLength)
        let numbers = clipboard.search("", kind: .number).prefix(Self.calculatorColumnLength)
        let columns = history.map(LauncherResult.pastCalculation) + numbers.map(LauncherResult.clipboard)
        cachedCalculatorColumns = (clipboard.revision, columns)
        return columns
    }

    /// The clipboard history view's items, taken from the cached results.
    var clipboardItems: [ClipboardItem] {
        results.compactMap { if case .clipboard(let item) = $0 { item } else { nil } }
    }

    func imageURL(for item: ClipboardItem) -> URL? {
        clipboard.imageURL(for: item)
    }

    func reset() {
        open(.root)
    }

    var showsCalculatorLayout: Bool {
        if mode == .calculator { return true }
        return mode == .root && results.first?.isCalculation == true
    }

    func moveSelection(by offset: Int) {
        let results = results
        if let layout = calculatorLayout(results) {
            selection = layout.verticalMove(from: selection, by: offset)
            return
        }
        guard !results.isEmpty else { return }
        selection = min(max(selection + offset, 0), results.count - 1)
    }

    /// Moves between the calculator columns, returning false when the selection is not in a column so the key can edit the text instead.
    func moveColumn(by offset: Int) -> Bool {
        guard let layout = calculatorLayout(results), let target = layout.horizontalMove(from: selection, by: offset) else {
            return false
        }
        selection = target
        return true
    }

    private func calculatorLayout(_ results: [LauncherResult]) -> CalculatorLayout? {
        guard showsCalculatorLayout else { return nil }
        let indices = results.indices
        return CalculatorLayout(
            card: indices.first { results[$0].isCalculation },
            columns: [
                indices.filter { if case .pastCalculation = results[$0] { return true }; return false },
                indices.filter { if case .clipboard = results[$0] { return true }; return false },
            ]
        )
    }

    var selectedResult: LauncherResult? {
        let results = results
        return results.indices.contains(selection) ? results[selection] : nil
    }

    func perform(_ action: ResultAction) {
        guard let result = selectedResult, action.isAvailable(for: result) else { return }
        switch (action, result) {
        case (.primary, _):
            activate()
        case (.secondary, .app(let app)):
            NSWorkspace.shared.activateFileViewerSelecting([app.url])
            onDismiss()
        case (.secondary, _):
            activate(copyOnly: true)
        case (.togglePin, .clipboard(let item)):
            clipboard.setPinned(item.pinnedAt == nil, item: item)
            selection = results.firstIndex { $0.id == result.id } ?? 0
        case (.copyPath, .app(let app)):
            clipboard.copy(text: app.url.path)
            onDismiss()
            Toast.shared.show(String(localized: "Copied Path"), symbol: "link")
        case (.delete, .clipboard(let item)):
            clipboard.delete(item)
            selection = min(selection, max(results.count - 1, 0))
        default:
            break
        }
    }

    func show(_ newMode: Mode) {
        open(newMode)
    }

    /// Switches view with an empty search and the default selection for that view.
    private func open(_ newMode: Mode) {
        // App launch counts, which rank results, aren't observed, so each view starts from fresh results.
        cachedResults = nil
        mode = newMode
        query = ""
        clipboardKind = nil
        isEnteringDuration = false
        resetSelection()
    }

    /// Clipboard history opens on the most recent copy rather than the pinned items above it.
    private func resetSelection() {
        if mode == .clipboard {
            selection = clipboardItems.firstIndex { $0.pinnedAt == nil } ?? 0
            return
        }
        selection = 0
    }

    /// Runs the selected result. Clipboard items and answers are pasted into `targetApp`, or only copied when `copyOnly`.
    func activate(copyOnly: Bool = false) {
        if isEnteringDuration {
            startTimedCaffeinate()
            return
        }
        let results = results
        guard results.indices.contains(selection) else { return }

        switch results[selection] {
        case .calculation(let calculation):
            clipboard.recordCalculation(
                expression: query.trimmingCharacters(in: .whitespaces),
                answer: calculation.answer,
                isRPN: calculation.isRPN
            )
            clipboard.copy(text: calculation.answer)
            dismissAndPaste(copyOnly: copyOnly)
        case .pastCalculation(let record):
            clipboard.copy(text: record.answer)
            dismissAndPaste(copyOnly: copyOnly)
        case .calculator:
            open(.calculator)
        case .settings:
            onOpenSettings()
        case .sendFeedback:
            onSendFeedback()
        case .readFeedback:
            onReadFeedback()
        case .changelog:
            NSWorkspace.shared.open(Self.changelogURL)
            onDismiss()
        case .caffeinate:
            caffeine.start(seconds: nil)
            onDismiss()
        case .caffeinateFor:
            durationFields = ["", "", ""]
            isEnteringDuration = true
        case .caffeinateMenuBar(let isShown):
            caffeine.showsInMenuBar = !isShown
            onDismiss()
            Toast.shared.show(
                isShown ? String(localized: "Caffeinate hidden from menu bar") : String(localized: "Caffeinate shown in menu bar"),
                symbol: "menubar.rectangle"
            )
        case .decaffeinate:
            caffeine.stop()
            onDismiss()
        case .quit:
            NSApp.terminate(nil)
        case .clipboardHistory:
            open(.clipboard)
        case .app(let app):
            appIndex.open(app)
            onDismiss()
        case .clipboard(let item):
            guard clipboard.copy(item) else {
                NSSound.beep()
                return
            }
            dismissAndPaste(copyOnly: copyOnly)
        }
    }

    func actionTitle(for result: LauncherResult) -> String {
        if isEnteringDuration, case .caffeinateFor = result { return String(localized: "Caffeinate") }
        guard result.pastes, let name = targetApp?.localizedName else { return result.actionTitle }
        return String(localized: "Paste to \(name)")
    }

    /// Without Accessibility permission the item stays copied and macOS is asked to show its permission prompt.
    private func dismissAndPaste(copyOnly: Bool) {
        onDismiss()
        if !copyOnly, targetApp != nil, Paster.isTrusted {
            Paster.pasteAfterPanelCloses()
            return
        }
        if !copyOnly, targetApp != nil {
            Paster.requestTrust()
        }
        Toast.shared.show(String(localized: "Copied to Clipboard"), symbol: "doc.on.doc")
    }

    /// Starts "Caffeinate for…" with the typed duration; blank fields count as zero, and a zero or invalid duration beeps.
    func startTimedCaffeinate() {
        let parts = durationFields.map { $0.trimmingCharacters(in: .whitespaces) }
        let values = parts.map { $0.isEmpty ? 0 : Int($0) }
        guard values.allSatisfy({ ($0 ?? -1) >= 0 }) else {
            NSSound.beep()
            return
        }
        let seconds = zip(values.compactMap { $0 }, [3600, 60, 1]).reduce(0) { $0 + $1.0 * $1.1 }
        guard seconds > 0 else {
            NSSound.beep()
            return
        }
        caffeine.start(seconds: seconds)
        onDismiss()
    }

    func back() {
        if isEnteringDuration {
            isEnteringDuration = false
            return
        }
        if mode != .root {
            reset()
            return
        }
        onDismiss()
    }

    private func ranked(_ candidates: [LauncherResult]) -> [LauncherResult] {
        if query.isEmpty { return candidates }
        return candidates
            .compactMap { result in FuzzyMatch.score(query, in: result.title).map { (result: result, score: $0) } }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return launchCount(of: lhs.result) > launchCount(of: rhs.result)
            }
            .map(\.result)
    }

    /// Breaks ties between equally good matches in favour of apps opened more often.
    private func launchCount(of result: LauncherResult) -> Int {
        guard case .app(let app) = result else { return 0 }
        return appIndex.launchCount(of: app)
    }
}

/// Result indices of the calculator's card and its columns, for moving the selection in two dimensions.
private struct CalculatorLayout {
    let card: Int?
    let columns: [[Int]]

    func verticalMove(from selection: Int, by offset: Int) -> Int {
        guard let (column, row) = position(of: selection) else {
            guard offset > 0, let first = columns.first(where: { !$0.isEmpty })?.first else { return selection }
            return first
        }
        let target = row + offset
        if target < 0 { return card ?? selection }
        return columns[column][min(target, columns[column].count - 1)]
    }

    func horizontalMove(from selection: Int, by offset: Int) -> Int? {
        guard let (column, row) = position(of: selection) else { return nil }
        let target = column + offset
        guard columns.indices.contains(target), !columns[target].isEmpty else { return selection }
        return columns[target][min(row, columns[target].count - 1)]
    }

    private func position(of selection: Int) -> (column: Int, row: Int)? {
        for (column, indices) in columns.enumerated() {
            if let row = indices.firstIndex(of: selection) { return (column, row) }
        }
        return nil
    }
}
