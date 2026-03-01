//
//  LibraryGrouping.swift
//  QuizFlash
//
//  Pure logic: deck grouping and section titles for Library UI.
//

import Foundation

// MARK: - Deck Section (for list/gallery grouping)

struct DeckSection: Identifiable, Equatable {
    let id: String
    let title: String
    let decks: [DeckModel]
    let dateForSorting: Date
}

// MARK: - Grouping Helper

enum LibraryGrouping {
    /// Builds sections from decks based on sort order (by date or single "All Decks").
    static func sections(decks: [DeckModel], sortOrder: SortOrder) -> [DeckSection] {
        let sortedAll = decks.sorted { d1, d2 in
            switch sortOrder {
            case .newest: return d1.createdAt > d2.createdAt
            case .oldest: return d1.createdAt < d2.createdAt
            case .lastEdited: return d1.editedAt > d2.editedAt
            case .alphabetical: return d1.title.localizedCaseInsensitiveCompare(d2.title) == .orderedAscending
            }
        }

        if sortOrder == .alphabetical {
            if sortedAll.isEmpty { return [] }
            return [DeckSection(id: "all", title: "All Decks", decks: sortedAll, dateForSorting: Date())]
        }

        let calendar = Calendar.current
        let groups = Dictionary(grouping: sortedAll) { deck -> Date in
            let dateToCheck = sortOrder == .lastEdited ? deck.editedAt : deck.createdAt
            return calendar.startOfDay(for: dateToCheck)
        }

        var sections: [DeckSection] = groups.map { (startOfDay, decksInGroup) in
            DeckSection(
                id: Self.sectionTitle(for: startOfDay, calendar: calendar),
                title: Self.sectionTitle(for: startOfDay, calendar: calendar),
                decks: decksInGroup,
                dateForSorting: startOfDay
            )
        }

        sections.sort { s1, s2 in
            switch sortOrder {
            case .newest, .lastEdited: return s1.dateForSorting > s2.dateForSorting
            case .oldest: return s1.dateForSorting < s2.dateForSorting
            default: return true
            }
        }
        return sections
    }

    // MARK: - Reusable Formatters
    // Reusing DateFormatter instances avoids massive memory allocations
    // and main thread blocking when grouping many decks.
    private static let weekFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()

    private static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM d"
        return f
    }()

    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    /// Human-readable section title for a date (Today, Yesterday, This Week, etc.).
    static func sectionTitle(for date: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let now = Date()
        if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            return "This Week - " + weekFormatter.string(from: date)
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .month) {
            return monthDayFormatter.string(from: date)
        }
        return monthYearFormatter.string(from: date)
    }
}
