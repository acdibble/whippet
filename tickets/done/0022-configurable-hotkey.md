---
priority: high
labels: [ux, settings]
---

# Configurable hotkey

⌥Space is fixed and clashes with other tools, such as ChatGPT's desktop app.

## Done when

- [x] Settings › General records a new hotkey and saves it
- [x] A clash with another app's hotkey is reported
- [x] The menu bar menu and onboarding show the current hotkey

## Notes

Uses the KeyboardShortcuts package, which replaced the Carbon hotkey. Its recorder warns about clashes with system shortcuts and the app's menus; shortcuts registered by other apps cannot be detected through public APIs. Onboarding does not exist yet (0021), and the menu bar label only updates after a relaunch.

