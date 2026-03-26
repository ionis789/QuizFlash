// CalendarViewModel.swift
// QuizFlash
//
// Manages all calendar state and date logic for the Home screen.
// This is the single source of truth for:
//   - The currently displayed month
//   - The selected date
//   - The pre-computed grid of Day values
//   - Layout dimensions consumed by HomeCalendarSectionView
//
// Design notes:
//   - All DateFormatters are static to avoid repeated allocations.
//   - `monthRows` and `monthProgress` are recomputed on every state change
//     via `calculateMonthData()` — O(n) where n = days in month (~28-31).
//   - Layout constants live here so no View ever hardcodes dimensions,
//     making future layout adjustments a single-file change.

import SwiftUI

// MARK: - Day Model

/// A value type representing a single cell in the calendar grid.
///
/// Each `Day` carries everything needed to render one cell independently:
/// the display symbol, the raw `Date` for tap handling, and pre-computed
/// flags for today, selection, and out-of-month padding cells.
struct Day: Identifiable, Equatable {

    // MARK: - Properties

    let id = UUID()

    /// Two-digit day number displayed in the cell (e.g. `"01"`, `"15"`).
    var shortSymbol: String

    /// The underlying calendar date — passed to `CalendarViewModel.selectDate(_:)` on tap.
    var date: Date

    /// ISO-8601 date string (`yyyy-MM-dd`) used as the dictionary key for O(1) log lookups.
    var dateString: String

    /// `true` when this day belongs to the previous or next month (shown for grid alignment).
    var ignored: Bool = false

    /// `true` when this day matches `CalendarViewModel.selectedDate`.
    var isSelected: Bool = false

    /// Convenience inverse of `ignored`.
    var isCurrentMonth: Bool { !ignored }
}

// MARK: - Calendar View Model

/// Owns all calendar state and grid computation for the Home screen.
///
/// Instantiate once in `HomeView` with `@State` and pass as a `let` constant
/// to child views. SwiftUI's `@Observable` tracking ensures only the views
/// that read changed properties are re-evaluated.
///
/// ```swift
/// @State private var calendarVM = CalendarViewModel()
/// ```
@Observable
@MainActor
final class CalendarViewModel {

    // MARK: - Month Snapshot

    struct MonthSnapshot: Equatable, Identifiable {
        let monthStart: Date
        let monthString: String
        let yearString: String
        let rows: [[Day]]
        let monthProgress: CGFloat

        var id: Date { monthStart }
    }

    // MARK: - Dependencies

    private var calendar: Calendar

    // MARK: - State

    /// The month currently displayed in the calendar grid.
    ///
    /// Setting this triggers a full grid recalculation via `calculateMonthData()`.
    private(set) var selectedMonth: Date

    /// The date highlighted with the selection indicator.
    ///
    /// Setting this updates `isSelected` on all day cells via `calculateMonthData()`.
    private(set) var selectedDate: Date

    /// Preserves the user's intended day-of-month while paging across shorter months.
    private var preferredDayOfMonth: Int

    // MARK: - Cached Output (read-only outside this class)

    /// All weeks of the current month, each sub-array containing exactly 7 `Day` values.
    private(set) var monthRows: [[Day]] = []

    /// Full month name for the current `selectedMonth` (e.g. `"February"`).
    private(set) var currentMonthString: String = ""

    /// Four-digit year string for the current `selectedMonth` (e.g. `"2026"`).
    private(set) var yearString: String = ""

    /// Zero-based row index of the week containing the selected date.
    ///
    /// Used to drive the collapse animation offset in `HomeCalendarSectionView`.
    private(set) var monthProgress: CGFloat = 0.0

    // MARK: - Static Date Formatters

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMMM"; return f
    }()

    private static let yearFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy"; return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "dd"; return f
    }()

    private static let logFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    // MARK: - Layout Constants
    //
    // Consumed directly by HomeCalendarSectionView to compute extendedHeight,
    // compactHeight, and intermediate animation frames.
    // Adjust here to update the entire layout without touching any View files.

    /// Height of the month + year title row (including navigation chevrons).
    let titleHeight: CGFloat = 60.0

    /// Vertical spacing between the title row and the weekday label row.
    let titleBottomSpacing: CGFloat = 6.0

    /// Height of the row displaying abbreviated weekday names (Sun, Mon, …).
    let weekLabelHeight: CGFloat = 18.0

    /// Height of a single week row in the grid.
    let rowHeight: CGFloat = 38.0

    /// Vertical padding applied to the compact sticky capsule.
    let compactCapsuleVerticalPadding: CGFloat = UIConstants.Layout.homeCalendarCompactCapsuleVerticalPadding

    /// Horizontal padding applied to the compact sticky capsule.
    let compactCapsuleHorizontalPadding: CGFloat = UIConstants.Layout.homeCalendarCompactCapsuleHorizontalPadding

    /// Corner radius of the compact sticky capsule.
    let compactCapsuleCornerRadius: CGFloat = 28.0

    /// Rendered height of the compact sticky capsule.
    var compactCapsuleHeight: CGFloat {
        weekLabelHeight + rowHeight + (compactCapsuleVerticalPadding * 2)
    }

    /// Top padding applied when the header is fully expanded.
    var topPaddingExpanded: CGFloat {
        UIConstants.Layout.homeCalendarExpandedTopPadding
    }

    /// Top padding applied when the header is fully collapsed (compact sticky state).
    var topPaddingCollapsed: CGFloat {
        UIConstants.Layout.homeCalendarCollapsedTopPadding
    }

    /// Bottom padding below the calendar grid.
    let bottomPadding: CGFloat = 0.0

    // MARK: - Initializer

    init() {
        let initialCalendar = AppPreferences.shared.resolvedCalendar
        calendar = initialCalendar
        let today = initialCalendar.startOfDay(for: Date())
        selectedDate = today
        selectedMonth = CalendarViewModel.monthStart(for: today, calendar: initialCalendar)
        preferredDayOfMonth = initialCalendar.component(.day, from: today)
    }

    // MARK: - Setup

    /// Triggers the initial grid calculation the first time the view mounts.
    ///
    /// Deferred from `init` so we don't block SwiftUI's struct evaluation loop
    /// with heavy DateFormatter work during app startup.
    func setupIfNeeded() {
        if monthRows.isEmpty {
            calculateMonthData()
        }
    }

    // MARK: - Public Actions

    /// Advances or rewinds both `selectedMonth` and `selectedDate` by one calendar month.
    ///
    /// - Parameter increment: `true` to advance forward, `false` to go back.
    func monthUpdate(increment: Bool) {
        applyMonthOffset(increment ? 1 : -1)
    }

    /// Updates `selectedDate` and triggers a grid refresh to update `isSelected` flags.
    ///
    /// - Parameter date: The newly selected calendar date.
    func selectDate(_ date: Date) {
        let normalizedDate = calendar.startOfDay(for: date)
        preferredDayOfMonth = calendar.component(.day, from: normalizedDate)
        updateSelection(date: normalizedDate, visibleMonth: normalizedDate)
    }

    /// Rebuilds the calendar grid when the preferred start weekday changes.
    func applyWeekStartPreference(_ preference: AppWeekStartDayPreference) {
        let updatedCalendar = preference == .system
            ? Calendar.autoupdatingCurrent
            : preference.resolvedCalendar
        guard calendar.firstWeekday != updatedCalendar.firstWeekday else { return }
        calendar = updatedCalendar
        selectedDate = calendar.startOfDay(for: selectedDate)
        selectedMonth = CalendarViewModel.monthStart(for: selectedMonth, calendar: calendar)
        preferredDayOfMonth = calendar.component(.day, from: selectedDate)
        calculateMonthData()
    }

    func applyMonthOffset(_ value: Int) {
        guard
            let month = calendar.date(byAdding: .month, value: value, to: selectedMonth),
            let date = clampedDate(
                day: preferredDayOfMonth,
                in: CalendarViewModel.monthStart(for: month, calendar: calendar)
            )
        else { return }
        updateSelection(date: date, visibleMonth: month)
    }

    func monthSnapshot(offsetBy months: Int) -> MonthSnapshot {
        let visibleMonth: Date
        if months == 0 {
            visibleMonth = selectedMonth
        } else {
            visibleMonth = calendar.date(byAdding: .month, value: months, to: selectedMonth) ?? selectedMonth
        }

        let monthAnchor = CalendarViewModel.monthStart(for: visibleMonth, calendar: calendar)
        return snapshot(for: monthAnchor, selectedDate: selectedDate)
    }

    // MARK: - Private: Grid Calculation

    /// Rebuilds `monthRows` and `monthProgress` for the current `selectedMonth`.
    ///
    /// **Algorithm**:
    /// 1. Generate all dates within the month.
    /// 2. Prepend days from the previous month to align the first weekday column.
    /// 3. Append days from the next month to fill the trailing cells in the last row.
    /// 4. Chunk the flat array into rows of 7.
    /// 5. Record the row index of the selected date as `monthProgress` for the collapse animation.
    private func calculateMonthData() {
        let snapshot = snapshot(for: selectedMonth, selectedDate: selectedDate)
        currentMonthString = snapshot.monthString
        yearString = snapshot.yearString
        monthRows = snapshot.rows
        monthProgress = snapshot.monthProgress
    }

    private func updateSelection(date: Date, visibleMonth: Date) {
        selectedDate = calendar.startOfDay(for: date)
        selectedMonth = CalendarViewModel.monthStart(for: visibleMonth, calendar: calendar)
        calculateMonthData()
    }

    private func clampedDate(day: Int, in month: Date) -> Date? {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return nil }
        var components = calendar.dateComponents([.year, .month], from: month)
        components.day = min(day, range.count)
        return calendar.date(from: components)
    }

    private static func monthStart(for date: Date, calendar: Calendar) -> Date {
        let normalizedDate = calendar.startOfDay(for: date)
        let components = calendar.dateComponents([.year, .month], from: normalizedDate)
        return calendar.date(from: components) ?? normalizedDate
    }

    private func snapshot(for visibleMonth: Date, selectedDate: Date) -> MonthSnapshot {
        let monthAnchor = CalendarViewModel.monthStart(for: visibleMonth, calendar: calendar)
        let days = buildDays(for: monthAnchor, selectedDate: selectedDate)

        var rows: [[Day]] = []
        for index in stride(from: 0, to: days.count, by: 7) {
            rows.append(Array(days[index..<min(index + 7, days.count)]))
        }

        let selectedRow: CGFloat
        if let index = days.firstIndex(where: { $0.isSelected }) {
            selectedRow = CGFloat(index / 7).rounded(.down)
        } else {
            selectedRow = 0
        }

        return MonthSnapshot(
            monthStart: monthAnchor,
            monthString: Self.monthFormatter.string(from: monthAnchor),
            yearString: Self.yearFormatter.string(from: monthAnchor),
            rows: rows,
            monthProgress: selectedRow
        )
    }

    private func buildDays(for monthAnchor: Date, selectedDate: Date) -> [Day] {
        var days: [Day] = []

        guard let range = calendar.range(of: .day, in: .month, for: monthAnchor) else {
            return []
        }

        let monthDates = range.compactMap { value -> Date? in
            calendar.date(byAdding: .day, value: value - 1, to: monthAnchor)
        }

        guard let firstDate = monthDates.first, let lastDate = monthDates.last else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: firstDate)
        let leadingPadding = (firstWeekday - calendar.firstWeekday + 7) % 7
        for index in Array(0..<leadingPadding).reversed() {
            if let date = calendar.date(byAdding: .day, value: -index - 1, to: firstDate) {
                days.append(Day(
                    shortSymbol: Self.dayFormatter.string(from: date),
                    date: date,
                    dateString: Self.logFormatter.string(from: date),
                    ignored: true,
                    isSelected: calendar.isDate(date, inSameDayAs: selectedDate)
                ))
            }
        }

        for date in monthDates {
            days.append(Day(
                shortSymbol: Self.dayFormatter.string(from: date),
                date: date,
                dateString: Self.logFormatter.string(from: date),
                ignored: false,
                isSelected: calendar.isDate(date, inSameDayAs: selectedDate)
            ))
        }

        let minimumVisibleCells = 42
        let trailingPadding = max((7 - (days.count % 7)) % 7, minimumVisibleCells - days.count)
        if trailingPadding > 0 {
            for index in 0..<trailingPadding {
                if let date = calendar.date(byAdding: .day, value: index + 1, to: lastDate) {
                    days.append(Day(
                        shortSymbol: Self.dayFormatter.string(from: date),
                        date: date,
                        dateString: Self.logFormatter.string(from: date),
                        ignored: true,
                        isSelected: calendar.isDate(date, inSameDayAs: selectedDate)
                    ))
                }
            }
        }

        return days
    }
}
