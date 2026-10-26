import AppKit
import Observation

enum LauncherResult: Identifiable, Hashable {
    case calculation(Calculation)
    case pastCalculation(CalculationRecord)
    case calculator
    case floatingCalculator
    case settings
    case sendFeedback
    case readFeedback
    case changelog
    case shareWhippet
    case quit
    case clipboardHistory
    case caffeinate
    case caffeinateFor
    case decaffeinate(until: String)
    case caffeinateMenuBar(isShown: Bool)
    case system(SystemCommand)
    case quicklink(Quicklink)
    case createQuicklink
    /// A quicklink offered for the whole search text, opened with it straight away.
    case searchWithQuicklink(Quicklink)
    /// Clipboard history offered for the whole search text.
    case searchClipboard
    /// A timer typed into the search bar, such as `25m tea`.
    case startTimer(seconds: Int, name: String?)
    case newTimer
    case newStopwatch
    /// Opens the stopwatch view.
    case stopwatch
    /// Opens the timers view.
    case timersView
    /// A running or paused timer or stopwatch.
    case timer(TimerItem)
    /// A timer that has ended and is ringing.
    case ringingTimer(TimerItem)
    case timerPreset(TimerPreset)
    case app(AppEntry)
    case clipboard(ClipboardItem)

    var id: String {
        switch self {
        case .calculation: "calculation"
        case .pastCalculation(let record): "calculation:\(record.id)"
        case .calculator: "command:calculator"
        case .floatingCalculator: "command:floating-calculator"
        case .settings: "command:settings"
        case .sendFeedback: "command:send-feedback"
        case .readFeedback: "command:read-feedback"
        case .changelog: "command:changelog"
        case .shareWhippet: "command:share-whippet"
        case .quit: "command:quit"
        case .clipboardHistory: "command:clipboard-history"
        case .caffeinate: "command:caffeinate"
        case .caffeinateFor: "command:caffeinate-for"
        case .decaffeinate: "command:decaffeinate"
        case .caffeinateMenuBar: "command:caffeinate-menu-bar"
        case .system(let command): "command:system.\(command.rawValue)"
        case .quicklink(let quicklink): "quicklink:\(quicklink.uuid)"
        case .createQuicklink: "command:create-quicklink"
        case .searchWithQuicklink(let quicklink): "with:quicklink:\(quicklink.uuid)"
        case .searchClipboard: "with:clipboard-history"
        case .startTimer: "timer:start"
        case .newTimer: "command:start-timer"
        case .newStopwatch: "command:start-stopwatch"
        case .stopwatch: "command:stopwatch"
        case .timersView: "command:timers"
        case .timer(let item): "timer:\(item.id)"
        case .ringingTimer(let item): "ringing:\(item.id)"
        case .timerPreset(let preset): preset.launchKey
        case .app(let app): "app:\(app.url.path)"
        case .clipboard(let item): "clipboard:\(item.id)"
        }
    }

    var title: String {
        switch self {
        case .calculation(let calculation): calculation.displayAnswer
        case .pastCalculation(let record): "\(record.expression) = \(record.displayAnswer)".leftToRightIsolated
        case .calculator: String(localized: "Calculator")
        case .floatingCalculator: String(localized: "Floating Calculator")
        case .settings: String(localized: "Settings")
        case .sendFeedback: String(localized: "Send Feedback")
        case .readFeedback: String(localized: "Read Feedback")
        case .changelog: String(localized: "Changelog")
        case .shareWhippet: String(localized: "Share Whippet with a Friend")
        case .system(let command): command.title
        case .quicklink(let quicklink): quicklink.name
        case .createQuicklink: String(localized: "Create Quicklink")
        case .searchWithQuicklink(let quicklink): quicklink.name
        case .searchClipboard: String(localized: "Search Clipboard History")
        case .quit: String(localized: "Quit Whippet")
        case .clipboardHistory: String(localized: "Clipboard History")
        case .caffeinate: String(localized: "Caffeinate")
        case .caffeinateFor: String(localized: "Caffeinate for…")
        case .decaffeinate: String(localized: "Decaffeinate")
        case .caffeinateMenuBar(let isShown):
            isShown ? String(localized: "Hide Caffeinate in Menu Bar") : String(localized: "Show Caffeinate in Menu Bar")
        case .startTimer(let seconds, let name?):
            String(localized: "Start “\(name)” for \(TimerNaming.duration(TimeInterval(seconds)))")
        case .startTimer(let seconds, nil):
            String(localized: "Start Timer for \(TimerNaming.duration(TimeInterval(seconds)))")
        case .newTimer: String(localized: "Start Timer…")
        case .newStopwatch: String(localized: "Start Stopwatch")
        case .stopwatch: String(localized: "Stopwatch")
        case .timersView: String(localized: "Timers")
        case .timer(let item), .ringingTimer(let item): item.name
        case .timerPreset(let preset):
            preset.name.map { "\($0) · \(TimerNaming.duration(TimeInterval(preset.seconds)))" }
                ?? TimerNaming.defaultTimerName(seconds: preset.seconds)
        case .app(let app): app.name
        case .clipboard(let item): item.title
        }
    }

    var subtitle: String {
        switch self {
        case .calculation: String(localized: "Calculator")
        case .pastCalculation(let record): record.calculatedAt.formatted(.relative(presentation: .named))
        case .calculator, .floatingCalculator, .clipboardHistory, .settings, .sendFeedback, .readFeedback, .changelog,
             .shareWhippet, .quit:
            String(localized: "Command")
        case .caffeinate, .caffeinateFor: String(localized: "Keep this Mac awake")
        case .caffeinateMenuBar, .system, .createQuicklink, .searchClipboard: String(localized: "Command")
        case .quicklink, .searchWithQuicklink: String(localized: "Quicklink")
        case .decaffeinate(let until): until
        case .startTimer, .timerPreset: String(localized: "Timer")
        case .newTimer, .newStopwatch, .stopwatch, .timersView: String(localized: "Command")
        case .timer(let item): item.kind == .timer ? String(localized: "Timer") : String(localized: "Stopwatch")
        case .ringingTimer: String(localized: "Done")
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

    /// What search matches: a quicklink's keyword as well as its name, otherwise the title.
    var searchText: String {
        if case .quicklink(let quicklink) = self { return quicklink.searchText }
        return title
    }

    /// Return on it asks for text, and the quicklink is only counted as used once it opens with that text.
    var startsQuicklinkArgument: Bool {
        if case .quicklink(let quicklink) = self { return quicklink.takesArgument }
        return false
    }

    /// The key launches are recorded under: an app's bundle identifier, or a command's identifier. Calculations,
    /// clipboard items and Quit aren't recorded.
    var launchKey: String? {
        switch self {
        case .app(let app): app.stableID
        // Counted as using the quicklink or command itself.
        case .searchWithQuicklink(let quicklink): LauncherResult.quicklink(quicklink).id
        case .searchClipboard: LauncherResult.clipboardHistory.id
        // Counted as using the timer it starts, which then ranks among Recent Timers.
        case .startTimer(let seconds, let name): TimerPreset(name: name, seconds: seconds).launchKey
        case .calculation, .pastCalculation, .clipboard, .quit, .timer, .ringingTimer: nil
        default: id
        }
    }

    var actionTitle: String {
        switch self {
        case .calculation, .pastCalculation: String(localized: "Copy Answer")
        case .calculator, .floatingCalculator, .clipboardHistory, .settings, .sendFeedback, .readFeedback:
            String(localized: "Open Command")
        case .caffeinate, .decaffeinate, .caffeinateMenuBar: String(localized: "Run Command")
        case .caffeinateFor: String(localized: "Choose Duration")
        case .changelog: String(localized: "Open in Browser")
        case .shareWhippet: String(localized: "Copy Link")
        case .system: String(localized: "Run Command")
        case .quicklink(let quicklink): quicklink.takesArgument ? String(localized: "Enter Text") : String(localized: "Open Quicklink")
        case .createQuicklink: String(localized: "Open Command")
        case .searchWithQuicklink: String(localized: "Open Quicklink")
        case .searchClipboard: String(localized: "Search")
        case .quit: String(localized: "Quit")
        case .startTimer, .timerPreset: String(localized: "Start Timer")
        case .newTimer: String(localized: "Enter Duration")
        case .newStopwatch: String(localized: "Start Stopwatch")
        case .stopwatch, .timersView: String(localized: "Open Command")
        case .timer(let item) where item.kind == .stopwatch: String(localized: "Open Stopwatch")
        case .timer(let item): item.isPaused ? String(localized: "Resume") : String(localized: "Pause")
        case .ringingTimer: String(localized: "Stop")
        case .app: String(localized: "Open Application")
        case .clipboard: String(localized: "Copy to Clipboard")
        }
    }

    var isStopwatch: Bool {
        guard case .timer(let item) = self else { return false }
        return item.kind == .stopwatch
    }

    /// A timer counting down, running or paused, as opposed to a stopwatch.
    var isCountdown: Bool {
        guard case .timer(let item) = self else { return false }
        return item.kind == .timer
    }

    /// The timer or stopwatch a row shows, which stays the same when a timer finishes and its row changes.
    var timerID: UUID? {
        switch self {
        case .timer(let item), .ringingTimer(let item): item.id
        default: nil
        }
    }
}

/// What the search bar collects text for, shown as a label in front of it.
enum ArgumentTarget: Equatable {
    case quicklink(Quicklink)
    case timerDuration
    /// The name for a timer whose duration has been entered.
    case timerName(seconds: Int)
    case stopwatchName
    case rename(TimerItem)

    var label: String {
        switch self {
        case .quicklink(let quicklink): quicklink.name
        case .timerDuration: String(localized: "Start Timer")
        case .timerName(let seconds): String(localized: "Timer for \(TimerNaming.duration(TimeInterval(seconds)))")
        case .stopwatchName: String(localized: "Start Stopwatch")
        case .rename(let item): String(localized: "Rename \(item.name)")
        }
    }

    var placeholder: String {
        switch self {
        case .quicklink: String(localized: "Type and press Return")
        case .timerDuration: String(localized: "Duration, such as 25m, 1h30m or 4:30")
        case .timerName(let seconds):
            String(localized: "Name, or Return for “\(TimerNaming.defaultTimerName(seconds: seconds))”")
        case .stopwatchName: String(localized: "Name, or Return for “\(TimerNaming.defaultStopwatchName)”")
        case .rename: String(localized: "New name")
        }
    }
}

/// What can be done with a result, offered in the ⌘K menu and through each action's own shortcut.
enum ResultAction: CaseIterable {
    case primary
    case secondary
    case addMinute
    case addFiveMinutes
    case lap
    case restart
    case rename
    case snooze
    case togglePin
    case refreshPreview
    case copyPath
    case popOut
    case delete

    func isAvailable(for result: LauncherResult) -> Bool {
        switch (self, result) {
        case (.primary, _): true
        case (.secondary, .app): true
        case (.secondary, .timer), (.restart, .timer), (.rename, .timer), (.delete, .timer): true
        case (.addMinute, _), (.addFiveMinutes, _): result.isCountdown
        case (.lap, .timer(let item)): item.kind == .stopwatch && !item.isPaused
        case (.snooze, .ringingTimer), (.delete, .timerPreset): true
        case (.secondary, _): result.pastes
        case (.togglePin, .clipboard), (.delete, .clipboard), (.copyPath, .app): true
        case (.refreshPreview, .clipboard(let item)): item.kind == .link
        case (.popOut, .calculation), (.popOut, .pastCalculation), (.popOut, .calculator): true
        default: false
        }
    }

    @MainActor
    func title(for result: LauncherResult, model: LauncherModel) -> String {
        switch self {
        case .primary: model.actionTitle(for: result)
        case .secondary:
            switch result {
            case .app: String(localized: "Show in Finder")
            case .timer: result.isStopwatch ? String(localized: "Copy Elapsed Time") : String(localized: "Copy Time Left")
            default: String(localized: "Copy")
            }
        case .addMinute: String(localized: "Add 1 Minute")
        case .addFiveMinutes: String(localized: "Add 5 Minutes")
        case .lap: String(localized: "Lap")
        case .restart: result.isStopwatch ? String(localized: "Reset") : String(localized: "Restart")
        case .rename: String(localized: "Rename…")
        case .snooze: String(localized: "Snooze")
        case .togglePin: result.isPinned ? String(localized: "Unpin") : String(localized: "Pin")
        case .refreshPreview: String(localized: "Refresh Preview")
        case .copyPath: String(localized: "Copy Path")
        case .popOut: String(localized: "Pop Out Calculator")
        case .delete:
            switch result {
            case .timer: result.isStopwatch ? String(localized: "Stop Stopwatch") : String(localized: "Cancel Timer")
            case .timerPreset: String(localized: "Remove from Recent Timers")
            default: String(localized: "Delete")
            }
        }
    }

    var symbol: String {
        switch self {
        case .primary: "return"
        case .secondary: "doc.on.doc"
        case .addMinute: "plus"
        case .addFiveMinutes: "goforward.5"
        case .lap: "flag"
        case .restart: "arrow.counterclockwise"
        case .rename: "pencil"
        case .snooze: "zzz"
        case .togglePin: "pin"
        case .refreshPreview: "arrow.clockwise"
        case .copyPath: "link"
        case .popOut: "macwindow.on.rectangle"
        case .delete: "trash"
        }
    }

    /// The key equivalent shown in the menu; the panel's key monitor handles the same keys outside the menu.
    var shortcut: (key: String, modifiers: NSEvent.ModifierFlags)? {
        switch self {
        case .primary: ("\r", [])
        case .secondary: ("\r", [.command])
        case .addMinute: ("=", [.command])
        case .lap: ("l", [.command])
        case .restart: ("r", [.command])
        case .addFiveMinutes, .rename, .snooze, .refreshPreview: nil
        case .togglePin: ("p", [.command, .shift])
        case .copyPath: ("c", [.command, .shift])
        case .popOut: ("o", [.command, .shift])
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
        case stopwatch
        case timers
    }

    var query = "" {
        didSet {
            guard query != oldValue else { return }
            resetSelection()
            rememberInlineAnswer()
        }
    }
    /// The last complete answer in the search bar, kept while the next part of the calculation is typed.
    private(set) var lastInlineCalculation: Calculation?
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
    /// Opens the floating calculator, with the given expression in its input.
    @ObservationIgnored var onPopOutCalculator: (String?) -> Void = { _ in }
    @ObservationIgnored var onCreateQuicklink: () -> Void = {}

    /// The stopwatch the stopwatch view shows.
    private var stopwatchID: UUID?

    /// What the text typed after Tab is for, shown as a label in front of the search bar.
    private(set) var argumentTarget: ArgumentTarget?
    var argument = ""

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
        let timers: [TimerItem]
        let ringingTimers: [TimerItem]
        let timerPresets: [TimerPreset]
        let isCaffeinated: Bool
        let caffeinatedUntil: Date?
        let showsCaffeineInMenuBar: Bool
        let isShowingAll: Bool
        let launchRevision: Int
        let quicklinks: [Quicklink]
        /// Compared cheaply, since an unchanged array shares its storage.
        let apps: [AppEntry]
    }

    @ObservationIgnored private var cachedResults: (key: ResultsKey, results: [LauncherResult])?
    /// The calculator's history and number columns, which don't depend on the query, keyed by the clipboard revision.
    @ObservationIgnored private var cachedCalculatorColumns: (revision: Int, results: [LauncherResult])?

    private let appIndex: AppIndex
    private let history: LaunchHistory
    private let quicklinks: Quicklinks
    /// How many of the results lead the empty search's Suggestions section; set with the results.
    @ObservationIgnored private var suggestionCount = 0
    /// How many running and ringing timers lead the empty search, under Timers; set with the results.
    @ObservationIgnored private var timerRowCount = 0
    private static let suggestionLimit = 5
    private let clipboard: ClipboardHistory
    private let caffeine: Caffeine
    private let timers: Timers

    /// True while the Hours, Minutes and Seconds fields of "Caffeinate for…" are shown beside the search field.
    private(set) var isEnteringDuration = false
    /// Hours, minutes and seconds as typed into those fields.
    var durationFields = ["", "", ""]

    init(
        appIndex: AppIndex,
        clipboard: ClipboardHistory,
        caffeine: Caffeine,
        timers: Timers,
        history: LaunchHistory,
        quicklinks: Quicklinks
    ) {
        self.caffeine = caffeine
        self.timers = timers
        self.appIndex = appIndex
        self.clipboard = clipboard
        self.history = history
        self.quicklinks = quicklinks
        timers.onChange = { [weak self] in self?.keepSelectedTimer() }
    }

    /// Timers move between sections as they finish and stop, so a selected timer is found again by its ID rather than
    /// left on whatever row now has its place.
    private func keepSelectedTimer() {
        guard let previous = cachedResults?.results, previous.indices.contains(selection) else { return }
        let selected = previous[selection]
        let current = results
        let index = current.firstIndex { result in
            if let id = selected.timerID { return result.timerID == id }
            return result.id == selected.id
        }
        guard let index else {
            clampSelection()
            return
        }
        selection = index
    }

    private func clampSelection() {
        selection = min(selection, max(results.count - 1, 0))
    }

    /// True after ↓ in the empty search field, which shows Suggestions, then every command and app.
    private(set) var isShowingAll = false

    /// True while the main search holds a calculation, finished or still being typed. The search bar then stays one
    /// line tall, so it doesn't cover what you're reading, and ↓ opens the full calculator view.
    var isCalculatingInline: Bool {
        guard mode == .root, !isShowingAll, !query.isEmpty else { return false }
        return results.first?.isCalculation == true || looksLikeCalculation(query)
    }

    /// The answer shown in the search bar, once the calculation is complete.
    var inlineCalculation: Calculation? {
        guard isCalculatingInline, case .calculation(let calculation)? = results.first else { return nil }
        return calculation
    }

    /// A calculation or unit conversion still being typed. Text that's also a named timer, such as `10 min to feed`,
    /// stays a timer unless what follows `to` starts a unit that fits, such as `10 min to s`.
    private func looksLikeCalculation(_ query: String) -> Bool {
        Calculator.looksLikeCalculation(query)
            || UnitConversion.looksLikeConversion(query, requiresTarget: TimerDuration.parse(query) != nil)
    }

    private func rememberInlineAnswer() {
        if let inlineCalculation {
            lastInlineCalculation = inlineCalculation
        } else if !isCalculatingInline {
            lastInlineCalculation = nil
        }
    }

    var isExpanded: Bool {
        guard argumentTarget == nil else { return false }
        return mode != .root || isShowingAll || (!query.isEmpty && !isCalculatingInline)
    }

    /// Switches the search bar to typing the text for a quicklink.
    func beginArgument(for quicklink: Quicklink) {
        beginArgument(.quicklink(quicklink))
    }

    /// Switches the search bar to typing text for `target`, starting from `text`.
    func beginArgument(_ target: ArgumentTarget, text: String = "") {
        argument = text
        argumentTarget = target
    }

    /// Tab on a quicklink that takes text starts typing it, and on a timer command or a typed timer without a name
    /// asks for the duration or name. Returns false so Tab does its usual job otherwise.
    func beginArgumentForSelection() -> Bool {
        guard argumentTarget == nil else { return false }
        switch selectedResult {
        case .quicklink(let quicklink)? where quicklink.takesArgument: beginArgument(for: quicklink)
        case .newTimer?: beginArgument(.timerDuration)
        case .newStopwatch?: beginArgument(.stopwatchName)
        case .startTimer(let seconds, nil)?: beginArgument(.timerName(seconds: seconds))
        default: return false
        }
        return true
    }

    var results: [LauncherResult] {
        let key = ResultsKey(
            mode: mode,
            query: query,
            clipboardKind: clipboardKind,
            clipboardRevision: clipboard.revision,
            isFeedbackAdmin: isFeedbackAdmin,
            timers: timers.items,
            ringingTimers: timers.ringing,
            timerPresets: timers.presets,
            isCaffeinated: caffeine.isActive,
            caffeinatedUntil: caffeine.endsAt,
            showsCaffeineInMenuBar: caffeine.showsInMenuBar,
            isShowingAll: isShowingAll,
            launchRevision: history.revision,
            quicklinks: quicklinks.items,
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
            if let calculation = Calculator.calculate(query) {
                return calculatorResults(calculation)
            }
            // A calculation still being typed, such as "2+", gets the calculator's history rather than search results.
            if looksLikeCalculation(query) {
                return calculatorResults(nil)
            }
            let commands: [LauncherResult] = [.calculator, .floatingCalculator, .clipboardHistory, .settings, .sendFeedback, .changelog, .shareWhippet, .quit]
                + (isFeedbackAdmin ? [.readFeedback] : [])
                + [.caffeinate, .caffeinateFor]
                + (caffeine.isActive ? [.decaffeinate(until: caffeine.untilDescription)] : [])
                + [.caffeinateMenuBar(isShown: caffeine.showsInMenuBar)]
                + SystemCommand.allCases.map(LauncherResult.system)
                + [.createQuicklink, .newTimer, .timersView, .newStopwatch, .stopwatch]
            let timerRows = timers.ringing.map(LauncherResult.ringingTimer) + timers.items.map(LauncherResult.timer)
            let candidates = commands
                + quicklinks.items.map(LauncherResult.quicklink)
                + timers.presets.map(LauncherResult.timerPreset)
                + appIndex.apps.map(LauncherResult.app)
            guard query.isEmpty else {
                suggestionCount = 0
                timerRowCount = 0
                let typedTimer = TimerDuration.parse(query).map { LauncherResult.startTimer(seconds: $0.seconds, name: $0.name) }
                let ranked = Ranking.rank(timerRows + candidates, query: query, title: \.searchText, frecency: frecency(of:))
                return (typedTimer.map { [$0] } ?? []) + ranked + textFallbacks
            }
            let suggestions = Ranking.suggestions(candidates, limit: Self.suggestionLimit, frecency: frecency(of:))
            let suggestedIDs = Set(suggestions.map(\.id))
            suggestionCount = suggestions.count
            timerRowCount = timerRows.count
            return timerRows + suggestions + candidates.filter { !suggestedIDs.contains($0.id) }
        case .calculator:
            return calculatorResults(Calculator.calculate(query))
        case .clipboard:
            return clipboard.search(query, kind: clipboardKind).map(LauncherResult.clipboard)
        case .stopwatch:
            return []
        case .timers:
            return timers.ringing.map(LauncherResult.ringingTimer)
                + timers.items.filter { $0.kind == .timer }.map(LauncherResult.timer)
                + timers.presets.map(LauncherResult.timerPreset)
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
        if !isExpanded, offset > 0 {
            isShowingAll = true
            selection = 0
            return
        }
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

    /// In the stopwatch view, the stopwatch shown, so ⌘K and the action shortcuts work on it.
    var selectedResult: LauncherResult? {
        if mode == .stopwatch {
            return currentStopwatch.map(LauncherResult.timer)
        }
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
        case (.secondary, .timer(let item)):
            copyTime(of: item)
        case (.secondary, _):
            activate(copyOnly: true)
        case (.refreshPreview, .clipboard(let item)):
            clipboard.refreshPreview(item)
        case (.togglePin, .clipboard(let item)):
            clipboard.setPinned(item.pinnedAt == nil, item: item)
            selection = results.firstIndex { $0.id == result.id } ?? 0
        case (.popOut, .calculation):
            onPopOutCalculator(query.trimmingCharacters(in: .whitespaces))
        case (.popOut, .pastCalculation(let record)):
            onPopOutCalculator(record.expression)
        case (.popOut, _):
            onPopOutCalculator(nil)
        case (.copyPath, .app(let app)):
            clipboard.copy(text: app.url.path)
            onDismiss()
            Toast.shared.show(String(localized: "Copied Path"), symbol: "link")
        case (.delete, .clipboard(let item)):
            clipboard.delete(item)
            clampSelection()
        case (.addMinute, .timer(let item)):
            timers.add(60, to: item.id)
        case (.addFiveMinutes, .timer(let item)):
            timers.add(300, to: item.id)
        case (.lap, .timer(let item)):
            timers.lap(item.id)
        case (.restart, .timer(let item)):
            timers.restart(item.id)
        case (.rename, .timer(let item)):
            beginArgument(.rename(item), text: item.name)
        case (.snooze, .ringingTimer(let item)):
            timers.snooze(item.id)
            if mode != .timers {
                onDismiss()
            }
        case (.delete, .timer(let item)):
            timers.remove(item.id)
            if mode == .stopwatch {
                showStopwatch()
                return
            }
            clampSelection()
        case (.delete, .timerPreset(let preset)):
            timers.forget(preset)
            clampSelection()
        default:
            break
        }
    }

    func show(_ newMode: Mode) {
        open(newMode)
    }

    var stopwatches: [TimerItem] {
        timers.items.filter { $0.kind == .stopwatch }
    }

    /// The stopwatch shown, or another one if it was stopped elsewhere, such as from the menu bar.
    var currentStopwatch: TimerItem? {
        let stopwatches = stopwatches
        return stopwatches.first { $0.id == stopwatchID } ?? stopwatches.last
    }

    /// Opens the stopwatch view on a stopwatch, by default the newest. With none, the view waits at zero until Return
    /// or Space starts one.
    func showStopwatch(_ id: UUID? = nil) {
        let target = id.flatMap { id in stopwatches.first { $0.id == id } } ?? stopwatches.last
        if mode != .stopwatch {
            open(.stopwatch)
        }
        stopwatchID = target?.id
    }

    /// Starts a stopwatch and opens the stopwatch view on it.
    func startStopwatch(name: String? = nil) {
        showStopwatch(timers.startStopwatch(name: name).id)
    }

    /// Opens the timers view, with a timer selected if given.
    func showTimers(selecting id: UUID? = nil) {
        open(.timers)
        if let id {
            selectTimer(id)
        }
    }

    /// True in the stopwatch and timers views while no text is being typed, when plain keys control them.
    var usesPlainKeys: Bool {
        (mode == .stopwatch || mode == .timers) && argumentTarget == nil
    }

    /// The key that runs an action. In the stopwatch and timers views, their own actions need no modifier.
    func shortcut(for action: ResultAction) -> (key: String, modifiers: NSEvent.ModifierFlags)? {
        guard usesPlainKeys else { return action.shortcut }
        switch (mode, action) {
        case (.stopwatch, .lap): return ("l", [])
        case (_, .restart): return ("r", [])
        case (.timers, .addMinute): return ("+", [])
        case (.timers, .snooze): return ("s", [])
        case (.timers, .delete): return ("\u{8}", [])
        default: return action.shortcut
        }
    }

    /// A key pressed without modifiers in the stopwatch or timers view.
    func performPlainKey(_ key: Character) {
        switch (mode, key) {
        case (.stopwatch, "l"): perform(.lap)
        case (_, "r"): perform(.restart)
        case (.timers, "+"), (.timers, "="): perform(.addMinute)
        case (.timers, "s"): perform(.snooze)
        case (.timers, "n"): beginArgument(.timerDuration)
        default: break
        }
    }

    /// ⌫ cancels the selected timer in the timers view. A stopwatch is stopped from ⌘K, so one key can't lose it.
    func deleteWithPlainKey() {
        guard mode == .timers else { return }
        perform(.delete)
    }

    /// Moves to the previous or next stopwatch, returning false when there's only one so the key can edit the name.
    func switchStopwatch(by offset: Int) -> Bool {
        let stopwatches = stopwatches
        guard mode == .stopwatch, argumentTarget == nil, stopwatches.count > 1 else { return false }
        let index = stopwatches.firstIndex { $0.id == currentStopwatch?.id } ?? 0
        showStopwatch(stopwatches[(index + offset + stopwatches.count) % stopwatches.count].id)
        return true
    }

    /// Switches view with an empty search and the default selection for that view.
    private func open(_ newMode: Mode) {
        mode = newMode
        query = ""
        clipboardKind = nil
        isEnteringDuration = false
        isShowingAll = false
        argumentTarget = nil
        stopwatchID = nil
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
        if let argumentTarget {
            submitArgument(for: argumentTarget)
            return
        }
        if mode == .stopwatch {
            guard let currentStopwatch else {
                startStopwatch()
                return
            }
            timers.togglePause(currentStopwatch.id)
            return
        }
        if mode == .timers {
            activateInTimers()
            return
        }
        // An unfinished calculation in the search bar has nothing to copy yet.
        if isCalculatingInline, inlineCalculation == nil {
            NSSound.beep()
            return
        }
        let results = results
        guard results.indices.contains(selection) else { return }
        // Apps are recorded by AppIndex.open, which their hotkeys use too, and a quicklink that takes text when it opens.
        if !results[selection].isApp, !results[selection].startsQuicklinkArgument, let key = results[selection].launchKey {
            history.record(key)
        }

        switch results[selection] {
        case .calculation(let calculation):
            if !calculation.isPlainNumber {
                clipboard.recordCalculation(
                    expression: query.trimmingCharacters(in: .whitespaces),
                    answer: calculation.answer,
                    isRPN: calculation.isRPN
                )
            }
            clipboard.copy(text: calculation.answer)
            dismissAndPaste(copyOnly: copyOnly)
        case .pastCalculation(let record):
            clipboard.copy(text: record.answer)
            dismissAndPaste(copyOnly: copyOnly)
        case .calculator:
            open(.calculator)
        case .floatingCalculator:
            onPopOutCalculator(nil)
        case .settings:
            onOpenSettings()
        case .sendFeedback:
            onSendFeedback()
        case .readFeedback:
            onReadFeedback()
        case .shareWhippet:
            onDismiss()
            ShareLink.copy(using: clipboard)
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
        case .quicklink(let quicklink):
            if quicklink.takesArgument {
                beginArgument(for: quicklink)
                return
            }
            guard Quicklinks.open(quicklink) else {
                NSSound.beep()
                return
            }
            onDismiss()
        case .createQuicklink:
            onCreateQuicklink()
        case .searchWithQuicklink(let quicklink):
            guard Quicklinks.open(quicklink, argument: query.trimmingCharacters(in: .whitespaces)) else {
                NSSound.beep()
                return
            }
            onDismiss()
        case .searchClipboard:
            let text = query
            open(.clipboard)
            query = text
        case .system(let command):
            onDismiss()
            // After the panel has gone, so neither a confirmation nor the system's own response is hidden behind it.
            DispatchQueue.main.async { Self.run(command) }
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
        case .startTimer(let seconds, let name):
            timers.startTimer(seconds: seconds, name: name)
            onDismiss()
        case .timerPreset(let preset):
            timers.startTimer(seconds: preset.seconds, name: preset.name)
            onDismiss()
        case .newTimer:
            beginArgument(.timerDuration)
        case .newStopwatch:
            startStopwatch()
        case .stopwatch:
            showStopwatch()
        case .timersView:
            showTimers()
        case .timer(let item) where item.kind == .stopwatch:
            showStopwatch(item.id)
        case .timer(let item):
            showTimers(selecting: item.id)
        case .ringingTimer(let item):
            timers.stop(item.id)
            onDismiss()
        }
    }

    /// Return or Space in the timers view acts on the selected row and stays in the view.
    private func activateInTimers() {
        switch selectedResult {
        case .timer(let item)?: timers.togglePause(item.id)
        case .ringingTimer(let item)?:
            timers.stop(item.id)
            clampSelection()
        case .timerPreset(let preset)?:
            history.record(preset.launchKey)
            selectTimer(timers.startTimer(seconds: preset.seconds, name: preset.name, announces: false).id)
        default: beginArgument(.timerDuration)
        }
    }

    /// Selects a timer in the timers view.
    private func selectTimer(_ id: UUID) {
        selection = results.firstIndex { if case .timer(let item) = $0 { item.id == id } else { false } } ?? selection
    }

    /// A timer started from the search bar closes the panel; one started in the timers view goes back to the list,
    /// with it selected.
    private func didStartTimer(_ item: TimerItem) {
        guard mode == .timers else {
            onDismiss()
            return
        }
        argumentTarget = nil
        selectTimer(item.id)
    }

    /// Return after typing the text for a quicklink, a timer or a stopwatch.
    private func submitArgument(for target: ArgumentTarget) {
        let text = argument.trimmingCharacters(in: .whitespaces)
        switch target {
        case .quicklink(let quicklink):
            guard Quicklinks.open(quicklink, argument: argument) else {
                NSSound.beep()
                return
            }
            history.record(LauncherResult.quicklink(quicklink).id)
            onDismiss()
        case .timerDuration:
            guard let parsed = TimerDuration.parse(text, plainNumberIsMinutes: true) else {
                NSSound.beep()
                return
            }
            guard let name = parsed.name else {
                beginArgument(.timerName(seconds: parsed.seconds))
                return
            }
            history.record(TimerPreset(name: name, seconds: parsed.seconds).launchKey)
            didStartTimer(timers.startTimer(seconds: parsed.seconds, name: name, announces: mode != .timers))
        case .timerName(let seconds):
            let name = text.isEmpty ? nil : text
            history.record(TimerPreset(name: name, seconds: seconds).launchKey)
            didStartTimer(timers.startTimer(seconds: seconds, name: name, announces: mode != .timers))
        case .stopwatchName:
            argumentTarget = nil
            startStopwatch(name: text.isEmpty ? nil : text)
        case .rename(let item):
            guard !text.isEmpty else {
                NSSound.beep()
                return
            }
            timers.rename(item.id, to: text)
            argumentTarget = nil
        }
    }

    func actionTitle(for result: LauncherResult) -> String {
        if isEnteringDuration, case .caffeinateFor = result { return String(localized: "Caffeinate") }
        if mode == .root, case .timer(let item) = result, item.kind == .timer { return String(localized: "Open Timers") }
        guard result.pastes, let name = targetApp?.localizedName else { return result.actionTitle }
        return String(localized: "Paste to \(name)")
    }

    /// Copies a timer's time left or a stopwatch's elapsed time, from the launcher or the menu bar.
    func copyTime(of item: TimerItem) {
        let value = item.value()
        clipboard.copy(text: item.kind == .stopwatch ? TimerNaming.stopwatchClock(value) : TimerNaming.clock(value))
        dismissAndPaste(copyOnly: true)
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
        guard let seconds = CaffeineDuration.seconds(
            hours: durationFields[0],
            minutes: durationFields[1],
            seconds: durationFields[2]
        ) else {
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
        if argumentTarget != nil {
            argumentTarget = nil
            return
        }
        if mode != .root {
            reset()
            return
        }
        if isShowingAll {
            isShowingAll = false
            selection = 0
            return
        }
        onDismiss()
    }

    /// Asks first for commands that can't be undone. Whippet is hidden once the panel closes, so it comes forward to
    /// show the alert.
    private static func run(_ command: SystemCommand) {
        if let confirmation = command.confirmation {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = confirmation.title
            alert.informativeText = confirmation.message
            alert.addButton(withTitle: confirmation.button)
            alert.addButton(withTitle: String(localized: "Cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        do {
            try command.run()
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            NSAlert(error: error).runModal()
        }
    }

    /// What the search text can be used with even when it matches nothing by name: quicklinks that take text, most used
    /// first, then clipboard history.
    private var textFallbacks: [LauncherResult] {
        let quicklinkResults = quicklinks.items.filter(\.takesArgument).map(LauncherResult.searchWithQuicklink)
        let ordered = quicklinkResults.enumerated().sorted { lhs, rhs in
            let left = frecency(of: lhs.element), right = frecency(of: rhs.element)
            return left != right ? left > right : lhs.offset < rhs.offset
        }
        return ordered.map(\.element) + [.searchClipboard]
    }

    private func frecency(of result: LauncherResult) -> Double {
        result.launchKey.map { history.frecency(of: $0) } ?? 0
    }

    /// With an empty search, the most used apps and commands come first under Suggestions, then the rest by kind.
    func sectionTitle(at index: Int) -> String {
        let results = results
        guard results.indices.contains(index) else { return "" }
        switch results[index] {
        case .clipboard: return String(localized: "Clipboard History")
        case .searchWithQuicklink, .searchClipboard: return String(localized: "Use “\(query)” with…")
        default: break
        }
        if mode == .timers {
            if case .timerPreset = results[index] { return String(localized: "Recent") }
            return String(localized: "Timers")
        }
        guard mode == .root, query.isEmpty else { return String(localized: "Results") }
        if index < timerRowCount { return String(localized: "Timers") }
        if index < timerRowCount + suggestionCount { return String(localized: "Suggestions") }
        switch results[index] {
        case .app: return String(localized: "Applications")
        case .quicklink: return String(localized: "Quicklinks")
        case .timerPreset: return String(localized: "Recent Timers")
        default: return String(localized: "Commands")
        }
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
