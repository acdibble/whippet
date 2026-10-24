# Changelog

All notable changes to Whippet. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Whippet checks for updates and installs them, with Check for Updates… in the menu bar menu and Settings › General.
  Earlier versions need this one downloaded by hand.

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

[Unreleased]: https://github.com/acdibble/whippet/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/acdibble/whippet/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/acdibble/whippet/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/acdibble/whippet/releases/tag/v0.1.0
