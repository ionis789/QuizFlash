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
    /// Last-opened date shown in row metadata when available.
    let lastOpenedAt: Date?
    /// Denormalized card count, projected once on the main context.
    let cardCount: Int
    /// Whether the deck currently contains at least one flashcard.
    let hasFlashcards: Bool
    /// Whether the deck currently contains at least one quiz card.
    let hasQuizCards: Bool
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
    static func makeDeckSnapshots(
        from decks: [DeckModel],
        includeCardKindPresence: Bool = true
    ) -> [LibraryDeckRowSnapshot] {
        decks.map { deck in
            let cardKinds = includeCardKindPresence
                ? Self.cardKindPresence(for: deck)
                : (hasFlashcards: false, hasQuizCards: false)
            return LibraryDeckRowSnapshot(
                id: deck.persistentModelID,
                title: deck.title,
                colorHex: deck.colorHex,
                createdAt: deck.createdAt,
                editedAt: deck.editedAt,
                lastOpenedAt: deck.lastOpenedAt,
                cardCount: deck.cardCount,
                hasFlashcards: cardKinds.hasFlashcards,
                hasQuizCards: cardKinds.hasQuizCards,
                folderTitle: deck.folder?.title
            )
        }
    }

    /// Reads card kinds once while building immutable row snapshots.
    private static func cardKindPresence(for deck: DeckModel) -> (hasFlashcards: Bool, hasQuizCards: Bool) {
        guard deck.cardCount > 0 else {
            return (false, false)
        }

        var hasFlashcards = false
        var hasQuizCards = false

        for card in deck.cards {
            switch card.kind {
            case .flashcard:
                hasFlashcards = true
            case .quiz:
                hasQuizCards = true
            }

            if hasFlashcards && hasQuizCards {
                break
            }
        }

        return (hasFlashcards, hasQuizCards)
    }

    /// Builds and sorts sections from a flat array of decks based on the active `SortOrder`.
    static func sections(
        decks: [LibraryDeckRowSnapshot],
        sortOrder: SortOrder,
        locale: Locale,
        calendar: Calendar
    ) -> [DeckSection] {
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
            return [
                DeckSection(
                    id: "all",
                    title: AppLocalization.string("All Decks", locale: locale),
                    decks: sortedAll,
                    dateForSorting: Date()
                )
            ]
        }

        let groups = Dictionary(grouping: sortedAll) { deck -> Date in
            let dateToCheck = sortOrder == .lastEdited ? deck.editedAt : deck.createdAt
            return calendar.startOfDay(for: dateToCheck)
        }

        var sections: [DeckSection] = groups.map { (startOfDay, decksInGroup) in
            DeckSection(
                id: "section-\(startOfDay.timeIntervalSinceReferenceDate)",
                title: Self.sectionTitle(for: startOfDay, calendar: calendar, locale: locale),
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

    /// Human-readable section title for a date (Today, Yesterday, This Week, etc.).
    static func sectionTitle(for date: Date, calendar: Calendar, locale: Locale) -> String {
        if calendar.isDateInToday(date) {
            return AppLocalization.string("Today", locale: locale)
        }
        if calendar.isDateInYesterday(date) {
            return AppLocalization.string("Yesterday", locale: locale)
        }

        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let startOfDate = calendar.startOfDay(for: date)
        let dayDistance = calendar.dateComponents([.day], from: startOfDate, to: startOfToday).day ?? .max

        if (2...6).contains(dayDistance) {
            let weekFormatter = DateFormatter()
            weekFormatter.locale = locale
            weekFormatter.calendar = calendar
            weekFormatter.setLocalizedDateFormatFromTemplate("EEEE")
            return weekFormatter.string(from: date)
        }

        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            let monthDayFormatter = DateFormatter()
            monthDayFormatter.locale = locale
            monthDayFormatter.calendar = calendar
            monthDayFormatter.setLocalizedDateFormatFromTemplate("MMMMd")
            return monthDayFormatter.string(from: date)
        }

        let monthDayYearFormatter = DateFormatter()
        monthDayYearFormatter.locale = locale
        monthDayYearFormatter.calendar = calendar
        monthDayYearFormatter.setLocalizedDateFormatFromTemplate("yMMMMd")
        return monthDayYearFormatter.string(from: date)
    }
}
