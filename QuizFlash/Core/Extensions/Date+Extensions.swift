//
//  Date+Extensions.swift
//  QuizFlash
//

import SwiftUI

// MARK: - Date Extensions

extension Date {

    // MARK: - Current Period Helpers

    /// Returns the seven `Day` values for the current calendar week,
    /// starting from the locale's first day of the week.
    static var currentWeek: [Day] {
        let calendar = Calendar.current
        guard let firstWeekDay = calendar.dateInterval(of: .weekOfMonth, for: .now)?.start else {
            return []
        }

        var week: [Day] = []
        for index in 0..<7 {
            if let day = calendar.date(byAdding: .day, value: index, to: firstWeekDay) {
                week.append(.init(date: day))
            }
        }

        return week
    }

    /// Returns all `Day` values for the current calendar month, padded with
    /// leading and trailing days from adjacent months to fill a complete grid.
    static var currentMonth: [Day] {
        return extractDates(for: .now)
    }

    // MARK: - Grid Date Extraction

    /// Returns up to 42 `Day` values covering the full calendar grid for the
    /// month containing `month`, including padding days from adjacent months.
    ///
    /// 42 slots accommodate the maximum possible 6-row calendar grid (7 columns × 6 rows).
    /// Days outside the target month have `isCurrentMonth` set to `false`,
    /// allowing them to be rendered as greyed-out cells.
    ///
    /// - Parameter month: Any date within the desired calendar month.
    /// - Returns: An array of up to 42 `Day` values, or an empty array on failure.
    static func extractDates(for month: Date) -> [Day] {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: month),
              let firstDayOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: monthInterval.start)) else {
            return []
        }

        var days: [Day] = []
        guard let range = calendar.range(of: .day, in: .month, for: firstDayOfMonth) else {
            return []
        }
        _ = range // used only for bounds validation

        // Calculate how many padding days precede the first day of the month.
        let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth)
        let firstWeekdayIndex = firstWeekday - calendar.firstWeekday
        let paddingOffset = firstWeekdayIndex < 0 ? firstWeekdayIndex + 7 : firstWeekdayIndex

        // Build 42 slots to fill a 6-row calendar grid.
        for index in 0..<42 {
            let dayOffset = index - paddingOffset
            if let date = calendar.date(byAdding: .day, value: dayOffset, to: firstDayOfMonth) {
                var day = Day(date: date)
                day.isCurrentMonth = calendar.isDate(date, equalTo: month, toGranularity: .month)
                days.append(day)
            }
        }

        return days
    }

    // MARK: - Formatting

    /// Formats the date using the given `DateFormatter` format string and returns
    /// the result as a `String`.
    ///
    /// - Parameter format: A `DateFormatter`-compatible format string, e.g. `"dd MMM yyyy"`.
    /// - Returns: The formatted date string.
    func string(_ format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.string(from: self)
    }

    // MARK: - Comparison

    /// Returns `true` if `self` and `date` fall on the same calendar day.
    ///
    /// - Parameter date: The date to compare against. Returns `false` if `nil`.
    func isSame(_ date: Date?) -> Bool {
        guard let date else { return false }
        return Calendar.current.isDate(self, inSameDayAs: date)
    }

    // MARK: - Day

    /// A value type representing a single calendar day in a date grid.
    struct Day: Identifiable, Hashable {

        /// A stable unique identifier for this day (UUID string).
        var id: String = UUID().uuidString

        /// The underlying `Date` value for this calendar day.
        var date: Date

        /// `true` when this day belongs to the month being displayed;
        /// `false` for padding days from adjacent months.
        var isCurrentMonth: Bool = true
    }
}
