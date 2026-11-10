# Modules

Everything Whippet does belongs to a module, such as Calculator, Clipboard History or Timers. A module declares its
**commands** (rows in the search, each of which can have a hotkey) and its **features** (what it does without being a
command, such as currency conversion or link previews) in a manifest, along with what each one uses: the network,
Accessibility, Screen Recording and so on.

Settings › Commands is built from the manifests. Any module, command or feature can be turned off there, and each
module's page shows what it uses. Whippet enforces what's declared: a command or feature can only use what its manifest
lists, and only while it's turned on.

Extensions are modules too. Their commands are listed with the built-in ones, and what their `manifest.json` asks for
is shown and enforced the same way (see [extensions.md](extensions.md)).

## Manifests

Each built-in module has a folder in `Sources/Whippet/Modules/<Name>/` with its manifest, an extension on
`ModuleManifest`:

```swift
extension ModuleManifest {
    static let calculator = ModuleManifest(
        id: "calculator",
        title: String(localized: "Calculator"),
        summary: String(localized: "Calculations, conversions and time zones, with a history of answers."),
        icon: "plus.forwardslash.minus",
        tint: .orange,
        commands: [
            ModuleCommand(
                id: "calculator", title: String(localized: "Calculator"), icon: "plus.forwardslash.minus",
                permissions: [.accessibility(.paste)], legacyHotkey: "command.calculator"),
        ],
        features: [
            ModuleFeature(
                id: "currency", title: String(localized: "Currency Conversion"),
                summary: String(localized: "Fetches the European Central Bank's daily exchange rates every 6 hours."),
                permissions: [.network(["www.ecb.europa.eu"])]),
        ]
    )
}

extension ModuleRef {
    static let calculator = ModuleManifest.calculator.ref("calculator")
    static let currencyConversion = ModuleManifest.calculator.ref("currency")
}
```

- **IDs** are kebab-case and never change: they name the switch in user defaults (`module.calculator.enabled`,
  `module.calculator.currency.enabled`) and a new command's hotkey (`command.calculator.<id>`).
- **`legacyHotkey`** keeps the name a hotkey had before modules, so hotkeys people set still work. New commands leave
  it out.
- **`legacyItemID`** keeps the id a command's row had before modules where that isn't `command:<id>`, so its launches
  and its place in Favorites are kept. New commands leave it out.
- **`isRequired`** keeps a command on, as for Settings and Quit, so Settings can always be reached. A module with a
  required command can't be turned off.
- **`stage: .beta(summary:)`** keeps a module off, and out of Settings › Commands, until its beta feature is on.

`ModuleRef` names a module, or a command or feature in it, and is what everything checks: `ModuleSettings.isEnabled`,
`PermissionGate.allows` and the hotkeys.

## Permissions

`Permission`, in WhippetCore so extensions use it too, is what a command or feature can use:

| Permission | For |
|---|---|
| `.network([hosts])` | Connecting to hosts given as patterns: `api.github.com`, `*.example.com`, or `*` for any website |
| `.clipboardRead` | Reading what's copied in any app |
| `.accessibility(.paste)` | Sending ⌘V to the app Whippet opened over |
| `.accessibility(.windows)` | Moving and resizing other apps' windows |
| `.screenRecording` | Reading text on the screen |
| `.automation([targets])` | Asking apps such as System Events or Finder to do things with Apple Events |
| `.notifications` | Posting notifications |
| `.iCloud(.privateDatabase)` / `.iCloud(.publicDatabase)` | Syncing through the user's iCloud, or sending feedback |
| `.systemDownloads` | Downloads macOS makes for Whippet, such as translation languages |

Declare what each command or feature uses, not the module: Settings shows it beside the switch that turns it off, and
`PermissionGate` checks each use against the row it's for.

### Using one

Code that uses something sensitive goes through `PermissionGate` (`Sources/Whippet/Permissions/`), naming the command
or feature it's for:

```swift
// A network session allowed only the hosts currency conversion declares, and only while it's on.
let session = PermissionGate.shared.network(for: .currencyConversion)
let (data, _) = try await session.data(for: request)

// Pastes into the app Whippet opened over, if Clipboard History declares it, is on, and macOS allows it.
PermissionGate.shared.paste(into: targetApp, for: .clipboardHistory)

guard PermissionGate.shared.hasAccessibility(.windows, for: command.moduleRef) else { return }
try PermissionGate.shared.runAppleScript(source, in: .finder, for: SystemCommand.emptyTrash.moduleRef)

// The pasteboard to read from, the public database, and a notification, each nil, thrown or false while it's off.
guard let pasteboard = PermissionGate.shared.clipboard(for: .clipboardRecording) else { return }
let database = try PermissionGate.shared.publicDatabase(for: .sendFeedback)
let isPosted = await Notifications.shared.post(.timerDone, identifier: id, title: title, body: body, for: .timersModule)
```

- **Undeclared** use is a bug: a debug build stops at an assertion, and a release build refuses it and logs a fault
  under the `permissions` category. The gate fails closed: until it's given the switches, first thing at launch,
  nothing is allowed.
- **Network** requests go through `ScopedSession`, which checks the scheme and host of every request and redirect
  against the declared patterns, and asks before each request whether the feature is still on, so turning it off stops
  it even mid-refresh. Requests macOS makes itself, such as LinkPresentation's, are checked against the session first
  (`LinkMetadata`).
- **Requests the system makes** that Whippet can't route are declared like the rest and started through the gate:
  the public database (`publicDatabase(for:)`) and translation downloads (`languageDownload(_:for:onFinish:)`).
  Cloud Sync's private database and Sparkle are started by their own services, which their modules allow only while
  they're on.
- **Notifications** are posted through `Notifications` for the command or feature they're from. A new kind is a case
  of `Notifications.Kind` with its buttons, and whoever posts it sets what's called when it's clicked with
  `onResponse(to:)`.

`just lint` and CI run `scripts/check-permissions.sh`, which fails when `URLSession(`, `LPMetadataProvider`,
`AXIsProcessTrusted`, Screen Recording's APIs, `NSAppleScript`, `UNUserNotificationCenter`, a synthesized key event,
`CKContainer(`, `CKSyncEngine(`, `prepareTranslation` or a read of `NSPasteboard.general` is used outside
`Sources/Whippet/Permissions/`, `ScopedSession` and `CloudSync`. A new kind of use gets a method on `PermissionGate`.

### Entitlements

Entitlements and usage descriptions are signed into the app, so they can't be turned off, but `ManifestTests` keeps
them in step with the manifests: every entitlement in `Resources/Whippet*.entitlements` and every
`NS*UsageDescription` in `project.yml` has to be claimed by a kind of permission some module declares, in the tables at
the top of the test. Turning a module off means Whippet never uses its entitlements.

## The module

Each module is a `LauncherModule` in its folder, such as `Modules/Timers/TimersModule.swift`, built in
`AppDelegate.makeModules()`. A module owns what only it uses, such as `Timers` or the floating calculator, and is
given only what's shared, such as clipboard history. What it does with the panel or with windows of its own goes
through the host too (`closePanelForWindow()`, `panelWindowNumber`, `hasOpenWindow`), so the app delegate holds no
module's code. The host, `LauncherModel`, knows nothing of what modules do:
it asks them for rows and actions and runs them.

```swift
@MainActor
final class CaffeinateModule: LauncherModule {
    let manifest = ModuleManifest.caffeinate

    func row(for command: ModuleRef, _ item: LauncherItem) -> LauncherItem? {
        // Decaffeinate is only listed while something is keeping the Mac awake.
        command == .decaffeinate && !caffeine.isActive ? nil : item
    }

    func actions(for item: LauncherItem) -> [ItemAction] {
        switch item.command {
        case .caffeinate?:
            [.command(owner: .caffeinate) { [caffeine] in
                caffeine.start(seconds: nil)
                return .dismiss
            }]
        default: []
        }
    }

    func runHotkey(for command: ModuleRef) -> Bool {  // only where the hotkey differs
        guard command == .caffeinate else { return false }
        caffeine.toggle()
        return true
    }
}
```

- **Commands** are listed for the module: the host makes a row for every command in the manifest, from its title,
  icon and id (`LauncherItem.command(_:of:)`), so the search can't disagree with Settings › Commands. The module
  changes what differs in `row(for:_:)`, such as a subtitle, or returns nil to leave a command out for now. It tells
  its commands apart by `item.command`, a `ModuleRef`, and offers their actions in `actions(for:)`.
- **Other rows**, those that come and go such as each app or a typed timer, are the module's `contributions(for:)`.
- **Rows** are `LauncherItem`s: an id (what launches and favorites are kept under, so keep it stable), title, icon,
  section, and the module's own value in `payload`, which it gets back with `item.payload(as:)`.
- **Where they go** in the main search is the `Contribution`: `.listed` (ranked, and under Favorites, Suggestions or
  its section), `.top` (above the empty search, as running timers are), `.leading` (above the ranked results, as a
  typed timer is), `.fallback` (under “Use … with”), `.pinned` (fixed above the list, as a translation is) or
  `.exclusive(screen)`, which takes the search over, as the calculator does for `2+3`.
- **Actions** are offered by the screen an item is in. The first runs on Return, the second on ⌘Return, and ⌘K lists
  them all with their shortcuts. In the main search, the item's module offers them. Each returns an `ActionOutcome`
  the host handles the same way for every module: `.dismiss`, `.push(screen)`, `.input(request)`, `.fail()` and so
  on. `owner` names the command or feature it belongs to, which has to be on for it to be offered.
- **Other modules' rows** describe what they hold with `traits(of:)`, and a module can offer actions on them with
  `contributedActions(for:traits:)`, so neither names the other: Timers offers Start Timer on anything with a duration,
  such as a calculation.
- **The host** is all a module or its screens know of the launcher: the `ModuleHost` it's given in `attach(to:)`.
  A module never casts it to `LauncherModel` or reaches another module through it, so it runs the same against
  `FakeHost` in tests. What a module needs from the launcher is added to `ModuleHost`. Only a module's SwiftUI views
  read `LauncherModel` itself, from the environment.
- **Screens** are `LauncherScreen`s, pushed with `.push`. A screen gives the search bar (`.field` or `.title`), an
  accessory at the end of the bar, its items for the query, the actions for each, its `content` (the host's list or a
  view of its own, `.custom`, which reads the host from the environment) and its `footer` (the selected item's
  actions by default, with the command's badge if it gives one, or a view of its own). The host keeps the bar at the
  top and the footer at the bottom, and gives the content the height between them, clipped to it, so a view scrolls
  whatever might not fit. Plain keys, ↑↓ and ←→ in its own layout,
  and Escape are its to take, through `keys`, `verticalMove`, `horizontalMove` and `back()`.
- **Text in the bar** is an `InputRequest`: a label and one or more fields, submitted with Return. Its submit returns
  an outcome too, so `.input` asks for more, as Start Timer… asks for a name after the duration.
- **Settings** is filled in by the modules, so it names none of them. While a module is on, its `settingsPane` is
  listed in the sidebar and its `generalSettings` (switches, or a section) in General. Its `dynamicRows`, the rows
  that come and go such as each app, get a switch each under it in Commands and a hotkey each in Shortcuts. A feature
  whose switch already belongs to a service, such as Cloud Sync's own, returns that switch from
  `externalSwitch(for:)`, so the one in Commands and the one in its pane are the same.
- **Hotkeys**: every command in the manifest has one, which runs the first action of the command's row, opening the
  panel on a screen or input the action asks for (`LauncherModel.runCommand`, or `ModuleHost.runCommand` from a
  module's own menu). A module takes the hotkey itself in `runHotkey(for:)` only where it differs from choosing the
  command, as Caffeinate's also stops it. Rows that come and go, such as each app, register their own handlers and
  name the hotkeys in `dynamicRows`.

## Turning things off

`ModuleSettings` keeps the switches. Everything is on until it's turned off, so features added in an update start on;
their changelog entry should say what they use, so What's New tells people.

What's off must do no work:

- **Rows** are listed only while everything in their `refs` is on, and a module that's off isn't asked for any.
- **Actions** whose `owner` is off aren't offered.
- **Hotkeys** of commands that are off are unregistered, and kept for when they're turned back on.
- **Background work** starts and stops in the module's `update(_:)`, which runs at launch and after every switch or
  beta feature changes, such as the clipboard watcher, exchange rates or a status item.
- **Settings panes** are listed only while their module is on.

### Locked while in use

Something running keeps the switches needed to manage it on, so turning them off can't strand it. A module's
`activity` returns an `ActivityLock` for each, naming the module, the rows it keeps on and why:

```swift
ActivityLock(module: "timers", rows: ["timers", "stopwatch"], reason: String(localized: "A timer or stopwatch is running"))
```

The module itself is always locked. Settings shows the reason, and `ModuleSettings.setOn` refuses to turn a locked row
off.

### Beta modules

A module that's still being tried out declares `stage: .beta(summary:)` in its manifest. It's listed under Settings ›
General › Beta Features, starts off, and joins Settings › Commands once it's turned on. The host enforces it:
`ModuleSettings.isEnabled` is false for the module and everything in it until then, so its rows, actions, hotkeys and
pane are left out like those of a module that's switched off, and its `update(_:)` runs when the flag changes. The
module never reads the flag itself.

## Adding a module

1. Add `Sources/Whippet/Modules/<Name>/<Name>Manifest.swift` with its manifest and `ModuleRef`s, and add it to
   `ModuleRegistry.all`, in the order Settings lists modules.
2. Add its `LauncherModule`, with its screens and views beside it, and build it in `AppDelegate.makeModules()`, where
   its place in the list is where its rows go in the empty search. The launcher stops at launch if the modules built
   there and the manifests in the registry aren't the same set.
3. Declare what each command and feature uses, and use it through `PermissionGate`.
4. Put logic that needs no app in `Modules/<Name>/Core/`, which the tests compile, and test it there; test its rows in
   the main search against `FakeHost`.
5. Translate its strings into Farsi; `ManifestTests` checks its titles and summaries.
6. Add a changelog entry saying what it does and what it uses.

Adding a command or feature to a module, or a permission to one, is the same: declare it in the manifest first.
