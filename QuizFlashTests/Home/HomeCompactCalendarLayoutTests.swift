//
//  HomeCompactCalendarLayoutTests.swift
//  QuizFlashTests
//
//  Guards the single-surface Home calendar layout across wide and compact widths.
//

import XCTest
@testable import QuizFlash

final class HomeCompactCalendarLayoutTests: XCTestCase {
    func testResolvedModeTracksRealContainerWidthBuckets() {
        XCTAssertEqual(HomeCalendarAdaptiveLayout.resolvedMode(containerWidth: 500), .narrow)
        XCTAssertEqual(HomeCalendarAdaptiveLayout.resolvedMode(containerWidth: 700), .medium)
        XCTAssertEqual(HomeCalendarAdaptiveLayout.resolvedMode(containerWidth: 1100), .wide)

        let narrowContext = HomeAdaptiveLayoutContext(containerWidth: 500)
        let mediumContext = HomeAdaptiveLayoutContext(containerWidth: 700)
        let portraitPadContext = HomeAdaptiveLayoutContext(containerWidth: 834)
        let wideContext = HomeAdaptiveLayoutContext(containerWidth: 1100)

        XCTAssertEqual(narrowContext.mode, .narrow)
        XCTAssertEqual(mediumContext.mode, .medium)
        XCTAssertEqual(portraitPadContext.mode, .medium)
        XCTAssertEqual(wideContext.mode, .wide)
        XCTAssertEqual(narrowContext.headerScaffold, .compact)
        XCTAssertEqual(mediumContext.headerScaffold, .compact)
        XCTAssertEqual(portraitPadContext.headerScaffold, .compact)
        XCTAssertEqual(wideContext.headerScaffold, .compact)
    }

    func testSingleSurfaceCalendarUsesFullAvailableWidthOnMediumAndWidePads() {
        let mediumLayout = HomeCalendarAdaptiveLayout(
            containerWidth: 834,
            safeAreaTop: 24,
            monthRowCount: 6,
            mode: .medium,
            scaffold: .compact
        )
        let wideLayout = HomeCalendarAdaptiveLayout(
            containerWidth: 1100,
            safeAreaTop: 24,
            monthRowCount: 6,
            mode: .wide,
            scaffold: .compact
        )

        XCTAssertFalse(mediumLayout.usesSplitTopHeader)
        XCTAssertFalse(wideLayout.usesSplitTopHeader)
        XCTAssertEqual(mediumLayout.expandedCalendarWidth, mediumLayout.availableContentWidth, accuracy: 0.001)
        XCTAssertEqual(wideLayout.expandedCalendarWidth, wideLayout.availableContentWidth, accuracy: 0.001)
        XCTAssertEqual(mediumLayout.expandedCompanionWidth, 0, accuracy: 0.001)
        XCTAssertEqual(wideLayout.expandedCompanionWidth, 0, accuracy: 0.001)
    }

    func testPadLayoutsKeepExpandedGridTallerThanPhoneLayout() {
        let phoneLayout = HomeCalendarAdaptiveLayout(
            containerWidth: 393,
            safeAreaTop: 24,
            monthRowCount: 6,
            mode: .narrow,
            scaffold: .compact
        )
        let mediumLayout = HomeCalendarAdaptiveLayout(
            containerWidth: 834,
            safeAreaTop: 24,
            monthRowCount: 6,
            mode: .medium,
            scaffold: .compact
        )

        XCTAssertEqual(phoneLayout.kind, .phone)
        XCTAssertEqual(mediumLayout.kind, .pad)
        XCTAssertGreaterThan(mediumLayout.expanded.rowHeight, phoneLayout.expanded.rowHeight)
        XCTAssertGreaterThan(mediumLayout.expanded.dayColumnWidth, phoneLayout.expanded.dayColumnWidth)
        XCTAssertGreaterThan(mediumLayout.extendedHeight, phoneLayout.extendedHeight)
    }

    func testCompactStateStaysWithinAvailableWidth() {
        let layout = HomeCalendarAdaptiveLayout(
            containerWidth: 560,
            safeAreaTop: 24,
            monthRowCount: 6,
            mode: .narrow,
            scaffold: .compact
        )

        XCTAssertEqual(layout.expandedCalendarWidth, layout.availableContentWidth, accuracy: 0.001)
        XCTAssertLessThan(layout.compactCapsuleWidth, layout.availableContentWidth)
        XCTAssertEqual(layout.collapsed.topPadding, 0, accuracy: 0.001)
        XCTAssertFalse(layout.showsInlineAvatar)
        XCTAssertTrue(layout.showsFloatingAvatar)
    }

    func testMediumCompactLayoutPromotesFloatingAvatarDuringCollapse() {
        let layout = HomeCalendarAdaptiveLayout(
            containerWidth: 700,
            safeAreaTop: 24,
            monthRowCount: 6,
            mode: .medium,
            scaffold: .compact
        )

        XCTAssertTrue(layout.showsInlineAvatar)
        XCTAssertTrue(layout.showsFloatingAvatar)
        XCTAssertEqual(layout.floatingAvatarOpacity(for: 0), 0, accuracy: 0.001)
        XCTAssertGreaterThan(layout.floatingAvatarOpacity(for: 0.75), 0.9)
        XCTAssertEqual(layout.floatingAvatarOpacity(for: 1), 1, accuracy: 0.001)
    }

    func testCalendarDayMetricsPromoteDetailOnlyWhenCellBudgetAllowsIt() {
        let compactMetrics = HomeCalendarDayMetrics(
            collapseProgress: 0.95,
            dayColumnWidth: 40,
            rowHeight: 38,
            hasGoalNote: false,
            hasExamGoalCount: false,
            isHighlighted: false
        )
        let summaryMetrics = HomeCalendarDayMetrics(
            collapseProgress: 0.15,
            dayColumnWidth: 74,
            rowHeight: 62,
            hasGoalNote: false,
            hasExamGoalCount: false,
            isHighlighted: true
        )
        let detailMetrics = HomeCalendarDayMetrics(
            collapseProgress: 0.05,
            dayColumnWidth: 116,
            rowHeight: 88,
            hasGoalNote: true,
            hasExamGoalCount: true,
            isHighlighted: true
        )

        XCTAssertEqual(compactMetrics.contentMode, .compact)
        XCTAssertEqual(summaryMetrics.contentMode, .summary)
        XCTAssertEqual(detailMetrics.contentMode, .detail)
        XCTAssertTrue(detailMetrics.showsSecondaryNoteMarker)
        XCTAssertTrue(detailMetrics.usesMarkerCapsule)
    }
}
