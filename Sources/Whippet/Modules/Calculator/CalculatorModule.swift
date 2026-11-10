import AppKit
import SwiftUI
import WhippetCore

/// Calculations, conversions and time zones, answered as they're typed in the main search or in the calculator's own
/// screen, with a history of answers and a floating calculator.
@MainActor
final class CalculatorModule: LauncherModule {
    let manifest = ModuleManifest.calculator
    let clipboard: ClipboardHistory
    let exchangeRates: ExchangeRateStore
    let floatingCalculator: FloatingCalculator
    private(set) weak var host: (any ModuleHost)?
    /// The screen the main search shows in its place while a calculation is typed.
    private lazy var inline = CalculatorScreen(module: self, isInline: true)
    /// The history and number columns, which don't depend on what's typed, kept until either changes.
    private var cachedColumns: (key: [Int], items: [LauncherItem])?

    static let columnLength = 10

    init(clipboard: ClipboardHistory, exchangeRates: ExchangeRateStore, floatingCalculator: FloatingCalculator) {
        self.clipboard = clipboard
        self.exchangeRates = exchangeRates
        self.floatingCalculator = floatingCalculator
    }

    func attach(to host: any ModuleHost) {
        self.host = host
    }

    func update(_ modules: ModuleSettings) {
        if modules.isEnabled(.currencyConversion) {
            exchangeRates.start()
        } else {
            exchangeRates.stop()
        }
    }

    var activity: [ActivityLock] {
        guard floatingCalculator.isVisible else { return [] }
        return [
            ActivityLock(
                module: manifest.id, rows: ["floating-calculator"],
                reason: String(localized: "The floating calculator is open"))
        ]
    }

    var revision: AnyHashable {
        [AnyHashable(clipboard.revision), AnyHashable(exchangeRates.availableRates)]
    }

    func contributions(for query: String) -> [Contribution] {
        if !query.isEmpty, host?.modules.isEnabled(.inlineCalculation) ?? true,
            calculate(query) != nil || looksLikeCalculation(query)
        {
            return [.exclusive(inline)]
        }
        return [
            .listed(
                .command(
                    .calculator, id: "command:calculator", title: String(localized: "Calculator"),
                    icon: .symbol("plus.forwardslash.minus"))),
            .listed(
                .command(
                    .floatingCalculator, id: "command:floating-calculator",
                    title: String(localized: "Floating Calculator"), icon: .symbol("macwindow.on.rectangle"))),
        ]
    }

    func calculate(_ query: String) -> Calculation? {
        Calculator.calculate(query, rates: exchangeRates.availableRates)
    }

    /// A calculation, conversion or time calculation still being typed. Text that's also a named timer, such as
    /// `10 min to feed`, stays a timer unless what follows `to` starts a unit that fits, such as `10 min to s`.
    func looksLikeCalculation(_ query: String) -> Bool {
        guard host?.modules.isEnabled(.inlineCalculation) ?? true else { return false }
        let typedTimer = (host?.modules.isEnabled(.typedTimers) ?? true) && TimerDuration.parse(query) != nil
        return Calculator.looksLikeCalculation(query)
            || UnitConversion.looksLikeConversion(query, requiresTarget: typedTimer)
            || BaseConversion.looksLikeConversion(query)
            || (exchangeRates.isEnabled && CurrencyConversion.looksLikeConversion(query))
            || TimeCalculation.looksLikeTimeCalculation(query)
    }

    func actions(for item: LauncherItem) -> [ItemAction] {
        if item.id == "command:floating-calculator" {
            return [
                .open(owner: .floatingCalculator) { [weak self] in
                    self?.popOut(nil)
                    return .stay
                }
            ]
        }
        return [
            .open(owner: .calculator) { [weak self] in
                self.map { .push(CalculatorScreen(module: $0, isInline: false)) } ?? .stay
            },
            popOutAction(nil),
        ]
    }

    func popOutAction(_ expression: String?) -> ItemAction {
        ItemAction(
            id: "calculator.pop-out", title: String(localized: "Pop Out Calculator"),
            icon: "macwindow.on.rectangle", shortcut: KeyShortcut("o", [.command, .shift]),
            owner: .floatingCalculator
        ) { [weak self] in
            self?.popOut(expression)
            return .stay
        }
    }

    func popOut(_ expression: String?) {
        host?.dismiss()
        floatingCalculator.show(expression: expression)
    }

    /// Past calculations, then numbers copied elsewhere, from clipboard history while it's on.
    func columns() -> [LauncherItem] {
        let clipboardIsOn = host?.modules.isEnabled(.clipboardModule) ?? true
        let key = [clipboard.revision, clipboardIsOn ? 1 : 0]
        if let cachedColumns, cachedColumns.key == key { return cachedColumns.items }
        let history = clipboard.recentCalculations(limit: Self.columnLength).map { record in
            LauncherItem(
                id: "calculation:\(record.id)", module: manifest.id,
                title: "\(record.expression) = \(record.displayAnswer)".leftToRightIsolated,
                subtitle: record.calculatedAt.formatted(.relative(presentation: .named)),
                icon: .symbol("clock.arrow.circlepath"), payload: record)
        }
        let numbers =
            clipboardIsOn
            ? clipboard.search("", kind: .number).prefix(Self.columnLength).map { item in
                LauncherItem(
                    id: "clipboard:\(item.id)", module: manifest.id, title: item.title,
                    subtitle: item.copiedAt.formatted(.relative(presentation: .named)),
                    icon: .symbol(item.kind.symbolName), payload: item)
            } : []
        let items = history + numbers
        cachedColumns = (key, items)
        return items
    }

    func traits(of item: LauncherItem) -> ItemTraits {
        guard let calculation = item.payload(as: Calculation.self) else { return ItemTraits() }
        return ItemTraits(text: { calculation.answer }, duration: { calculation.timerSeconds() })
    }

    func run(command: String) {
        switch command {
        case "floating-calculator":
            floatingCalculator.toggle()
        default:
            host?.openDirectly { [weak self] in
                guard let self else { return }
                host?.push(CalculatorScreen(module: self, isInline: false))
            }
        }
    }
}

/// The calculator: what's typed worked out on a card, with past answers and copied numbers in two columns under it.
/// In the main search it stands in for the results while a calculation is typed, and the bar shows the answer.
@MainActor
final class CalculatorScreen: LauncherScreen {
    let module: CalculatorModule
    /// Standing in for the main search, rather than opened from the Calculator command.
    let isInline: Bool
    /// The last complete answer, kept dimmed in the bar while the next part of the calculation is typed.
    private var lastAnswer: Calculation?
    private var current: Calculation?

    init(module: CalculatorModule, isInline: Bool) {
        self.module = module
        self.isInline = isInline
    }

    var id: String { isInline ? "calculator.inline" : "calculator" }

    var searchBar: SearchBar {
        .field(placeholder: String(localized: "Type a calculation…"))
    }

    var revision: AnyHashable { module.revision }

    var content: ScreenContent { .custom(AnyView(CalculatorResults(screen: self))) }

    func items(for query: String) -> [LauncherItem] {
        current = module.calculate(query)
        if let current {
            lastAnswer = current
        } else if !module.looksLikeCalculation(query) {
            lastAnswer = nil
        }
        let card = current.map { calculation in
            [
                LauncherItem(
                    id: "calculation", module: module.id, title: calculation.displayAnswer,
                    subtitle: String(localized: "Calculator"), icon: .symbol("equal.square"), payload: calculation)
            ]
        }
        return (card ?? []) + module.columns()
    }

    /// The answer at the end of the search bar while the panel shows only the bar.
    func accessory() -> AnyView? {
        guard isInline, let host = module.host as? LauncherModel, !host.isExpanded,
            let calculation = current ?? lastAnswer
        else { return nil }
        return AnyView(
            Text("= \(calculation.displayAnswer)".leftToRightIsolated)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.launcherSecondary)
                .opacity(current == nil ? 0.5 : 1)
                .lineLimit(1)
                .fixedSize())
    }

    func actions(for item: LauncherItem) -> [ItemAction] {
        guard let host = module.host else { return [] }
        if let calculation = item.payload(as: Calculation.self) {
            let ref: ModuleRef = isInline ? .inlineCalculation : .calculator
            let copy = { [module, weak host] (answer: String, copyOnly: Bool) -> ActionOutcome in
                if !calculation.isPlainNumber {
                    module.clipboard.recordCalculation(
                        expression: (host?.query ?? "").trimmingCharacters(in: .whitespaces), answer: answer,
                        isRPN: calculation.isRPN)
                }
                module.clipboard.copy(text: answer)
                return host?.dismissAndPaste(copyOnly: copyOnly, for: ref) ?? .stay
            }
            var actions = [
                ItemAction(
                    id: "calculator.paste",
                    title: host.targetApp == nil ? String(localized: "Copy Answer") : ClipboardScreen.pasteTitle(host),
                    icon: "return"
                ) { copy(calculation.answer, false) },
                ItemAction(
                    id: "calculator.copy", title: String(localized: "Copy"), icon: "doc.on.doc",
                    shortcut: .commandReturn
                ) { copy(calculation.answer, true) },
            ]
            for base in calculation.otherBases {
                actions.append(
                    ItemAction(
                        id: "calculator.copy-\(base)", title: String(localized: "Copy as \(base.name)"),
                        icon: "number"
                    ) {
                        guard let answer = calculation.answer(in: base) else { return .fail() }
                        return copy(answer, true)
                    })
            }
            actions.append(module.popOutAction(host.query.trimmingCharacters(in: .whitespaces)))
            return actions
        }
        if let record = item.payload(as: CalculationRecord.self) {
            let paste = { [module, weak host] (copyOnly: Bool) -> ActionOutcome in
                module.clipboard.copy(text: record.answer)
                return host?.dismissAndPaste(copyOnly: copyOnly, for: .calculator) ?? .stay
            }
            return [
                ItemAction(id: "calculator.paste", title: ClipboardScreen.pasteTitle(host), icon: "return") {
                    paste(false)
                },
                ItemAction(
                    id: "calculator.copy", title: String(localized: "Copy"), icon: "doc.on.doc",
                    shortcut: .commandReturn
                ) { paste(true) },
                module.popOutAction(record.expression),
            ]
        }
        if let clip = item.payload(as: ClipboardItem.self) {
            return ClipboardScreen.pasteActions(for: clip, clipboard: module.clipboard, host: host)
        }
        return []
    }

    /// An unfinished calculation in the bar has nothing to copy yet, so Return beeps rather than pasting a past one.
    var screenActions: [ItemAction] { [] }

    var blocksReturn: Bool {
        guard isInline, let host = module.host as? LauncherModel else { return false }
        return current == nil && !host.isExpanded
    }

    // MARK: - Moving in two columns

    private func layout(_ items: [LauncherItem]) -> (card: Int?, columns: [[Int]]) {
        let indices = items.indices
        return (
            indices.first { items[$0].payload(as: Calculation.self) != nil },
            [
                indices.filter { items[$0].payload(as: CalculationRecord.self) != nil },
                indices.filter { items[$0].payload(as: ClipboardItem.self) != nil },
            ]
        )
    }

    private func position(of selection: Int, in columns: [[Int]]) -> (column: Int, row: Int)? {
        for (column, indices) in columns.enumerated() {
            if let row = indices.firstIndex(of: selection) { return (column, row) }
        }
        return nil
    }

    func verticalMove(from selection: Int, by offset: Int, in items: [LauncherItem]) -> Int? {
        let (card, columns) = layout(items)
        guard let (column, row) = position(of: selection, in: columns) else {
            guard offset > 0, let first = columns.first(where: { !$0.isEmpty })?.first else { return selection }
            return first
        }
        let target = row + offset
        if target < 0 { return card ?? selection }
        return columns[column][min(target, columns[column].count - 1)]
    }

    /// ← and → between the columns, or left to the field outside them.
    func horizontalMove(by offset: Int) -> Bool {
        guard let host = module.host as? LauncherModel else { return false }
        let items = host.results
        let (_, columns) = layout(items)
        guard let (column, row) = position(of: host.selection, in: columns) else { return false }
        let target = column + offset
        guard columns.indices.contains(target), !columns[target].isEmpty else { return true }
        host.selection = columns[target][min(row, columns[target].count - 1)]
        return true
    }
}
