import AppKit
import Foundation
import Testing

@testable import WhippetCore

/// The real modules against a fake host, with history and defaults of the test's own. Actions are looked at rather
/// than run, except those that only open a screen or ask for text: running Sleep or Quit would do it.
@MainActor
final class ModuleTests {
    let suiteName = "WhippetModules-\(UUID().uuidString)"
    let defaults: UserDefaults
    let directory = FileManager.default.temporaryDirectory.appending(path: "WhippetModules-\(UUID().uuidString)")
    let host: FakeHost
    let clipboard: ClipboardHistory

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
        host = FakeHost(defaults: defaults)
        clipboard = ClipboardHistory(directory: directory)
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }

    private func install(_ modules: [any LauncherModule]) {
        host.launcherModules = modules
        for module in modules {
            module.attach(to: host)
        }
    }

    private func quicklinksModule() -> QuicklinksModule {
        QuicklinksModule(
            quicklinks: Quicklinks(store: clipboard.store), navigation: SettingsNavigation(), createQuicklink: {})
    }

    private func items(for query: String) -> [LauncherItem] {
        host.query = query
        return host.root.resolve(query).items
    }

    /// Every command in a manifest is listed by its module, unless it's left out for now, and offers an action that
    /// belongs to it, so turning the command off takes the action away. Updates and Cloud Sync are left out: they
    /// start Sparkle and open iCloud as they're made.
    @Test func everyCommandHasARowAndAnAction() {
        let feedback = FeedbackModule(store: FeedbackStore(), showFeedback: {}, readFeedback: {})
        feedback.isAdmin = true
        install([
            CalculatorModule(clipboard: clipboard), ClipboardModule(clipboard: clipboard), CaptureTextModule(),
            WhippetModule(clipboard: clipboard), feedback, TranslationModule(), CaffeinateModule(), SystemModule(),
            WindowManagementModule(), quicklinksModule(), TimersModule(timers: Timers(defaults: defaults)),
        ])

        var leftOut: [ModuleRef] = []
        var count = 0
        for module in host.launcherModules {
            for command in module.manifest.commands {
                let ref = module.manifest.ref(command.id)
                guard let item = host.root.commandItem(ref) else {
                    leftOut.append(ref)
                    continue
                }
                count += 1
                #expect(item.command == ref)
                #expect(item.module == module.id)
                let actions = host.ownActions(for: item)
                #expect(!actions.isEmpty, "\(ref.defaultsKey) has a row but no action")
                #expect(actions.first?.owner == ref, "\(ref.defaultsKey)'s first action isn't its own")
            }
        }
        // Nothing is keeping the Mac awake.
        #expect(leftOut == [.decaffeinate])
        #expect(count > 30)
    }

    @Test func caffeinateSaysWhatItsCommandsDo() {
        let module = CaffeinateModule()
        install([module])

        let rows = items(for: "")
        #expect(
            rows.map(\.id) == ["command:caffeinate", "command:caffeinate-for", "command:caffeinate-menu-bar"])
        #expect(rows[0].subtitle == "Keep this Mac awake")
        #expect(rows[2].title == "Show Caffeinate in Menu Bar")
        // Only Caffeinate's own hotkey differs from choosing it.
        #expect(!module.runHotkey(for: .caffeinateFor))
        #expect(module.generalSettings?.rows != nil)
    }

    @Test func readFeedbackIsForAdmins() {
        let module = FeedbackModule(store: FeedbackStore(), showFeedback: {}, readFeedback: {})
        install([module])

        #expect(items(for: "").map(\.id) == ["command:send-feedback"])

        module.isAdmin = true
        let rows = items(for: "")
        #expect(rows.map(\.id) == ["command:send-feedback", "command:read-feedback"])
        #expect(rows[1].isAdminOnly)
    }

    @Test func windowCommandsHaveTheirOwnSection() {
        install([WindowManagementModule(), SystemModule()])

        let rows = items(for: "")
        let windows = rows.filter { $0.module == "window" }
        #expect(windows.count == WindowCommand.allCases.count)
        #expect(windows.allSatisfy { $0.section == "Window" && $0.subtitle == "Window" })
        #expect(rows.first { $0.id == "command:window.centerThird" }?.icon == .assetSymbol(WindowCommand.centerThird.symbol))
        #expect(rows.first { $0.id == "command:system.sleep" }?.section == "Commands")
    }

    /// A calculation takes the search over, unless answers in the search bar are off, and a typed timer stays a timer.
    @Test func theCalculatorTakesOverTheSearch() {
        install([CalculatorModule(clipboard: clipboard), TimersModule(timers: Timers(defaults: defaults))])

        host.query = "2+3"
        let (answer, exclusive) = host.root.resolve("2+3")
        #expect(exclusive?.id == "calculator.inline")
        #expect(answer.first?.title == "5")

        let timer = host.root.resolve("25m tea")
        #expect(timer.exclusive == nil)
        #expect(timer.items.first?.id == "timer:start")

        host.modules.setOn(.inlineCalculation, false)
        #expect(host.root.resolve("2+3").exclusive == nil)
    }

    @Test func timersAreOfferedForWhatsTyped() throws {
        let module = TimersModule(timers: Timers(defaults: defaults))
        install([module])

        let typed = try #require(items(for: "25m tea").first)
        #expect(typed.id == "timer:start")
        #expect(typed.title.contains("tea"))
        #expect(typed.refs == [.typedTimers])
        #expect(host.ownActions(for: typed).first?.id != nil)

        host.modules.setOn(.typedTimers, false)
        #expect(!items(for: "25m tea").contains { $0.id == "timer:start" })

        // Start Timer… asks for a duration in the search bar, and counts as a use of the command.
        let command = try #require(host.root.commandItem(.startTimer))
        let outcome = try #require(host.ownActions(for: command).first).perform()
        guard case .input = outcome else {
            Issue.record("Start Timer… didn't ask for a duration")
            return
        }
        #expect(host.history.frecency(of: "command:start-timer") > 0)

        // Anything that holds a duration can start a timer for it.
        let offered = module.contributedActions(for: command, traits: ItemTraits(duration: { 1500 }))
        #expect(offered.map(\.id) == ["timers.start-for"])
        #expect(offered.first?.owner == .timersModule)
        #expect(module.contributedActions(for: command, traits: ItemTraits()).isEmpty)
    }

    @Test func quicklinksAreListedAndOfferedForText() throws {
        let module = quicklinksModule()
        install([module])
        try module.quicklinks.save(
            Quicklink(uuid: "test-search", name: "Search Example", keyword: "ex", template: "https://example.com/?q={query}"))
        try module.quicklinks.save(Quicklink(uuid: "test-home", name: "Example Home", template: "https://example.com"))

        let rows = items(for: "")
        #expect(rows.first?.id == "command:create-quicklink")
        #expect(rows.contains { $0.id == "quicklink:test-search" })
        #expect(rows.contains { $0.id == "quicklink:test-home" })

        // Only one that takes text is offered for what's typed, and it asks for text when chosen itself.
        let fallbacks = items(for: "hello").filter { $0.id.hasPrefix("with:quicklink:test-") }
        #expect(fallbacks.map(\.id) == ["with:quicklink:test-search"])
        let search = try #require(rows.first { $0.id == "quicklink:test-search" })
        #expect(host.ownActions(for: search).first?.runsOnTab == true)

        host.modules.setOn(.quicklinkFallbacks, false)
        #expect(!items(for: "hello").contains { $0.id.hasPrefix("with:quicklink:") })

        // Each has a switch in Settings › Commands and a hotkey in Settings › Shortcuts.
        #expect(module.dynamicRows.map(\.ref).contains(.quicklink("test-search")))
        host.modules.setOn(.quicklink("test-home"), false)
        #expect(!items(for: "").contains { $0.id == "quicklink:test-home" })
    }

    /// Clipboard History is offered for what's typed, and opens its screen.
    @Test func clipboardHistoryOpensItsScreen() throws {
        install([ClipboardModule(clipboard: clipboard)])

        let command = try #require(host.root.commandItem(.clipboardHistory))
        guard case .push(let screen) = try #require(host.ownActions(for: command).first).perform() else {
            Issue.record("Clipboard History didn't open its screen")
            return
        }
        #expect(screen is ClipboardScreen)
        #expect(items(for: "clip").map(\.id) == ["command:clipboard-history", "with:clipboard-history"])
        #expect(items(for: "hello").map(\.id) == ["with:clipboard-history"])

        host.modules.setOn(.clipboardSearchFallback, false)
        #expect(items(for: "clip").map(\.id) == ["command:clipboard-history"])
    }
}
