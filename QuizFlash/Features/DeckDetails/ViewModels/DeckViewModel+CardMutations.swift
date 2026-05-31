//
//  DeckViewModel+CardMutations.swift
//  QuizFlash
//
//  Selection and card mutation flows for the deck screen.
//

import SwiftUI
import SwiftData
import OSLog

extension DeckViewModel {
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
            presentMutationError(error)
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
            presentMutationError(error)
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
            presentMutationError(error)
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
            presentMutationError(error)
        }
    }
}
