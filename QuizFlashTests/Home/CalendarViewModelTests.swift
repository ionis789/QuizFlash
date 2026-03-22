//
//  CalendarViewModelTests.swift
//  QuizFlashTests
//
//  Covers calendar grid alignment when the preferred week start changes.
//

import XCTest
@testable import QuizFlash

@MainActor
final class CalendarViewModelTests: XCTestCase {
    func testMondayWeekStartAlignsMonthGridToMondayColumn() throws {
        let viewModel = CalendarViewModel()
        let calendar = AppWeekStartDayPreference.monday.resolvedCalendar
        let marchFirst = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 1)))

        viewModel.applyWeekStartPreference(.monday)
        viewModel.selectDate(marchFirst)

        let firstVisibleDay = try XCTUnwrap(viewModel.monthRows.first?.first)
        let components = calendar.dateComponents([.year, .month, .day], from: firstVisibleDay.date)

        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 2)
        XCTAssertEqual(components.day, 23)
        XCTAssertTrue(firstVisibleDay.ignored)
    }

    func testSundayWeekStartKeepsSundayAsFirstVisibleColumn() throws {
        let viewModel = CalendarViewModel()
        let calendar = AppWeekStartDayPreference.sunday.resolvedCalendar
        let marchFirst = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 1)))

        viewModel.applyWeekStartPreference(.sunday)
        viewModel.selectDate(marchFirst)

        let firstVisibleDay = try XCTUnwrap(viewModel.monthRows.first?.first)
        let components = calendar.dateComponents([.year, .month, .day], from: firstVisibleDay.date)

        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 3)
        XCTAssertEqual(components.day, 1)
        XCTAssertFalse(firstVisibleDay.ignored)
    }

    func testCalendarAlwaysRendersSixRowsForStableHomeHeaderHeight() throws {
        let viewModel = CalendarViewModel()
        let calendar = AppWeekStartDayPreference.monday.resolvedCalendar
        let aprilDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 20)))
        let augustDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 20)))

        viewModel.applyWeekStartPreference(.monday)
        viewModel.selectDate(aprilDate)
        XCTAssertEqual(viewModel.monthRows.count, 6)

        viewModel.selectDate(augustDate)
        XCTAssertEqual(viewModel.monthRows.count, 6)
    }

    func testCompactCapsuleHeightMatchesCalendarRowMetrics() {
        let viewModel = CalendarViewModel()

        XCTAssertEqual(
            viewModel.compactCapsuleHeight,
            viewModel.weekLabelHeight + viewModel.rowHeight + (viewModel.compactCapsuleVerticalPadding * 2),
            accuracy: 0.001
        )
    }
}
