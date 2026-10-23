import AppKit
import Observation

enum LauncherResult: Identifiable, Hashable {
    case calculation(Calculation)
    case pastCalculation(CalculationRecord)
    case calculator
    case settings
    case quit
    case clipboardHistory
    case app(AppEntry)
    case clipboard(ClipboardItem)

    var id: String {
        switch self {
        case .calculation: "calculation"
        case .pastCalculation(let record): "calculation:\(record.id)"
        case .calculator: "command:calculator"
        case .settings: "command:settings"
        case .quit: "command:quit"
        case .clipboardHistory: "command:clipboard-history"
        case .app(let app): "app:\(app.url.path)"
        case .clipboard(let item): "clipboard:\(item.id)"
        }
    }

    var title: String {
        switch self {
        case .calculation(let calculation): calculation.answer
        case .pastCalculation(let record): "\(record.expression) = \(record.answer)"
        case .calculator: String(localized: "Calculator")
        case .settings: String(localized: "Settings")
        case .quit: String(localized: "Quit Fetch")
        case .clipboardHistory: String(localized: "Clipboard History")
        case .app(let app): app.name
        case .clipboard(let item): item.title
        }
    }

    var subtitle: String {
        switch self {
        case .calculation: String(localized: "Calculator")
        case .pastCalculation(let record): record.calculatedAt.formatted(.relative(presentation: .named))
        case .calculator, .clipboardHistory, .settings, .quit: String(localized: "Command")
        case .app: String(localized: "Application")
        case .clipboard(let item): item.copiedAt.formatted(.relative(presentation: .named))
        }
    }

    var isCalculation: Bool {
        guard case .calculation = self else { return false }
        return true
    }

    var actionTitle: String {
        switch self {
        case .calculation, .pastCalculation: String(localized: "Copy Answer")
        case .calculator, .clipboardHistory, .settings: String(localized: "Open Command")
        case .quit: String(localized: "Quit")
        case .app: String(localized: "Open Application")
        case .clipboard: String(localized: "Copy to Clipboard")
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
        didSet { resetSelection() }
    }
    var selection = 0
    var clipboardKind: ClipboardKind? {
        didSet { resetSelection() }
    }
    private(set) var mode = Mode.root

    @ObservationIgnored var onDismiss: () -> Void = {}
    @ObservationIgnored var onOpenSettings: () -> Void = {}

    private static let calculatorColumnLength = 10

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
            if let calculation = Calculator.evaluate(query) {
                return calculatorResults(calculation)
            }
            let commands: [LauncherResult] = [.calculator, .clipboardHistory, .settings, .quit]
            return ranked(commands + appIndex.apps.map(LauncherResult.app))
        case .calculator:
            return calculatorResults(Calculator.evaluate(query))
        case .clipboard:
            return clipboardItems.map(LauncherResult.clipboard)
        }
    }

    /// The current calculation, if any, followed by the calculator history and numeric clipboard items shown beside it.
    private func calculatorResults(_ calculation: Calculation?) -> [LauncherResult] {
        let current = calculation.map { [LauncherResult.calculation($0)] } ?? []
        let history = clipboard.recentCalculations(limit: Self.calculatorColumnLength)
        let numbers = clipboard.search("", kind: .number).prefix(Self.calculatorColumnLength)
        return current + history.map(LauncherResult.pastCalculation) + numbers.map(LauncherResult.clipboard)
    }

    var clipboardItems: [ClipboardItem] {
        clipboard.search(query, kind: clipboardKind)
    }

    func imageURL(for item: ClipboardItem) -> URL? {
        clipboard.imageURL(for: item)
    }

    func reset() {
        mode = .root
        query = ""
        clipboardKind = nil
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
        case .calculation(let calculation):
            clipboard.recordCalculation(
                expression: query.trimmingCharacters(in: .whitespaces),
                answer: calculation.answer,
                isRPN: calculation.isRPN
            )
            clipboard.copy(text: calculation.answer)
            onDismiss()
        case .pastCalculation(let record):
            clipboard.copy(text: record.answer)
            onDismiss()
        case .calculator:
            mode = .calculator
            query = ""
        case .settings:
            onOpenSettings()
        case .quit:
            NSApp.terminate(nil)
        case .clipboardHistory:
            mode = .clipboard
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
