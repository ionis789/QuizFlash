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
            dayColumnWidth: 116,
            rowHeight: 88,
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
        XCTAssertEqual(expanded.contentMode, .detail)
        XCTAssertEqual(collapsed.contentMode, .compact)
        XCTAssertLessThan(collapsed.markerDotSize, expanded.markerDotSize)
        XCTAssertGreaterThan(collapsed.markerOffsetY, expanded.markerOffsetY)
        XCTAssertGreaterThan(expanded.valueFontSize, expanded.captionFontSize)
    }

    func testCollapsedMetricsSimplifySecondaryNoteMarker() {
        let expanded = HomeCalendarDayMetrics(
            collapseProgress: 0.2,
            dayColumnWidth: 76,
            rowHeight: 62,
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
