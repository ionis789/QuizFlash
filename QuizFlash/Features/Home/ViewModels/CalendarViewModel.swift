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

    /// `true` when this day is today. Precomputed with the grid so cells do
    /// not call Calendar APIs during scroll-driven render passes.
    var isToday: Bool = false

    /// Stable identity so calendar cells do not churn during scroll-only updates.
    var id: String { dateString }

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

    private struct MonthGridCacheEntry {
        let monthString: String
        let yearString: String
        let rows: [[Day]]
        let rowIndexByDateString: [String: CGFloat]
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

    // MARK: - Cached Output (read-only outside this class)

    /// All weeks of the current month, each sub-array containing exactly 7 `Day` values.
    private(set) var monthRows: [[Day]] = []

    /// Full month name for the current `selectedMonth` (e.g. `"February"`).
    private(set) var currentMonthString: String = ""

    /// Four-digit year string for the current `selectedMonth` (e.g. `"2026"`).
    private(set) var yearString: String = ""

    /// Localized weekday labels ordered by the active first weekday preference.
    private(set) var orderedWeekdaySymbols: [String] = []

    /// Zero-based row index of the week containing the selected date.
    ///
    /// Used to drive the collapse animation offset in `HomeCalendarSectionView`.
    private(set) var monthProgress: CGFloat = 0.0

    /// Reusable per-month grid cache so month paging does not regenerate the full
    /// day matrix and date formatting payloads every time the visible month changes.
    private var monthGridCache: [Date: MonthGridCacheEntry] = [:]

    /// Last locale identifier used for cached month titles and day symbols.
    private var presentationLocaleIdentifier: String = AppPreferences.shared.resolvedLocale.identifier

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
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
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
        var initialCalendar = AppPreferences.shared.resolvedCalendar
        initialCalendar.locale = AppPreferences.shared.resolvedLocale
        calendar = initialCalendar
        let today = initialCalendar.startOfDay(for: Date())
        selectedDate = today
        selectedMonth = CalendarViewModel.monthStart(for: today, calendar: initialCalendar)
        orderedWeekdaySymbols = CalendarViewModel.orderedWeekdaySymbols(for: initialCalendar)
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

    /// Advances or rewinds the visible month without changing the selected day.
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
        updateSelection(date: normalizedDate, visibleMonth: normalizedDate)
    }

    /// Rebuilds the calendar grid when the preferred start weekday changes.
    func applyWeekStartPreference(_ preference: AppWeekStartDayPreference) {
        var updatedCalendar = preference == .system
            ? Calendar.autoupdatingCurrent
            : preference.resolvedCalendar
        updatedCalendar.locale = AppPreferences.shared.resolvedLocale
        guard calendar.firstWeekday != updatedCalendar.firstWeekday else { return }
        calendar = updatedCalendar
        orderedWeekdaySymbols = CalendarViewModel.orderedWeekdaySymbols(for: updatedCalendar)
        monthGridCache.removeAll(keepingCapacity: true)
        selectedDate = calendar.startOfDay(for: selectedDate)
        selectedMonth = CalendarViewModel.monthStart(for: selectedMonth, calendar: calendar)
        calculateMonthData()
    }

    func applyMonthOffset(_ value: Int) {
        guard
            let month = calendar.date(byAdding: .month, value: value, to: selectedMonth)
        else { return }
        selectedMonth = CalendarViewModel.monthStart(for: month, calendar: calendar)
        calculateMonthData()
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
        refreshPresentationLocaleIfNeeded()
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

    private static func monthStart(for date: Date, calendar: Calendar) -> Date {
        let normalizedDate = calendar.startOfDay(for: date)
        let components = calendar.dateComponents([.year, .month], from: normalizedDate)
        return calendar.date(from: components) ?? normalizedDate
    }

    private func cachedMonthGrid(for monthAnchor: Date) -> MonthGridCacheEntry {
        refreshPresentationLocaleIfNeeded()

        if let cached = monthGridCache[monthAnchor] {
            return cached
        }

        let days = buildDays(for: monthAnchor)
        var rows: [[Day]] = []
        rows.reserveCapacity(max(1, days.count / 7))

        for index in stride(from: 0, to: days.count, by: 7) {
            rows.append(Array(days[index..<min(index + 7, days.count)]))
        }

        var rowIndexByDateString: [String: CGFloat] = [:]
        rowIndexByDateString.reserveCapacity(days.count)
        for (rowIndex, row) in rows.enumerated() {
            let resolvedRowIndex = CGFloat(rowIndex)
            for day in row {
                rowIndexByDateString[day.dateString] = resolvedRowIndex
            }
        }

        let cacheEntry = MonthGridCacheEntry(
            monthString: localizedMonthString(for: monthAnchor),
            yearString: localizedYearString(for: monthAnchor),
            rows: rows,
            rowIndexByDateString: rowIndexByDateString
        )
        monthGridCache[monthAnchor] = cacheEntry
        return cacheEntry
    }

    private func snapshot(for visibleMonth: Date, selectedDate: Date) -> MonthSnapshot {
        let monthAnchor = CalendarViewModel.monthStart(for: visibleMonth, calendar: calendar)
        let cachedGrid = cachedMonthGrid(for: monthAnchor)
        let selectedKey = Self.logFormatter.string(from: calendar.startOfDay(for: selectedDate))
        let selectedRow = cachedGrid.rowIndexByDateString[selectedKey] ?? 0
        let rows: [[Day]]

        if cachedGrid.rowIndexByDateString[selectedKey] != nil {
            rows = cachedGrid.rows.map { row in
                row.map { day in
                    var resolvedDay = day
                    resolvedDay.isSelected = day.dateString == selectedKey
                    return resolvedDay
                }
            }
        } else {
            rows = cachedGrid.rows
        }

        return MonthSnapshot(
            monthStart: monthAnchor,
            monthString: cachedGrid.monthString,
            yearString: cachedGrid.yearString,
            rows: rows,
            monthProgress: selectedRow
        )
    }

    private func buildDays(for monthAnchor: Date) -> [Day] {
        refreshPresentationLocaleIfNeeded()
        var days: [Day] = []

        guard let range = calendar.range(of: .day, in: .month, for: monthAnchor) else {
            return []
        }

        let monthDates = range.compactMap { value -> Date? in
            calendar.date(byAdding: .day, value: value - 1, to: monthAnchor)
        }
        let todayKey = Self.logFormatter.string(from: calendar.startOfDay(for: Date()))

        guard let firstDate = monthDates.first, let lastDate = monthDates.last else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: firstDate)
        let leadingPadding = (firstWeekday - calendar.firstWeekday + 7) % 7
        for index in Array(0..<leadingPadding).reversed() {
            if let date = calendar.date(byAdding: .day, value: -index - 1, to: firstDate) {
                let dateString = Self.logFormatter.string(from: date)
                days.append(Day(
                    shortSymbol: localizedDaySymbol(for: date),
                    date: date,
                    dateString: dateString,
                    ignored: true,
                    isToday: dateString == todayKey
                ))
            }
        }

        for date in monthDates {
            let dateString = Self.logFormatter.string(from: date)
            days.append(Day(
                shortSymbol: localizedDaySymbol(for: date),
                date: date,
                dateString: dateString,
                ignored: false,
                isToday: dateString == todayKey
            ))
        }

        let trailingPadding = (7 - (days.count % 7)) % 7
        if trailingPadding > 0 {
            for index in 0..<trailingPadding {
                if let date = calendar.date(byAdding: .day, value: index + 1, to: lastDate) {
                    let dateString = Self.logFormatter.string(from: date)
                    days.append(Day(
                        shortSymbol: localizedDaySymbol(for: date),
                        date: date,
                        dateString: dateString,
                        ignored: true,
                        isToday: dateString == todayKey
                    ))
                }
            }
        }

        return days
    }

    private func refreshPresentationLocaleIfNeeded() {
        let resolvedLocale = AppPreferences.shared.resolvedLocale
        let localeIdentifier = resolvedLocale.identifier
        guard presentationLocaleIdentifier != localeIdentifier else { return }

        presentationLocaleIdentifier = localeIdentifier
        monthGridCache.removeAll(keepingCapacity: true)
        calendar.locale = resolvedLocale
        orderedWeekdaySymbols = CalendarViewModel.orderedWeekdaySymbols(for: calendar)
    }

    private static func orderedWeekdaySymbols(for calendar: Calendar) -> [String] {
        let symbols = calendar.shortWeekdaySymbols
        let startIndex = max(calendar.firstWeekday - 1, 0)
        return Array(symbols[startIndex...]) + Array(symbols[..<startIndex])
    }

    private func localizedMonthString(for date: Date) -> String {
        Self.monthFormatter.locale = AppPreferences.shared.resolvedLocale
        Self.monthFormatter.calendar = calendar
        return Self.monthFormatter.string(from: date)
    }

    private func localizedYearString(for date: Date) -> String {
        Self.yearFormatter.locale = AppPreferences.shared.resolvedLocale
        Self.yearFormatter.calendar = calendar
        return Self.yearFormatter.string(from: date)
    }

    private func localizedDaySymbol(for date: Date) -> String {
        Self.dayFormatter.locale = AppPreferences.shared.resolvedLocale
        Self.dayFormatter.calendar = calendar
        return Self.dayFormatter.string(from: date)
    }
}
