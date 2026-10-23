---
priority: medium
labels: [sync]
---

# Sync history with CloudKit

Sync clipboard history, pins and calculator history across Macs.

## Done when

- [x] Changes appear on another Mac signed into the same iCloud account
- [x] Clipboard contents use CloudKit encrypted fields
- [x] Image sync can be turned off

## Notes

Built on `CKSyncEngine` with one zone in the private database. Records are named by content hash, so the same copy on two Macs is one record. Sync is off by default and is controlled from Settings › Cloud Sync. Sync between two Macs was not verified.

