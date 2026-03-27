//
//  DeckViewModel.swift
//  QuizFlash
//
//  Manages all UI state and business logic for the Deck detail screen.
//
//  ## iOS 17 Memory-Safe Card Loading
//  All card fetches are delegated to `CardPreviewCache` (which uses a background actor).
//  The main `ModelContext` never reads a single `CardModel` — only `Sendable` value types
//  (`GridCardInfo`, `DeckStats`) cross the actor boundary.
//  This prevents the iOS 17 row-cache accumulation (+1 MB/cycle) bug.
//
//  ## Deletion Flow
//  Mutations still happen on the main context (they require the live `DeckModel`).
//  After `save()`, `allCardInfos` is updated in-memory for instant UI feedback, then
//  an async `loadSnapshot` refreshes accurate stats. No `deck.cards` read on main.

import SwiftUI
import SwiftData
import OSLog

// MARK: - Grid Card Info

/// A lightweight, `Sendable` value type representing one card's display data.
///
/// This is the only SwiftData-derived type that crosses actor boundaries in this
/// architecture. It contains no `ModelContext` references, preventing row-cache retention.
struct GridCardInfo: Identifiable, Equatable, Hashable, Sendable {

    let id: PersistentIdentifier
    let kind: CardKind
    let creationSource: CardCreationSource
    let conversionMetadata: CardConversionMetadata?
    let cardNumber: Int
    let interval: Int
    let reviewHistoryIsEmpty: Bool
    let isPinned: Bool
    let frontText: String
    let backText: String
    let frontPreviewText: String
    let backPreviewText: String
    let searchDocumentText: String
    let createdAt: Date
    let editedAt: Date

    var isConverted: Bool { conversionMetadata != nil }
}

// MARK: - Deck Progress Stats

/// A value type that bundles all pre-computed card-progress breakdown values.
///
/// Computed once inside `DeckViewModel` and passed wholesale to `DeckProgressView`,
/// keeping the view entirely dumb (no logic, no dependencies on `[GridCardInfo]`).
struct DeckProgressStats: Equatable {
    /// Number of cards that have never been reviewed.
    let newCards: Int
    /// Number of cards under active learning (reviewed but interval < 14 days).
    let learningCards: Int
    /// Number of cards considered mastered (interval ≥ 14 days).
    let masteredCards: Int
    /// Total denominator used for ratio calculations (always ≥ 1).
    let total: Int

    /// Fraction of mastered cards in [0, 1].
    var masteredRatio: Double { Double(masteredCards) / Double(total) }
    /// Fraction of learning cards in [0, 1].
    var learningRatio: Double { Double(learningCards) / Double(total) }
    /// Fraction of new cards in [0, 1].
    var newRatio: Double { Double(newCards) / Double(total) }

    /// Zero-state placeholder used before the first snapshot load.
    static let empty = DeckProgressStats(newCards: 0, learningCards: 0, masteredCards: 0, total: 1)
}

// MARK: - Deck View Model

/// The ViewModel for `DeckView`, managing card data, selection, search, sort, and export state.
///
/// Isolated to `@MainActor` and using `@Observable` for iOS 17+ observation.
/// The class is `final` as it is not designed to be subclassed.
@Observable
@MainActor
final class DeckViewModel {
    let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "QuizFlash",
        category: "DeckViewModel"
    )
    @ObservationIgnored var snapshotLoadTask: Task<Void, Never>?
    @ObservationIgnored var conversionTask: Task<Void, Never>?

    // MARK: - Selection State

    /// Whether the view is currently in multi-card selection mode.
    var isSelecting = false
    /// The set of card `PersistentIdentifier`s currently selected.
    var selectedCards: Set<PersistentIdentifier> = []
    /// Controls the destructive delete confirmation alert.
    var showDeleteConfirmation = false

    // MARK: - Card Data (Read-Only from Outside)

    /// All card infos for the current deck, updated by every `loadSnapshot` call.
    var allCardInfos: [GridCardInfo] = []
    /// Grouped and sorted card sections ready for consumption by `DeckCardGridView`.
    var cachedGroupedCards: [DeckCardGridView.CardSection] = []

    /// Spaced-repetition aggregate stats. Updated after every `loadSnapshot` call.
    var currentStats: DeckStats = .empty

    /// Pre-computed progress breakdown. Derived from `allCardInfos`; consumed by `DeckProgressView`.
    var progressStats: DeckProgressStats = .empty

    /// Lightweight compatibility counts used by deck play-mode surfaces.
    var playModeAvailability: PlayModeCardAvailability = .empty

    /// Compact readiness summary used by preview and deck-level diagnostics UI.
    var readinessSummary: DeckReadinessSummary {
        CardReadinessDiagnostics.deckSurfaceSummary(for: allCardInfos)
    }

    // MARK: - Scroll Restoration

    /// Persisted pixel scroll offset used by `ScrollPositionRestorer` in `DeckView`.
    var savedScrollOffset: CGFloat = 0

    // MARK: - Search

    /// Active search query; `nil` means no filter is applied.
    var searchQuery: String?

    // MARK: - Sorting

    /// Active sort order applied to the card grid.
    var sortOrder: SortOrder = .newest

    /// Active section grouping applied on top of the current sort order.
    var groupingMode: DeckCardGroupingMode = .chronological

    // MARK: - Export State

    /// `true` while an async deck export is in progress.
    var isExporting = false
    /// The locally exported file URL, set on successful export.
    var exportedURL: URL?
    /// Controls the system `ShareSheet` presentation.
    var showShareSheet = false
    /// Controls the export-error alert presentation.
    var showExportError = false
    /// Human-readable description of the last export error.
    var exportErrorMessage = ""

    // MARK: - Conversion State

    /// Mutable configuration shown in the deck conversion sheet.
    var conversionRequest: DeckCardConversionRequest?
    /// Live progress while a conversion run is underway.
    var conversionProgress: DeckCardConversionProgress?
    /// Final summary after a completed conversion run.
    var conversionSummary: DeckCardConversionSummary?
    /// Fatal conversion error shown inline in the sheet.
    var conversionErrorMessage: String?

    /// Whether the sheet is currently executing an AI conversion run.
    var isConvertingCards: Bool {
        conversionProgress != nil
    }

    // MARK: - Initialization

    /// Creates a new instance, optionally seeding an initial search query.
    /// - Parameter searchQuery: Pre-fill the search field (e.g. from a deep-link).
    init(searchQuery: String? = nil) {
        self.searchQuery = searchQuery
    }

    func exportDeck(_ deck: DeckModel) {
        isExporting = true
        Task {
            do {
                let url = try await DeckSharingManager.shared.exportDeck(deck)
                self.isExporting = false
                self.exportedURL = url
                self.showShareSheet = true
            } catch {
                self.isExporting = false
                self.exportErrorMessage = error.localizedDescription
                self.showExportError = true
            }
        }
    }

    // MARK: - Grouping & Filtering

    /// Applies the active search filter and sort order to the given card array,
    /// then writes the result into `cachedGroupedCards` for consumption by `DeckCardGridView`.
    ///
    /// Called after:
    /// - `loadSnapshot` (initial load and post-deletion stats refresh)
    /// - In-memory deletion (immediate visual update before async re-fetch)
    /// - Sort order or search query changes (triggered from `DeckView` via `.onChange`)
    ///
    /// - Parameter cards: The unfiltered, unsorted source array to process.
    func performGrouping(on cards: [GridCardInfo]) {
        var filtered = cards

        if let query = searchQuery,
            !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let tokens: [String] = query
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
            if !tokens.isEmpty {
                let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
                filtered = filtered.filter { card in
                    return tokens.allSatisfy { card.searchDocumentText.range(of: $0, options: options) != nil }
                }
            }
        }

        let sorted = filtered.sorted(by: compareCards(lhs:rhs:))

        let pinnedCards = sorted.filter(\.isPinned)
        let regularCards = sorted.filter { !$0.isPinned }
        var sections: [DeckCardGridView.CardSection] = []

        if !pinnedCards.isEmpty {
            sections.append(
                DeckCardGridView.CardSection(
                    id: "pinned",
                    title: "Pinned",
                    cards: pinnedCards,
                    dateForSorting: nil
                )
            )
        }

        let regularSections: [DeckCardGridView.CardSection]
        switch groupingMode {
        case .chronological:
            regularSections = buildChronologicalSections(from: regularCards)
        case .byCardType:
            regularSections = buildTypeSections(from: regularCards)
        }

        cachedGroupedCards = sections + regularSections
    }

    // MARK: - Date Formatters
    // Static formatters allocated once for the lifetime of the process.

    /// Formats a date as the full weekday name, e.g. "Monday".
    private static let weekFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE"; return f
    }()

    /// Formats a date as month and day, e.g. "March 7".
    private static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMMM d"; return f
    }()

    /// Formats a date as month and year, e.g. "March 2026".
    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; return f
    }()

    /// Returns a human-readable section title for a given calendar day.
    ///
    /// Produces "Today", "Yesterday", "This Week – Monday", "March 7", or "March 2026"
    /// depending on how far the date is from the current moment.
    ///
    /// - Parameters:
    ///   - date: The start-of-day `Date` to label.
    ///   - calendar: The calendar to use for comparison.
    /// - Returns: A localised section title string.
    private func sectionTitle(for date: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let now = Date()
        if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            return "This Week – " + Self.weekFormatter.string(from: date)
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .month) {
            return Self.monthDayFormatter.string(from: date)
        }
        return Self.monthYearFormatter.string(from: date)
    }

    private func buildChronologicalSections(from cards: [GridCardInfo]) -> [DeckCardGridView.CardSection] {
        guard !cards.isEmpty else { return [] }

        if sortOrder == .alphabetical {
            return [
                DeckCardGridView.CardSection(
                    id: "all",
                    title: "All Cards",
                    cards: cards,
                    dateForSorting: nil
                )
            ]
        }

        let calendar = Calendar.current
        let groups = Dictionary(grouping: cards) { card -> Date in
            let date = sortOrder == .lastEdited ? card.editedAt : card.createdAt
            return calendar.startOfDay(for: date)
        }

        return groups
            .map { startOfDay, cardsInGroup in
                let title = sectionTitle(for: startOfDay, calendar: calendar)
                return DeckCardGridView.CardSection(
                    id: title,
                    title: title,
                    cards: cardsInGroup,
                    dateForSorting: startOfDay
                )
            }
            .sorted { lhs, rhs in
                guard let lhsDate = lhs.dateForSorting, let rhsDate = rhs.dateForSorting else { return false }
                return sortOrder == .oldest ? lhsDate < rhsDate : lhsDate > rhsDate
            }
    }

    private func buildTypeSections(from cards: [GridCardInfo]) -> [DeckCardGridView.CardSection] {
        let groupedCards = Dictionary(grouping: cards, by: \.kind)

        return groupedCards
            .map { kind, cardsInGroup in
                DeckCardGridView.CardSection(
                    id: "kind-\(kind.rawValue)",
                    title: kind.sectionTitle,
                    cards: cardsInGroup.sorted(by: compareCards(lhs:rhs:)),
                    dateForSorting: sectionReferenceDate(for: cardsInGroup)
                )
            }
            .sorted(by: compareSections(lhs:rhs:))
    }

    private func compareCards(lhs: GridCardInfo, rhs: GridCardInfo) -> Bool {
        if lhs.isPinned != rhs.isPinned {
            return lhs.isPinned && !rhs.isPinned
        }

        switch sortOrder {
        case .newest:
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        case .oldest:
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        case .lastEdited:
            if lhs.editedAt != rhs.editedAt { return lhs.editedAt > rhs.editedAt }
        case .alphabetical:
            let comparison = lhs.frontText.localizedCaseInsensitiveCompare(rhs.frontText)
            if comparison != .orderedSame {
                return comparison == .orderedAscending
            }
        }

        if lhs.cardNumber != rhs.cardNumber {
            return lhs.cardNumber < rhs.cardNumber
        }

        return lhs.createdAt < rhs.createdAt
    }

    private func sectionReferenceDate(for cards: [GridCardInfo]) -> Date? {
        guard !cards.isEmpty else { return nil }

        switch sortOrder {
        case .newest:
            return cards.map(\.createdAt).max()
        case .oldest:
            return cards.map(\.createdAt).min()
        case .lastEdited:
            return cards.map(\.editedAt).max()
        case .alphabetical:
            return nil
        }
    }

    private func compareSections(
        lhs: DeckCardGridView.CardSection,
        rhs: DeckCardGridView.CardSection
    ) -> Bool {
        switch sortOrder {
        case .newest:
            if lhs.dateForSorting != rhs.dateForSorting {
                return (lhs.dateForSorting ?? .distantPast) > (rhs.dateForSorting ?? .distantPast)
            }
        case .oldest:
            if lhs.dateForSorting != rhs.dateForSorting {
                return (lhs.dateForSorting ?? .distantFuture) < (rhs.dateForSorting ?? .distantFuture)
            }
        case .lastEdited:
            if lhs.dateForSorting != rhs.dateForSorting {
                return (lhs.dateForSorting ?? .distantPast) > (rhs.dateForSorting ?? .distantPast)
            }
        case .alphabetical:
            break
        }

        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
}

// MARK: - GridCardInfo Updates

extension GridCardInfo {
    /// Returns a copy with only the mutable presentation fields replaced.
    func updating(isPinned: Bool, editedAt: Date) -> GridCardInfo {
        GridCardInfo(
            id: id,
            kind: kind,
            creationSource: creationSource,
            conversionMetadata: conversionMetadata,
            cardNumber: cardNumber,
            interval: interval,
            reviewHistoryIsEmpty: reviewHistoryIsEmpty,
            isPinned: isPinned,
            frontText: frontText,
            backText: backText,
            frontPreviewText: frontPreviewText,
            backPreviewText: backPreviewText,
            searchDocumentText: searchDocumentText,
            createdAt: createdAt,
            editedAt: editedAt
        )
    }
}

private extension CardKind {
    var sectionTitle: String {
        switch self {
        case .flashcard:
            return "Flashcards"
        case .match:
            return "Match Cards"
        case .quiz:
            return "Quiz Cards"
        case .write:
            return "Write Cards"
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }

        var result: [[Element]] = []
        var index = startIndex

        while index < endIndex {
            let nextIndex = Swift.min(index + size, endIndex)
            result.append(Array(self[index..<nextIndex]))
            index = nextIndex
        }

        return result
    }
}
