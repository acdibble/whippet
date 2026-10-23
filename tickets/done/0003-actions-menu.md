---
priority: high
labels: [ui]
---

# ⌘K Actions menu

Each result has one action today. A ⌘K menu lists the rest for the selected item.

## Done when

- [x] ⌘K opens a filterable list of actions for the selected result
- [x] Clipboard items: paste, copy, paste as plain text, pin, delete
- [x] Apps: open, show in Finder, copy path
- [x] The footer shows "Actions ⌘K"

## Notes

Built as a native NSMenu above the footer, so keyboard navigation comes from AppKit; it offers type-to-select rather than a filter field. Paste as plain text is left out because history stores plain text only, so it would match Paste. Deletes also remove the item from iCloud.
