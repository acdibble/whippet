---
priority: high
labels: [search]
---

# Refresh the app index

Apps are indexed once at launch, so newly installed apps never appear, and results are not ranked by use.

## Done when

- [x] Installing or removing an app updates search without relaunching
- [x] Frequently opened apps rank above equal fuzzy matches

## Notes

Watches the application folders with dispatch sources and rescans a second after a change. Launch counts are kept in user defaults and only break ties between equal fuzzy scores. An app copied in slowly can be indexed half-copied until the folder next changes.

