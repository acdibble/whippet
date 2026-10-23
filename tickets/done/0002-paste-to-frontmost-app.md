---
priority: high
labels: [clipboard, calculator, accessibility]
---

# Paste to frontmost app

Return only copies. Raycast pastes the clipboard item or calculator answer straight into the app you were using, which saves a ⌘V every time.

## Done when

- [x] Return pastes into the previously active app; ⌘Return copies only
- [x] Accessibility permission is requested on first use, with a clear fallback to copying when denied
- [x] The footer names the target app, as in "Paste to iTerm2"

## Notes

Sends ⌘V through `CGEvent` 80 ms after the panel closes. Settings › General shows whether Accessibility is allowed. Fixed along the way: Return re-assigned the search text, which reset the selection to the first item before pasting.

