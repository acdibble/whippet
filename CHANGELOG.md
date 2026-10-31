# Changelog

All notable changes to Whippet. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Start Timer (⌘T, or from ⌘K) on a calculator answer that's a time: an amount, such as `90 min to h` or
  `1 h + 30 min`, or a moment to count down to, such as `time until 5pm`, `now + 90 min` or `3pm in london`.

## [1.2.1] - 2026-10-30

### Added

- Percentages in the calculator, such as `20% of 50`, `50 + 20%`, `80 - 15%`, `15% off 80` or `15% on 80`. A `%`
  followed by a number is still the remainder, as in `10 % 3`.
- Adding time to a date, such as `today + 3 weeks`, `dec 25 - 10 days`, `now + 90 min` or `tomorrow 9am + 2 h`.
- Numbers in another base, such as `255 in hex`, `0xFF to binary`, `0b1010 as decimal` or `(12 + 4) in octal`.

## [1.2.0] - 2026-10-30

### Added

- The time somewhere else, such as `time in tokyo`, `3pm pst in london` or `15:30 to new york`, by city, country,
  time zone abbreviation or offset.
- The time since or until a date, such as `time until dec 25`, `time since 5 may 1990 10am` or `days until friday`.
- Arithmetic with units and rates, such as `2100 seconds / 3 in minutes`, `1 h + 30 min`, `5 ft 10 in to cm`,
  `100 km / 2 h to mph` or `20 items / second * 1 h`. Arithmetic or a rate shows its answer straight away, such as
  `20 items / second` as 20 items/s, before you type what to convert it to.

### Changed

- Currency conversions show when the exchange rates were last updated, instead of the day they're for.

## [1.1.0] - 2026-10-30

### Added

- Currency conversion, such as `10 usd to eur`, `$20 in €`, `€1,000 to pounds` or `2 * 3 GBP as yen`, with the
  European Central Bank's daily reference rates. Rates are fetched a few times a day and kept for when you're offline.

## [1.0.1] - 2026-10-30

### Added

- Unit conversion handles rates, such as `9.35 items per second in hours`, `60 km/h to per minute` or
  `2 cups per day to weeks`, or for units that are rates already, `60 mph in minutes`.

## [1.0.0] - 2026-10-29

### Added

- An app icon: a whippet's head in white on orange.

### Changed

- A new whippet head in the menu bar.

## [0.12.0] - 2026-10-29

### Added

- The Changelog command shows every version's changes in the launcher, and ⌘↩ still opens it on GitHub.
- After an update, What's New at the top of the launcher gathers the changes since the version you had, for a week or
  until you open or dismiss it.

## [0.11.3] - 2026-10-29

### Added

- Paste as JPEG and Copy as JPEG for images in clipboard history, in the ⌘K actions. The JPEG goes on the clipboard as
  a file named after the image, so web pages and apps that only take JPEG accept it, and transparency turns white.

### Fixed

- Images copied from apps that offer only another format, such as HEIC or WebP, are now kept in clipboard history.
- Photos copied from Photos show their format rather than the name of a file inside the Photos library.
- Return in the ⌘K actions menu runs the highlighted action rather than always pasting.

## [0.11.2] - 2026-10-28

### Added

- Clipboard history keeps copied files, with their full names and extensions, under a new Files filter. Pasting one
  pastes the file, and files stay on this Mac rather than syncing.
- Images copied as files in Finder show their file name, and paste as the file where it still exists. Other images
  show their format, such as “PNG image (1920×1080)”.

## [0.11.1] - 2026-10-27

### Changed

- Escape clears what you've typed before going back, and closes Whippet from a view opened with its own shortcut or
  the menu bar rather than going back to the main list. Escape while renaming keeps the saved name.
- Caffeinate carries on after Whippet restarts or updates, until its time runs out or it's turned off.

## [0.11.0] - 2026-10-26

### Added

- Window commands that move and resize the front window: left, right, top and bottom halves, thirds and two thirds,
  Maximize, Center, Next Display and Restore. Each can have its own hotkey in Settings › Shortcuts. They use the
  Accessibility permission pasting already asks for.

## [0.10.6] - 2026-10-26

### Changed

- Link previews in clipboard history show the page title first, with the image in the space below, and the details
  list the URL. Images no longer list how many words were recognized.

### Fixed

- Link previews use the page's share image when macOS doesn't find one, as on GitHub, instead of the site's icon.
  Previews already fetched are fetched again once, and sites that ask for a pause are retried later.

## [0.10.5] - 2026-10-26

### Fixed

- Pasting from clipboard history with Settings open pastes into the app you were in, not into Settings.

## [0.10.4] - 2026-10-26

### Added

- Up to 10 images can be attached to feedback, by pasting, dropping or choosing them. They're sent at full size,
  sealed like the rest of the feedback, without their location or other camera details.

### Fixed

- Pasting from clipboard history into Whippet's own windows, such as Send Feedback, pastes there, and no longer
  hides the window.
- Clicking the Dock icon brings back the open window, such as Send Feedback, and opens Settings only when nothing is
  open.
- Closing the feedback window clears it, so the next feedback starts empty.

## [0.10.3] - 2026-10-26

### Fixed

- A quicklink that takes text counts as used when it opens with that text, whether started with Return, Tab or
  its hotkey, and not when you start typing and then cancel.

## [0.10.2] - 2026-10-26

### Changed

- The search in Settings › Shortcuts filters commands and quicklinks as well as applications, and hides lists with
  no matches.

## [0.10.1] - 2026-10-26

### Added

- A Share Whippet with a Friend command, and a Copy Download Link button in Settings › About, which copy a link to
  download the latest release.

### Fixed

- With more than one screen, the launcher opened on the screen with Settings when Settings was open, rather than
  the screen you were working on.
- A command or app whose name starts with what you type now comes before matches scattered through other names, so
  `set` finds Settings before Search YouTube.

## [0.10.0] - 2026-10-25

### Added

- Timers and stopwatches. Type a duration such as `25m`, `1h30m` or `4:30` to start a timer, with a name after it
  (`25m tea`), or use Start Timer… and Start Stopwatch. Several can run at once, each with its own name. They're listed
  at the top of the launcher, where you can pause, add time, restart, take laps, rename or cancel them. A finished timer
  rings and sends a notification you can snooze.
- A timers view in the launcher, opened with the Timers command or from a running timer: every timer in one list
  with its progress, managed in place with Space to pause or resume, + to add a minute, R to restart, ⌫ to cancel, S
  to snooze and N for a new timer, and recent timers to start again.
- A stopwatch view in the launcher, opened with the Stopwatch command or from a running stopwatch, with a large
  clock, laps marked fastest and slowest, and Return or Space, L and R to start, lap and reset. ← and → switch between
  stopwatches.
- Settings › Notifications, to turn Whippet's notifications off altogether or one kind at a time, with the timer alert
  sound and snooze length.
  Settings › General can show a timer countdown in the menu bar.
- Unit conversion in the calculator: type `5 km to mi`, `72 f in c` or `2 * 3 hogsheads to l`. It covers length, mass,
  volume, temperature, time, data, speed, area, energy, pressure and angles, including parsecs, furlongs, fortnights
  and smoots. A unit that could mean two things, such as `m` or `c`, takes the meaning that fits the other unit.
  Return copies or pastes the number, and conversions are kept in calculator history.
- Links in clipboard history show their page's title and preview image, and both the title and any text in the
  image are searchable. Previews are fetched on each Mac and not synced; turn them off in Settings › Clipboard
  History › Fetch Link Previews. ⌘K › Refresh Preview fetches one again.

## [0.9.0] - 2026-10-24

### Added

- An Appearance setting in Settings › General to keep Whippet light or dark, or follow the system.

### Fixed

- In Dark mode, the launcher panel and toasts turned light over bright windows behind them.
- With iCloud sync on, a deleted clipboard item could come back straight away, as could an image deleted while its
  text was being recognized.

## [0.8.0] - 2026-10-24

### Added

- Quicklinks: saved links that take what you type, such as Search GitHub. Select one and press Tab to type the text,
  then Return to open it. Manage them in Settings › Quicklinks, or with the Create Quicklink command. They sync through
  iCloud, can have hotkeys, and come with Google, GitHub, Wikipedia and Maps to start.
- Search text is offered to every quicklink that takes text, and to clipboard history, even when it matches nothing by
  name, under "Use … with…".

### Changed

- A plain number, such as 0xFF or 1,000.5, shows its value in the search bar straight away, ready to copy or paste.

### Fixed

- Moving through results with the arrow keys could highlight the wrong rows, or two at once, across sections.

## [0.7.0] - 2026-10-24

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

[Unreleased]: https://github.com/acdibble/whippet/compare/v1.2.1...HEAD
[1.2.1]: https://github.com/acdibble/whippet/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/acdibble/whippet/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/acdibble/whippet/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/acdibble/whippet/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/acdibble/whippet/compare/v0.12.0...v1.0.0
[0.12.0]: https://github.com/acdibble/whippet/compare/v0.11.3...v0.12.0
[0.11.3]: https://github.com/acdibble/whippet/compare/v0.11.2...v0.11.3
[0.11.2]: https://github.com/acdibble/whippet/compare/v0.11.1...v0.11.2
[0.11.1]: https://github.com/acdibble/whippet/compare/v0.11.0...v0.11.1
[0.11.0]: https://github.com/acdibble/whippet/compare/v0.10.6...v0.11.0
[0.10.6]: https://github.com/acdibble/whippet/compare/v0.10.5...v0.10.6
[0.10.5]: https://github.com/acdibble/whippet/compare/v0.10.4...v0.10.5
[0.10.4]: https://github.com/acdibble/whippet/compare/v0.10.3...v0.10.4
[0.10.3]: https://github.com/acdibble/whippet/compare/v0.10.2...v0.10.3
[0.10.2]: https://github.com/acdibble/whippet/compare/v0.10.1...v0.10.2
[0.10.1]: https://github.com/acdibble/whippet/compare/v0.10.0...v0.10.1
[0.10.0]: https://github.com/acdibble/whippet/compare/v0.9.0...v0.10.0
[0.9.0]: https://github.com/acdibble/whippet/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/acdibble/whippet/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/acdibble/whippet/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/acdibble/whippet/compare/v0.5.1...v0.6.0
[0.5.1]: https://github.com/acdibble/whippet/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/acdibble/whippet/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/acdibble/whippet/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/acdibble/whippet/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/acdibble/whippet/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/acdibble/whippet/releases/tag/v0.1.0
