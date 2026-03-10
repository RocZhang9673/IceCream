//
//  SharedDatabaseManager.swift
//  IceCream
//

#if os(macOS)
import Cocoa
#else
import UIKit
#endif

import CloudKit

final class SharedDatabaseManager: DatabaseManager {

    let container: CKContainer
    let syncObjects: [Syncable]

    /// Accessed lazily so that unit tests that never enqueue CKOperations do not
    /// trigger CloudKit's container-identifier validation at init time.
    lazy var database: CKDatabase = container.sharedCloudDatabase

    /// Maps zoneName (e.g. "DogsZone") → the real CKRecordZone.ID that includes the owner's recordName.
    /// Access is serialised through `zoneIDsQueue`.
    let zoneIDsQueue = DispatchQueue(label: "com.icecream.shared.zoneIDsQueue")
    var _discoveredZoneIDs: [String: CKRecordZone.ID] = [:]

    init(objects: [Syncable], container: CKContainer) {
        self.syncObjects = objects
        self.container = container
    }

    // MARK: - DatabaseManager

    /// Override the default prepare() so that zone IDs on outgoing records are rewritten
    /// to the real owner-scoped zone ID before being submitted to CloudKit.
    func prepare() {
        syncObjects.forEach { syncObject in
            syncObject.pipeToEngine = { [weak self] recordsToStore, recordIDsToDelete in
                guard let self = self else { return }
                let remapped = self.remapRecords(recordsToStore)
                let remappedDeletes = self.remapRecordIDs(recordIDsToDelete)
                guard !remapped.isEmpty || !remappedDeletes.isEmpty else { return }
                self.syncRecordsToCloudKit(recordsToStore: remapped, recordIDsToDelete: remappedDeletes)
            }
        }
    }

    /// Rewrites CKRecord zone IDs from the placeholder (CKCurrentUserDefaultName) to the real
    /// owner-scoped zone IDs discovered from sharedCloudDatabase. Records whose zone has not yet
    /// been discovered are silently dropped.
    func remapRecords(_ records: [CKRecord]) -> [CKRecord] {
        let snapshot = zoneIDsQueue.sync { _discoveredZoneIDs }
        return SharedDatabaseManager.remapRecords(records, using: snapshot)
    }

    /// Rewrites CKRecord.ID zone IDs from placeholder to the real owner-scoped zone IDs.
    func remapRecordIDs(_ recordIDs: [CKRecord.ID]) -> [CKRecord.ID] {
        let snapshot = zoneIDsQueue.sync { _discoveredZoneIDs }
        return SharedDatabaseManager.remapRecordIDs(recordIDs, using: snapshot)
    }

    // MARK: - Testable static helpers (no CKContainer required)

    /// Pure remapping logic – extracted so it can be unit-tested without a CloudKit container.
    static func remapRecords(_ records: [CKRecord],
                             using discoveredZoneIDs: [String: CKRecordZone.ID]) -> [CKRecord] {
        return records.compactMap { original in
            let zoneName = original.recordID.zoneID.zoneName
            guard let realZoneID = discoveredZoneIDs[zoneName] else { return nil }
            let newRecordID = CKRecord.ID(recordName: original.recordID.recordName,
                                         zoneID: realZoneID)
            let newRecord = CKRecord(recordType: original.recordType, recordID: newRecordID)
            original.allKeys().forEach { newRecord[$0] = original[$0] }
            newRecord.parent = original.parent
            return newRecord
        }
    }

    /// Pure remapping logic – extracted so it can be unit-tested without a CloudKit container.
    static func remapRecordIDs(_ recordIDs: [CKRecord.ID],
                               using discoveredZoneIDs: [String: CKRecordZone.ID]) -> [CKRecord.ID] {
        return recordIDs.compactMap { recordID in
            guard let realZoneID = discoveredZoneIDs[recordID.zoneID.zoneName] else { return nil }
            return CKRecord.ID(recordName: recordID.recordName, zoneID: realZoneID)
        }
    }

    /// Match a sync object by zone name only – extracted so it can be unit-tested without a container.
    static func syncObject(in syncObjects: [Syncable], for zoneID: CKRecordZone.ID) -> Syncable? {
        return syncObjects.first { $0.zoneID.zoneName == zoneID.zoneName }
    }

    /// Returns the UserDefaults key used for a given zone's change token.
    /// Exposed as static so tests can verify key isolation without a CloudKit container.
    static func zoneChangesTokenKey(for zoneID: CKRecordZone.ID) -> String {
        return "icecream.keys.shared.\(zoneID.zoneName).\(zoneID.ownerName).zoneChangesToken"
    }

    func fetchChangesInDatabase(_ callback: ((Error?) -> Void)?) {
        let changesOperation = CKFetchDatabaseChangesOperation(previousServerChangeToken: databaseChangeToken)

        changesOperation.changeTokenUpdatedBlock = { [weak self] newToken in
            self?.databaseChangeToken = newToken
        }

        var changedZoneIDs: [CKRecordZone.ID] = []

        changesOperation.recordZoneWithIDChangedBlock = { [weak self] zoneID in
            guard let self = self else { return }
            changedZoneIDs.append(zoneID)
            self.zoneIDsQueue.async {
                self._discoveredZoneIDs[zoneID.zoneName] = zoneID
            }
        }

        changesOperation.recordZoneWithIDWasDeletedBlock = { [weak self] zoneID in
            self?.handleDeletedZone(zoneID)
        }

        changesOperation.fetchDatabaseChangesCompletionBlock = { [weak self] newToken, _, error in
            guard let self = self else { return }
            switch ErrorHandler.shared.resultType(with: error) {
            case .success:
                self.databaseChangeToken = newToken
                if changedZoneIDs.isEmpty {
                    callback?(nil)
                } else {
                    self.fetchChangesInZones(changedZoneIDs, callback: callback)
                }
            case .retry(let timeToWait, _):
                ErrorHandler.shared.retryOperationIfPossible(retryAfter: timeToWait) {
                    self.fetchChangesInDatabase(callback)
                }
            case .recoverableError(let reason, _):
                switch reason {
                case .changeTokenExpired:
                    self.databaseChangeToken = nil
                    self.fetchChangesInDatabase(callback)
                default:
                    return
                }
            default:
                return
            }
        }

        database.add(changesOperation)
    }

    /// Participants cannot create zones in sharedCloudDatabase; zones are owned by the sharer.
    func createCustomZonesIfAllowed() {
        // No-op: zones in the shared database are created by the owner, not the participant.
    }

    func createDatabaseSubscriptionIfHaveNot() {
        #if os(iOS) || os(tvOS) || os(macOS)
        guard !sharedSubscriptionIsLocallyCached else { return }
        let subscription = CKDatabaseSubscription(subscriptionID: IceCreamSubscription.cloudKitSharedDatabaseSubscriptionID.id)

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true // Silent Push

        subscription.notificationInfo = notificationInfo

        let createOp = CKModifySubscriptionsOperation(subscriptionsToSave: [subscription], subscriptionIDsToDelete: [])
        createOp.modifySubscriptionsCompletionBlock = { [weak self] _, _, error in
            guard error == nil else { return }
            self?.sharedSubscriptionIsLocallyCached = true
        }
        createOp.qualityOfService = .utility
        database.add(createOp)
        #endif
    }

    func startObservingTermination() {
        #if os(iOS) || os(tvOS)
        NotificationCenter.default.addObserver(self, selector: #selector(cleanUp),
                                               name: UIApplication.willTerminateNotification, object: nil)
        #elseif os(macOS)
        NotificationCenter.default.addObserver(self, selector: #selector(cleanUp),
                                               name: NSApplication.willTerminateNotification, object: nil)
        #endif
    }

    func registerLocalDatabase() {
        syncObjects.forEach { object in
            DispatchQueue.main.async {
                object.registerLocalDatabase()
            }
        }
    }

    // MARK: - Private

    private func fetchChangesInZones(_ zoneIDs: [CKRecordZone.ID], callback: ((Error?) -> Void)?) {
        var optionsByZoneID: [CKRecordZone.ID: CKFetchRecordZoneChangesOperation.ZoneOptions] = [:]
        for zoneID in zoneIDs {
            let options = CKFetchRecordZoneChangesOperation.ZoneOptions()
            options.previousServerChangeToken = zoneChangesToken(for: zoneID)
            optionsByZoneID[zoneID] = options
        }

        let changesOp = CKFetchRecordZoneChangesOperation(recordZoneIDs: zoneIDs,
                                                          optionsByRecordZoneID: optionsByZoneID)
        changesOp.fetchAllChanges = true

        changesOp.recordZoneChangeTokensUpdatedBlock = { [weak self] zoneID, token, _ in
            self?.setZoneChangesToken(token, for: zoneID)
        }

        changesOp.recordChangedBlock = { [weak self] record in
            guard let self = self else { return }
            guard let syncObject = self.syncObject(for: record.recordID.zoneID) else { return }
            syncObject.add(record: record)
        }

        changesOp.recordWithIDWasDeletedBlock = { [weak self] recordID, _ in
            guard let self = self else { return }
            guard let syncObject = self.syncObject(for: recordID.zoneID) else { return }
            syncObject.delete(recordID: recordID)
        }

        changesOp.recordZoneFetchCompletionBlock = { [weak self] zoneID, token, _, _, error in
            guard let self = self else { return }
            switch ErrorHandler.shared.resultType(with: error) {
            case .success:
                self.setZoneChangesToken(token, for: zoneID)
            case .retry(let timeToWait, _):
                ErrorHandler.shared.retryOperationIfPossible(retryAfter: timeToWait) {
                    self.fetchChangesInZones(zoneIDs, callback: callback)
                }
            case .recoverableError(let reason, _):
                switch reason {
                case .changeTokenExpired:
                    self.setZoneChangesToken(nil, for: zoneID)
                    self.fetchChangesInZones(zoneIDs, callback: callback)
                default:
                    return
                }
            default:
                return
            }
        }

        changesOp.fetchRecordZoneChangesCompletionBlock = { [weak self] error in
            guard let self = self else { return }
            self.syncObjects.forEach { $0.resolvePendingRelationships() }
            callback?(error)
        }

        database.add(changesOp)
    }

    /// Called when the owner revokes sharing for a zone.
    private func handleDeletedZone(_ zoneID: CKRecordZone.ID) {
        zoneIDsQueue.async {
            self._discoveredZoneIDs.removeValue(forKey: zoneID.zoneName)
        }
        setZoneChangesToken(nil, for: zoneID)
    }

    /// Match a sync object by zone name only, ignoring ownerName.
    /// The naming convention "<RecordType>sZone" is stable across devices and users.
    func syncObject(for zoneID: CKRecordZone.ID) -> Syncable? {
        return SharedDatabaseManager.syncObject(in: syncObjects, for: zoneID)
    }

    @objc func cleanUp() {
        for syncObject in syncObjects {
            syncObject.cleanUp()
        }
    }
}

// MARK: - Token & Flag Storage

extension SharedDatabaseManager {

    var databaseChangeToken: CKServerChangeToken? {
        get {
            guard let data = UserDefaults.standard.object(forKey: IceCreamKey.sharedDatabaseChangesTokenKey.value) as? Data else { return nil }
            return NSKeyedUnarchiver.unarchiveObject(with: data) as? CKServerChangeToken
        }
        set {
            guard let token = newValue else {
                UserDefaults.standard.removeObject(forKey: IceCreamKey.sharedDatabaseChangesTokenKey.value)
                return
            }
            let data = NSKeyedArchiver.archivedData(withRootObject: token)
            UserDefaults.standard.set(data, forKey: IceCreamKey.sharedDatabaseChangesTokenKey.value)
        }
    }

    var sharedSubscriptionIsLocallyCached: Bool {
        get {
            return UserDefaults.standard.object(forKey: IceCreamKey.sharedSubscriptionIsLocallyCachedKey.value) as? Bool ?? false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: IceCreamKey.sharedSubscriptionIsLocallyCachedKey.value)
        }
    }

    func zoneChangesToken(for zoneID: CKRecordZone.ID) -> CKServerChangeToken? {
        let key = SharedDatabaseManager.zoneChangesTokenKey(for: zoneID)
        guard let data = UserDefaults.standard.object(forKey: key) as? Data else { return nil }
        return NSKeyedUnarchiver.unarchiveObject(with: data) as? CKServerChangeToken
    }

    func setZoneChangesToken(_ token: CKServerChangeToken?, for zoneID: CKRecordZone.ID) {
        let key = SharedDatabaseManager.zoneChangesTokenKey(for: zoneID)
        guard let token = token else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        let data = NSKeyedArchiver.archivedData(withRootObject: token)
        UserDefaults.standard.set(data, forKey: key)
    }
}
