//
//  CloudSyncConflictResolutionTests.swift
//  QuizFlashTests
//

import Foundation
import XCTest
@testable import QuizFlash

@MainActor
final class CloudSyncConflictResolutionTests: XCTestCase {
    func testSubMillisecondFirestoreTimestampDriftDoesNotCreateAnotherUpload() {
        let remote = Date(timeIntervalSince1970: 1_000)
        let local = remote.addingTimeInterval(0.0005)

        XCTAssertFalse(CloudSyncCoordinator.localEditIsMeaningfullyNewer(local, than: remote))
    }

    func testLaterLocalEditWinsConflict() {
        let remote = Date(timeIntervalSince1970: 1_000)
        let local = remote.addingTimeInterval(1)

        XCTAssertTrue(CloudSyncCoordinator.localEditIsMeaningfullyNewer(local, than: remote))
    }
}
