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
    let frontText: String
    let backText: String
    let createdAt: Date
    let editedAt: Date
}

// MARK: - Deck View Model

/// The ViewModel for `DeckView`, managing card data, selection, search, sort, and export state.
///
/// Isolated to `@MainActor` and using `@Observable` for iOS 17+ observation.
/// The class is `final` as it is not designed to be subclassed.
@Observable
@MainActor
final class DeckViewModel {

    // MARK: - Selection State
    var isSelecting = false
    var selectedCards: Set<PersistentIdentifier> = []
    var showDeleteConfirmation = false

    // MARK: - Card Data (Read-Only from Outside)
    private(set) var allCardInfos: [GridCardInfo] = []
    private(set) var cachedGroupedCards: [DeckCardGridView.CardSection] = []

    /// Replaces the DeckStats return value of the old updateGroupedCards.
    /// Updated after every loadSnapshot call (initial load and post-deletion refresh).
    private(set) var currentStats: DeckStats = .empty

    // MARK: - Scroll Restoration
    /// Non-zero value signals DeckView to restore scroll position after a sheet dismissal.
    var savedScrollOffset: CGFloat = 0

    // MARK: - Search
    var searchQuery: String?

    // MARK: - Sorting
    var sortOrder: SortOrder = .newest

    // MARK: - Export State
    var isExporting = false
    var exportedURL: URL?
    var showShareSheet = false
    var showExportError = false
    var exportErrorMessage = ""

    // MARK: - Initialization
    init(searchQuery: String? = nil) {
        self.searchQuery = searchQuery
    }

    // MARK: - Lifecycle

    /// Call from DeckView.onDisappear (or wherever the deck screen is dismissed).
    ///
    /// Clears the view model's in-memory state AND flushes CardPreviewCache, which
    /// triggers CardFetchActor.tearDown() → modelContext.reset().
    /// This is the final step of the iOS 17 fix: it ensures the background ModelContext
    /// is properly dismantled before the view cycle ends.
    func tearDown() {
        // We INTENTIONALLY leave `allCardInfos` and `cachedGroupedCards` intact.
        // If we remove them, DeckView loses its content immediately upon .onDisappear
        // (which fires when sheets/FullCovers open), instantly destroying native scroll position.
        
        // This triggers CardFetchActor.tearDown() → modelContext.reset() → iOS 17 zombie fix.
        CardPreviewCache.shared.flush()
    }

    // MARK: - Initial Card Load (iOS 17 Memory-Safe Path)

    /// Loads all cards for the given deck without touching the main ModelContext.
    ///
    /// Call site in DeckView:
    ///   .task(id: deck.persistentModelID) {
    ///       await viewModel.loadSnapshot(deckID: deck.persistentModelID,
    ///                                    container: modelContext.container)
    ///   }
    ///
    /// The @discardableResult allows DeckView to call this without storing the stats
    /// locally — currentStats on the view model is the source of truth.
    @discardableResult
    func loadSnapshot(deckID: PersistentIdentifier, container: ModelContainer) async -> DeckStats {
        let snapshot = await CardPreviewCache.shared.fetchSnapshot(
            deckID: deckID,
            container: container
        )
        guard !Task.isCancelled else { return .empty }
        allCardInfos = snapshot.gridCards
        currentStats = snapshot.stats
        performGrouping(on: snapshot.gridCards)
        return snapshot.stats
    }

    // MARK: - Selection Actions

    func toggleSelection(for id: PersistentIdentifier) {
        if selectedCards.contains(id) {
            selectedCards.remove(id)
        } else {
            selectedCards.insert(id)
        }
    }

    func exitSelectionMode() {
        isSelecting = false
        selectedCards.removeAll()
    }

    // MARK: - Deletion

    /// Deletes a single card.
    ///
    /// Two-phase update:
    ///   Phase 1 (sync): Remove from allCardInfos in-memory → instant UI response, no DB read.
    ///   Phase 2 (async): Re-fetch snapshot via CardFetchActor → accurate stats refresh.
    ///   The main ModelContext is used ONLY for the delete + save mutation, never to read cards.
    ///
    /// Safety note: `ModelContext.model(for:)` can crash at runtime on iOS 17/26 if the
    /// persistent identifier cannot be resolved (deleted row, schema mismatch). We use
    /// a `FetchDescriptor` predicate lookup instead — returns empty array instead of crashing.
    func deleteSingleCard(id: PersistentIdentifier, from deck: DeckModel, context: ModelContext) {
        // Safe fetch: avoids the ModelContext.model(for:) fatal crash when the
        // identifier cannot be resolved (e.g. already-deleted record, schema change).
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

        // Instant in-memory grid update — no deck.cards read required.
        allCardInfos.removeAll { $0.id == id }
        performGrouping(on: allCardInfos)

        // Async stats refresh. GridCardInfo does not carry review history, so we
        // need a full re-fetch to produce accurate DeckStats after deletion.
        let deckID = deck.persistentModelID
        let container = context.container
        Task { [weak self] in
            await self?.loadSnapshot(deckID: deckID, container: container)
        }
    }

    /// Deletes all currently selected cards.
    ///
    /// Same two-phase approach as deleteSingleCard. Batch in-memory removal gives
    /// instant feedback; async re-fetch corrects the stats.
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
        performGrouping(on: allCardInfos)

        let deckID = deck.persistentModelID
        let container = context.container
        Task { [weak self] in
            await self?.loadSnapshot(deckID: deckID, container: container)
        }
    }

    // MARK: - Export

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

    /// Applies the active search filter and sort order to a given card array.
    ///
    /// Called after:
    ///   - loadSnapshot (initial load and post-deletion stats refresh)
    ///   - In-memory deletion (immediate visual update before async re-fetch)
    ///   - Sort order or search query changes (trigger from DeckView via .onChange)
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
            switch sortOrder {
            case .newest: return c1.createdAt > c2.createdAt
            case .oldest: return c1.createdAt < c2.createdAt
            case .lastEdited: return c1.editedAt > c2.editedAt
            case .alphabetical: return c1.frontText
                    .localizedCaseInsensitiveCompare(c2.frontText) == .orderedAscending
            }
        }

        guard sortOrder != .alphabetical else {
            cachedGroupedCards = sorted.isEmpty ? [] : [
    DeckCardGridView.CardSection(
        id: "all", title: "All Cards", cards: sorted, dateForSorting: nil
    )
]
            return
        }

        let calendar = Calendar.current
        let groups = Dictionary(grouping: sorted) { card -> Date in
            let date = sortOrder == .lastEdited ? card.editedAt : card.createdAt
            return calendar.startOfDay(for: date)
        }

        cachedGroupedCards = groups
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
            return sortOrder == .oldest ? d1 < d2: d1 > d2
        }
    }

    // MARK: - Date Formatters (Static — allocated once for the lifetime of the process)

    private static let weekFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE"; return f
    }()

    private static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMMM d"; return f
    }()

    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; return f
    }()

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
