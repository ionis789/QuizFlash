//
//  Date+Extensions.swift
//  QuizFlash
//

import SwiftUI

extension Date {
    /// Gives the current week dates
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
    
    /// Gives the dates for the current month
    static var currentMonth: [Day] {
        return extractDates(for: .now)
    }
    
    /// Helper to extract all dates for a given month, padded with previous/next month days to complete the visual grid rows
    static func extractDates(for month: Date) -> [Day] {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: month),
              let firstDayOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: monthInterval.start)) else {
            return []
        }
        
        var days: [Day] = []
        let range = calendar.range(of: .day, in: .month, for: firstDayOfMonth)!
        
        // Find the week day of the first day to calculate padding
        let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth)
        
        // Get previous month padding (assuming Sunday is 1, Monday is 2. Adjust if Monday is first day)
        // Adjusting firstWeekday so Monday=1, Sunday=7 if desired, but Apple defaults to system Locale.
        // Let's use standard default Calendar behavior where startOfWeek is Sunday or Monday based on locale.
        let firstWeekdayIndex = firstWeekday - calendar.firstWeekday
        let paddingOffset = firstWeekdayIndex < 0 ? firstWeekdayIndex + 7 : firstWeekdayIndex
        
        for index in 0..<42 { // A typical 6 row calendar has 42 days minimum to fit all months
            let dayOffset = index - paddingOffset
            if let date = calendar.date(byAdding: .day, value: dayOffset, to: firstDayOfMonth) {
                // If you only want exact current month, you can filter `calendar.isDate(date, equalTo: month, toGranularity: .month)`
                // But typically UI needs the greyed out days from adjacent months too.
                var day = Day(date: date)
                day.isCurrentMonth = calendar.isDate(date, equalTo: month, toGranularity: .month)
                days.append(day)
            }
        }
        
        return days
    }
    
    /// Convert date to string in the given format
    func string(_ format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        
        return formatter.string(from: self)
    }
    
    /// Check if both the dates are same
    func isSame(_ date: Date?) -> Bool {
        guard let date else { return false }
        return Calendar.current.isDate(self, inSameDayAs: date)
    }
    
    struct Day: Identifiable, Hashable {
        var id: String = UUID().uuidString
        var date: Date
        var isCurrentMonth: Bool = true
        /// Other additional Properties as per your needs!
    }
}
