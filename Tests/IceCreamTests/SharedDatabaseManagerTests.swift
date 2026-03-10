//
//  SharedDatabaseManagerTests.swift
//  IceCreamTests
//
//  Pure unit tests for SharedDatabaseManager – no network calls or CKContainer needed.
//  All tests call static helper methods that contain the pure logic so that no
//  CloudKit container initialization occurs during testing.
//
//  Test coverage:
//    1. Zone name matching  – syncObject(in:for:) matches by zoneName, not ownerName
//    2. Unknown zone → nil  – unregistered zoneName returns nil
//    3. Token key isolation – different ownerNames for same zoneName use separate keys
//    4. Zone ID remapping   – remapRecords(_:using:) rewrites placeholder → real zone ID,
//                             preserving all fields
//    5. Write skipped       – remapRecords returns [] when discoveredZoneIDs is empty
//    6. createCustomZonesIfAllowed is a no-op (documented via empty function body)
//    7. IceCreamKey new constant values are pinned
//    8. IceCreamSubscription new constant is pinned
//

import XCTest
import CloudKit
@testable import IceCream

// MARK: - Helpers

/// Minimal Syncable implementation used as test data. No CKContainer involved.
private final class MockSyncable: Syncable {
    var recordType: String
    var zoneID: CKRecordZone.ID
    var zoneChangesToken: CKServerChangeToken?
    var isCustomZoneCreated: Bool = false
    var pipeToEngine: ((_ recordsToStore: [CKRecord], _ recordIDsToDelete: [CKRecord.ID]) -> ())?

    init(recordType: String, zoneName: String) {
        self.recordType = recordType
        self.zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    }

    func registerLocalDatabase() {}
    func cleanUp() {}
    func add(record: CKRecord) {}
    func delete(recordID: CKRecord.ID) {}
    func resolvePendingRelationships() {}
    func pushLocalObjectsToCloudKit() {}
}

// MARK: - Tests

final class SharedDatabaseManagerTests: XCTestCase {

    // MARK: - 1. Zone name matching

    func testSyncObjectMatchesByZoneName() {
        let mock = MockSyncable(recordType: "Dog", zoneName: "DogsZone")
        // Zone ID with DIFFERENT ownerName than the syncObject's own placeholder
        let queryZoneID = CKRecordZone.ID(zoneName: "DogsZone", ownerName: "_someOtherOwner123")
        let found = SharedDatabaseManager.syncObject(in: [mock], for: queryZoneID)
        XCTAssertNotNil(found, "syncObject(in:for:) should match by zoneName regardless of ownerName")
    }

    func testSyncObjectReturnsCorrectObjectAmongMultiple() {
        let dogs = MockSyncable(recordType: "Dog", zoneName: "DogsZone")
        let cats = MockSyncable(recordType: "Cat", zoneName: "CatsZone")
        let queryZoneID = CKRecordZone.ID(zoneName: "CatsZone", ownerName: "_ownerABC")
        let found = SharedDatabaseManager.syncObject(in: [dogs, cats], for: queryZoneID)
        XCTAssertTrue(found === cats, "Should return the Cats sync object, not Dogs")
    }

    // MARK: - 2. Unknown zone returns nil

    func testSyncObjectReturnsNilForUnknownZoneName() {
        let mock = MockSyncable(recordType: "Dog", zoneName: "DogsZone")
        let unknownZoneID = CKRecordZone.ID(zoneName: "CatsZone", ownerName: CKCurrentUserDefaultName)
        let found = SharedDatabaseManager.syncObject(in: [mock], for: unknownZoneID)
        XCTAssertNil(found, "Unregistered zone name should return nil")
    }

    // MARK: - 3. Token key isolation

    func testDifferentOwnerNamesProduceDifferentTokenKeys() {
        let zoneID1 = CKRecordZone.ID(zoneName: "DogsZone", ownerName: "_owner1")
        let zoneID2 = CKRecordZone.ID(zoneName: "DogsZone", ownerName: "_owner2")
        let key1 = SharedDatabaseManager.zoneChangesTokenKey(for: zoneID1)
        let key2 = SharedDatabaseManager.zoneChangesTokenKey(for: zoneID2)
        XCTAssertNotEqual(key1, key2, "Different ownerNames must produce different UserDefaults keys")
    }

    func testSameZoneAndOwnerProduceSameKey() {
        let zoneID = CKRecordZone.ID(zoneName: "DogsZone", ownerName: "_owner1")
        let key1 = SharedDatabaseManager.zoneChangesTokenKey(for: zoneID)
        let key2 = SharedDatabaseManager.zoneChangesTokenKey(for: zoneID)
        XCTAssertEqual(key1, key2, "Same zone/owner must produce an identical key on every call")
    }

    func testTokenKeyContainsZoneNameAndOwnerName() {
        let zoneID = CKRecordZone.ID(zoneName: "DogsZone", ownerName: "_cfd1234")
        let key = SharedDatabaseManager.zoneChangesTokenKey(for: zoneID)
        XCTAssertTrue(key.contains("DogsZone"), "Key must include zone name")
        XCTAssertTrue(key.contains("_cfd1234"), "Key must include owner name")
    }

    // MARK: - 4. Zone ID remapping

    func testRemapRecordsRewritesZoneIDToRealOwner() {
        let realOwnerName = "_cfd69bc7realOwner"
        let realZoneID = CKRecordZone.ID(zoneName: "DogsZone", ownerName: realOwnerName)
        let discoveredZoneIDs: [String: CKRecordZone.ID] = ["DogsZone": realZoneID]

        let placeholderZoneID = CKRecordZone.ID(zoneName: "DogsZone",
                                                ownerName: CKCurrentUserDefaultName)
        let originalRecordID = CKRecord.ID(recordName: "dog-1", zoneID: placeholderZoneID)
        let original = CKRecord(recordType: "Dog", recordID: originalRecordID)
        original["name"] = "Buddy" as CKRecordValue
        original["age"]  = 3 as CKRecordValue

        let remapped = SharedDatabaseManager.remapRecords([original], using: discoveredZoneIDs)

        XCTAssertEqual(remapped.count, 1, "Should produce exactly one remapped record")
        let result = remapped[0]
        XCTAssertEqual(result.recordID.zoneID.ownerName, realOwnerName,
                       "ownerName should be rewritten to the real owner")
        XCTAssertEqual(result.recordID.zoneID.zoneName, "DogsZone")
        XCTAssertEqual(result.recordID.recordName, "dog-1")
        XCTAssertEqual(result["name"] as? String, "Buddy", "String field should be preserved")
        XCTAssertEqual(result["age"] as? Int, 3, "Int field should be preserved")
    }

    func testRemapRecordsPreservesMultipleFields() {
        let realZoneID = CKRecordZone.ID(zoneName: "DogsZone", ownerName: "_owner")
        let discoveredZoneIDs: [String: CKRecordZone.ID] = ["DogsZone": realZoneID]

        let placeholderZoneID = CKRecordZone.ID(zoneName: "DogsZone",
                                                ownerName: CKCurrentUserDefaultName)
        let original = CKRecord(recordType: "Dog",
                                recordID: CKRecord.ID(recordName: "d1", zoneID: placeholderZoneID))
        original["score"]   = 9.5 as CKRecordValue
        original["isGood"]  = true as CKRecordValue
        let payload = "woof".data(using: .utf8)!
        original["payload"] = payload as CKRecordValue

        let result = SharedDatabaseManager.remapRecords([original], using: discoveredZoneIDs)[0]
        XCTAssertNotNil(result["score"] as? Double)
        XCTAssertEqual(result["score"] as! Double, 9.5, accuracy: 0.001)
        XCTAssertEqual(result["isGood"] as? Bool, true)
        XCTAssertEqual(result["payload"] as? Data, payload)
    }

    // MARK: - 5. Write skipped when no zone discovered

    func testRemapRecordsReturnsEmptyWhenNoZoneDiscovered() {
        let placeholderZoneID = CKRecordZone.ID(zoneName: "DogsZone",
                                                ownerName: CKCurrentUserDefaultName)
        let record = CKRecord(recordType: "Dog",
                              recordID: CKRecord.ID(recordName: "dog-1", zoneID: placeholderZoneID))
        let remapped = SharedDatabaseManager.remapRecords([record], using: [:])
        XCTAssertTrue(remapped.isEmpty,
                      "remapRecords should drop records when zone has not yet been discovered")
    }

    func testRemapRecordIDsReturnsEmptyWhenNoZoneDiscovered() {
        let placeholderZoneID = CKRecordZone.ID(zoneName: "DogsZone",
                                                ownerName: CKCurrentUserDefaultName)
        let recordID = CKRecord.ID(recordName: "dog-1", zoneID: placeholderZoneID)
        let remapped = SharedDatabaseManager.remapRecordIDs([recordID], using: [:])
        XCTAssertTrue(remapped.isEmpty,
                      "remapRecordIDs should drop IDs when zone has not yet been discovered")
    }

    // MARK: - 6. createCustomZonesIfAllowed is a no-op
    // The function body is intentionally empty (participants cannot create zones in
    // sharedCloudDatabase). The static method tests above fully exercise the pure logic.
    // A runtime invocation test would require a CKContainer, which is not available
    // in the Swift Package test environment – the empty body is verified by code review.

    // MARK: - 7. IceCreamKey new constant values

    func testSharedDatabaseChangesTokenKeyValue() {
        XCTAssertEqual(IceCreamKey.sharedDatabaseChangesTokenKey.value,
                       "icecream.keys.sharedDatabaseChangesTokenKey")
    }

    func testSharedSubscriptionIsLocallyCachedKeyValue() {
        XCTAssertEqual(IceCreamKey.sharedSubscriptionIsLocallyCachedKey.value,
                       "icecream.keys.sharedSubscriptionIsLocallyCachedKey")
    }

    // MARK: - 8. IceCreamSubscription new constant

    func testCloudKitSharedDatabaseSubscriptionID() {
        XCTAssertEqual(IceCreamSubscription.cloudKitSharedDatabaseSubscriptionID.id,
                       "shared_changes")
    }
}
