//
//  HomeCompactCalendarLayoutTests.swift
//  QuizFlashTests
//
//  Guards the adaptive Home calendar layout across wide and compact widths.
//

import XCTest
@testable import QuizFlash

final class HomeCompactCalendarLayoutTests: XCTestCase {
    func testPadLayoutReservesRoomForCompanionAndKeepsCompactCapsuleControlled() {
        let layout = HomeCalendarAdaptiveLayout(
            containerWidth: 834,
            safeAreaTop: 24,
            monthRowCount: 6,
            kind: .pad
        )

        XCTAssertEqual(layout.headerColumnWidth, layout.expandedCalendarWidth)
        XCTAssertGreaterThan(layout.expandedCompanionWidth, 0)
        XCTAssertLessThan(layout.expandedCalendarWidth, layout.availableContentWidth)
        XCTAssertLessThanOrEqual(
            layout.expandedCalendarWidth + layout.expandedCompanionWidth + layout.expandedColumnSpacing,
            layout.availableContentWidth - layout.trailingReservation + 0.001
        )
        XCTAssertEqual(layout.expandedContentLeadingInset, 0, accuracy: 0.001)
        XCTAssertEqual(layout.contentLeadingInset(for: 0), 0, accuracy: 0.001)
        XCTAssertEqual(layout.contentLeadingInset(for: 1), 0, accuracy: 0.001)
        XCTAssertLessThan(layout.compactCapsuleWidth, layout.availableContentWidth)
        XCTAssertLessThanOrEqual(layout.compactCapsuleWidth, layout.availableContentWidth - layout.trailingReservation)
        XCTAssertGreaterThanOrEqual(layout.compactCapsuleWidth, 420)
    }

    func testPadTopHeaderStateKeepsStickyCalendarWithinAvailableWidth() {
        let layout = HomeCalendarAdaptiveLayout(
            containerWidth: 1024,
            safeAreaTop: 24,
            monthRowCount: 6,
            kind: .pad
        )

        let expanded = layout.topHeaderState(for: 0, stickyOffset: 0)
        let compact = layout.topHeaderState(for: 1, stickyOffset: 32)

        XCTAssertEqual(expanded.calendarWidth, layout.expandedCalendarWidth, accuracy: 0.001)
        XCTAssertEqual(compact.calendarWidth, layout.expandedCalendarWidth, accuracy: 0.001)
        XCTAssertEqual(expanded.companionWidth, layout.expandedCompanionWidth, accuracy: 0.001)
        XCTAssertEqual(compact.companionWidth, layout.expandedCompanionWidth, accuracy: 0.001)
        XCTAssertLessThanOrEqual(
            compact.calendarWidth + layout.trailingReservation,
            layout.availableContentWidth + 0.001
        )
        XCTAssertEqual(compact.avatarTop, expanded.avatarTop, accuracy: 0.001)
        XCTAssertEqual(expanded.companionProgress, 0, accuracy: 0.001)
        XCTAssertEqual(compact.companionProgress, 0, accuracy: 0.001)
        XCTAssertEqual(compact.companionHeight, layout.expandedContentHeight, accuracy: 0.001)
    }

    func testPadLayoutUsesMoreWidthThanPhoneLayout() {
        let padLayout = HomeCalendarAdaptiveLayout(
            containerWidth: 1024,
            safeAreaTop: 24,
            monthRowCount: 6,
            kind: .pad
        )
        let phoneLayout = HomeCalendarAdaptiveLayout(
            containerWidth: 393,
            safeAreaTop: 24,
            monthRowCount: 6,
            kind: .phone
        )

        XCTAssertGreaterThan(padLayout.expanded.dayColumnWidth, phoneLayout.expanded.dayColumnWidth)
        XCTAssertGreaterThan(padLayout.compactCapsuleWidth, phoneLayout.compactCapsuleWidth)
        XCTAssertGreaterThan(padLayout.extendedHeight, phoneLayout.extendedHeight)
    }
}
