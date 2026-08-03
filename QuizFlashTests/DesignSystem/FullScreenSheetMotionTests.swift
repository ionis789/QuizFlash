//
//  FullScreenSheetMotionTests.swift
//  QuizFlashTests
//
//  Verifies the shared custom-sheet motion contract.
//

import XCTest
@testable import QuizFlash

final class FullScreenSheetMotionTests: XCTestCase {
    func testFullPresentationAndDismissUseCanonicalDuration() {
        XCTAssertEqual(FullScreenSheetMotion.duration, 0.28, accuracy: 0.0001)
        XCTAssertEqual(
            FullScreenSheetMotion.continuationDuration(
                from: 0,
                to: 420,
                travelDistance: 420
            ),
            FullScreenSheetMotion.duration,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            FullScreenSheetMotion.continuationDuration(
                from: 420,
                to: 0,
                travelDistance: 420
            ),
            FullScreenSheetMotion.duration,
            accuracy: 0.0001
        )
    }

    func testTravelDistanceUsesResolvedSheetHeight() {
        XCTAssertEqual(FullScreenSheetMotion.travelDistance(sheetHeight: 220), 220)
        XCTAssertEqual(FullScreenSheetMotion.travelDistance(sheetHeight: 844), 844)
    }

    func testDragContinuationScalesWithRemainingDistance() {
        XCTAssertEqual(
            FullScreenSheetMotion.continuationDuration(
                from: 210,
                to: 420,
                travelDistance: 420
            ),
            0.14,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            FullScreenSheetMotion.continuationDuration(
                from: 105,
                to: 0,
                travelDistance: 420
            ),
            0.07,
            accuracy: 0.0001
        )
    }

    func testContinuationDurationIsClampedToCanonicalDuration() {
        XCTAssertEqual(
            FullScreenSheetMotion.continuationDuration(
                from: -200,
                to: 800,
                travelDistance: 400
            ),
            FullScreenSheetMotion.duration,
            accuracy: 0.0001
        )
    }

    func testShortSnapBackUsesMinimumSmoothSettleDuration() {
        XCTAssertEqual(
            FullScreenSheetMotion.settleDuration(
                from: 12,
                to: 0,
                travelDistance: 420
            ),
            FullScreenSheetMotion.minimumSettleDuration,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            FullScreenSheetMotion.settleDuration(
                from: 0,
                to: 0,
                travelDistance: 420
            ),
            0,
            accuracy: 0.0001
        )
    }
}
