//
//  LibraryGrouping.swift
//  QuizFlash
//
//  Pure logic: deck grouping and section titles for Library UI.
//

import Foundation
import SwiftData

// MARK: - Deck Row Snapshot

/// Lightweight deck projection used by the Library scroll surface.
///
/// iOS 17 is particularly sensitive to SwiftData model observation on large
/// scrolling surfaces. The Library list therefore renders immutable value
/// snapshots instead of reading `DeckModel` directly inside each row.
struct LibraryDeckRowSnapshot: Identifiable, Equatable, Sendable {
    /// Stable identifier used for navigation, selection, and diffing.
    let id: PersistentIdentifier
    /// Display title shown in the deck row.
    let title: String
    /// Persisted accent tint used by the row separator.
    let colorHex: String
    /// Original creation date used by section sorting.
    let createdAt: Date
    /// Last edit date used by section sorting and metadata display.
    let editedAt: Date
    /// Denormalized card count, projected once on the main context.
    let cardCount: Int
    /// Optional parent folder title rendered as secondary metadata.
    let folderTitle: String?
}

// MARK: - Deck Action Target

/// Minimal deck payload kept in UI state for destructive and menu actions.
struct LibraryDeckActionTarget: Identifiable, Equatable, Sendable {
    /// Stable identifier for later `safeModel` resolution.
    let id: PersistentIdentifier
    /// Frozen title used in confirmation dialogs without retaining the model.
    let title: String
}

// MARK: - Deck Section (For List/Gallery Grouping)

/// Represents a grouped section of decks tailored for list or gallery presentation.
struct DeckSection: Identifiable, Equatable, Sendable {
    /// A unique identifier for the section.
    let id: String
    /// The display title for the section (e.g., "Today", "This Week").
    let title: String
    /// Immutable deck rows rendered inside the section.
    let decks: [LibraryDeckRowSnapshot]
    /// The date reference used for sorting this section relative to others.
    let dateForSorting: Date
}

// MARK: - Grouping Helper

/// A utility enum providing logic to group a list of decks into sections.
nonisolated enum LibraryGrouping {
    /// Projects SwiftData decks into value snapshots safe for long scroll surfaces.
    static func makeDeckSnapshots(from decks: [DeckModel]) -> [LibraryDeckRowSnapshot] {
        decks.map { deck in
            LibraryDeckRowSnapshot(
                id: deck.persistentModelID,
                title: deck.title,
                colorHex: deck.colorHex,
                createdAt: deck.createdAt,
                editedAt: deck.editedAt,
                cardCount: deck.cardCount,
                folderTitle: deck.folder?.title
            )
        }
    }

    /// Builds and sorts sections from a flat array of decks based on the active `SortOrder`.
    static func sections(decks: [LibraryDeckRowSnapshot], sortOrder: SortOrder) -> [DeckSection] {
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
                id: "section-\(startOfDay.timeIntervalSinceReferenceDate)",
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

    private static let monthDayYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM d, yyyy"
        return f
    }()

    /// Human-readable section title for a date (Today, Yesterday, This Week, etc.).
    static func sectionTitle(for date: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }

        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let startOfDate = calendar.startOfDay(for: date)
        let dayDistance = calendar.dateComponents([.day], from: startOfDate, to: startOfToday).day ?? .max

        if (2...6).contains(dayDistance) {
            return weekFormatter.string(from: date)
        }

        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return monthDayFormatter.string(from: date)
        }

        return monthDayYearFormatter.string(from: date)
    }
}
