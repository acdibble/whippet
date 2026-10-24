# Changelog

All notable changes to Whippet. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- A floating calculator that stays above other windows without taking focus from them, so you can do sums while
  reading. Open it with the Floating Calculator command or its hotkey, or pop a calculation out of the launcher with
  ⌘⇧O.

### Changed

- A calculation typed in the main search is answered inside the search bar, which stays one line tall. Press ↓ for
  the full calculator view.

### Fixed

- After ⌘-dragging the Caffeinate item out of the menu bar, turning Show Caffeinate in Menu Bar back on didn't show it.

## [0.6.0] - 2026-10-24

### Added

- Press ↓ in the empty search field to see every command and app, with the ones you use most under Suggestions.
- Lock Screen, Sleep, Restart, Shut Down, Empty Trash and Toggle Dark Mode commands. Restart, Shut Down and Empty
  Trash ask first.

### Changed

- Search ranks apps and commands by how often and how recently you open them, and matches initials and word starts
  better, so "vsc" finds Visual Studio Code.
- Feedback is encrypted so only Whippet's developer can read it, including the email address and system details.
- Clipboard history with many screenshots scrolls smoothly, since images are shown from small copies kept in memory.

### Fixed

- Copying an image from clipboard history could add it again as a duplicate.

## [0.5.1] - 2026-10-24

### Changed

- On macOS 26, the launcher panel, its buttons and confirmation toasts use Liquid Glass.

## [0.5.0] - 2026-10-24

### Fixed

- Check for Updates in 0.4.0 couldn't start. Install this version by hand once, and updates work from then on.

## [0.4.0] - 2026-10-24

### Added

- Whippet checks for updates and installs them, with Check for Updates… in the menu bar menu and Settings › General.
  Earlier versions need this one downloaded by hand.
- Apps and commands show their hotkey in search results.
- A Clipboard History pane in Settings, with how long to keep items, apps whose copies are never saved, item counts and
  Clear History.

### Changed

- Copying no longer makes Whippet pause, since saving to history happens in the background.
- Text copies larger than 500 KB aren't saved to history.

### Fixed

- App search didn't find Finder, Keychain Access or the other system apps in `/System/Library/CoreServices`.

## [0.3.0] - 2026-10-24

### Added

- Calculator history syncs through iCloud.
- A Changelog command that opens this page.
- A Developer pane in Settings that shows the iCloud user record.

### Changed

- Everything Whippet syncs is end-to-end encrypted, including images, the source app and timestamps, and record names
  no longer reveal what was copied. Turning sync on again uploads history in the new format.
- Typing in the launcher is faster, since results are computed once per change.

### Fixed

- A synced image that couldn't be saved could make Whippet crash at every launch.
- Copying an image whose file was missing emptied the clipboard.
- Pasting deeply nested input into the calculator could crash Whippet, and long input could freeze it.
- Caffeinate for… crashed Whippet when given a huge duration. Durations are now limited to a week.
- Turning sync off and on quickly could start it twice.
- Items deleted while sync was off, or while it was starting, stayed in iCloud and on other Macs.
- Images copied on another Mac while Include Images was off never arrived after turning it back on.
- Launcher shortcuts didn't work with Caps Lock on, ⌘-keypad-Enter did nothing, and the arrow keys, Return and Escape
  couldn't be used to choose Japanese or Chinese input candidates in the search field.
- Launcher shortcuts such as ⌘K used the key in the K position of a US keyboard rather than the key labelled K, on
  layouts like AZERTY and Dvorak.
- Settings showed version 0.1.0 in builds made from source.

## [0.2.0] - 2026-10-24

### Added

- Caffeinate, Caffeinate for… and Decaffeinate commands to keep the Mac awake, with an optional menu bar item.
- Send Feedback, from the menu bar, the launcher and Settings, with an option to open a GitHub issue instead.

## [0.1.0] - 2026-10-24

Tagged but never published, since notarization timed out; 0.2.0 was the first release.

### Added

- A launcher panel, opened with a hotkey you can change, that searches apps with fuzzy matching ranked by use.
- Clipboard history for text, links, numbers and images, with search, filters, pins and text recognized in images.
- Pasting clipboard items and calculator answers straight into the app you were using.
- A calculator for standard and RPN input, thousands separators and hex, octal and binary, with a history of answers.
- Hotkeys for any app or command, and a ⌘K menu of actions for the selected result.
- iCloud sync of clipboard history and pins across your Macs.
- A Farsi translation.

[Unreleased]: https://github.com/acdibble/whippet/compare/v0.6.0...HEAD
[0.6.0]: https://github.com/acdibble/whippet/compare/v0.5.1...v0.6.0
[0.5.1]: https://github.com/acdibble/whippet/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/acdibble/whippet/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/acdibble/whippet/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/acdibble/whippet/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/acdibble/whippet/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/acdibble/whippet/releases/tag/v0.1.0
