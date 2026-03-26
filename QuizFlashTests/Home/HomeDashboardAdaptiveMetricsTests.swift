//
//  HomeDashboardAdaptiveMetricsTests.swift
//  QuizFlashTests
//
//  Regression coverage for Home dashboard width-bucket composition.
//

import XCTest
@testable import QuizFlash

final class HomeDashboardAdaptiveMetricsTests: XCTestCase {

    func testNarrowWidthKeepsPhoneLikeSections() {
        let metrics = HomeDashboardAdaptiveMetrics(contentWidth: 560)

        XCTAssertTrue(metrics.isNarrowSection)
        XCTAssertFalse(metrics.usesRegularMetrics)
        XCTAssertFalse(metrics.usesDashboardColumns)
        XCTAssertFalse(metrics.usesRecentDeckGrid)
        XCTAssertEqual(metrics.folderColumnCount, 1)
    }

    func testMediumWidthPromotesGridWithoutWideDashboardColumns() {
        let metrics = HomeDashboardAdaptiveMetrics(contentWidth: 760)

        XCTAssertFalse(metrics.isNarrowSection)
        XCTAssertTrue(metrics.usesRegularMetrics)
        XCTAssertFalse(metrics.usesDashboardColumns)
        XCTAssertTrue(metrics.usesRecentDeckGrid)
        XCTAssertEqual(metrics.folderColumnCount, 2)
        XCTAssertEqual(metrics.recentDeckColumnCount, 2)
    }

    func testWideWidthUnlocksMultiColumnDashboard() {
        let metrics = HomeDashboardAdaptiveMetrics(contentWidth: 1180)

        XCTAssertTrue(metrics.usesRegularMetrics)
        XCTAssertTrue(metrics.usesDashboardColumns)
        XCTAssertTrue(metrics.usesRecentDeckGrid)
        XCTAssertEqual(metrics.folderColumnCount, 3)
        XCTAssertEqual(metrics.recentDeckColumnCount, 3)
    }

    func testQuickStripWidthsStayBoundedAcrossCompactWindows() {
        let compact = HomeDashboardAdaptiveMetrics(contentWidth: 360)
        let roomy = HomeDashboardAdaptiveMetrics(contentWidth: 560)

        XCTAssertEqual(compact.quickStripVisibleLimit, 3)
        XCTAssertEqual(roomy.quickStripVisibleLimit, 4)
        XCTAssertGreaterThanOrEqual(compact.quickStripChipWidth, 220)
        XCTAssertLessThanOrEqual(roomy.quickStripPromptWidth, 330)
    }
}
