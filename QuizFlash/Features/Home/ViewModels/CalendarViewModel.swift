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
final class CalendarViewModel {

    // MARK: - State

    /// The month currently displayed in the calendar grid.
    ///
    /// Setting this triggers a full grid recalculation via `calculateMonthData()`.
    var selectedMonth: Date = Date() { didSet { calculateMonthData() } }

    /// The date highlighted with the selection indicator.
    ///
    /// Setting this updates `isSelected` on all day cells via `calculateMonthData()`.
    var selectedDate: Date = Date() { didSet { calculateMonthData() } }

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
        let f = DateFormatter(); f.dateFormat = "YYYY"; return f
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
    let titleHeight: CGFloat = 68.0

    /// Vertical spacing between the title row and the weekday label row.
    let titleBottomSpacing: CGFloat = 12.0

    /// Height of the row displaying abbreviated weekday names (Sun, Mon, …).
    let weekLabelHeight: CGFloat = 24.0

    /// Height of a single week row in the grid.
    let rowHeight: CGFloat = 44.0

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

    init() {}

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
        let calendar = Calendar.current
        let value = increment ? 1 : -1
        guard
            let month = calendar.date(byAdding: .month, value: value, to: selectedMonth),
            let date  = calendar.date(byAdding: .month, value: value, to: selectedDate)
        else { return }
        selectedMonth = month
        selectedDate  = date
    }

    /// Updates `selectedDate` and triggers a grid refresh to update `isSelected` flags.
    ///
    /// - Parameter date: The newly selected calendar date.
    func selectDate(_ date: Date) {
        selectedDate = date
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
        currentMonthString = Self.monthFormatter.string(from: selectedMonth)
        yearString = Self.yearFormatter.string(from: selectedMonth)

        var days: [Day] = []
        let calendar = Calendar.current

        guard let range = calendar.range(of: .day, in: .month, for: selectedMonth)?
            .compactMap({ value -> Date? in
                calendar.date(byAdding: .day, value: value - 1, to: selectedMonth)
            })
        else { return }

        // Prepend trailing days from the previous month.
        let firstWeekday = calendar.component(.weekday, from: range.first!)
        for index in Array(0..<firstWeekday - 1).reversed() {
            if let date = calendar.date(byAdding: .day, value: -index - 1, to: range.first!) {
                days.append(Day(
                    shortSymbol: Self.dayFormatter.string(from: date),
                    date: date,
                    dateString: Self.logFormatter.string(from: date),
                    ignored: true,
                    isSelected: calendar.isDate(date, inSameDayAs: selectedDate)
                ))
            }
        }

        // Add all days within the current month.
        for date in range {
            days.append(Day(
                shortSymbol: Self.dayFormatter.string(from: date),
                date: date,
                dateString: Self.logFormatter.string(from: date),
                ignored: false,
                isSelected: calendar.isDate(date, inSameDayAs: selectedDate)
            ))
        }

        // Append leading days from the next month to complete the final row.
        let lastWeekday = 7 - calendar.component(.weekday, from: range.last!)
        if lastWeekday > 0 {
            for index in 0..<lastWeekday {
                if let date = calendar.date(byAdding: .day, value: index + 1, to: range.last!) {
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

        // Chunk the flat array into week rows.
        var rows: [[Day]] = []
        for i in stride(from: 0, to: days.count, by: 7) {
            rows.append(Array(days[i..<min(i + 7, days.count)]))
        }
        self.monthRows = rows

        // Record the selected day's row index for the collapse animation offset.
        if let index = days.firstIndex(where: { $0.isSelected }) {
            self.monthProgress = CGFloat(index / 7).rounded(.down)
        } else {
            self.monthProgress = 0
        }
    }
}
