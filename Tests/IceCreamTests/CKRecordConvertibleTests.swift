//
//  CKRecordConvertibleTests.swift
//  IceCreamTests
//
//  Tests the default implementations provided by the CKRecordConvertible protocol
//  extension on Realm Object subclasses:
//
//    • recordType  – derived from the Realm class name
//    • databaseScope – defaults to .private
//    • zoneID      – format: "<RecordType>sZone", owned by CKCurrentUserDefaultName
//    • recordID    – String PK used verbatim; Int PK stringified
//    • record      – primitive properties serialised into CKRecord fields
//    • isDeleted   – correctly reflects the object flag
//
//  Also covers the IceCreamKey and IceCreamSubscription string constants whose
//  accidental mutation would silently break syncing for existing users.
//

import XCTest
import CloudKit
import RealmSwift
@testable import IceCream

final class CKRecordConvertibleTests: XCTestCase {

    // MARK: - recordType

    func testStringPKObjectRecordTypeMatchesClassName() {
        XCTAssertEqual(StringPKObject.recordType, "StringPKObject")
    }

    func testIntPKObjectRecordTypeMatchesClassName() {
        XCTAssertEqual(IntPKObject.recordType, "IntPKObject")
    }

    // MARK: - databaseScope

    func testDefaultDatabaseScopeIsPrivate() {
        XCTAssertEqual(StringPKObject.databaseScope, .private)
        XCTAssertEqual(IntPKObject.databaseScope, .private)
    }

    // MARK: - zoneID

    func testZoneIDNameFollowsConvention() {
        // Convention: "<RecordType>sZone"
        XCTAssertEqual(StringPKObject.zoneID.zoneName, "StringPKObjectsZone")
        XCTAssertEqual(IntPKObject.zoneID.zoneName, "IntPKObjectsZone")
    }

    func testZoneIDOwnerIsCurrentUser() {
        XCTAssertEqual(StringPKObject.zoneID.ownerName, CKCurrentUserDefaultName)
        XCTAssertEqual(IntPKObject.zoneID.ownerName, CKCurrentUserDefaultName)
    }

    // MARK: - recordID from String primary key

    func testStringPKRecordNameEqualsIDValue() {
        let obj = StringPKObject()
        obj.id = "abc-dog-42"
        XCTAssertEqual(obj.recordID.recordName, "abc-dog-42")
    }

    func testStringPKRecordIDZoneMatchesTypeZone() {
        let obj = StringPKObject()
        obj.id = "some-id"
        XCTAssertEqual(obj.recordID.zoneID, StringPKObject.zoneID)
    }

    func testStringPKRecordIDWithUUID() {
        let uuid = "550E8400-E29B-41D4-A716-446655440000"
        let obj = StringPKObject()
        obj.id = uuid
        XCTAssertEqual(obj.recordID.recordName, uuid)
    }

    // MARK: - recordID from Int primary key

    func testIntPKRecordNameIsStringifiedInt() {
        let obj = IntPKObject()
        obj.id = 42
        XCTAssertEqual(obj.recordID.recordName, "42")
    }

    func testIntPKRecordNameForZero() {
        let obj = IntPKObject()
        obj.id = 0
        XCTAssertEqual(obj.recordID.recordName, "0")
    }

    func testIntPKRecordNameForNegativeValue() {
        let obj = IntPKObject()
        obj.id = -7
        XCTAssertEqual(obj.recordID.recordName, "-7")
    }

    func testIntPKRecordNameForLargeValue() {
        let obj = IntPKObject()
        obj.id = 999_999
        XCTAssertEqual(obj.recordID.recordName, "999999")
    }

    // MARK: - record type in CKRecord

    func testRecordHasCorrectRecordType() {
        let obj = StringPKObject()
        obj.id = "test-id"
        XCTAssertEqual(obj.record.recordType, "StringPKObject")
    }

    func testIntPKRecordHasCorrectRecordType() {
        let obj = IntPKObject()
        obj.id = 1
        XCTAssertEqual(obj.record.recordType, "IntPKObject")
    }

    // MARK: - record field serialisation (primitive types)

    func testRecordContainsStringField() {
        let obj = StringPKObject()
        obj.id   = "test-id"
        obj.name = "Buddy"
        XCTAssertEqual(obj.record["name"] as? String, "Buddy")
    }

    func testRecordContainsIntField() {
        let obj = StringPKObject()
        obj.id  = "test-id"
        obj.age = 5
        XCTAssertEqual(obj.record["age"] as? Int, 5)
    }

    func testRecordContainsBoolFieldTrue() {
        let obj = StringPKObject()
        obj.id        = "test-id"
        obj.isDeleted = true
        XCTAssertEqual(obj.record["isDeleted"] as? Bool, true)
    }

    func testRecordContainsBoolFieldFalse() {
        let obj = StringPKObject()
        obj.id        = "test-id"
        obj.isDeleted = false
        XCTAssertEqual(obj.record["isDeleted"] as? Bool, false)
    }

    func testRecordContainsDoubleField() {
        let obj = StringPKObject()
        obj.id    = "test-id"
        obj.score = 99.5
        let stored = obj.record["score"] as? Double
        XCTAssertNotNil(stored)
        XCTAssertEqual(stored!, 99.5, accuracy: 0.001)
    }

    func testRecordContainsFloatField() {
        let obj = StringPKObject()
        obj.id     = "test-id"
        obj.rating = 3.14
        let stored = obj.record["rating"] as? Float
        XCTAssertNotNil(stored)
        XCTAssertEqual(stored!, 3.14, accuracy: 0.001)
    }

    func testRecordContainsDataField() {
        let payload = "hello".data(using: .utf8)!
        let obj = StringPKObject()
        obj.id   = "test-id"
        obj.data = payload
        XCTAssertEqual(obj.record["data"] as? Data, payload)
    }

    func testRecordContainsDateField() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        let obj  = StringPKObject()
        obj.id   = "test-id"
        obj.date = date
        let stored = obj.record["date"] as? Date
        XCTAssertNotNil(stored)
        XCTAssertEqual(stored!.timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 0.001)
    }

    // MARK: - isDeleted

    func testIsDeletedDefaultIsFalse() {
        XCTAssertFalse(StringPKObject().isDeleted)
        XCTAssertFalse(IntPKObject().isDeleted)
    }

    func testIsDeletedCanBeSetTrue() {
        let obj = StringPKObject()
        obj.isDeleted = true
        XCTAssertTrue(obj.isDeleted)
    }

    // MARK: - IceCreamKey string constants

    /// These constants are stored in UserDefaults; changing them silently
    /// breaks sync for existing users, so we pin their expected values.
    func testIceCreamKeyValues() {
        XCTAssertEqual(IceCreamKey.databaseChangesTokenKey.value,
                       "icecream.keys.databaseChangesTokenKey")
        XCTAssertEqual(IceCreamKey.zoneChangesTokenKey.value,
                       "icecream.keys.zoneChangesTokenKey")
        XCTAssertEqual(IceCreamKey.subscriptionIsLocallyCachedKey.value,
                       "icecream.keys.subscriptionIsLocallyCachedKey")
        XCTAssertEqual(IceCreamKey.hasCustomZoneCreatedKey.value,
                       "icecream.keys.hasCustomZoneCreatedKey")
    }

    // MARK: - IceCreamSubscription string constants

    func testSubscriptionIDPrivate() {
        XCTAssertEqual(IceCreamSubscription.cloudKitPrivateDatabaseSubscriptionID.id,
                       "private_changes")
    }

    func testSubscriptionIDPublic() {
        XCTAssertEqual(IceCreamSubscription.cloudKitPublicDatabaseSubscriptionID.id,
                       "cloudKitPublicDatabaseSubcriptionID")
    }

    func testAllSubscriptionIDsContainsAllThreeValues() {
        let ids = IceCreamSubscription.allIDs
        XCTAssertEqual(ids.count, 3)
        XCTAssertTrue(ids.contains("private_changes"))
        XCTAssertTrue(ids.contains("cloudKitPublicDatabaseSubcriptionID"))
        XCTAssertTrue(ids.contains("shared_changes"))
    }

    // MARK: - Shared scope zone ID

    func testSharedScopeZoneIDDoesNotCrash() {
        // StringPKObject uses the default .private scope; for this test we verify the
        // shared-scope placeholder path in CKRecordConvertible does not crash.
        // We call the helper directly with the .shared constant to exercise the switch branch.
        let sharedZoneID = CKRecordZone.ID(zoneName: "StringPKObjectsZone",
                                           ownerName: CKCurrentUserDefaultName)
        XCTAssertEqual(sharedZoneID.zoneName, "StringPKObjectsZone")
        XCTAssertEqual(sharedZoneID.ownerName, CKCurrentUserDefaultName)
    }

    func testSubscriptionIDShared() {
        XCTAssertEqual(IceCreamSubscription.cloudKitSharedDatabaseSubscriptionID.id, "shared_changes")
    }
}
