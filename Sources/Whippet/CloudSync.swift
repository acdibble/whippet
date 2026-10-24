import CloudKit
import CryptoKit
import GRDB

/// Syncs clipboard and calculator history through the user's private CloudKit database with `CKSyncEngine`.
/// Records are named by a keyed hash of their content, so the same text copied on two Macs becomes one record without
/// the name revealing it. Every field is in `encryptedValues`, and images are encrypted before upload, so iCloud holds
/// nothing readable without the key, which is itself end-to-end encrypted in the zone.
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
            if includesImages, !oldValue {
                Task { await fetchSkippedImages() }
            }
        }
    }

    /// Called after changes from another Mac were merged into the local store.
    @ObservationIgnored var onRemoteChanges: () -> Void = {}

    @ObservationIgnored private let store: ClipboardStore?
    @ObservationIgnored private var engine: CKSyncEngine?
    @ObservationIgnored private var keys: SyncKeys?
    /// Checks the account and loads the key before creating the engine. Only the latest start may finish, so toggling
    /// sync quickly can't leave two engines on the same state file.
    @ObservationIgnored private var startTask: Task<Void, Never>?
    @ObservationIgnored private let container = CKContainer(identifier: "iCloud.codes.dibble.whippet")

    private static let zoneID = CKRecordZone.ID(zoneName: "Whippet")
    private static let clipboardType = "Clip"
    private static let calculationType = "Calc"
    private static let keyType = "SyncKey"
    private static let keyRecordID = CKRecord.ID(recordName: "sync-key", zoneID: zoneID)

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

    /// The CloudKit user record ID of the account signed into iCloud on this Mac, which is the record to give a role
    /// to in the CloudKit Console.
    func userRecordName() async -> String? {
        try? await container.userRecordID().recordName
    }

    /// Queues an item changed on this Mac for upload.
    func recordChanged(_ item: SyncItem) {
        enqueue([item])
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
            // Sync may have stopped or restarted with a new engine meanwhile, which owns the status now.
            guard self.engine === engine else { return }
            lastSyncedAt = .now
            status = .upToDate
        } catch {
            guard self.engine === engine else { return }
            status = .failed(error.localizedDescription)
        }
        updatePendingChanges()
    }

    /// Images that arrive while Include Images is off are dropped, and the engine's change token moves past them, so
    /// turning it back on reads the whole zone once more for them. Their kind is encrypted, so CloudKit can't filter
    /// them on the server.
    private func fetchSkippedImages() async {
        guard let engine else { return }
        status = .syncing
        var changeToken: CKServerChangeToken?
        do {
            var moreComing = true
            while moreComing {
                let changes = try await container.privateCloudDatabase.recordZoneChanges(inZoneWith: Self.zoneID, since: changeToken)
                // Sync may have stopped or restarted meanwhile, which owns the status now.
                guard self.engine === engine else { return }
                for case .success(let modification) in changes.modificationResultsByID.values
                where modification.record.encryptedValues["kind"] as? String == ClipboardKind.image.rawValue {
                    merge(modification.record)
                }
                changeToken = changes.changeToken
                moreComing = changes.moreComing
            }
            onRemoteChanges()
            lastSyncedAt = .now
            status = .upToDate
        } catch {
            guard self.engine === engine else { return }
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
        startTask?.cancel()
        startTask = Task {
            let accountStatus = try? await container.accountStatus()
            guard !Task.isCancelled else { return }
            guard accountStatus == .available else {
                status = .unavailable(Self.describe(accountStatus))
                return
            }

            let keys: SyncKeys
            do {
                keys = SyncKeys(secret: try await loadSecret())
            } catch {
                if !Task.isCancelled {
                    status = .failed(error.localizedDescription)
                }
                return
            }
            guard !Task.isCancelled else { return }
            self.keys = keys

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
            enqueueUnsyncedRecords()
            await syncNow()
        }
    }

    private func stop() {
        startTask?.cancel()
        startTask = nil
        engine = nil
        keys = nil
        status = .off
        pendingChanges = 0
    }

    /// Forgets everything about the zone and starts over, for when the zone, and so its key, is gone or belongs to another account.
    private func restart() {
        try? store?.forgetAllSyncState()
        deleteSavedState()
        lastSyncedAt = nil
        stop()
        if isEnabled {
            start()
        }
    }

    /// Queues everything changed or deleted on this Mac that hasn't reached iCloud, including while sync was off.
    private func enqueueUnsyncedRecords() {
        if let items = try? store?.unsyncedItems(includeImages: includesImages) {
            enqueue(items)
        }
        // After the saves, since naming an item that was copied again cancels its deletion.
        guard let engine, let deletions = try? store?.pendingDeletions(), !deletions.isEmpty else { return }
        engine.state.add(pendingRecordZoneChanges: deletions.map { .deleteRecord(Self.recordID($0)) })
        updatePendingChanges()
    }

    /// Names the items with the key and queues them for upload.
    private func enqueue(_ items: [SyncItem]) {
        guard let engine, let keys, let store, !items.isEmpty else { return }
        let names = Dictionary(items.map { ($0, keys.recordName(for: $0)) }, uniquingKeysWith: { first, _ in first })
        guard (try? store.assignRecordNames(names)) != nil else { return }
        engine.state.add(pendingRecordZoneChanges: names.values.map { .saveRecord(Self.recordID($0)) })
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

    // MARK: - Key

    /// The secret that names records and encrypts images. The first Mac to sync creates it in the zone, where it is
    /// end-to-end encrypted, and every Mac caches it beside the history it protects.
    private func loadSecret() async throws -> Data {
        if let secret = try? Data(contentsOf: keyURL), secret.count == SyncKeys.secretSize {
            return secret
        }
        let database = container.privateCloudDatabase
        let (zoneResults, _) = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: Self.zoneID)], deleting: [])
        _ = try zoneResults[Self.zoneID]?.get()

        let secret: Data
        do {
            secret = try Self.secret(in: try await database.record(for: Self.keyRecordID))
        } catch let error as CKError where error.code == .unknownItem {
            secret = try await createSecret(in: database)
        }
        try secret.write(to: keyURL, options: .atomic)
        return secret
    }

    private func createSecret(in database: CKDatabase) async throws -> Data {
        let secret = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        let record = CKRecord(recordType: Self.keyType, recordID: Self.keyRecordID)
        record.encryptedValues["secret"] = secret
        let (saveResults, _) = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged)
        do {
            _ = try saveResults[Self.keyRecordID]?.get()
            return secret
        } catch let error as CKError where error.code == .serverRecordChanged {
            // Another Mac created the key first.
            guard let serverRecord = error.serverRecord else { throw error }
            return try Self.secret(in: serverRecord)
        }
    }

    private static func secret(in record: CKRecord) throws -> Data {
        guard let secret = record.encryptedValues["secret"] as? Data, secret.count == SyncKeys.secretSize else {
            throw MissingKeyError()
        }
        return secret
    }

    private var keyURL: URL {
        ClipboardStore.defaultDirectory.appending(path: "cloud-sync-key-\(container.containerIdentifier ?? "default")")
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

    /// Forgets the engine state and the cached key, which both belong to one account's zone.
    private func deleteSavedState() {
        try? FileManager.default.removeItem(at: stateURL)
        try? FileManager.default.removeItem(at: keyURL)
    }

    // MARK: - Records

    private static func recordID(_ recordName: String) -> CKRecord.ID {
        CKRecord.ID(recordName: recordName, zoneID: zoneID)
    }

    /// Builds the record to upload, reusing the server's system fields so CloudKit sees an update rather than a conflict.
    private func record(for recordID: CKRecord.ID) -> CKRecord? {
        guard let store, let keys, let row = try? store.syncRow(recordName: recordID.recordName) else { return nil }
        if recordID.recordName.hasPrefix(SyncItem.clipboardPrefix) {
            return clipboardRecord(from: row, id: recordID, keys: keys, store: store)
        }
        let record = Self.makeRecord(type: Self.calculationType, id: recordID, systemFields: row["cloudSystemFields"])
        record.encryptedValues["expression"] = row["expression"] as String
        record.encryptedValues["answer"] = row["answer"] as String
        record.encryptedValues["mode"] = row["mode"] as String
        record.encryptedValues["calculatedAt"] = row["calculatedAt"] as Date
        record.encryptedValues["updatedAt"] = row["updatedAt"] as Date?
        return record
    }

    private func clipboardRecord(from row: Row, id: CKRecord.ID, keys: SyncKeys, store: ClipboardStore) -> CKRecord? {
        let kind: String = row["kind"]
        if kind == ClipboardKind.image.rawValue, !includesImages { return nil }

        let record = Self.makeRecord(type: Self.clipboardType, id: id, systemFields: row["cloudSystemFields"])
        record.encryptedValues["contentHash"] = row["contentHash"] as String
        record.encryptedValues["kind"] = kind
        record.encryptedValues["copiedAt"] = row["copiedAt"] as Date
        record.encryptedValues["updatedAt"] = row["updatedAt"] as Date
        record.encryptedValues["timesCopied"] = row["timesCopied"] as Int
        record.encryptedValues["pinnedAt"] = row["pinnedAt"] as Date?
        record.encryptedValues["sourceBundleID"] = row["sourceBundleID"] as String?
        record.encryptedValues["imageWidth"] = row["imageWidth"] as Int?
        record.encryptedValues["imageHeight"] = row["imageHeight"] as Int?
        record.encryptedValues["imageBytes"] = row["imageBytes"] as Int?
        record.encryptedValues["text"] = row["text"] as String?
        record.encryptedValues["ocrText"] = row["ocrText"] as String?
        if let imageFile = row["imageFile"] as String? {
            let source = store.imagesDirectory.appending(path: imageFile)
            guard let upload = encryptImage(at: source, recordName: id.recordName, key: keys.images) else { return nil }
            record["image"] = CKAsset(fileURL: upload)
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
        guard let store, let keys else { return }
        let name = record.recordID.recordName
        let systemFields = record.encodedSystemFields
        let values = record.encryptedValues
        let item: SyncItem
        let isLocalAhead: Bool?

        switch record.recordType {
        case Self.clipboardType:
            // The hash names the image file, so anything else is rejected.
            guard let hash = values["contentHash"] as? String, hash.count == 64, hash.allSatisfy(\.isHexDigit) else { return }
            let kind = (values["kind"] as? String).flatMap(ClipboardKind.init(rawValue:)) ?? .text
            if kind == .image, !includesImages { return }
            let imageFile = kind == .image ? saveImage(record["image"] as? CKAsset, hash: hash, key: keys.images, store: store) : nil
            // An image whose file couldn't be saved can't be stored, so it waits until the record changes again.
            if kind == .image, imageFile == nil { return }
            item = .clipboard(contentHash: hash)
            isLocalAhead = try? store.mergeRemote(
                RemoteClipboardItem(
                    hash: hash,
                    kind: kind,
                    text: values["text"] as? String,
                    ocrText: values["ocrText"] as? String,
                    imageFile: imageFile,
                    imageWidth: values["imageWidth"] as? Int,
                    imageHeight: values["imageHeight"] as? Int,
                    imageBytes: values["imageBytes"] as? Int,
                    copiedAt: values["copiedAt"] as? Date ?? .now,
                    sourceBundleID: values["sourceBundleID"] as? String,
                    timesCopied: values["timesCopied"] as? Int ?? 1,
                    pinnedAt: values["pinnedAt"] as? Date,
                    updatedAt: values["updatedAt"] as? Date ?? .distantPast,
                    recordName: name,
                    systemFields: systemFields
                )
            )
        case Self.calculationType:
            guard
                let expression = values["expression"] as? String,
                let answer = values["answer"] as? String
            else { return }
            let mode = values["mode"] as? String ?? "standard"
            let key = ClipboardStore.calculationKey(expression: expression, mode: mode)
            item = .calculation(key: key)
            isLocalAhead = try? store.mergeRemote(
                RemoteCalculation(
                    key: key,
                    expression: expression,
                    answer: answer,
                    mode: mode,
                    calculatedAt: values["calculatedAt"] as? Date ?? .now,
                    updatedAt: values["updatedAt"] as? Date ?? .distantPast,
                    recordName: name,
                    systemFields: systemFields
                )
            )
        default:
            return
        }

        if isLocalAhead == true {
            recordChanged(item)
        }
    }

    // MARK: - Images

    /// Images go up as assets, which `encryptedValues` can't hold, so they are encrypted into a temporary file first.
    private func encryptImage(at source: URL, recordName: String, key: SymmetricKey) -> URL? {
        guard
            let png = try? Data(contentsOf: source),
            let sealed = try? AES.GCM.seal(png, using: key).combined,
            (try? FileManager.default.createDirectory(at: Self.uploadsDirectory, withIntermediateDirectories: true)) != nil
        else { return nil }
        let upload = Self.uploadsDirectory.appending(path: recordName)
        guard (try? sealed.write(to: upload, options: .atomic)) != nil else { return nil }
        return upload
    }

    private static func removeUpload(for recordID: CKRecord.ID) {
        try? FileManager.default.removeItem(at: uploadsDirectory.appending(path: recordID.recordName))
    }

    private static let uploadsDirectory = FileManager.default.temporaryDirectory.appending(path: "Whippet Uploads")

    /// Decrypts a downloaded image into the images folder under its content hash and returns the file name.
    private func saveImage(_ asset: CKAsset?, hash: String, key: SymmetricKey, store: ClipboardStore) -> String? {
        let fileName = "\(hash).png"
        let destination = store.imagesDirectory.appending(path: fileName)
        if FileManager.default.fileExists(atPath: destination.path) {
            return fileName
        }
        guard
            let source = asset?.fileURL,
            let sealed = try? Data(contentsOf: source),
            let box = try? AES.GCM.SealedBox(combined: sealed),
            let png = try? AES.GCM.open(box, using: key),
            (try? png.write(to: destination, options: .atomic)) != nil
        else { return nil }
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
            // The zone was removed, for example by resetting the development environment, and its key with it, so sync
            // starts over with a new key. Only the first failure restarts; the rest belong to the stopped engine.
            guard self.engine === engine else { return }
            restart()
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
            restart()
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
                Self.removeUpload(for: record.recordID)
            }
            sent.failedRecordSaves.forEach { Self.removeUpload(for: $0.record.recordID) }
            sent.failedRecordSaves.forEach { handleFailedSave($0, engine: syncEngine) }
            // A record that's already gone counts as deleted.
            let alreadyGone = sent.failedRecordDeletes.filter { $0.value.code == .unknownItem }.keys
            try? store?.forgetDeletions((sent.deletedRecordIDs + alreadyGone).map(\.recordName))
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

/// Keys derived from the secret in the zone, one for naming records and one for encrypting images, so neither key does
/// both jobs.
private struct SyncKeys {
    static let secretSize = 32

    let images: SymmetricKey
    private let names: SymmetricKey

    init(secret: Data) {
        let secret = SymmetricKey(data: secret)
        names = HKDF<SHA256>.deriveKey(inputKeyMaterial: secret, info: Data("record names".utf8), outputByteCount: 32)
        images = HKDF<SHA256>.deriveKey(inputKeyMaterial: secret, info: Data("images".utf8), outputByteCount: 32)
    }

    func recordName(for item: SyncItem) -> String {
        switch item {
        case .clipboard(let contentHash): SyncItem.clipboardPrefix + code(for: contentHash)
        case .calculation(let key): SyncItem.calculationPrefix + code(for: key)
        }
    }

    private func code(for value: String) -> String {
        HMAC<SHA256>.authenticationCode(for: Data(value.utf8), using: names).map { String(format: "%02x", $0) }.joined()
    }
}

private struct MissingKeyError: LocalizedError {
    var errorDescription: String? {
        String(localized: "The key for iCloud sync is missing or damaged.")
    }
}
