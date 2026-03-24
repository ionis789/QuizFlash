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
            dayColumnWidth: 56,
            rowHeight: 42,
            hasGoalNote: true,
            hasExamGoalCount: true,
            isHighlighted: true
        )
        let collapsed = HomeCalendarDayMetrics(
            collapseProgress: 1,
            dayColumnWidth: 44,
            rowHeight: 38,
            hasGoalNote: true,
            hasExamGoalCount: true,
            isHighlighted: true
        )

        XCTAssertGreaterThan(expanded.highlightDiameter, collapsed.highlightDiameter)
        XCTAssertGreaterThan(expanded.streakRingDiameter, expanded.highlightDiameter)
        XCTAssertLessThan(collapsed.markerDotSize, expanded.markerDotSize)
        XCTAssertGreaterThan(collapsed.markerOffsetY, expanded.markerOffsetY)
    }

    func testCollapsedMetricsSimplifySecondaryNoteMarker() {
        let expanded = HomeCalendarDayMetrics(
            collapseProgress: 0.2,
            dayColumnWidth: 54,
            rowHeight: 40,
            hasGoalNote: true,
            hasExamGoalCount: true,
            isHighlighted: false
        )
        let collapsed = HomeCalendarDayMetrics(
            collapseProgress: 0.9,
            dayColumnWidth: 42,
            rowHeight: 36,
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
