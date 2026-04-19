//
//  DeckViewModel+SnapshotLoading.swift
//  QuizFlash
//
//  Snapshot loading and lightweight derived state for the deck screen.
//

import SwiftUI
import SwiftData
import OSLog

extension DeckViewModel {
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
        todayActivitySummary = snapshot.todayActivity
        activityHistorySummary = snapshot.activityHistory
        playModeAvailability = buildPlayModeAvailability(from: snapshot.gridCards)
        performGrouping(on: snapshot.gridCards)
    }

    /// Derives mixed-card compatibility counts from the lightweight deck snapshot.
    private func buildPlayModeAvailability(from cards: [GridCardInfo]) -> PlayModeCardAvailability {
        PlayModeCardAvailability(
            totalCards: cards.count,
            flashcardCards: cards.filter { $0.kind == .flashcard }.count,
            matchCards: cards.filter { $0.kind == .match }.count,
            quizCards: cards.filter { $0.kind == .quiz }.count,
            writeCards: cards.filter { $0.kind == .write }.count
        )
    }

    /// Seeds the in-memory grouping mode from the persisted deck preference.
    func configureGroupingMode(from groupingMode: DeckCardGroupingMode) {
        guard self.groupingMode != groupingMode else { return }
        self.groupingMode = groupingMode
        if !allCardInfos.isEmpty {
            performGrouping(on: allCardInfos)
        }
    }

    /// Persists a new grouping mode and immediately rebuilds the current sections.
    func updateGroupingMode(
        _ groupingMode: DeckCardGroupingMode,
        for deck: DeckModel,
        context: ModelContext
    ) {
        guard self.groupingMode != groupingMode else { return }

        let previousGroupingMode = deck.cardGroupingMode
        let previousEditedAt = deck.editedAt
        let now = Date()

        self.groupingMode = groupingMode
        deck.cardGroupingMode = groupingMode
        deck.editedAt = now
        performGrouping(on: allCardInfos)

        do {
            try context.save()
        } catch {
            deck.cardGroupingMode = previousGroupingMode
            deck.editedAt = previousEditedAt
            self.groupingMode = previousGroupingMode
            performGrouping(on: allCardInfos)
            logger.error("Failed to persist deck grouping mode: \(error.localizedDescription, privacy: .public)")
            presentMutationError(error)
        }
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
    func computeProgressStats(from cards: [GridCardInfo], deckCardCount: Int?) -> DeckProgressStats {
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

}
