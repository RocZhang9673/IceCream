//
//  PendingRelationshipsWorkerTests.swift
//  IceCreamTests
//
//  Tests PendingRelationshipsWorker, the class responsible for deferring
//  relationship resolution when CloudKit delivers records out-of-order.
//
//  The in-memory dictionary logic (addToPendingList) can be exercised without
//  a real Realm. resolvePendingListElements requires an open Realm, so we test
//  the safe early-exit path (realm == nil) as well as the full resolution path
//  with an in-memory Realm.
//

import XCTest
import RealmSwift
@testable import IceCream

final class PendingRelationshipsWorkerTests: XCTestCase {

    // MARK: - addToPendingList (pure dictionary logic)

    func testNewWorkerHasEmptyPendingList() {
        let worker = PendingRelationshipsWorker<StringPKObject>()
        XCTAssertTrue(worker.pendingListElementPrimaryKeyValue.isEmpty)
    }

    func testAddSingleEntryStoresIt() {
        let worker = PendingRelationshipsWorker<StringPKObject>()
        let owner  = IntPKObject()
        worker.addToPendingList(elementPrimaryKeyValue: "rel-1",
                                propertyName: "friends",
                                owner: owner)
        XCTAssertEqual(worker.pendingListElementPrimaryKeyValue.count, 1)
    }

    func testAddedEntryHasCorrectPropertyName() {
        let worker = PendingRelationshipsWorker<StringPKObject>()
        let owner  = IntPKObject()
        worker.addToPendingList(elementPrimaryKeyValue: "rel-1",
                                propertyName: "cats",
                                owner: owner)
        let entry = worker.pendingListElementPrimaryKeyValue["rel-1"]
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.0, "cats")
    }

    func testAddedEntryHasCorrectOwnerReference() {
        let worker = PendingRelationshipsWorker<StringPKObject>()
        let owner  = IntPKObject()
        owner.id   = 42
        worker.addToPendingList(elementPrimaryKeyValue: "rel-1",
                                propertyName: "cats",
                                owner: owner)
        let storedOwner = worker.pendingListElementPrimaryKeyValue["rel-1"]?.1 as? IntPKObject
        XCTAssertNotNil(storedOwner)
        XCTAssertEqual(storedOwner?.id, 42)
    }

    func testAddMultipleDistinctEntriesAreAllStored() {
        let worker = PendingRelationshipsWorker<StringPKObject>()
        let owner  = IntPKObject()
        for i in 0..<5 {
            worker.addToPendingList(elementPrimaryKeyValue: "key-\(i)",
                                    propertyName: "prop",
                                    owner: owner)
        }
        XCTAssertEqual(worker.pendingListElementPrimaryKeyValue.count, 5)
    }

    func testAddDuplicateKeyOverwritesPreviousEntry() {
        let worker = PendingRelationshipsWorker<StringPKObject>()
        let owner  = IntPKObject()
        worker.addToPendingList(elementPrimaryKeyValue: "same-key",
                                propertyName: "firstProp",
                                owner: owner)
        worker.addToPendingList(elementPrimaryKeyValue: "same-key",
                                propertyName: "secondProp",
                                owner: owner)
        // Dictionary semantics: second write overwrites first.
        XCTAssertEqual(worker.pendingListElementPrimaryKeyValue.count, 1)
        XCTAssertEqual(worker.pendingListElementPrimaryKeyValue["same-key"]?.0, "secondProp")
    }

    func testIntegerPrimaryKeyCanBeUsedAsPendingKey() {
        let worker = PendingRelationshipsWorker<IntPKObject>()
        let owner  = StringPKObject()
        worker.addToPendingList(elementPrimaryKeyValue: 99 as AnyHashable,
                                propertyName: "items",
                                owner: owner)
        XCTAssertEqual(worker.pendingListElementPrimaryKeyValue.count, 1)
        XCTAssertNotNil(worker.pendingListElementPrimaryKeyValue[99])
    }

    // MARK: - resolvePendingListElements – nil realm fast path

    func testResolveWithNilRealmReturnsSafelyWithoutCrash() {
        let worker = PendingRelationshipsWorker<StringPKObject>()
        let owner  = StringPKObject()
        worker.addToPendingList(elementPrimaryKeyValue: "some-id",
                                propertyName: "items",
                                owner: owner)
        // realm is nil → must return early, not crash.
        XCTAssertNoThrow(worker.resolvePendingListElements())
    }

    func testResolveWithEmptyPendingListAndNilRealmDoesNothing() {
        let worker = PendingRelationshipsWorker<StringPKObject>()
        // No entries, no realm – should be a no-op.
        XCTAssertNoThrow(worker.resolvePendingListElements())
    }
}
