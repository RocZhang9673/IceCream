//
//  CreamAssetTests.swift
//  IceCreamTests
//
//  Tests CreamAsset factory methods, file-system behaviour, and cleanup utilities.
//
//  CreamAsset stores binary payloads in Documents/CreamAsset/<objectID>_<propName>
//  so that large data can bypass Realm's 16 MB property limit and be stored as
//  CKAsset on CloudKit.
//
//  All test object IDs use a unique prefix to prevent collisions with existing
//  files, and every test cleans up after itself in tearDown.
//

import XCTest
@testable import IceCream

final class CreamAssetTests: XCTestCase {

    // Unique prefix so parallel / repeated test runs don't collide.
    private let objectID  = "icetest-\(UUID().uuidString)"
    private let propName  = "avatar"
    private let testData  = "Hello, CreamAsset!".data(using: .utf8)!

    override func tearDown() {
        super.tearDown()
        CreamAsset.deleteCreamAssetFile(with: objectID)
        // Also clean up any extra IDs used in individual tests.
        CreamAsset.deleteCreamAssetFile(with: "url-test-\(objectID)")
        CreamAsset.deleteCreamAssetFile(with: "overwrite-test-\(objectID)")
        CreamAsset.deleteCreamAssetFile(with: "no-overwrite-test-\(objectID)")
        CreamAsset.deleteCreamAssetFile(with: "multi-test-A-\(objectID)")
        CreamAsset.deleteCreamAssetFile(with: "multi-test-B-\(objectID)")
    }

    // MARK: - creamAssetDefaultURL

    func testDefaultURLExistsAsDirectory() {
        let url = CreamAsset.creamAssetDefaultURL()
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        XCTAssertTrue(exists, "CreamAsset directory must exist")
        XCTAssertTrue(isDir.boolValue, "CreamAsset path must be a directory")
    }

    func testDefaultURLIsNestedInsideDocuments() {
        let docs = try! FileManager.default.url(for: .documentDirectory,
                                                in: .userDomainMask,
                                                appropriateFor: nil,
                                                create: false)
        let assetURL = CreamAsset.creamAssetDefaultURL()
        XCTAssertTrue(assetURL.path.hasPrefix(docs.path))
    }

    func testDefaultURLLastComponentIsCreamAsset() {
        XCTAssertEqual(CreamAsset.creamAssetDefaultURL().lastPathComponent, "CreamAsset")
    }

    // MARK: - create(objectID:propName:data:)

    func testCreateFromDataReturnsNonNil() {
        XCTAssertNotNil(CreamAsset.create(objectID: objectID, propName: propName, data: testData))
    }

    func testCreateFromDataCreatesFileOnDisk() {
        let asset = CreamAsset.create(objectID: objectID, propName: propName, data: testData)!
        XCTAssertTrue(FileManager.default.fileExists(atPath: asset.filePath.path))
    }

    func testStoredDataMatchesOriginalPayload() {
        let asset = CreamAsset.create(objectID: objectID, propName: propName, data: testData)!
        XCTAssertEqual(asset.storedData(), testData)
    }

    func testFilePathLastComponentContainsObjectID() {
        let asset = CreamAsset.create(objectID: objectID, propName: propName, data: testData)!
        XCTAssertTrue(asset.filePath.lastPathComponent.contains(objectID))
    }

    func testFilePathLastComponentContainsPropName() {
        let asset = CreamAsset.create(objectID: objectID, propName: propName, data: testData)!
        XCTAssertTrue(asset.filePath.lastPathComponent.contains(propName))
    }

    func testFilePathIsInsideCreamAssetDirectory() {
        let asset = CreamAsset.create(objectID: objectID, propName: propName, data: testData)!
        let base  = CreamAsset.creamAssetDefaultURL().path
        XCTAssertTrue(asset.filePath.path.hasPrefix(base))
    }

    // MARK: - shouldOverwrite behaviour

    func testOverwriteTrueReplacesExistingFile() {
        let id      = "overwrite-test-\(objectID)"
        let first   = "First payload".data(using: .utf8)!
        let second  = "Second payload".data(using: .utf8)!

        let a1 = CreamAsset.create(objectID: id, propName: propName, data: first,  shouldOverwrite: true)!
        let a2 = CreamAsset.create(objectID: id, propName: propName, data: second, shouldOverwrite: true)!

        XCTAssertEqual(a2.storedData(), second)
        // a1 filePath == a2 filePath (same object)
        _ = a1
    }

    func testOverwriteFalseKeepsExistingFile() {
        let id     = "no-overwrite-test-\(objectID)"
        let first  = "First payload".data(using: .utf8)!
        let second = "Second payload".data(using: .utf8)!

        let a1 = CreamAsset.create(objectID: id, propName: propName, data: first,  shouldOverwrite: true)!
        _      = CreamAsset.create(objectID: id, propName: propName, data: second, shouldOverwrite: false)

        // The file was already present; shouldOverwrite:false must leave it untouched.
        XCTAssertEqual(a1.storedData(), first)
    }

    // MARK: - create(objectID:propName:url:)

    func testCreateFromURLReturnsNonNil() throws {
        let id   = "url-test-\(objectID)"
        let tmp  = FileManager.default.temporaryDirectory
                       .appendingPathComponent("cream_url_src_\(UUID().uuidString).dat")
        try testData.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let asset = CreamAsset.create(objectID: id, propName: propName, url: tmp, shouldOverwrite: true)
        XCTAssertNotNil(asset)
    }

    func testCreateFromURLCopiesFileContents() throws {
        let id   = "url-test-\(objectID)"
        let tmp  = FileManager.default.temporaryDirectory
                       .appendingPathComponent("cream_url_src2_\(UUID().uuidString).dat")
        try testData.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let asset = CreamAsset.create(objectID: id, propName: propName, url: tmp, shouldOverwrite: true)!
        XCTAssertEqual(asset.storedData(), testData)
    }

    // MARK: - deleteCreamAssetFile(with:)

    func testDeleteRemovesFileFromDisk() {
        let asset = CreamAsset.create(objectID: objectID, propName: propName, data: testData)!
        XCTAssertTrue(FileManager.default.fileExists(atPath: asset.filePath.path))

        CreamAsset.deleteCreamAssetFile(with: objectID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: asset.filePath.path))
    }

    func testDeleteDoesNotRemoveUnrelatedFiles() {
        let idA = "multi-test-A-\(objectID)"
        let idB = "multi-test-B-\(objectID)"

        let assetA = CreamAsset.create(objectID: idA, propName: propName, data: testData)!
        let assetB = CreamAsset.create(objectID: idB, propName: propName, data: testData)!

        CreamAsset.deleteCreamAssetFile(with: idA)

        XCTAssertFalse(FileManager.default.fileExists(atPath: assetA.filePath.path),
                       "Asset A must be deleted")
        XCTAssertTrue(FileManager.default.fileExists(atPath: assetB.filePath.path),
                      "Asset B must be untouched")
    }

    func testDeleteOnNonExistentIDDoesNotCrash() {
        XCTAssertNoThrow(CreamAsset.deleteCreamAssetFile(with: "nonexistent-id-xyz"))
    }

    // MARK: - creamAssetFilesPaths

    func testCreatedFileAppearsInFilesPaths() {
        let asset = CreamAsset.create(objectID: objectID, propName: propName, data: testData)!
        let expectedName = asset.filePath.lastPathComponent
        let paths = CreamAsset.creamAssetFilesPaths()
        XCTAssertTrue(paths.contains(expectedName), "Expected \(expectedName) in \(paths)")
    }

    func testDeletedFileDoesNotAppearInFilesPaths() {
        let asset = CreamAsset.create(objectID: objectID, propName: propName, data: testData)!
        let expectedName = asset.filePath.lastPathComponent

        CreamAsset.deleteCreamAssetFile(with: objectID)

        let paths = CreamAsset.creamAssetFilesPaths()
        XCTAssertFalse(paths.contains(expectedName))
    }

    // MARK: - CKAsset wrapping

    func testAssetFileURLMatchesFilePath() {
        let asset = CreamAsset.create(objectID: objectID, propName: propName, data: testData)!
        XCTAssertEqual(asset.asset.fileURL, asset.filePath)
    }
}
