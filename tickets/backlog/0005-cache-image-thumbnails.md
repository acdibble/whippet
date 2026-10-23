---
priority: medium
labels: [clipboard, performance]
---

# Cache image thumbnails

Clipboard rows and the preview decode the full PNG from disk on every render, which gets slow with many large screenshots.

## Done when

- [ ] Thumbnails are downsampled once and cached in memory
- [ ] Scrolling a history of 100 screenshots stays smooth

## Notes

