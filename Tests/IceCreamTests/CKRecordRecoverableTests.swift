//
//  CKRecordRecoverableTests.swift
//  IceCreamTests
//
//  Tests CKRecordRecoverable.primaryKeyForRecordID(recordID:schema:).
//
//  This static method is the mirror of CKRecordConvertible.recordID:
//    • String PK objects → record name returned as-is
//    • Int PK objects    → record name parsed with Int()
//    • Non-numeric string for Int PK → nil  (Int() returns nil)
//
//  Also exercises parseFromRecord for primitive scalar fields using an
//  in-memory Realm so no file-system state is modified.
//

import XCTest
import CloudKit
import RealmSwift
@testable import IceCream

final class CKRecordRecoverableTests: XCTestCase {

    // MARK: - primaryKeyForRecordID – String PK

    func testStringPKReturnsRecordNameAsIs() {
        let recordID = CKRecord.ID(recordName: "my-dog-abc",
                                   zoneID: StringPKObject.zoneID)
        let key = StringPKObject.primaryKeyForRecordID(recordID: recordID)
        XCTAssertEqual(key as? String, "my-dog-abc")
    }

    func testStringPKPreservesUUIDFormat() {
        let uuid = "550E8400-E29B-41D4-A716-446655440000"
        let recordID = CKRecord.ID(recordName: uuid,
                                   zoneID: StringPKObject.zoneID)
        let key = StringPKObject.primaryKeyForRecordID(recordID: recordID)
        XCTAssertEqual(key as? String, uuid)
    }

    func testStringPKPreservesSpecialCharacters() {
        // CloudKit record names support ASCII; hyphens and underscores are common.
        let name = "user-profile-123"
        let recordID = CKRecord.ID(recordName: name,
                                   zoneID: StringPKObject.zoneID)
        let key = StringPKObject.primaryKeyForRecordID(recordID: recordID)
        XCTAssertEqual(key as? String, name)
    }

    // MARK: - primaryKeyForRecordID – Int PK

    func testIntPKParsesPositiveInteger() {
        let recordID = CKRecord.ID(recordName: "99",
                                   zoneID: IntPKObject.zoneID)
        let key = IntPKObject.primaryKeyForRecordID(recordID: recordID)
        XCTAssertEqual(key as? Int, 99)
    }

    func testIntPKParsesZero() {
        let recordID = CKRecord.ID(recordName: "0",
                                   zoneID: IntPKObject.zoneID)
        let key = IntPKObject.primaryKeyForRecordID(recordID: recordID)
        XCTAssertEqual(key as? Int, 0)
    }

    func testIntPKParsesNegativeInteger() {
        let recordID = CKRecord.ID(recordName: "-1",
                                   zoneID: IntPKObject.zoneID)
        let key = IntPKObject.primaryKeyForRecordID(recordID: recordID)
        XCTAssertEqual(key as? Int, -1)
    }

    func testIntPKWithNonNumericStringReturnsNil() {
        let recordID = CKRecord.ID(recordName: "not-a-number",
                                   zoneID: IntPKObject.zoneID)
        let key = IntPKObject.primaryKeyForRecordID(recordID: recordID)
        XCTAssertNil(key, "Int(\"not-a-number\") must return nil")
    }

    func testIntPKWithFloatStringReturnsNil() {
        let recordID = CKRecord.ID(recordName: "3.14",
                                   zoneID: IntPKObject.zoneID)
        let key = IntPKObject.primaryKeyForRecordID(recordID: recordID)
        XCTAssertNil(key, "Int(\"3.14\") must return nil")
    }

    // MARK: - Round-trip: recordID → primaryKeyForRecordID

    func testStringPKRoundTrip() {
        let obj = StringPKObject()
        obj.id = "round-trip-test"
        // CKRecordConvertible encodes the PK into the recordID
        let encoded = obj.recordID
        // CKRecordRecoverable decodes it back
        let decoded = StringPKObject.primaryKeyForRecordID(recordID: encoded)
        XCTAssertEqual(decoded as? String, obj.id)
    }

    func testIntPKRoundTrip() {
        let obj = IntPKObject()
        obj.id = 12345
        let encoded = obj.recordID
        let decoded = IntPKObject.primaryKeyForRecordID(recordID: encoded)
        XCTAssertEqual(decoded as? Int, obj.id)
    }

    // MARK: - parseFromRecord (primitive scalar fields)

    func testParseFromRecordRecoversStringField() throws {
        let config = Realm.Configuration.inMemory(identifier: "parse-string-test",
                                                  objectTypes: [StringPKObject.self,
                                                                IntPKObject.self])
        let realm = try Realm(configuration: config)

        let record = CKRecord(recordType: StringPKObject.recordType,
                              recordID: CKRecord.ID(recordName: "parsed-id",
                                                    zoneID: StringPKObject.zoneID))
        record["id"]   = "parsed-id"
        record["name"] = "Recovered Name"
        record["age"]  = 7
        record["score"] = 42.5
        record["flag"]  = true
        record["isDeleted"] = false

        let noop = PendingRelationshipsWorker<StringPKObject>()
        let noop2 = PendingRelationshipsWorker<IntPKObject>()
        let noop3 = PendingRelationshipsWorker<IntPKObject>()

        let obj = StringPKObject.parseFromRecord(
            record: record,
            realm: realm,
            notificationToken: nil,
            pendingUTypeRelationshipsWorker: noop,
            pendingVTypeRelationshipsWorker: noop2,
            pendingWTypeRelationshipsWorker: noop3
        )

        XCTAssertNotNil(obj)
        XCTAssertEqual(obj?.id, "parsed-id")
        XCTAssertEqual(obj?.name, "Recovered Name")
        XCTAssertEqual(obj?.age, 7)
        XCTAssertEqual(obj?.score ?? 0, 42.5, accuracy: 0.001)
        XCTAssertEqual(obj?.flag, true)
        XCTAssertEqual(obj?.isDeleted, false)
    }

    func testParseFromRecordWithMissingOptionalFieldsDoesNotCrash() throws {
        let config = Realm.Configuration.inMemory(identifier: "parse-missing-test",
                                                  objectTypes: [StringPKObject.self,
                                                                IntPKObject.self])
        let realm = try Realm(configuration: config)

        // Record with only the primary key set; all other fields absent.
        let record = CKRecord(recordType: StringPKObject.recordType,
                              recordID: CKRecord.ID(recordName: "sparse-id",
                                                    zoneID: StringPKObject.zoneID))
        record["id"] = "sparse-id"

        let noop = PendingRelationshipsWorker<StringPKObject>()
        let noop2 = PendingRelationshipsWorker<IntPKObject>()
        let noop3 = PendingRelationshipsWorker<IntPKObject>()

        XCTAssertNoThrow(
            StringPKObject.parseFromRecord(
                record: record,
                realm: realm,
                notificationToken: nil,
                pendingUTypeRelationshipsWorker: noop,
                pendingVTypeRelationshipsWorker: noop2,
                pendingWTypeRelationshipsWorker: noop3
            )
        )
    }
}
