//
//  TestModels.swift
//  IceCreamTests
//
//  Lightweight Realm Object subclasses used across all test suites.
//  Using in-memory Realm configurations avoids file-system side effects.
//

import CloudKit
import RealmSwift
@testable import IceCream

// MARK: - String Primary Key Model

/// A test object whose primary key is a String. Covers all primitive
/// property types that CKRecordConvertible must handle.
class StringPKObject: Object, CKRecordConvertible, CKRecordRecoverable {
    @objc dynamic var id      = ""
    @objc dynamic var name    = ""
    @objc dynamic var age     = 0
    @objc dynamic var score   = 0.0
    @objc dynamic var rating: Float = 0
    @objc dynamic var flag    = false
    @objc dynamic var data    = Data()
    @objc dynamic var date    = Date(timeIntervalSince1970: 0)
    @objc dynamic var isDeleted = false

    override class func primaryKey() -> String? { return "id" }
}

// MARK: - Int Primary Key Model

/// A test object whose primary key is an Int.
/// Tests that integer primary keys are correctly stringified for CloudKit.
class IntPKObject: Object, CKRecordConvertible, CKRecordRecoverable {
    @objc dynamic var id   = 0
    @objc dynamic var name = ""
    @objc dynamic var isDeleted = false

    override class func primaryKey() -> String? { return "id" }
}

// MARK: - Realm Configuration Helpers

extension Realm.Configuration {
    /// Returns an in-memory configuration that includes only the given object types.
    /// Each call with a unique identifier produces an isolated Realm store.
    static func inMemory(identifier: String, objectTypes: [Object.Type]) -> Realm.Configuration {
        var config = Realm.Configuration()
        config.inMemoryIdentifier = identifier
        config.objectTypes = objectTypes
        return config
    }
}
