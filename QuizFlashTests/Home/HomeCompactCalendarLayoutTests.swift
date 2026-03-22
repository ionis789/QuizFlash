//
//  HomeCompactCalendarLayoutTests.swift
//  QuizFlashTests
//
//  Guards the compact Home calendar capsule so collapsed weeks stay fully visible.
//

import XCTest
@testable import QuizFlash

final class HomeCompactCalendarLayoutTests: XCTestCase {
    func testCollapsedLayoutKeepsWeekWideEnoughForVisibleDayCells() {
        let layout = HomeCompactCalendarLayout(
            collapseProgress: 1,
            avatarSize: 50,
            outerHorizontalInset: 20,
            collapsedHorizontalPadding: 10,
            collapsedVerticalPadding: 6,
            trailingGap: 10,
            cornerRadius: 28
        )

        let collapsedWeekWidth = layout.collapsedWeekContentWidth(for: 353)

        XCTAssertGreaterThanOrEqual(
            collapsedWeekWidth / 7,
            HomeCompactCalendarLayout.minimumCollapsedDayWidth
        )
    }
}
