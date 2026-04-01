//
//  CreateDeckViewModelTests.swift
//  QuizFlashTests
//
//  Covers create, update, and delete mutations for deck authoring.
//

import XCTest
import SwiftData
@testable import QuizFlash

@MainActor
final class CreateDeckViewModelTests: XCTestCase {
    func testSaveDeckCreatesDeckAndCardsInSelectedFolder() throws {
        let context = try TestModelContainerFactory.makeContext()
        let folder = FolderModel(title: "Science", colorHex: "#22AA88")
        context.insert(folder)
        try context.save()

        let viewModel = CreateDeckViewModel(deckToEdit: nil)
        viewModel.deckTitle = "  Biology  "
        viewModel.selectedFolder = folder
        viewModel.addCard(content: TestMutationFactory.flashcard(front: "Cell", back: "Basic unit"))
        viewModel.addCard(content: TestMutationFactory.match(prompt: "ATP", answer: "Energy"))

        let didSave = viewModel.saveDeck(context: context)

        XCTAssertTrue(didSave)

        let decks = try context.fetchAll(DeckModel.self)
        XCTAssertEqual(decks.count, 1)

        let deck = try XCTUnwrap(decks.first)
        XCTAssertEqual(deck.title, "Biology")
        XCTAssertEqual(deck.folder?.persistentModelID, folder.persistentModelID)
        XCTAssertEqual(folder.deckCount, 1)
        XCTAssertEqual(deck.cardCount, 2)
        XCTAssertEqual(deck.lastAssignedCardNumber, 2)
        XCTAssertEqual(deck.cards.count, 2)
        XCTAssertEqual(deck.cards.map(\.cardNumber).sorted(), [1, 2])
        XCTAssertEqual(
            deck.cards.map(\.cardContent.kind).sorted { $0.rawValue < $1.rawValue },
            [.flashcard, .match].sorted { $0.rawValue < $1.rawValue }
        )
    }

    func testSaveDeckUpdatesExistingDeckAndReconcilesCardsAndFolder() throws {
        let context = try TestModelContainerFactory.makeContext()
        let sourceFolder = FolderModel(title: "Old", colorHex: "#111111")
        let destinationFolder = FolderModel(title: "New", colorHex: "#222222")
        sourceFolder.deckCount = 1
        context.insert(sourceFolder)
        context.insert(destinationFolder)

        let deck = DeckModel(title: "Original", icon: "book.closed.fill", colorHex: "#FFFFFF")

        context.insert(sourceFolder)
        context.insert(destinationFolder)
        context.insert(deck)

        deck.folder = sourceFolder

        let firstCard = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.flashcard(front: "Q1", back: "A1"),
            cardNumber: 1
        )

        let secondCard = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.flashcard(front: "Q2", back: "A2"),
            cardNumber: 2
        )

        deck.cards = [firstCard, secondCard]
        deck.cardCount = 2
        deck.lastAssignedCardNumber = 2

        context.insert(firstCard)
        context.insert(secondCard)
        try context.save()

        let editableDeck = try XCTUnwrap(
            context.model(for: deck.persistentModelID) as? DeckModel
        )

        let viewModel = CreateDeckViewModel(deckToEdit: editableDeck)
        viewModel.deckTitle = "Updated Deck"
        viewModel.selectedFolder = destinationFolder

        let firstDraft = try XCTUnwrap(viewModel.draftCards.first(where: { $0.cardNumber == 1 }))
        viewModel.updateCard(
            firstDraft,
            content: TestMutationFactory.flashcard(front: "Edited Question", back: "Edited Answer")
        )
        viewModel.draftCards.removeAll { $0.cardNumber == 2 }
        viewModel.addCard(content: TestMutationFactory.write(prompt: "Water formula", answer: "H2O"))

        let didSave = viewModel.saveDeck(context: context)
        XCTAssertTrue(didSave)

        XCTAssertEqual(editableDeck.title, "Updated Deck")
        XCTAssertEqual(editableDeck.folder?.persistentModelID, destinationFolder.persistentModelID)
        XCTAssertEqual(sourceFolder.deckCount, 0)
        XCTAssertEqual(destinationFolder.deckCount, 1)
        XCTAssertEqual(editableDeck.cardCount, 2)
        XCTAssertEqual(editableDeck.lastAssignedCardNumber, 3)

        let persistedCards = editableDeck.cards.sorted { $0.cardNumber < $1.cardNumber }
        XCTAssertEqual(persistedCards.count, 2)
        XCTAssertEqual(persistedCards.map(\.cardNumber), [1, 3])
        XCTAssertEqual(persistedCards[0].cardContent.previewCache.front, "Edited Question")
        XCTAssertEqual(persistedCards[1].cardContent.kind, .write)
    }

    func testDeleteDeckRemovesPersistedDeckAndUpdatesFolderCount() throws {
        let context = try TestModelContainerFactory.makeContext()
        let folder = FolderModel(title: "Delete", colorHex: "#333333")
        folder.deckCount = 1

        let deck = DeckModel(title: "Disposable", icon: "book.closed.fill", colorHex: "#FFFFFF")

        context.insert(folder)
        context.insert(deck)
        deck.folder = folder
        try context.save()

        let viewModel = CreateDeckViewModel(deckToEdit: deck)
        let didDelete = viewModel.deleteDeck(
            context: context,
            router: NavigationManager(),
            dismissAction: {}
        )

        XCTAssertTrue(didDelete)
        XCTAssertTrue(try context.fetchAll(DeckModel.self).isEmpty)
        XCTAssertEqual(folder.deckCount, 0)
    }

    func testDeleteSelectedDraftCardsRemovesOnlyChosenDrafts() {
        let viewModel = CreateDeckViewModel(deckToEdit: nil)
        viewModel.addCard(content: TestMutationFactory.flashcard(front: "One", back: "1"))
        viewModel.addCard(content: TestMutationFactory.flashcard(front: "Two", back: "2"))
        viewModel.addCard(content: TestMutationFactory.write(prompt: "Three", answer: "3"))

        let selectedIDs = Set(viewModel.draftCards.prefix(2).map(\.id))
        viewModel.enterCardSelectionMode()
        viewModel.selectedDraftCardIDs = selectedIDs
        viewModel.requestDeleteSelectedCards()
        viewModel.deleteSelectedCards()

        XCTAssertEqual(viewModel.draftCards.count, 1)
        XCTAssertEqual(viewModel.draftCards.first?.content.kind, .write)
        XCTAssertFalse(viewModel.isSelectingCards)
        XCTAssertTrue(viewModel.selectedDraftCardIDs.isEmpty)
        XCTAssertFalse(viewModel.showDeleteSelectedCardsConfirmation)
    }

    func testRevertToInitialStateRestoresOriginalDraftDeckState() throws {
        let context = try TestModelContainerFactory.makeContext()
        let folder = FolderModel(title: "Initial", colorHex: "#111111")
        let deck = DeckModel(title: "Original Title", icon: "book.closed.fill", colorHex: "#FFFFFF")
        let card = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.flashcard(front: "Prompt", back: "Answer"),
            cardNumber: 1
        )

        context.insert(folder)
        context.insert(deck)
        context.insert(card)
        deck.folder = folder
        deck.cards = [card]
        deck.cardCount = 1
        deck.lastAssignedCardNumber = 1
        try context.save()

        let editableDeck = try XCTUnwrap(context.model(for: deck.persistentModelID) as? DeckModel)
        let viewModel = CreateDeckViewModel(deckToEdit: editableDeck)
        let originalDraftID = try XCTUnwrap(viewModel.draftCards.first?.id)

        viewModel.deckTitle = "Changed"
        viewModel.selectedFolder = nil
        viewModel.addCard(content: TestMutationFactory.match(prompt: "ATP", answer: "Energy"))
        viewModel.enterCardSelectionMode()
        viewModel.selectedDraftCardIDs = [originalDraftID]
        viewModel.requestDeleteSelectedCards()

        viewModel.revertToInitialState()

        XCTAssertEqual(viewModel.deckTitle, "Original Title")
        XCTAssertEqual(viewModel.selectedFolder?.persistentModelID, folder.persistentModelID)
        XCTAssertEqual(viewModel.draftCards.count, 1)
        XCTAssertEqual(viewModel.draftCards.first?.cardNumber, 1)
        XCTAssertFalse(viewModel.isSelectingCards)
        XCTAssertTrue(viewModel.selectedDraftCardIDs.isEmpty)
        XCTAssertFalse(viewModel.showDeleteSelectedCardsConfirmation)
    }

    func testSaveDeckResetsWorkshopStateAfterSuccessfulCreate() async throws {
        let context = try TestModelContainerFactory.makeContext()
        let folder = FolderModel(title: "Reset", colorHex: "#445566")
        context.insert(folder)
        try context.save()

        let viewModel = CreateDeckViewModel(deckToEdit: nil)
        viewModel.deckTitle = "Physics"
        viewModel.selectedFolder = folder
        viewModel.addCard(content: TestMutationFactory.flashcard(front: "Mass", back: "Matter amount"))

        XCTAssertTrue(viewModel.saveDeck(context: context))

        try await Task.sleep(for: .milliseconds(1300))

        XCTAssertEqual(viewModel.deckTitle, "")
        XCTAssertNil(viewModel.selectedFolder)
        XCTAssertTrue(viewModel.draftCards.isEmpty)
        XCTAssertFalse(viewModel.showSuccessOverlay)
        XCTAssertFalse(viewModel.isEditingExistingDeck)
        XCTAssertFalse(viewModel.hasUnsavedChanges)
    }

    func testSaveDeckResetsWorkshopStateAfterSuccessfulEdit() async throws {
        let context = try TestModelContainerFactory.makeContext()
        let deck = DeckModel(title: "Original", icon: "book.closed.fill", colorHex: "#FFFFFF")
        let card = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.flashcard(front: "Prompt", back: "Answer"),
            cardNumber: 1
        )

        context.insert(deck)
        context.insert(card)
        deck.cards = [card]
        deck.cardCount = 1
        deck.lastAssignedCardNumber = 1
        try context.save()

        let editableDeck = try XCTUnwrap(context.model(for: deck.persistentModelID) as? DeckModel)
        let viewModel = CreateDeckViewModel(deckToEdit: editableDeck)
        viewModel.deckTitle = "Updated"
        let draft = try XCTUnwrap(viewModel.draftCards.first)
        viewModel.updateCard(
            draft,
            content: TestMutationFactory.flashcard(front: "Edited", back: "Changed")
        )

        XCTAssertTrue(viewModel.saveDeck(context: context))
        try await Task.sleep(for: .milliseconds(1300))

        XCTAssertEqual(editableDeck.title, "Updated")
        XCTAssertEqual(editableDeck.cards.first?.cardContent.previewCache.front, "Edited")
        XCTAssertEqual(viewModel.deckTitle, "")
        XCTAssertTrue(viewModel.draftCards.isEmpty)
        XCTAssertFalse(viewModel.isEditingExistingDeck)
        XCTAssertFalse(viewModel.hasUnsavedChanges)
    }

    func testIntegrateAllDraftCardsIntoBaselineClearsInlineAISessionState() {
        let viewModel = CreateDeckViewModel(deckToEdit: nil)
        let existingDraft = DraftCard(
            cardNumber: 1,
            content: TestMutationFactory.flashcard(front: "Cell", back: "Basic unit"),
            isPinned: false,
            creationSource: .manual,
            createdAt: Date(),
            editedAt: Date()
        )
        let generatedDraft = DraftCard(
            cardNumber: 2,
            content: TestMutationFactory.flashcard(front: "ATP", back: "Energy molecule"),
            isPinned: false,
            creationSource: .ai,
            createdAt: Date(),
            editedAt: Date()
        )

        viewModel.draftCards = [existingDraft, generatedDraft]
        viewModel.replaceDraftSessionBaseline(with: [existingDraft])
        viewModel.registerSessionDraftID(generatedDraft.id, marksAsAI: true)

        XCTAssertEqual(viewModel.baseDraftCards.count, 1)
        XCTAssertEqual(viewModel.aiSessionDraftCards.count, 1)

        viewModel.integrateAllDraftCardsIntoBaseline()

        XCTAssertFalse(viewModel.hasAISessionDraftCards)
        XCTAssertEqual(viewModel.baseDraftCards.count, 2)
        XCTAssertEqual(viewModel.sessionDraftCards.count, 0)
        XCTAssertEqual(viewModel.draftCards.count, 2)
    }

    func testCompleteAIGenerationMovesGeneratedCardsIntoBaseline() {
        let viewModel = CreateDeckViewModel(deckToEdit: nil)
        let existingDraft = DraftCard(
            cardNumber: 1,
            content: TestMutationFactory.flashcard(front: "Cell", back: "Basic unit"),
            isPinned: false,
            creationSource: .manual,
            createdAt: Date(),
            editedAt: Date()
        )
        let generatedDraft = DraftCard(
            cardNumber: 2,
            content: TestMutationFactory.flashcard(front: "ATP", back: "Energy molecule"),
            isPinned: false,
            creationSource: .ai,
            createdAt: Date(),
            editedAt: Date()
        )

        viewModel.draftCards = [existingDraft, generatedDraft]
        viewModel.replaceDraftSessionBaseline(with: [existingDraft])
        viewModel.registerSessionDraftID(generatedDraft.id, marksAsAI: true)
        viewModel.aiGeneratedCardCount = 1
        viewModel.aiTargetCardCount = 1
        viewModel.aiState = .generatingCards(progress: 1, foundCount: 1)

        viewModel.completeAIGeneration()

        XCTAssertEqual(viewModel.baseDraftCards.count, 2)
        XCTAssertEqual(viewModel.sessionDraftCards.count, 0)
        XCTAssertFalse(viewModel.hasAISessionDraftCards)
        XCTAssertEqual(viewModel.aiGeneratedCardCount, 0)
        XCTAssertEqual(viewModel.aiTargetCardCount, 0)
        XCTAssertEqual(viewModel.aiState, .idle)
    }

    func testBeginAIGenerationSessionForResumeKeepsExistingAISessionCardsVisible() {
        let viewModel = CreateDeckViewModel(deckToEdit: nil)
        let existingDraft = DraftCard(
            cardNumber: 1,
            content: TestMutationFactory.flashcard(front: "Cell", back: "Basic unit"),
            isPinned: false,
            creationSource: .manual,
            createdAt: Date(),
            editedAt: Date()
        )
        let generatedDraft = DraftCard(
            cardNumber: 2,
            content: TestMutationFactory.flashcard(front: "ATP", back: "Energy molecule"),
            isPinned: false,
            creationSource: .ai,
            createdAt: Date(),
            editedAt: Date()
        )

        viewModel.draftCards = [existingDraft, generatedDraft]
        viewModel.replaceDraftSessionBaseline(with: [existingDraft])
        viewModel.registerSessionDraftID(generatedDraft.id, marksAsAI: true)
        viewModel.aiGeneratedCardCount = 1
        viewModel.aiTargetCardCount = 3

        viewModel.beginAIGenerationSession(targetCardCount: 2, shouldResetProgress: false)

        XCTAssertEqual(viewModel.aiGeneratedCardCount, 1)
        XCTAssertEqual(viewModel.aiTargetCardCount, 3)
        XCTAssertEqual(viewModel.aiSessionDraftCards.map(\.id), [generatedDraft.id])
    }

    func testFlushPendingGeneratedCardsPromotesQueuedCardsIntoActiveAISession() throws {
        let viewModel = CreateDeckViewModel(deckToEdit: nil)
        let existingDraft = DraftCard(
            cardNumber: 1,
            content: TestMutationFactory.flashcard(front: "Cell", back: "Basic unit"),
            isPinned: false,
            creationSource: .manual,
            createdAt: Date(),
            editedAt: Date()
        )

        viewModel.draftCards = [existingDraft]
        viewModel.replaceDraftSessionBaseline(with: [existingDraft])
        viewModel.aiTargetCardCount = 2
        viewModel.pendingAIGeneratedCards = [
            AIFlashcard(question: "Q1", answer: "A1"),
            AIFlashcard(question: "Q2", answer: "A2")
        ]

        viewModel.flushPendingGeneratedCards()

        XCTAssertTrue(viewModel.pendingAIGeneratedCards.isEmpty)
        XCTAssertEqual(viewModel.aiGeneratedCardCount, 2)
        XCTAssertEqual(viewModel.aiSessionDraftCards.count, 2)
        XCTAssertEqual(viewModel.draftCards.count, 3)
    }
}
