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
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "QuizFlash",
        category: "DeckViewModel"
    )
    @ObservationIgnored private var snapshotLoadTask: Task<Void, Never>?
    @ObservationIgnored private var conversionTask: Task<Void, Never>?

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

    /// Lightweight compatibility counts used by deck play-mode surfaces.
    private(set) var playModeAvailability: PlayModeCardAvailability = .empty

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
        cancelConversion()
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
    func enterSelectionMode() {
        isSelecting = true
        selectedCards.removeAll()
    }

    /// Exits selection mode and clears all selected cards.
    func exitSelectionMode() {
        isSelecting = false
        selectedCards.removeAll()
    }

    /// Clears the current multi-card selection without leaving selection mode.
    func clearSelection() {
        selectedCards.removeAll()
    }

    // MARK: - Single Card Actions

    /// Toggles the pinned state of a single card and refreshes the grouped grid.
    func togglePinnedState(
        for id: PersistentIdentifier,
        in deck: DeckModel,
        context: ModelContext
    ) {
        let descriptor = FetchDescriptor<CardModel>(
            predicate: #Predicate { $0.persistentModelID == id }
        )

        do {
            guard let card = try context.fetch(descriptor).first else { return }
            let newPinnedState = !card.isPinned
            let now = Date()

            card.isPinned = newPinnedState
            card.editedAt = now
            deck.editedAt = now
            try context.save()

            if let index = allCardInfos.firstIndex(where: { $0.id == id }) {
                allCardInfos[index] = allCardInfos[index].updating(
                    isPinned: newPinnedState,
                    editedAt: now
                )
                performGrouping(on: allCardInfos)
            }

            let deckID = deck.persistentModelID
            let container = context.container
            Task { [weak self] in
                await self?.loadSnapshot(deckID: deckID, container: container)
            }
        } catch {
            logger.error("Failed to toggle pin state: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Deletes a single card and keeps in-memory grid state in sync until the next snapshot refresh.
    func deleteCard(
        withID id: PersistentIdentifier,
        from deck: DeckModel,
        context: ModelContext
    ) {
        let descriptor = FetchDescriptor<CardModel>(
            predicate: #Predicate { $0.persistentModelID == id }
        )

        do {
            guard let card = try context.fetch(descriptor).first else { return }
            context.delete(card)
            deck.cards.removeAll { $0.persistentModelID == id }
            deck.cardCount = max(0, deck.cardCount - 1)
            deck.editedAt = Date()
            try context.save()

            allCardInfos.removeAll { $0.id == id }
            progressStats = computeProgressStats(from: allCardInfos, deckCardCount: nil)
            performGrouping(on: allCardInfos)
            selectedCards.remove(id)

            let deckID = deck.persistentModelID
            let container = context.container
            Task { [weak self] in
                await self?.loadSnapshot(deckID: deckID, container: container)
            }
        } catch {
            logger.error("Failed to delete card: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Creation

    /// Creates and persists a new manual card inside the current deck.
    ///
    /// The next `cardNumber` is derived from both the persisted deck counter and the
    /// loaded snapshot, which heals legacy state where `lastAssignedCardNumber` may
    /// lag behind the actual maximum card number already stored in the deck.
    func addCard(
        content: DraftCardContent,
        to deck: DeckModel,
        context: ModelContext
    ) {
        let originalLastAssigned = deck.lastAssignedCardNumber
        let originalCardCount = deck.cardCount
        let originalEditedAt = deck.editedAt
        let nextCardNumber = max(
            deck.lastAssignedCardNumber,
            allCardInfos.map(\.cardNumber).max() ?? 0
        ) + 1
        let now = Date()

        let newCard = CardModel(
            content: content,
            cardNumber: nextCardNumber,
            isPinned: false,
            creationSource: .manual
        )
        newCard.deck = deck

        deck.lastAssignedCardNumber = nextCardNumber
        deck.cardCount = originalCardCount + 1
        deck.editedAt = now
        deck.cards.append(newCard)
        context.insert(newCard)

        do {
            try context.save()
        } catch {
            deck.lastAssignedCardNumber = originalLastAssigned
            deck.cardCount = originalCardCount
            deck.editedAt = originalEditedAt
            deck.cards.removeAll { $0.persistentModelID == newCard.persistentModelID }
            context.delete(newCard)
            logger.error("Failed to create card in deck: \(error.localizedDescription, privacy: .public)")
            return
        }

        let deckID = deck.persistentModelID
        let container = context.container
        Task { [weak self] in
            await self?.loadSnapshot(deckID: deckID, container: container)
        }
    }

    /// Creates and persists a new manual flashcard inside the current deck.
    func addCard(
        frontZone: ZoneModel,
        backZone: ZoneModel,
        to deck: DeckModel,
        context: ModelContext
    ) {
        addCard(
            content: .flashcard(
                FlashcardCardContent(
                    frontZone: frontZone,
                    backZone: backZone,
                    frontType: .text,
                    backType: .text
                )
            ),
            to: deck,
            context: context
        )
    }

    // MARK: - Deletion

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
        do {
            let cards = try context.fetch(descriptor)
            for card in cards { context.delete(card) }
            deck.cards.removeAll { idsToDelete.contains($0.persistentModelID) }
            deck.cardCount = max(0, deck.cardCount - idsToDelete.count)
            deck.editedAt = Date()
            try context.save()

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
        } catch {
            logger.error("Failed to delete selected cards: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Conversion

    /// Opens the conversion flow starting from the full current deck.
    func presentDeckConversion(
        for deck: DeckModel,
        preferredTargetKind: CardKind? = nil
    ) {
        conversionRequest = makeConversionRequest(
            for: deck,
            preferredScope: .wholeDeck,
            singleCardID: nil,
            preferredTargetKind: preferredTargetKind,
            recommendedCardIDs: []
        )
        conversionProgress = nil
        conversionSummary = nil
        conversionErrorMessage = nil
    }

    /// Opens the conversion flow starting from the current multi-card selection.
    func presentSelectionConversion(
        for deck: DeckModel,
        preferredTargetKind: CardKind? = nil
    ) {
        guard !orderedSelectedCardIDs().isEmpty else { return }
        conversionRequest = makeConversionRequest(
            for: deck,
            preferredScope: .selectedCards,
            singleCardID: nil,
            preferredTargetKind: preferredTargetKind,
            recommendedCardIDs: []
        )
        conversionProgress = nil
        conversionSummary = nil
        conversionErrorMessage = nil
    }

    /// Opens the conversion flow starting from one specific card.
    func presentSingleCardConversion(
        for cardID: PersistentIdentifier,
        in deck: DeckModel,
        preferredTargetKind: CardKind? = nil
    ) {
        conversionRequest = makeConversionRequest(
            for: deck,
            preferredScope: .singleCard,
            singleCardID: cardID,
            preferredTargetKind: preferredTargetKind,
            recommendedCardIDs: []
        )
        conversionProgress = nil
        conversionSummary = nil
        conversionErrorMessage = nil
    }

    /// Opens the conversion flow for cards specifically flagged by readiness diagnostics.
    func presentReadinessConversion(
        for targetKind: CardKind,
        in deck: DeckModel
    ) {
        let recommendedCardIDs = recommendedConversionCardIDs(for: targetKind)
        guard !recommendedCardIDs.isEmpty else { return }

        conversionRequest = makeConversionRequest(
            for: deck,
            preferredScope: .recommendedCards,
            singleCardID: nil,
            preferredTargetKind: targetKind,
            recommendedCardIDs: recommendedCardIDs
        )
        conversionProgress = nil
        conversionSummary = nil
        conversionErrorMessage = nil
    }

    /// Cancels any in-flight conversion task and clears the sheet state.
    func dismissConversionSheet() {
        cancelConversion()
        conversionRequest = nil
        conversionProgress = nil
        conversionSummary = nil
        conversionErrorMessage = nil
    }

    /// Starts the configured conversion run and keeps progress in sync for the sheet UI.
    func startConversion(
        for deck: DeckModel,
        context: ModelContext
    ) {
        guard let request = conversionRequest, request.canStart else { return }

        cancelConversion()
        conversionSummary = nil
        conversionErrorMessage = nil
        conversionProgress = DeckCardConversionProgress(
            totalCount: request.sourceCount,
            completedCount: 0,
            createdCount: 0,
            skippedCount: 0,
            failedCount: 0,
            statusMessage: "Preparing source cards"
        )

        conversionTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                try await self.runConversion(
                    request: request,
                    deck: deck,
                    context: context
                )
            } catch is CancellationError {
                self.conversionProgress = nil
            } catch {
                self.conversionProgress = nil
                self.conversionErrorMessage = error.localizedDescription
            }

            self.conversionTask = nil
        }
    }

    private func cancelConversion() {
        conversionTask?.cancel()
        conversionTask = nil
    }

    private func runConversion(
        request: DeckCardConversionRequest,
        deck: DeckModel,
        context: ModelContext
    ) async throws {
        let sourceSnapshots = try await fetchConversionSources(
            request: request,
            deckID: deck.persistentModelID,
            container: context.container
        )

        guard !sourceSnapshots.isEmpty else {
            conversionProgress = nil
            conversionErrorMessage = "No compatible source cards were available for conversion."
            return
        }

        guard let activeProfile = AIProviderStore.shared.activeProfile else {
            throw NSError(
                domain: "DeckConversion",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No AI provider is configured. Open Settings > AI Providers."]
            )
        }

        if let validationMessage = activeProfile.generationValidationMessage {
            throw NSError(
                domain: "DeckConversion",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: validationMessage]
            )
        }

        let aiService = AIFlashcardService(provider: activeProfile)
        let batchID = UUID()
        let convertedAt = Date()
        let totalCount = sourceSnapshots.count
        var completedCount = 0
        var createdCount = 0
        var skippedCount = 0
        var failedCount = 0
        var destinationDeck: DeckModel? = nil

        let sourcesByID = Dictionary(uniqueKeysWithValues: sourceSnapshots.map { ($0.id, $0) })
        let skippedSources = sourceSnapshots.filter {
            $0.kind == request.targetKind ||
            $0.content.searchDocumentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let convertibleSources = sourceSnapshots.filter { source in
            !skippedSources.contains(where: { $0.id == source.id })
        }

        if !skippedSources.isEmpty {
            skippedCount += skippedSources.count
            completedCount += skippedSources.count
            updateConversionProgress(
                totalCount: totalCount,
                completedCount: completedCount,
                createdCount: createdCount,
                skippedCount: skippedCount,
                failedCount: failedCount,
                statusMessage: "Skipped \(skippedSources.count) card\(skippedSources.count == 1 ? "" : "s") already in \(request.targetKind.displayTitle)"
            )
        }

        if !convertibleSources.isEmpty {
            updateConversionProgress(
                totalCount: totalCount,
                completedCount: completedCount,
                createdCount: createdCount,
                skippedCount: skippedCount,
                failedCount: failedCount,
                statusMessage: "Planning AI conversion batches"
            )
        }

        let conversionStream = aiService.convertCardsStream(
            convertibleSources.map {
                AICardConversionSource(id: $0.id, kind: $0.kind, content: $0.content)
            },
            to: request.targetKind.aiGenerationType
        )

        do {
            for try await chunk in conversionStream {
                try Task.checkCancellation()

                let persistedCount = try persistConvertedOutputs(
                    chunk.outputs,
                    request: request,
                    sourcesByID: sourcesByID,
                    batchID: batchID,
                    convertedAt: convertedAt,
                    sourceDeck: deck,
                    destinationDeck: &destinationDeck,
                    context: context
                )

                let batchFailures = max(0, chunk.plannedCardCount - persistedCount)
                createdCount += persistedCount
                failedCount += batchFailures
                completedCount += chunk.plannedCardCount

                updateConversionProgress(
                    totalCount: totalCount,
                    completedCount: completedCount,
                    createdCount: createdCount,
                    skippedCount: skippedCount,
                    failedCount: failedCount,
                    statusMessage: conversionStatusMessage(
                        for: chunk,
                        targetKind: request.targetKind,
                        persistedCount: persistedCount
                    )
                )
            }
        } catch {
            let remainingCount = max(0, totalCount - completedCount)
            if remainingCount > 0 {
                failedCount += remainingCount
                completedCount += remainingCount
            }
            logger.error("Conversion stream finished with partial failures: \(error.localizedDescription, privacy: .public)")
        }

        conversionProgress = nil
        conversionSummary = DeckCardConversionSummary(
            sourceCount: totalCount,
            createdCount: createdCount,
            skippedCount: skippedCount,
            failedCount: failedCount,
            targetKind: request.targetKind,
            destination: request.destination,
            destinationDeckTitle: request.destination == .sameDeck
                ? deck.title
                : (destinationDeck?.title ?? request.destinationDeckTitle ?? deck.title),
            destinationDeckID: request.destination == .sameDeck
                ? deck.persistentModelID
                : destinationDeck?.persistentModelID
        )

        if request.destination == .sameDeck || createdCount > 0 {
            await loadSnapshot(deckID: deck.persistentModelID, container: context.container)
        }
    }

    private func conversionStatusMessage(
        for chunk: AIConversionBatchChunk,
        targetKind: CardKind,
        persistedCount: Int
    ) -> String {
        let rejectedCount = max(0, chunk.plannedCardCount - persistedCount)

        if rejectedCount > 0, targetKind == .match {
            return "Accepted \(persistedCount) high-quality Match card\(persistedCount == 1 ? "" : "s") from \(chunk.sourceLabel). Rejected \(rejectedCount) verbose pair\(rejectedCount == 1 ? "" : "s")."
        }

        if rejectedCount > 0 {
            return "Converted \(persistedCount) card\(persistedCount == 1 ? "" : "s") from \(chunk.sourceLabel). \(rejectedCount) could not be completed."
        }

        return "Converted \(persistedCount) \(targetKind.displayTitle.lowercased()) card\(persistedCount == 1 ? "" : "s") from \(chunk.sourceLabel)."
    }

    private func fetchConversionSources(
        request: DeckCardConversionRequest,
        deckID: PersistentIdentifier,
        container: ModelContainer
    ) async throws -> [CardConversionSourceSnapshot] {
        let actor = CardFetchActor(container: container)
        let sources = await actor.fetchConversionSources(
            deckID: deckID,
            cardIDs: request.resolvedCardIDs()
        )
        await actor.tearDown()
        return sources
    }

    func persistConvertedOutputs(
        _ outputs: [AICardConversionOutput],
        request: DeckCardConversionRequest,
        sourcesByID: [PersistentIdentifier: CardConversionSourceSnapshot],
        batchID: UUID,
        convertedAt: Date,
        sourceDeck: DeckModel,
        destinationDeck: inout DeckModel?,
        context: ModelContext
    ) throws -> Int {
        guard !outputs.isEmpty else { return 0 }

        let destinationWasCreatedInThisCall = destinationDeck == nil && request.destination == .newDeck
        let targetDeck = try resolveDestinationDeck(
            for: request,
            sourceDeck: sourceDeck,
            destinationDeck: &destinationDeck,
            context: context
        )

        let originalLastAssigned = targetDeck.lastAssignedCardNumber
        let originalCardCount = targetDeck.cardCount
        let originalEditedAt = targetDeck.editedAt
        let insertedCardsStart = targetDeck.cards.count
        var insertedCards: [CardModel] = []
        var nextCardNumber = targetDeck.lastAssignedCardNumber

        do {
            for output in outputs {
                guard let source = sourcesByID[output.sourceCardID] else {
                    throw NSError(
                        domain: "DeckConversion",
                        code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "One converted result could not be matched back to its source card."]
                    )
                }

                let content = try AIGeneratedCardContentMapper.map(output.generatedCard)
                nextCardNumber += 1

                let newCard = CardModel(
                    content: content,
                    cardNumber: nextCardNumber,
                    isPinned: false,
                    creationSource: .ai,
                    conversionMetadata: CardConversionMetadata(
                        sourceCardID: source.id,
                        sourceKind: source.kind,
                        targetKind: request.targetKind,
                        batchID: batchID,
                        convertedAt: convertedAt
                    )
                )
                newCard.deck = targetDeck
                targetDeck.cards.append(newCard)
                context.insert(newCard)
                insertedCards.append(newCard)
            }

            targetDeck.lastAssignedCardNumber = nextCardNumber
            targetDeck.cardCount = originalCardCount + insertedCards.count
            targetDeck.editedAt = Date()
            try context.save()
            return insertedCards.count
        } catch {
            for card in insertedCards {
                context.delete(card)
            }
            targetDeck.cards.removeSubrange(insertedCardsStart..<targetDeck.cards.count)
            targetDeck.lastAssignedCardNumber = originalLastAssigned
            targetDeck.cardCount = originalCardCount
            targetDeck.editedAt = originalEditedAt

            if destinationWasCreatedInThisCall {
                if let folder = targetDeck.folder {
                    folder.deckCount = max(0, folder.deckCount - 1)
                }
                context.delete(targetDeck)
                destinationDeck = nil
            }
            throw error
        }
    }

    private func resolveDestinationDeck(
        for request: DeckCardConversionRequest,
        sourceDeck: DeckModel,
        destinationDeck: inout DeckModel?,
        context: ModelContext
    ) throws -> DeckModel {
        if let destinationDeck {
            return destinationDeck
        }

        switch request.destination {
        case .sameDeck:
            return sourceDeck
        case .newDeck:
            guard let title = request.destinationDeckTitle else {
                throw NSError(
                    domain: "DeckConversion",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "Add a title for the new converted deck."]
                )
            }

            let newDeck = DeckModel(
                title: title,
                icon: sourceDeck.icon,
                colorHex: sourceDeck.colorHex
            )
            newDeck.cardGroupingMode = sourceDeck.cardGroupingMode
            context.insert(newDeck)
            if let folder = sourceDeck.folder {
                newDeck.folder = folder
                folder.deckCount += 1
            }
            destinationDeck = newDeck
            return newDeck
        }
    }

    private func updateConversionProgress(
        totalCount: Int,
        completedCount: Int,
        createdCount: Int,
        skippedCount: Int,
        failedCount: Int,
        statusMessage: String
    ) {
        conversionProgress = DeckCardConversionProgress(
            totalCount: totalCount,
            completedCount: completedCount,
            createdCount: createdCount,
            skippedCount: skippedCount,
            failedCount: failedCount,
            statusMessage: statusMessage
        )
    }

    private func makeConversionRequest(
        for deck: DeckModel,
        preferredScope: DeckCardConversionScopeOption,
        singleCardID: PersistentIdentifier?,
        preferredTargetKind: CardKind?,
        recommendedCardIDs: [PersistentIdentifier]
    ) -> DeckCardConversionRequest? {
        let selectedIDs = orderedSelectedCardIDs()
        let selectedIDSet = Set(selectedIDs)
        let recommendedIDSet = Set(recommendedCardIDs)
        let visibleCards = visibleCardsInDisplayOrder()

        let wholeDeckSources = allCardInfos.map {
            DeckCardConversionSourceDescriptor(id: $0.id, kind: $0.kind)
        }
        let selectedSources = visibleCards
            .filter { selectedIDSet.contains($0.id) }
            .map { DeckCardConversionSourceDescriptor(id: $0.id, kind: $0.kind) }
        let recommendedSources = visibleCards
            .filter { recommendedIDSet.contains($0.id) }
            .map { DeckCardConversionSourceDescriptor(id: $0.id, kind: $0.kind) }
        let singleSources = singleCardID.flatMap { id in
            allCardInfos
                .first(where: { $0.id == id })
                .map { [DeckCardConversionSourceDescriptor(id: $0.id, kind: $0.kind)] }
        } ?? []

        var availableScopes: [DeckCardConversionScopeOption] = [.wholeDeck]
        if !recommendedCardIDs.isEmpty {
            availableScopes.insert(.recommendedCards, at: 0)
        }
        if !selectedIDs.isEmpty {
            availableScopes.append(.selectedCards)
        }
        if singleCardID != nil {
            availableScopes.insert(.singleCard, at: 0)
        }

        guard availableScopes.contains(preferredScope) else { return nil }

        let currentSources: [DeckCardConversionSourceDescriptor]
        switch preferredScope {
        case .wholeDeck:
            currentSources = wholeDeckSources
        case .recommendedCards:
            currentSources = recommendedSources
        case .selectedCards:
            currentSources = selectedSources
        case .singleCard:
            currentSources = singleSources
        }

        let sourceKinds = currentSources.map(\.kind)
        guard !sourceKinds.isEmpty else { return nil }

        let targetKind = preferredTargetKind ?? defaultConversionTargetKind(for: sourceKinds)
        let sourceKindFilters = Set(
            currentSources
                .map(\.kind)
                .filter { $0 != targetKind }
        )
        let newDeckTitle = "\(deck.title) \(targetKind.displayTitle)s"

        return DeckCardConversionRequest(
            availableScopes: availableScopes,
            wholeDeckSources: wholeDeckSources,
            recommendedSources: recommendedSources,
            selectedSources: selectedSources,
            singleSources: singleSources,
            scope: preferredScope,
            sourceKindFilters: sourceKindFilters,
            targetKind: targetKind,
            destination: .sameDeck,
            newDeckTitle: newDeckTitle
        )
    }

    private func defaultConversionTargetKind(for sourceKinds: [CardKind]) -> CardKind {
        let sourceKindSet = Set(sourceKinds)
        let orderedTargets: [CardKind] = [.match, .quiz, .write, .flashcard]
        return orderedTargets.first(where: { !sourceKindSet.contains($0) }) ?? .match
    }

    private func orderedSelectedCardIDs() -> [PersistentIdentifier] {
        visibleCardsInDisplayOrder()
            .filter { selectedCards.contains($0.id) }
            .map(\.id)
    }

    private func recommendedConversionCardIDs(for targetKind: CardKind) -> [PersistentIdentifier] {
        visibleCardsInDisplayOrder()
            .filter { card in
                CardReadinessDiagnostics.diagnostics(for: card)
                    .contains { $0.recommendedConversionTargetKind == targetKind }
            }
            .map(\.id)
    }

    private func visibleCardsInDisplayOrder() -> [GridCardInfo] {
        cachedGroupedCards.flatMap(\.cards)
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

private extension GridCardInfo {
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
