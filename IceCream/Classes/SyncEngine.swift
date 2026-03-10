//
//  SyncEngine.swift
//  IceCream
//
//  Created by 蔡越 on 08/11/2017.
//

import CloudKit
import RealmSwift

/// SyncEngine talks to CloudKit directly.
/// Logically,
/// 1. it takes care of the operations of **CKDatabase**
/// 2. it handles all of the CloudKit config stuffs, such as subscriptions
/// 3. it hands over CKRecordZone stuffs to SyncObject so that it can have an effect on local Realm Database

public final class SyncEngine {
    
    private let databaseManager: DatabaseManager
    
    public convenience init(objects: [Syncable], databaseScope: CKDatabase.Scope = .private, container: CKContainer = .default()) {
        switch databaseScope {
        case .private:
            let privateDatabaseManager = PrivateDatabaseManager(objects: objects, container: container)
            self.init(databaseManager: privateDatabaseManager)
        case .public:
            let publicDatabaseManager = PublicDatabaseManager(objects: objects, container: container)
            self.init(databaseManager: publicDatabaseManager)
        case .shared:
            let sharedDatabaseManager = SharedDatabaseManager(objects: objects, container: container)
            self.init(databaseManager: sharedDatabaseManager)
        @unknown default:
            fatalError("Unknown database scope")
        }
    }
    
    private init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
        setup()
    }
    
    private func setup() {
        databaseManager.prepare()
        databaseManager.container.accountStatus { [weak self] (status, error) in
            guard let self = self else { return }
            switch status {
            case .available:
                self.databaseManager.registerLocalDatabase()
                self.databaseManager.createCustomZonesIfAllowed()
                self.databaseManager.fetchChangesInDatabase(nil)
                self.databaseManager.resumeLongLivedOperationIfPossible()
                self.databaseManager.startObservingRemoteChanges()
                self.databaseManager.startObservingTermination()
                self.databaseManager.createDatabaseSubscriptionIfHaveNot()
            case .noAccount, .restricted:
                guard self.databaseManager is PublicDatabaseManager else { break }
                self.databaseManager.fetchChangesInDatabase(nil)
                self.databaseManager.resumeLongLivedOperationIfPossible()
                self.databaseManager.startObservingRemoteChanges()
                self.databaseManager.startObservingTermination()
                self.databaseManager.createDatabaseSubscriptionIfHaveNot()
            case .couldNotDetermine:
                break
            @unknown default:
                break
            }
        }
    }
    
}

// MARK: Public Method
extension SyncEngine {

    /// Fetch data on the CloudKit and merge with local
    ///
    /// - Parameter completionHandler: Supported in the `privateCloudDatabase` when the fetch data process completes, completionHandler will be called. The error will be returned when anything wrong happens. Otherwise the error will be `nil`.
    public func pull(completionHandler: ((Error?) -> Void)? = nil) {
        databaseManager.fetchChangesInDatabase(completionHandler)
    }

    /// Push all existing local data to CloudKit
    /// You should NOT to call this method too frequently
    public func pushAll() {
        databaseManager.syncObjects.forEach { $0.pushLocalObjectsToCloudKit() }
    }

    // MARK: - Participant: accept a share invitation

    /// Accept a CloudKit share invitation and immediately fetch the shared records into Realm.
    public func acceptShare(metadata: CKShare.Metadata,
                            completionHandler: @escaping (Error?) -> Void) {
        databaseManager.container.accept(metadata) { [weak self] _, error in
            if let error = error { completionHandler(error); return }
            DispatchQueue.global(qos: .utility).async {
                self?.databaseManager.fetchChangesInDatabase { completionHandler($0) }
            }
        }
    }

    // MARK: - Owner: create a zone-level share for a record type (iOS 15+)

    /// Share an entire record zone (all records of the given type) with other iCloud users.
    /// Only the owner calls this; the resulting `CKShare.url` can be sent to participants.
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
    public func createShare<T: Object & CKRecordConvertible>(
        type: T.Type,
        publicPermission: CKShare.Participant.Permission = .readOnly,
        completionHandler: @escaping (CKShare?, URL?, Error?) -> Void
    ) {
        let share = CKShare(recordZoneID: T.zoneID)
        share.publicPermission = publicPermission
        let op = CKModifyRecordsOperation(recordsToSave: [share], recordIDsToDelete: nil)
        op.savePolicy = .ifServerRecordUnchanged
        op.modifyRecordsCompletionBlock = { _, _, error in
            completionHandler(error == nil ? share : nil, share.url, error)
        }
        // Always saves to the owner's private database
        databaseManager.container.privateCloudDatabase.add(op)
    }

}

public enum Notifications: String, NotificationName {
    case cloudKitDataDidChangeRemotely
}

public enum IceCreamKey: String {
    /// Tokens
    case databaseChangesTokenKey
    case zoneChangesTokenKey
    case sharedDatabaseChangesTokenKey

    /// Flags
    case subscriptionIsLocallyCachedKey
    case hasCustomZoneCreatedKey
    case sharedSubscriptionIsLocallyCachedKey

    var value: String {
        return "icecream.keys." + rawValue
    }
}

/// Dangerous part:
/// In most cases, you should not change the string value cause it is related to user settings.
/// e.g.: the cloudKitSubscriptionID, if you don't want to use "private_changes" and use another string. You should remove the old subsription first.
/// Or your user will not save the same subscription again. So you got trouble.
/// The right way is remove old subscription first and then save new subscription.
public enum IceCreamSubscription: String, CaseIterable {
    case cloudKitPrivateDatabaseSubscriptionID = "private_changes"
    case cloudKitPublicDatabaseSubscriptionID = "cloudKitPublicDatabaseSubcriptionID"
    case cloudKitSharedDatabaseSubscriptionID = "shared_changes"

    var id: String {
        return rawValue
    }

    public static var allIDs: [String] {
        return IceCreamSubscription.allCases.map { $0.rawValue }
    }
}
