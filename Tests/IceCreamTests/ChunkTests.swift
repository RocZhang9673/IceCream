//
//  ChunkTests.swift
//  IceCreamTests
//
//  Tests the Array<CKRecord>.chunkItUp(by:) extension defined in ErrorHandler.swift.
//  Chunking is used by the database managers to work around CloudKit's 400-record
//  per-operation limit.
//

import XCTest
import CloudKit
@testable import IceCream

final class ChunkTests: XCTestCase {

    // MARK: - Helpers

    private func makeRecords(_ count: Int) -> [CKRecord] {
        (0..<count).map { i in
            CKRecord(recordType: "TestChunk",
                     recordID: CKRecord.ID(recordName: "record-\(i)"))
        }
    }

    // MARK: - Edge cases

    func testChunkEmptyArrayProducesNoChunks() {
        let records: [CKRecord] = []
        XCTAssertEqual(records.chunkItUp(by: 3).count, 0)
    }

    func testChunkSingleElement() {
        let chunks = makeRecords(1).chunkItUp(by: 5)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].count, 1)
    }

    // MARK: - Exact fits

    func testChunkCountSmallerThanChunkSize() {
        let chunks = makeRecords(3).chunkItUp(by: 10)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].count, 3)
    }

    func testChunkCountEqualsChunkSize() {
        let chunks = makeRecords(5).chunkItUp(by: 5)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].count, 5)
    }

    // MARK: - Even split

    func testChunkEvenlyDivisible() {
        let chunks = makeRecords(9).chunkItUp(by: 3)
        XCTAssertEqual(chunks.count, 3)
        for chunk in chunks {
            XCTAssertEqual(chunk.count, 3)
        }
    }

    // MARK: - Uneven split (remainder)

    func testChunkUnevenSplitHasCorrectRemainder() {
        let chunks = makeRecords(10).chunkItUp(by: 3)
        XCTAssertEqual(chunks.count, 4)
        XCTAssertEqual(chunks[0].count, 3)
        XCTAssertEqual(chunks[1].count, 3)
        XCTAssertEqual(chunks[2].count, 3)
        XCTAssertEqual(chunks[3].count, 1)
    }

    func testChunkByOneProducesOneChunkPerRecord() {
        let chunks = makeRecords(5).chunkItUp(by: 1)
        XCTAssertEqual(chunks.count, 5)
        chunks.forEach { XCTAssertEqual($0.count, 1) }
    }

    // MARK: - Total count and order preservation

    func testChunkPreservesTotalRecordCount() {
        let count = 17
        let chunks = makeRecords(count).chunkItUp(by: 5)
        let totalInChunks = chunks.reduce(0) { $0 + $1.count }
        XCTAssertEqual(totalInChunks, count)
    }

    func testChunkPreservesOrder() {
        let records = makeRecords(7)
        let chunks = records.chunkItUp(by: 3)
        let flattened = chunks.flatMap { $0 }
        for (i, record) in flattened.enumerated() {
            XCTAssertEqual(record.recordID.recordName, "record-\(i)")
        }
    }

    // MARK: - Typical CloudKit limit scenario

    func testChunkByCloudKitTypicalLimit() {
        // CloudKit allows up to 400 records per operation; IceCream uses 300-record chunks.
        let count = 750
        let chunkSize = 300
        let chunks = makeRecords(count).chunkItUp(by: chunkSize)
        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[0].count, 300)
        XCTAssertEqual(chunks[1].count, 300)
        XCTAssertEqual(chunks[2].count, 150)
    }
}
