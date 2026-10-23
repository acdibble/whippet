---
priority: high
labels: [search]
---

# Refresh the app index

Apps are indexed once at launch, so newly installed apps never appear, and results are not ranked by use.

## Done when

- [ ] Installing or removing an app updates search without relaunching
- [ ] Frequently opened apps rank above equal fuzzy matches

## Notes

Watch the application folders with FSEvents, or re-index when the panel opens.

