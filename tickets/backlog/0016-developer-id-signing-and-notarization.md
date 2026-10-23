---
priority: high
labels: [release]
---

# Developer ID signing and notarization

Release builds must be signed with Developer ID and notarized, or Gatekeeper blocks them on other Macs.

## Done when

- [ ] A Developer ID Application certificate exists for the team
- [ ] A Release build signs with it, with hardened runtime
- [ ] The build is notarized with `xcrun notarytool` and stapled
- [ ] It opens without warnings on a Mac that has never run it

## Notes

Notarization needs an app-specific password or an App Store Connect API key, stored in the keychain with `notarytool store-credentials`.

