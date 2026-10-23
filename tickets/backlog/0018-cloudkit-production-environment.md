---
priority: high
labels: [release, sync]
---

# CloudKit production environment

Release builds use CloudKit's Production environment, which has no schema until it is deployed, so sync would fail for every user.

## Done when

- [ ] The schema is deployed from Development to Production in the CloudKit Console
- [ ] Release builds use `aps-environment: production` and a Developer ID profile that includes iCloud
- [ ] Sync works in a notarized build on two Macs

## Notes

Redeploy the schema whenever record types or fields change.

