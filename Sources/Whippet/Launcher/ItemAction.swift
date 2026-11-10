import AppKit

/// Something that can be done with an item, offered by the screen it's shown in. Return runs a screen's first action
/// for the selected item and ⌘Return its second, ⌘K lists them all, and each runs on its own shortcut. The host keeps
/// no list of actions of its own: it runs what the screen offers.
struct ItemAction: Identifiable {
    /// Stable, such as `timers.add-minute`, for telling actions apart.
    let id: String
    var title: String
    /// An SF Symbol, shown in ⌘K.
    var icon: String?
    var shortcut: KeyShortcut?
    /// The keys that run it without modifiers, on screens whose plain keys are on, such as `+` or `=` in Timers.
    var plainKeys: String?
    /// A heading it's listed under in ⌘K.
    var section: String?
    /// Shown in red, last.
    var isDestructive = false
    /// Tab runs it too, as for a quicklink that takes text.
    var runsOnTab = false
    /// The command or feature it belongs to, which has to be on for it to be offered: turning off Floating Calculator
    /// takes Pop Out off calculations.
    var owner: ModuleRef?
    /// The item's launch is recorded when it runs, unless it asks for input, which records it when that's submitted.
    var recordsLaunch = false
    let perform: @MainActor () -> ActionOutcome
}

/// What the host does after an action, the same for every module.
enum ActionOutcome {
    /// Closes the panel.
    case dismiss
    /// Nothing more.
    case stay
    /// Selects the same item again after the list changes, as after pinning it.
    case keepSelection
    /// The item is gone, so the selection stays in range.
    case removed
    /// Opens a screen over the current one.
    case push(any LauncherScreen)
    /// Asks for text in the search bar.
    case input(InputRequest)
    /// Beeps, with a toast when there's a message.
    case fail(String? = nil)
}

/// A key with modifiers, such as ⇧⌘P.
struct KeyShortcut: Equatable {
    /// What the key types, such as `p`, `=` or `\r` for Return.
    let key: String
    let modifiers: NSEvent.ModifierFlags

    init(_ key: String, _ modifiers: NSEvent.ModifierFlags = []) {
        self.key = key
        self.modifiers = modifiers
    }

    static let returnKey = KeyShortcut("\r")
    static let commandReturn = KeyShortcut("\r", .command)
    static let delete = KeyShortcut("x", .control)
}

/// Text the search bar asks for, shown as a label in front of one or more fields: a quicklink's text, a timer's
/// duration and then its name, or Caffeinate for…'s hours, minutes and seconds.
struct InputRequest {
    struct Field {
        var placeholder: String
        var text = ""
        /// Narrow fields sit side by side, as for hours, minutes and seconds.
        var isNarrow = false
    }

    var label: String
    var fields: [Field]
    /// The title of Return in the footer.
    var submitTitle = String(localized: "Done")
    /// Escape clears what's typed before it cancels. A rename starts from the saved name, so it cancels outright.
    var escapeClears = true
    /// Recorded as a launch when it's submitted, such as the quicklink it opens.
    var launchKey: String?
    /// Given each field's text; `.input` asks for more, as a timer's name after its duration, and `.fail` beeps.
    let submit: @MainActor ([String]) -> ActionOutcome

    init(
        label: String, placeholder: String, text: String = "", submitTitle: String = String(localized: "Done"),
        escapeClears: Bool = true, launchKey: String? = nil, submit: @escaping @MainActor (String) -> ActionOutcome
    ) {
        self.label = label
        fields = [Field(placeholder: placeholder, text: text)]
        self.submitTitle = submitTitle
        self.escapeClears = escapeClears
        self.launchKey = launchKey
        self.submit = { values in submit(values.first ?? "") }
    }

    init(
        label: String, fields: [Field], submitTitle: String = String(localized: "Done"), launchKey: String? = nil,
        submit: @escaping @MainActor ([String]) -> ActionOutcome
    ) {
        self.label = label
        self.fields = fields
        self.submitTitle = submitTitle
        self.launchKey = launchKey
        self.submit = submit
    }
}
