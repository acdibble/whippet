# Whippet

A fast, keyboard-driven launcher for macOS. Free and open source.

- **Search and open apps** with fuzzy matching, ranked by how often you use them
- **Clipboard history** for text, links, numbers and images, with full-text search, recognized text in images, pinning, and paste straight into the app you were using
- **Calculator** that understands standard and RPN input, thousands separators and hex, octal and binary, with a history of answers
- **Hotkeys** for opening Whippet, any app or any command
- **Caffeinate** to keep your Mac awake until you turn it off or for a set time, with an optional menu bar item
- **iCloud sync** of clipboard history, pins and calculator history across your Macs, end-to-end encrypted, images included

## Install

Download the latest `Whippet-x.y.z.dmg` from [Releases](../../releases), open it and drag Whippet to Applications.
Requires macOS 15 or later.

Press **⌥ Space** to open Whippet. To paste into other apps, allow Whippet under
System Settings › Privacy & Security › Accessibility.

## Build

Requires Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate
open Whippet.xcodeproj
```

The project signs with the Dibble Codes team and its iCloud container. To build your own copy, change
`DEVELOPMENT_TEAM`, the bundle identifier and the iCloud container in `project.yml`,
`Resources/*.entitlements` and `Sources/Whippet/CloudSync.swift`.

Debug builds are a separate app, Whippet Dev (`codes.dibble.whippet.dev`), with a yellow menu bar icon, its own
settings and data in `~/Library/Application Support/Whippet Dev`, and CloudKit's Development environment, so it runs
beside an installed release.

Releases are built, signed, notarized and published by `.github/workflows/release.yml` when a `v*` tag is pushed.
To cut one, rename the Unreleased section of [CHANGELOG.md](CHANGELOG.md) to the new version, make sure
`MARKETING_VERSION` in `project.yml` matches it, and tag that commit. The workflow refuses a tag that doesn't match,
and publishes the changelog section as the release notes. Afterwards, set `MARKETING_VERSION` to the next version.

Each release also attaches a signed `appcast.xml`, which Sparkle in the app reads to offer the update. It's signed with
the `SPARKLE_PRIVATE_KEY` repository secret, whose public key is `SUPublicEDKey` in `project.yml`.

## License

[MIT](LICENSE) © 2026 Dibble Codes
