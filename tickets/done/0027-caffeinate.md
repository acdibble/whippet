---
priority: medium
labels: [commands]
---

# Caffeinate

Keep the Mac and its display awake on demand, like Raycast's Caffeinate or the Caffeine app.

## Done when

- [x] Commands keep the Mac awake until turned off, or for a chosen duration
- [x] Decaffeinate turns it off, and timed sessions end on their own
- [x] The menu bar shows when the Mac is being kept awake, and until when
- [x] Caffeinate can have its own hotkey

## Notes

Uses an IOKit power assertion, released automatically if Whippet quits. Caffeinate for… takes hours, minutes and seconds inline in the search field. The optional menu bar item is an NSStatusItem, because SwiftUI's MenuBarExtra(isInserted:) would not hide when the setting changed outside SwiftUI. Commands show a toast when they run.
