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

// MARK: - Deck Daily Activity

/// Lightweight summary for a single card reviewed in the current deck today.
struct DeckTodayReviewedCardSummary: Identifiable, Equatable, Sendable {
    let id: PersistentIdentifier
    let title: String
    let finalDifficulty: ReviewDifficulty
    let reviewCount: Int
    let lastReviewedAt: Date
}

/// Pre-computed deck activity snapshot for the current local day.
struct DeckTodayActivitySummary: Equatable, Sendable {
    let activityDate: Date
    let activityLabel: String
    let uniqueCardsReviewed: Int
    let rawReviewCount: Int
    let landedCount: Int
    let retryCount: Int
    let headline: String
    let detailLine: String
    let cards: [DeckTodayReviewedCardSummary]

    var hasActivity: Bool {
        uniqueCardsReviewed > 0
    }

    nonisolated static func placeholder(referenceDate: Date = Date()) -> DeckTodayActivitySummary {
        let locale = AppPreferences.persistedResolvedLocale
        return DeckTodayActivitySummary(
            activityDate: referenceDate,
            activityLabel: AppLocalization.string("Today", locale: locale),
            uniqueCardsReviewed: 0,
            rawReviewCount: 0,
            landedCount: 0,
            retryCount: 0,
            headline: AppLocalization.string("No cards moved today", locale: locale),
            detailLine: AppLocalization.string("Open a play mode to generate live activity in this deck.", locale: locale),
            cards: []
        )
    }
}

/// Lightweight summary for a single active day in this deck's review history.
struct DeckActivityDaySummary: Identifiable, Equatable, Sendable {
    let id: Date
    let activityDate: Date
    let activityLabel: String
    let uniqueCardsReviewed: Int
    let rawReviewCount: Int
    let landedCount: Int
    let retryCount: Int
    let cards: [DeckTodayReviewedCardSummary]
}

/// Pre-computed deck review history grouped by local day.
struct DeckActivityHistorySummary: Equatable, Sendable {
    let totalActiveDays: Int
    let totalRawReviewCount: Int
    let daySummaries: [DeckActivityDaySummary]

    var hasActivity: Bool {
        !daySummaries.isEmpty
    }

    nonisolated static func placeholder() -> DeckActivityHistorySummary {
        DeckActivityHistorySummary(
            totalActiveDays: 0,
            totalRawReviewCount: 0,
            daySummaries: []
        )
    }
}

enum DeckActivitySheetPresentation: String, Identifiable {
    case history

    var id: String { rawValue }
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

    /// Pre-computed activity summary for the current local day in this deck.
    var todayActivitySummary: DeckTodayActivitySummary = .placeholder()

    /// Pre-computed grouped review history used by the deck activity detail sheet.
    var activityHistorySummary: DeckActivityHistorySummary = .placeholder()

    /// Lightweight compatibility counts used by deck play-mode surfaces.
    var playModeAvailability: PlayModeCardAvailability = .empty

    /// Cached deck-level readiness diagnostics for the current card snapshot.
    var readinessSummary: DeckReadinessSummary = .empty

    /// Controls the custom-sheet presentation for deck activity history.
    var activitySheetPresentation: DeckActivitySheetPresentation?

    // MARK: - Scroll Restoration

    /// Persisted pixel scroll offset used by `ScrollPositionRestorer` in `DeckView`.
    @ObservationIgnored
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
    /// Controls the deck-mutation save error alert presentation.
    var showMutationError = false
    /// Human-readable description of the last deck-mutation save error.
    var mutationErrorMessage = ""

    // MARK: - Initialization

    /// Creates a new instance, optionally seeding an initial search query.
    /// - Parameter searchQuery: Pre-fill the search field (e.g. from a deep-link).
    init(searchQuery: String? = nil) {
        self.searchQuery = searchQuery
    }

    /// Presents a user-facing save error for a deck mutation flow.
    /// - Parameters:
    ///   - error: The underlying persistence failure.
    ///   - fallbackMessage: Short fallback copy used when the error has no description.
    func presentMutationError(
        _ error: Error,
        fallbackMessage: String = "Your deck changes couldn't be saved right now."
    ) {
        let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        mutationErrorMessage = description.isEmpty ? fallbackMessage : description
        showMutationError = true
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

    func presentActivityHistorySheet() {
        activitySheetPresentation = .history
    }

    func dismissActivityHistorySheet() {
        activitySheetPresentation = nil
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
                    title: AppLocalization.string("Pinned", locale: AppPreferences.persistedResolvedLocale),
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
        let locale = AppPreferences.persistedResolvedLocale
        var localizedCalendar = calendar
        localizedCalendar.locale = locale

        if localizedCalendar.isDateInToday(date) {
            return AppLocalization.string("Today", locale: locale)
        }
        if localizedCalendar.isDateInYesterday(date) {
            return AppLocalization.string("Yesterday", locale: locale)
        }
        let now = Date()
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = localizedCalendar
        if localizedCalendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            formatter.setLocalizedDateFormatFromTemplate("EEEE")
            return AppLocalization.string("This Week", locale: locale) + " – " + formatter.string(from: date)
        }
        if localizedCalendar.isDate(date, equalTo: now, toGranularity: .month) {
            formatter.setLocalizedDateFormatFromTemplate("MMMMd")
            return formatter.string(from: date)
        }
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter.string(from: date)
    }

    private func buildChronologicalSections(from cards: [GridCardInfo]) -> [DeckCardGridView.CardSection] {
        guard !cards.isEmpty else { return [] }

        if sortOrder == .alphabetical {
            return [
                DeckCardGridView.CardSection(
                    id: "all",
                    title: AppLocalization.string("All Cards", locale: AppPreferences.persistedResolvedLocale),
                    cards: cards,
                    dateForSorting: nil
                )
            ]
        }

        let locale = AppPreferences.persistedResolvedLocale
        var calendar = AppPreferences.shared.resolvedCalendar
        calendar.locale = locale
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
        let locale = AppPreferences.persistedResolvedLocale
        switch self {
        case .flashcard:
            return AppLocalization.string("Flashcards", locale: locale)
        case .match:
            return AppLocalization.string("Match Cards", locale: locale)
        case .quiz:
            return AppLocalization.string("Quiz Cards", locale: locale)
        case .write:
            return AppLocalization.string("Write Cards", locale: locale)
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
