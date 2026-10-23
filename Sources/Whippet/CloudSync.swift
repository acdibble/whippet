import CloudKit
import GRDB

/// Syncs clipboard and calculator history through the user's private CloudKit database with `CKSyncEngine`.
/// Records are named by content, so the same text copied on two Macs becomes one record.
@MainActor
@Observable
final class CloudSync {
    enum Status: Equatable {
        case off
        case checkingAccount
        case unavailable(String)
        case syncing
        case upToDate
        case failed(String)
    }

    private(set) var status = Status.off
    private(set) var pendingChanges = 0
    private(set) var lastSyncedAt = UserDefaults.standard.object(forKey: "cloudLastSyncedAt") as? Date {
        didSet { UserDefaults.standard.set(lastSyncedAt, forKey: "cloudLastSyncedAt") }
    }

    var isEnabled = UserDefaults.standard.bool(forKey: "cloudSyncEnabled") {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "cloudSyncEnabled")
            if isEnabled {
                start()
                return
            }
            stop()
        }
    }

    var includesImages = UserDefaults.standard.object(forKey: "cloudSyncIncludesImages") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(includesImages, forKey: "cloudSyncIncludesImages")
            enqueueUnsyncedRecords()
        }
    }

    /// Called after changes from another Mac were merged into the local store.
    @ObservationIgnored var onRemoteChanges: () -> Void = {}

    @ObservationIgnored private let store: ClipboardStore?
    @ObservationIgnored private var engine: CKSyncEngine?
    @ObservationIgnored private let container = CKContainer(identifier: "iCloud.codes.dibble.whippet")

    private static let zoneID = CKRecordZone.ID(zoneName: "Whippet")
    private static let clipboardType = "ClipboardItem"

    init(store: ClipboardStore?) {
        self.store = store
        if isEnabled {
            start()
        }
    }

    var statusDescription: String {
        switch status {
        case .off: return String(localized: "Off")
        case .checkingAccount: return String(localized: "Checking iCloud account…")
        case .unavailable(let reason): return reason
        case .syncing: return String(localized: "Syncing…")
        case .failed(let message): return message
        case .upToDate:
            guard let lastSyncedAt else { return String(localized: "Up to date") }
            return String(localized: "Up to date, last synced \(lastSyncedAt.formatted(.relative(presentation: .named)))")
        }
    }

    /// Queues a record changed on this Mac for upload.
    func recordChanged(_ recordName: String) {
        guard let engine else { return }
        engine.state.add(pendingRecordZoneChanges: [.saveRecord(Self.recordID(recordName))])
        updatePendingChanges()
    }

    /// Queues the deletion of a record removed on this Mac.
    func recordDeleted(_ recordName: String) {
        guard let engine else { return }
        engine.state.add(pendingRecordZoneChanges: [.deleteRecord(Self.recordID(recordName))])
        updatePendingChanges()
    }

    func syncNow() async {
        guard let engine else { return }
        status = .syncing
        do {
            try await engine.fetchChanges()
            try await engine.sendChanges()
            lastSyncedAt = .now
            status = .upToDate
        } catch {
            status = .failed(error.localizedDescription)
        }
        updatePendingChanges()
    }

    /// Deletes the iCloud copy of everything and turns sync off; history on this Mac is kept.
    func deleteCloudData() async {
        guard let engine else { return }
        status = .syncing
        engine.state.remove(pendingRecordZoneChanges: engine.state.pendingRecordZoneChanges)
        engine.state.add(pendingDatabaseChanges: [.deleteZone(Self.zoneID)])
        do {
            try await engine.sendChanges()
            try store?.forgetAllSyncState()
            deleteSavedState()
            lastSyncedAt = nil
            isEnabled = false
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    // MARK: - Lifecycle

    private func start() {
        guard let store else {
            status = .unavailable(String(localized: "History could not be opened, so there is nothing to sync."))
            return
        }
        status = .checkingAccount
        Task {
            let accountStatus = try? await container.accountStatus()
            guard isEnabled else { return }
            guard accountStatus == .available else {
                status = .unavailable(Self.describe(accountStatus))
                return
            }

            let savedState = loadSavedState()
            let configuration = CKSyncEngine.Configuration(
                database: container.privateCloudDatabase,
                stateSerialization: savedState,
                delegate: self
            )
            let engine = CKSyncEngine(configuration)
            self.engine = engine
            if savedState == nil {
                // A first sync with this container: sync markers left over from another container or account are stale.
                try? store.forgetAllSyncState()
                engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
            }
            enqueueUnsyncedRecords(in: store)
            await syncNow()
        }
    }

    private func stop() {
        engine = nil
        status = .off
        pendingChanges = 0
    }

    private func enqueueUnsyncedRecords() {
        guard let store else { return }
        enqueueUnsyncedRecords(in: store)
    }

    private func enqueueUnsyncedRecords(in store: ClipboardStore) {
        guard let engine, let names = try? store.unsyncedRecordNames(includeImages: includesImages) else { return }
        engine.state.add(pendingRecordZoneChanges: names.map { .saveRecord(Self.recordID($0)) })
        updatePendingChanges()
    }

    private func updatePendingChanges() {
        pendingChanges = engine?.state.pendingRecordZoneChanges.count ?? 0
    }

    private static func describe(_ accountStatus: CKAccountStatus?) -> String {
        switch accountStatus {
        case .noAccount: String(localized: "Sign in to iCloud to sync.")
        case .restricted: String(localized: "iCloud is restricted on this Mac.")
        case .temporarilyUnavailable: String(localized: "iCloud is temporarily unavailable.")
        default: String(localized: "Couldn't check the iCloud account.")
        }
    }

    // MARK: - Saved engine state

    private var stateURL: URL {
        ClipboardStore.defaultDirectory.appending(path: "cloud-sync-state-\(container.containerIdentifier ?? "default").json")
    }

    private func loadSavedState() -> CKSyncEngine.State.Serialization? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private func save(_ state: CKSyncEngine.State.Serialization) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }

    private func deleteSavedState() {
        try? FileManager.default.removeItem(at: stateURL)
    }

    // MARK: - Records

    private static func recordID(_ recordName: String) -> CKRecord.ID {
        CKRecord.ID(recordName: recordName, zoneID: zoneID)
    }

    /// Builds the record to upload, reusing the server's system fields so CloudKit sees an update rather than a conflict.
    private func record(for recordID: CKRecord.ID) -> CKRecord? {
        guard let store else { return nil }
        let name = recordID.recordName
        guard name.hasPrefix("clip-"), let row = try? store.clipboardSyncRow(hash: String(name.dropFirst(5))) else { return nil }
        return clipboardRecord(from: row, id: recordID, store: store)
    }

    private func clipboardRecord(from row: Row, id: CKRecord.ID, store: ClipboardStore) -> CKRecord? {
        let kind: String = row["kind"]
        if kind == ClipboardKind.image.rawValue, !includesImages { return nil }

        let record = Self.makeRecord(type: Self.clipboardType, id: id, systemFields: row["cloudSystemFields"])
        let copiedAt: Date = row["copiedAt"]
        let updatedAt: Date = row["updatedAt"]
        let timesCopied: Int = row["timesCopied"]
        record["kind"] = kind
        record["copiedAt"] = copiedAt
        record["updatedAt"] = updatedAt
        record["timesCopied"] = timesCopied
        record["pinnedAt"] = row["pinnedAt"] as Date?
        record["sourceBundleID"] = row["sourceBundleID"] as String?
        record["imageWidth"] = row["imageWidth"] as Int?
        record["imageHeight"] = row["imageHeight"] as Int?
        record["imageBytes"] = row["imageBytes"] as Int?
        record.encryptedValues["text"] = row["text"] as String?
        record.encryptedValues["ocrText"] = row["ocrText"] as String?
        if let imageFile = row["imageFile"] as String? {
            record["image"] = CKAsset(fileURL: store.imagesDirectory.appending(path: imageFile))
        }
        return record
    }

    private static func makeRecord(type: String, id: CKRecord.ID, systemFields: Data?) -> CKRecord {
        guard let systemFields, let coder = try? NSKeyedUnarchiver(forReadingFrom: systemFields) else {
            return CKRecord(recordType: type, recordID: id)
        }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder) ?? CKRecord(recordType: type, recordID: id)
    }

    /// Merges a record from iCloud into the local store, and queues it for upload when this Mac's copy is ahead.
    private func merge(_ record: CKRecord) {
        guard let store else { return }
        let name = record.recordID.recordName
        let systemFields = record.encodedSystemFields
        let isLocalAhead: Bool?

        switch record.recordType {
        case Self.clipboardType:
            let kind = (record["kind"] as? String).flatMap(ClipboardKind.init(rawValue:)) ?? .text
            if kind == .image, !includesImages { return }
            let hash = String(name.dropFirst(5))
            isLocalAhead = try? store.mergeRemote(
                RemoteClipboardItem(
                    hash: hash,
                    kind: kind,
                    text: record.encryptedValues["text"] as? String,
                    ocrText: record.encryptedValues["ocrText"] as? String,
                    imageFile: kind == .image ? saveImage(record["image"] as? CKAsset, hash: hash, store: store) : nil,
                    imageWidth: record["imageWidth"] as? Int,
                    imageHeight: record["imageHeight"] as? Int,
                    imageBytes: record["imageBytes"] as? Int,
                    copiedAt: record["copiedAt"] as? Date ?? .now,
                    sourceBundleID: record["sourceBundleID"] as? String,
                    timesCopied: record["timesCopied"] as? Int ?? 1,
                    pinnedAt: record["pinnedAt"] as? Date,
                    updatedAt: record["updatedAt"] as? Date ?? .distantPast,
                    systemFields: systemFields
                )
            )
        default:
            return
        }

        if isLocalAhead == true {
            recordChanged(name)
        }
    }

    /// Copies a downloaded image into the images folder under its content hash and returns the file name.
    private func saveImage(_ asset: CKAsset?, hash: String, store: ClipboardStore) -> String? {
        guard let source = asset?.fileURL else { return nil }
        let fileName = "\(hash).png"
        let destination = store.imagesDirectory.appending(path: fileName)
        if !FileManager.default.fileExists(atPath: destination.path) {
            guard (try? FileManager.default.copyItem(at: source, to: destination)) != nil else { return nil }
        }
        return fileName
    }

    private func handleFailedSave(_ failure: CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave, engine: CKSyncEngine) {
        let recordID = failure.record.recordID
        switch failure.error.code {
        case .serverRecordChanged:
            guard let serverRecord = failure.error.serverRecord else { return }
            merge(serverRecord)
            engine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
        case .zoneNotFound:
            try? store?.forgetAllSyncState()
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
            engine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
        case .unknownItem:
            try? store?.forgetSyncState(recordName: recordID.recordName)
            engine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
        case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable, .requestRateLimited, .notAuthenticated:
            break
        default:
            status = .failed(failure.error.localizedDescription)
        }
    }

    private func handleAccountChange(_ change: CKSyncEngine.Event.AccountChange) {
        switch change.changeType {
        case .signIn:
            enqueueUnsyncedRecords()
        case .signOut, .switchAccounts:
            try? store?.forgetAllSyncState()
            deleteSavedState()
            lastSyncedAt = nil
            stop()
            if isEnabled {
                start()
            }
        @unknown default:
            break
        }
    }
}

extension CloudSync: CKSyncEngineDelegate {
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            save(update.stateSerialization)
        case .accountChange(let change):
            handleAccountChange(change)
        case .fetchedDatabaseChanges(let changes):
            if changes.deletions.contains(where: { $0.zoneID == Self.zoneID }) {
                try? store?.forgetAllSyncState()
                deleteSavedState()
                isEnabled = false
            }
        case .fetchedRecordZoneChanges(let changes):
            changes.modifications.forEach { merge($0.record) }
            changes.deletions.forEach { try? store?.deleteRecord(named: $0.recordID.recordName) }
            onRemoteChanges()
        case .sentRecordZoneChanges(let sent):
            for record in sent.savedRecords {
                try? store?.markSynced(recordName: record.recordID.recordName, systemFields: record.encodedSystemFields)
            }
            sent.failedRecordSaves.forEach { handleFailedSave($0, engine: syncEngine) }
            updatePendingChanges()
        case .willFetchChanges, .willSendChanges:
            status = .syncing
        case .didFetchChanges, .didSendChanges:
            lastSyncedAt = .now
            status = .upToDate
            updatePendingChanges()
        default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
            await self.record(for: recordID)
        }
    }
}

private extension CKRecord {
    var encodedSystemFields: Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }
}
