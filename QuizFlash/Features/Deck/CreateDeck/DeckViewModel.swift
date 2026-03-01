//
//  DeckViewModel.swift
//  QuizFlash
//
//  iOS 17 Memory Leak — Changes in this file:
//
//  BEFORE: updateGroupedCards(for deck: DeckModel, context: ModelContext) -> DeckStats
//    Called synchronously on the main actor. Reading Array(deck.cards) loaded every
//    CardModel into the main ModelContext's row cache. iOS 17 never evicted them on
//    back-navigation → the cumulative +1 MB/cycle leak.
//
//  AFTER: loadSnapshot(deckID:, container:) async
//    Delegates all DB reads to CardFetchActor (off the main actor). The main ModelContext
//    never touches a single CardModel. Only Sendable value types (GridCardInfo, DeckStats)
//    cross the actor boundary → zero contribution to the main context's row cache.
//
//  Deletion flow:
//    Mutations still happen on the main context (correct — they need the live DeckModel).
//    After save(), we update allCardInfos in-memory (instant UI) and fire an async
//    loadSnapshot to refresh accurate stats. No deck.cards read on the main context.
//

import SwiftUI
import SwiftData

// MARK: - GridCardInfo

/// Sendable value type representing a single card's display data.
/// The only SwiftData-derived type that crosses actor boundaries in this architecture.
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

// MARK: - DeckViewModel

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
    func deleteSingleCard(id: PersistentIdentifier, from deck: DeckModel, context: ModelContext) {
        if let card = context.model(for: id) as? CardModel {
            context.delete(card)
        }
        try? context.save()
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

        for id in idsToDelete {
            if let card = context.model(for: id) as? CardModel {
                context.delete(card)
            }
        }
        try? context.save()
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
