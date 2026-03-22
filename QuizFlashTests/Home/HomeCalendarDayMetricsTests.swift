//
//  HomeCalendarDayMetricsTests.swift
//  QuizFlashTests
//
//  Covers compact-calendar day metrics so the sticky Home header stays readable.
//

import XCTest
@testable import QuizFlash

final class HomeCalendarDayMetricsTests: XCTestCase {
    func testCollapsedMetricsReduceHighlightFootprint() {
        let expanded = HomeCalendarDayMetrics(
            collapseProgress: 0,
            hasGoalNote: true,
            hasExamGoalCount: true,
            isHighlighted: true
        )
        let collapsed = HomeCalendarDayMetrics(
            collapseProgress: 1,
            hasGoalNote: true,
            hasExamGoalCount: true,
            isHighlighted: true
        )

        XCTAssertEqual(expanded.highlightDiameter, 40, accuracy: 0.001)
        XCTAssertEqual(collapsed.highlightDiameter, 34, accuracy: 0.001)
        XCTAssertGreaterThan(expanded.streakRingDiameter, expanded.highlightDiameter)
        XCTAssertLessThan(collapsed.markerDotSize, expanded.markerDotSize)
        XCTAssertGreaterThan(collapsed.markerOffsetY, expanded.markerOffsetY)
    }

    func testCollapsedMetricsSimplifySecondaryNoteMarker() {
        let expanded = HomeCalendarDayMetrics(
            collapseProgress: 0.2,
            hasGoalNote: true,
            hasExamGoalCount: true,
            isHighlighted: false
        )
        let collapsed = HomeCalendarDayMetrics(
            collapseProgress: 0.9,
            hasGoalNote: true,
            hasExamGoalCount: true,
            isHighlighted: false
        )

        XCTAssertTrue(expanded.showsSecondaryNoteMarker)
        XCTAssertFalse(collapsed.showsSecondaryNoteMarker)
        XCTAssertTrue(expanded.usesMarkerCapsule)
        XCTAssertFalse(collapsed.usesMarkerCapsule)
    }
}
