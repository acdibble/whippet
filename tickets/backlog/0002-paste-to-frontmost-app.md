---
priority: high
labels: [clipboard, calculator, accessibility]
---

# Paste to frontmost app

Return only copies. Raycast pastes the clipboard item or calculator answer straight into the app you were using, which saves a ⌘V every time.

## Done when

- [ ] Return pastes into the previously active app; ⌘Return copies only
- [ ] Accessibility permission is requested on first use, with a clear fallback to copying when denied
- [ ] The footer names the target app, as in "Paste to iTerm2"

## Notes

Needs a simulated ⌘V through `CGEvent`, which requires Accessibility permission.

