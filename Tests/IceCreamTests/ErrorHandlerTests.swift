//
//  ErrorHandlerTests.swift
//  IceCreamTests
//
//  Tests ErrorHandler.resultType(with:) for every documented CKError code category:
//    - nil error             → .success
//    - non-CKError           → .fail(.unknown)
//    - serviceUnavailable /
//      requestRateLimited /
//      zoneBusy + retry key  → .retry(afterSeconds:)
//    - same without retry key→ .fail(.unknown)
//    - networkUnavailable /
//      networkFailure        → .recoverableError(.network)
//    - changeTokenExpired    → .recoverableError(.changeTokenExpired)
//    - serverRecordChanged   → .recoverableError(.serverRecordChanged)
//    - partialFailure        → .recoverableError(.partialFailure)
//    - limitExceeded         → .chunk
//    - quotaExceeded         → .fail(.quotaExceeded)
//    - share-related codes   → .fail(.shareRelated)
//    - anything else         → .fail(.unknown)
//

import XCTest
import CloudKit
@testable import IceCream

final class ErrorHandlerTests: XCTestCase {

    private let handler = ErrorHandler.shared

    // MARK: - Helpers

    /// Builds an NSError in the CKErrorDomain so the ErrorHandler can cast it as CKError.
    private func makeCKError(_ code: CKError.Code, userInfo: [String: Any] = [:]) -> Error {
        return NSError(domain: CKErrorDomain, code: code.rawValue, userInfo: userInfo)
    }

    // MARK: - nil / non-CKError

    func testNilErrorReturnsSuccess() {
        let result = handler.resultType(with: nil)
        guard case .success = result else {
            XCTFail("Expected .success for nil error, got \(result)")
            return
        }
    }

    func testNonCKErrorReturnsUnknownFail() {
        let nsError = NSError(domain: "com.test.UnknownDomain", code: 999)
        let result = handler.resultType(with: nsError)
        guard case .fail(let reason, _) = result else {
            XCTFail("Expected .fail for non-CKError, got \(result)")
            return
        }
        XCTAssertEqual(reason, .unknown)
    }

    // MARK: - RETRY path (serviceUnavailable / requestRateLimited / zoneBusy)

    func testServiceUnavailableWithRetryKeyReturnsRetry() {
        let error = makeCKError(.serviceUnavailable, userInfo: [CKErrorRetryAfterKey: Double(5)])
        let result = handler.resultType(with: error)
        guard case .retry(let seconds, _) = result else {
            XCTFail("Expected .retry, got \(result)")
            return
        }
        XCTAssertEqual(seconds, 5.0)
    }

    func testRequestRateLimitedWithRetryKeyReturnsRetry() {
        let error = makeCKError(.requestRateLimited, userInfo: [CKErrorRetryAfterKey: Double(3)])
        let result = handler.resultType(with: error)
        guard case .retry(let seconds, _) = result else {
            XCTFail("Expected .retry, got \(result)")
            return
        }
        XCTAssertEqual(seconds, 3.0)
    }

    func testZoneBusyWithRetryKeyReturnsRetry() {
        let error = makeCKError(.zoneBusy, userInfo: [CKErrorRetryAfterKey: Double(10)])
        let result = handler.resultType(with: error)
        guard case .retry(let seconds, _) = result else {
            XCTFail("Expected .retry, got \(result)")
            return
        }
        XCTAssertEqual(seconds, 10.0)
    }

    /// Without CKErrorRetryAfterKey the handler cannot determine the delay, so it falls back to .fail.
    func testServiceUnavailableWithoutRetryKeyReturnsFail() {
        let error = makeCKError(.serviceUnavailable)
        let result = handler.resultType(with: error)
        guard case .fail(let reason, _) = result else {
            XCTFail("Expected .fail when no retry key present, got \(result)")
            return
        }
        XCTAssertEqual(reason, .unknown)
    }

    func testRequestRateLimitedWithoutRetryKeyReturnsFail() {
        let error = makeCKError(.requestRateLimited)
        let result = handler.resultType(with: error)
        guard case .fail = result else {
            XCTFail("Expected .fail when no retry key present, got \(result)")
            return
        }
    }

    // MARK: - RECOVERABLE path

    func testNetworkUnavailableReturnsRecoverableNetwork() {
        let error = makeCKError(.networkUnavailable)
        let result = handler.resultType(with: error)
        guard case .recoverableError(let reason, _) = result else {
            XCTFail("Expected .recoverableError for networkUnavailable, got \(result)")
            return
        }
        XCTAssertEqual(reason, .network)
    }

    func testNetworkFailureReturnsRecoverableNetwork() {
        let error = makeCKError(.networkFailure)
        let result = handler.resultType(with: error)
        guard case .recoverableError(let reason, _) = result else {
            XCTFail("Expected .recoverableError for networkFailure, got \(result)")
            return
        }
        XCTAssertEqual(reason, .network)
    }

    func testChangeTokenExpiredReturnsRecoverableChangeToken() {
        let error = makeCKError(.changeTokenExpired)
        let result = handler.resultType(with: error)
        guard case .recoverableError(let reason, _) = result else {
            XCTFail("Expected .recoverableError for changeTokenExpired, got \(result)")
            return
        }
        XCTAssertEqual(reason, .changeTokenExpired)
    }

    func testServerRecordChangedReturnsRecoverableServerRecordChanged() {
        let error = makeCKError(.serverRecordChanged)
        let result = handler.resultType(with: error)
        guard case .recoverableError(let reason, _) = result else {
            XCTFail("Expected .recoverableError for serverRecordChanged, got \(result)")
            return
        }
        XCTAssertEqual(reason, .serverRecordChanged)
    }

    func testPartialFailureReturnsRecoverablePartialFailure() {
        let error = makeCKError(.partialFailure)
        let result = handler.resultType(with: error)
        guard case .recoverableError(let reason, _) = result else {
            XCTFail("Expected .recoverableError for partialFailure, got \(result)")
            return
        }
        XCTAssertEqual(reason, .partialFailure)
    }

    // MARK: - CHUNK path

    func testLimitExceededReturnsChunk() {
        let error = makeCKError(.limitExceeded)
        let result = handler.resultType(with: error)
        guard case .chunk = result else {
            XCTFail("Expected .chunk for limitExceeded, got \(result)")
            return
        }
    }

    // MARK: - QUOTA path

    func testQuotaExceededReturnsFailQuotaExceeded() {
        let error = makeCKError(.quotaExceeded)
        let result = handler.resultType(with: error)
        guard case .fail(let reason, _) = result else {
            XCTFail("Expected .fail for quotaExceeded, got \(result)")
            return
        }
        XCTAssertEqual(reason, .quotaExceeded)
    }

    // MARK: - SHARE-RELATED path

    func testAlreadySharedReturnsFailShareRelated() {
        let error = makeCKError(.alreadyShared)
        let result = handler.resultType(with: error)
        guard case .fail(let reason, _) = result else {
            XCTFail("Expected .fail for alreadyShared, got \(result)")
            return
        }
        XCTAssertEqual(reason, .shareRelated)
    }

    func testParticipantMayNeedVerificationReturnsFailShareRelated() {
        let error = makeCKError(.participantMayNeedVerification)
        let result = handler.resultType(with: error)
        guard case .fail(let reason, _) = result else {
            XCTFail("Expected .fail for participantMayNeedVerification, got \(result)")
            return
        }
        XCTAssertEqual(reason, .shareRelated)
    }

    func testReferenceViolationReturnsFailShareRelated() {
        let error = makeCKError(.referenceViolation)
        let result = handler.resultType(with: error)
        guard case .fail(let reason, _) = result else {
            XCTFail("Expected .fail for referenceViolation, got \(result)")
            return
        }
        XCTAssertEqual(reason, .shareRelated)
    }

    func testTooManyParticipantsReturnsFailShareRelated() {
        let error = makeCKError(.tooManyParticipants)
        let result = handler.resultType(with: error)
        guard case .fail(let reason, _) = result else {
            XCTFail("Expected .fail for tooManyParticipants, got \(result)")
            return
        }
        XCTAssertEqual(reason, .shareRelated)
    }

    // MARK: - DEFAULT (unhandled) path

    func testUnknownItemReturnsFailUnknown() {
        let error = makeCKError(.unknownItem)
        let result = handler.resultType(with: error)
        guard case .fail(let reason, _) = result else {
            XCTFail("Expected .fail for unknownItem, got \(result)")
            return
        }
        XCTAssertEqual(reason, .unknown)
    }

    func testInternalErrorReturnsFailUnknown() {
        let error = makeCKError(.internalError)
        let result = handler.resultType(with: error)
        guard case .fail(let reason, _) = result else {
            XCTFail("Expected .fail for internalError, got \(result)")
            return
        }
        XCTAssertEqual(reason, .unknown)
    }

    func testInvalidArgumentsReturnsFailUnknown() {
        let error = makeCKError(.invalidArguments)
        let result = handler.resultType(with: error)
        guard case .fail(let reason, _) = result else {
            XCTFail("Expected .fail for invalidArguments, got \(result)")
            return
        }
        XCTAssertEqual(reason, .unknown)
    }
}

