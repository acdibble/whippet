---
priority: medium
labels: [release]
---

# Versioning and release script

Each release should be one command: bump the version, build, sign, notarize, package and publish.

## Done when

- [ ] `CFBundleShortVersionString` and `CFBundleVersion` are bumped by the script
- [ ] One command produces a notarized DMG and an updated appcast
- [ ] Optionally runs in GitHub Actions with signing secrets

## Notes

Depends on 0016, 0017 and 0019.

