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
    let cardNumber: Int
    let interval: Int
    let reviewHistoryIsEmpty: Bool
    let isPinned: Bool
    let frontText: String
    let backText: String
    let frontPreviewText: String
    let backPreviewText: String
    let frontNeedsRichSnapshot: Bool
    let backNeedsRichSnapshot: Bool
    let createdAt: Date
    let editedAt: Date
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
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "QuizFlash",
        category: "DeckViewModel"
    )
    @ObservationIgnored private var snapshotLoadTask: Task<Void, Never>?

    // MARK: - Selection State

    /// Whether the view is currently in multi-card selection mode.
    var isSelecting = false
    /// The set of card `PersistentIdentifier`s currently selected.
    var selectedCards: Set<PersistentIdentifier> = []
    /// Controls the destructive delete confirmation alert.
    var showDeleteConfirmation = false

    // MARK: - Card Data (Read-Only from Outside)

    /// All card infos for the current deck, updated by every `loadSnapshot` call.
    private(set) var allCardInfos: [GridCardInfo] = []
    /// Grouped and sorted card sections ready for consumption by `DeckCardGridView`.
    private(set) var cachedGroupedCards: [DeckCardGridView.CardSection] = []

    /// Spaced-repetition aggregate stats. Updated after every `loadSnapshot` call.
    private(set) var currentStats: DeckStats = .empty

    /// Pre-computed progress breakdown. Derived from `allCardInfos`; consumed by `DeckProgressView`.
    private(set) var progressStats: DeckProgressStats = .empty

    // MARK: - Scroll Restoration

    /// Persisted pixel scroll offset used by `ScrollPositionRestorer` in `DeckView`.
    var savedScrollOffset: CGFloat = 0

    // MARK: - Search

    /// Active search query; `nil` means no filter is applied.
    var searchQuery: String?

    // MARK: - Sorting

    /// Active sort order applied to the card grid.
    var sortOrder: SortOrder = .newest

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

    // MARK: - Initialization

    /// Creates a new instance, optionally seeding an initial search query.
    /// - Parameter searchQuery: Pre-fill the search field (e.g. from a deep-link).
    init(searchQuery: String? = nil) {
        self.searchQuery = searchQuery
    }

    // MARK: - Lifecycle

    /// Releases in-flight resources when the deck screen disappears.
    ///
    /// Clears `CardPreviewCache`, which triggers `CardFetchActor.tearDown()` →
    /// `modelContext.reset()`. This is the final step of the iOS 17 fix: it ensures
    /// the background `ModelContext` is properly dismantled before the view cycle ends.
    ///
    /// - Note: `allCardInfos` and `cachedGroupedCards` are intentionally preserved.
    ///   Removing them would destroy the card grid instantly on `.onDisappear`, which
    ///   fires when sheets or full-screen covers are presented — breaking scroll restoration.
    func tearDown() {
        cancelSnapshotLoad()
        CardPreviewCache.shared.flush()
    }

    /// Cancels any in-flight snapshot reload started by the view layer.
    func cancelSnapshotLoad() {
        snapshotLoadTask?.cancel()
        snapshotLoadTask = nil
    }

    /// Starts a replaceable snapshot load for the visible deck screen.
    func requestSnapshotLoad(deckID: PersistentIdentifier, container: ModelContainer) {
        cancelSnapshotLoad()
        snapshotLoadTask = Task { [weak self] in
            guard let self else { return }
            await self.loadSnapshot(deckID: deckID, container: container)
        }
    }

    /// Suspends any expensive background reloads while the deck tab is inactive.
    func suspendHeavyWork() {
        cancelSnapshotLoad()
    }

    // MARK: - Initial Card Load (iOS 17 Memory-Safe Path)

    /// Loads all cards for the given deck without touching the main `ModelContext`.
    ///
    /// After a successful fetch, updates `allCardInfos`, `currentStats`, `progressStats`,
    /// and rebuilds `cachedGroupedCards` for the card grid.
    ///
    /// - Parameters:
    ///   - deckID: The persistent identifier of the deck to fetch.
    ///   - container: The `ModelContainer` passed to the background actor.
    /// - Returns: The freshly computed `DeckStats` (also stored on `currentStats`).
    ///
    /// Usage in `DeckView`:
    /// ```swift
    /// .task(id: deck.persistentModelID) {
    ///     await viewModel.loadSnapshot(deckID: deck.persistentModelID,
    ///                                  container: modelContext.container)
    /// }
    /// ```
    @discardableResult
    func loadSnapshot(deckID: PersistentIdentifier, container: ModelContainer) async -> DeckStats {
        let snapshot = await CardPreviewCache.shared.fetchSnapshot(
            deckID: deckID,
            container: container
        )
        guard !Task.isCancelled else { return .empty }
        applySnapshot(snapshot)
        return snapshot.stats
    }

    private func applySnapshot(_ snapshot: CardDataSnapshot) {
        allCardInfos = snapshot.gridCards
        currentStats = snapshot.stats
        progressStats = computeProgressStats(from: snapshot.gridCards, deckCardCount: nil)
        performGrouping(on: snapshot.gridCards)
    }

    // MARK: - Progress Stats Computation

    /// Derives a `DeckProgressStats` value from the current card info array.
    ///
    /// Centralising this logic in the ViewModel makes `DeckProgressView` a fully dumb,
    /// data-driven view with no business logic of its own.
    ///
    /// - Parameters:
    ///   - cards: The array of `GridCardInfo` to analyse.
    ///   - deckCardCount: Optional override for the total denominator (e.g. from `deck.cardCount`).
    ///     Pass `nil` to use the array count, which is accurate after a full snapshot load.
    /// - Returns: A freshly computed `DeckProgressStats`.
    private func computeProgressStats(from cards: [GridCardInfo], deckCardCount: Int?) -> DeckProgressStats {
        let newCards      = cards.filter { $0.reviewHistoryIsEmpty }.count
        let learningCards = cards.filter { !$0.reviewHistoryIsEmpty && $0.interval < 14 }.count
        let masteredCards = cards.filter { !$0.reviewHistoryIsEmpty && $0.interval >= 14 }.count
        let total         = max(deckCardCount ?? cards.count, 1)
        return DeckProgressStats(
            newCards: newCards,
            learningCards: learningCards,
            masteredCards: masteredCards,
            total: total
        )
    }

    // MARK: - Selection Actions

    /// Toggles the selection state of a single card by its persistent identifier.
    /// - Parameter id: The `PersistentIdentifier` of the card to toggle.
    func toggleSelection(for id: PersistentIdentifier) {
        if selectedCards.contains(id) {
            selectedCards.remove(id)
        } else {
            selectedCards.insert(id)
        }
    }

    /// Exits selection mode and clears all selected cards.
    func exitSelectionMode() {
        isSelecting = false
        selectedCards.removeAll()
    }

    // MARK: - Deletion

    /// Deletes a single card identified by its persistent identifier.
    ///
    /// **Two-phase update:**
    /// - Phase 1 (sync): Removes the card from `allCardInfos` in-memory for instant UI feedback.
    /// - Phase 2 (async): Re-fetches a full snapshot via `CardFetchActor` for accurate stats.
    ///
    /// The main `ModelContext` is used **only** for the delete + save mutation — never to read cards.
    ///
    /// - Note: Uses a `FetchDescriptor` lookup instead of `ModelContext.model(for:)` to avoid
    ///   a potential runtime crash on iOS 17/26 when the identifier cannot be resolved.
    ///
    /// - Parameters:
    ///   - id: The persistent identifier of the card to delete.
    ///   - deck: The parent `DeckModel` whose `cardCount` will be decremented.
    ///   - context: The main `ModelContext` used for the delete mutation.
    func deleteSingleCard(id: PersistentIdentifier, from deck: DeckModel, context: ModelContext) {
        let descriptor = FetchDescriptor<CardModel>(
            predicate: #Predicate { $0.persistentModelID == id }
        )
        if let card = (try? context.fetch(descriptor))?.first {
            context.delete(card)
            try? context.save()
        }

        deck.cardCount = max(0, deck.cardCount - 1)
        deck.editedAt = Date()
        selectedCards.remove(id)

        // Instant in-memory grid update — no deck.cards relationship read required.
        allCardInfos.removeAll { $0.id == id }
        progressStats = computeProgressStats(from: allCardInfos, deckCardCount: nil)
        performGrouping(on: allCardInfos)

        // Async stats refresh — GridCardInfo does not carry full review history,
        // so a full re-fetch is needed to produce accurate DeckStats after deletion.
        let deckID = deck.persistentModelID
        let container = context.container
        Task { [weak self] in
            await self?.loadSnapshot(deckID: deckID, container: container)
        }
    }

    /// Deletes all currently selected cards in a single batch.
    ///
    /// Same two-phase approach as `deleteSingleCard`. Batch in-memory removal gives
    /// instant feedback; the async re-fetch corrects the aggregate stats.
    ///
    /// - Parameters:
    ///   - deck: The parent `DeckModel` whose `cardCount` will be decremented.
    ///   - context: The main `ModelContext` used for the delete mutations.
    func deleteSelectedCards(from deck: DeckModel, context: ModelContext) {
        let idsToDelete = selectedCards

        // Safe batch fetch: a single round-trip avoids N individual model(for:) crashes.
        let descriptor = FetchDescriptor<CardModel>(
            predicate: #Predicate { idsToDelete.contains($0.persistentModelID) }
        )
        if let cards = try? context.fetch(descriptor) {
            for card in cards { context.delete(card) }
            try? context.save()
        }

        deck.cardCount = max(0, deck.cardCount - idsToDelete.count)
        deck.editedAt = Date()
        isSelecting = false
        selectedCards.removeAll()

        allCardInfos.removeAll { idsToDelete.contains($0.id) }
        progressStats = computeProgressStats(from: allCardInfos, deckCardCount: nil)
        performGrouping(on: allCardInfos)

        let deckID = deck.persistentModelID
        let container = context.container
        Task { [weak self] in
            await self?.loadSnapshot(deckID: deckID, container: container)
        }
    }

    /// Toggles the persistent pinned state of a single card and immediately re-groups the grid.
    ///
    /// Pinning is a presentation preference rather than a spaced-repetition statistic,
    /// so the ViewModel updates the in-memory snapshot directly instead of reloading the
    /// entire deck from the background actor.
    ///
    /// - Parameters:
    ///   - id: The persistent identifier of the card to pin or unpin.
    ///   - context: The main `ModelContext` used for the mutation.
    func togglePinnedState(for id: PersistentIdentifier, context: ModelContext) {
        let descriptor = FetchDescriptor<CardModel>(
            predicate: #Predicate { $0.persistentModelID == id }
        )

        do {
            guard let card = try context.fetch(descriptor).first else { return }

            let pinnedState = !card.isPinned
            let editDate = Date()
            card.isPinned = pinnedState
            card.editedAt = editDate
            card.deck?.editedAt = editDate
            try context.save()

            if let index = allCardInfos.firstIndex(where: { $0.id == id }) {
                allCardInfos[index] = allCardInfos[index].updating(
                    isPinned: pinnedState,
                    editedAt: editDate
                )
                performGrouping(on: allCardInfos)
            }
        } catch {
            logger.error("Failed to toggle pinned state for card: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Export

    /// Exports the deck to a shareable file and presents the system share sheet.
    ///
    /// Sets `isExporting` during the async operation. On success, stores the
    /// exported `URL` in `exportedURL` and flips `showShareSheet`. On failure,
    /// stores the error message and flips `showExportError`.
    ///
    /// - Parameter deck: The `DeckModel` to export.
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
                    let fullText = card.frontText + " \n " + card.backText
                    return tokens.allSatisfy { fullText.range(of: $0, options: options) != nil }
                }
            }
        }

        let sorted = filtered.sorted { c1, c2 in
            if c1.isPinned != c2.isPinned {
                return c1.isPinned && !c2.isPinned
            }
            switch sortOrder {
            case .newest: return c1.createdAt > c2.createdAt
            case .oldest: return c1.createdAt < c2.createdAt
            case .lastEdited: return c1.editedAt > c2.editedAt
            case .alphabetical: return c1.frontText
                    .localizedCaseInsensitiveCompare(c2.frontText) == .orderedAscending
            }
        }

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

        guard sortOrder != .alphabetical else {
            if !regularCards.isEmpty {
                sections.append(
                    DeckCardGridView.CardSection(
                        id: "all",
                        title: "All Cards",
                        cards: regularCards,
                        dateForSorting: nil
                    )
                )
            }
            cachedGroupedCards = sections
            return
        }

        let calendar = Calendar.current
        let groups = Dictionary(grouping: regularCards) { card -> Date in
            let date = sortOrder == .lastEdited ? card.editedAt : card.createdAt
            return calendar.startOfDay(for: date)
        }

        let groupedSections = groups
            .map { startOfDay, cardsInGroup -> DeckCardGridView.CardSection in
                let title = sectionTitle(for: startOfDay, calendar: calendar)
                return DeckCardGridView.CardSection(
                    id: title,
                    title: title,
                    cards: cardsInGroup,
                    dateForSorting: startOfDay
                )
            }
            .sorted { s1, s2 in
                guard let d1 = s1.dateForSorting, let d2 = s2.dateForSorting else { return false }
                return sortOrder == .oldest ? d1 < d2 : d1 > d2
            }

        cachedGroupedCards = sections + groupedSections
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
}

// MARK: - GridCardInfo Updates

private extension GridCardInfo {
    /// Returns a copy with only the mutable presentation fields replaced.
    func updating(isPinned: Bool, editedAt: Date) -> GridCardInfo {
        GridCardInfo(
            id: id,
            cardNumber: cardNumber,
            interval: interval,
            reviewHistoryIsEmpty: reviewHistoryIsEmpty,
            isPinned: isPinned,
            frontText: frontText,
            backText: backText,
            frontPreviewText: frontPreviewText,
            backPreviewText: backPreviewText,
            frontNeedsRichSnapshot: frontNeedsRichSnapshot,
            backNeedsRichSnapshot: backNeedsRichSnapshot,
            createdAt: createdAt,
            editedAt: editedAt
        )
    }
}
