//
//  DeckConversionPersistenceTests.swift
//  QuizFlashTests
//
//  Covers progressive converted-card persistence for same-deck and new-deck runs.
//

import XCTest
import SwiftData
@testable import QuizFlash

@MainActor
final class DeckConversionPersistenceTests: XCTestCase {
    func testPersistConvertedOutputsSameDeckAppendsConvertedCardsWithLineageMetadata() throws {
        let context = try TestModelContainerFactory.makeContext()
        let deck = DeckModel(title: "Graphs", colorHex: "#123456")
        let sourceCard = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.flashcard(front: "BFS", back: "Breadth-first search"),
            cardNumber: 1
        )

        context.insert(deck)
        context.insert(sourceCard)
        deck.cards = [sourceCard]
        deck.cardCount = 1
        deck.lastAssignedCardNumber = 1
        try context.save()

        let request = DeckCardConversionRequest(
            availableScopes: [.wholeDeck],
            wholeDeckSources: [
                DeckCardConversionSourceDescriptor(id: sourceCard.persistentModelID, kind: .flashcard)
            ],
            recommendedSources: [],
            selectedSources: [],
            singleSources: [],
            scope: .wholeDeck,
            sourceKind: .flashcard,
            targetKind: .match,
            destination: .sameDeck,
            newDeckTitle: ""
        )
        let sourceSnapshot = CardConversionSourceSnapshot(
            id: sourceCard.persistentModelID,
            kind: .flashcard,
            content: sourceCard.cardContent
        )
        let output = AICardConversionOutput(
            sourceCardID: sourceCard.persistentModelID,
            generatedCard: AIFlashcard(matchPrompt: "DFS", matchAnswer: "Depth-first search")
        )

        var destinationDeck: DeckModel?
        let batchID = UUID()
        let convertedAt = Date()
        let coordinator = AIWorkspaceCoordinator()

        let persistedCount = try coordinator.persistConvertedOutputs(
            [output],
            request: request,
            sourcesByID: [sourceSnapshot.id: sourceSnapshot],
            batchID: batchID,
            convertedAt: convertedAt,
            sourceDeck: deck,
            destinationDeck: &destinationDeck,
            context: context
        )

        XCTAssertEqual(persistedCount, 1)
        XCTAssertNil(destinationDeck)
        XCTAssertEqual(deck.cardCount, 2)
        XCTAssertEqual(deck.lastAssignedCardNumber, 2)
        XCTAssertEqual(deck.cards.count, 2)

        guard let convertedCard = deck.cards.first(where: {
            $0.creationSource == .ai && $0.cardNumber == 2
        }) else {
            return XCTFail("Expected the converted card to be appended to the same deck.")
        }

        XCTAssertEqual(convertedCard.creationSource, .ai)
        XCTAssertEqual(convertedCard.cardContent.kind, .match)
        guard let metadata = convertedCard.conversionMetadata else {
            return XCTFail("Expected converted cards to keep conversion lineage metadata.")
        }
        XCTAssertEqual(metadata.sourceCardID, sourceCard.persistentModelID)
        XCTAssertEqual(metadata.sourceKind, .flashcard)
        XCTAssertEqual(metadata.targetKind, .match)
        XCTAssertEqual(metadata.batchID, batchID)
        XCTAssertEqual(metadata.convertedAt.timeIntervalSince1970, convertedAt.timeIntervalSince1970, accuracy: 0.001)
    }

    func testPersistConvertedOutputsNewDeckCreatesSiblingDeckAndCarriesLineageMetadata() throws {
        let context = try TestModelContainerFactory.makeContext()
        let folder = FolderModel(title: "CS", colorHex: "#654321")
        let deck = DeckModel(title: "Graphs", colorHex: "#123456")
        deck.cardGroupingMode = .byCardType

        let sourceCard = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.flashcard(front: "BFS", back: "Breadth-first search"),
            cardNumber: 1
        )

        context.insert(folder)
        context.insert(deck)
        context.insert(sourceCard)
        deck.folder = folder
        folder.deckCount = 1
        deck.cards = [sourceCard]
        deck.cardCount = 1
        deck.lastAssignedCardNumber = 1
        try context.save()

        let request = DeckCardConversionRequest(
            availableScopes: [.wholeDeck],
            wholeDeckSources: [
                DeckCardConversionSourceDescriptor(id: sourceCard.persistentModelID, kind: .flashcard)
            ],
            recommendedSources: [],
            selectedSources: [],
            singleSources: [],
            scope: .wholeDeck,
            sourceKind: .flashcard,
            targetKind: .match,
            destination: .newDeck,
            newDeckTitle: "Graphs Match"
        )
        let sourceSnapshot = CardConversionSourceSnapshot(
            id: sourceCard.persistentModelID,
            kind: .flashcard,
            content: sourceCard.cardContent
        )
        let output = AICardConversionOutput(
            sourceCardID: sourceCard.persistentModelID,
            generatedCard: AIFlashcard(matchPrompt: "DFS", matchAnswer: "Depth-first search")
        )

        var destinationDeck: DeckModel?
        let batchID = UUID()
        let convertedAt = Date()
        let coordinator = AIWorkspaceCoordinator()

        let persistedCount = try coordinator.persistConvertedOutputs(
            [output],
            request: request,
            sourcesByID: [sourceSnapshot.id: sourceSnapshot],
            batchID: batchID,
            convertedAt: convertedAt,
            sourceDeck: deck,
            destinationDeck: &destinationDeck,
            context: context
        )

        XCTAssertEqual(persistedCount, 1)
        XCTAssertEqual(folder.deckCount, 2)

        guard let createdDeck = destinationDeck else {
            return XCTFail("Expected conversion to create a sibling destination deck.")
        }

        XCTAssertEqual(createdDeck.title, "Graphs Match")
        XCTAssertEqual(createdDeck.colorHex, deck.colorHex)
        XCTAssertEqual(createdDeck.folder?.persistentModelID, folder.persistentModelID)
        XCTAssertEqual(createdDeck.cardGroupingMode, .byCardType)
        XCTAssertEqual(createdDeck.cardCount, 1)
        XCTAssertEqual(createdDeck.cards.count, 1)

        guard let convertedCard = createdDeck.cards.first(where: { $0.creationSource == .ai }) else {
            return XCTFail("Expected the new deck to contain the converted card.")
        }

        XCTAssertEqual(convertedCard.creationSource, .ai)
        XCTAssertEqual(convertedCard.cardContent.kind, .match)
        guard let metadata = convertedCard.conversionMetadata else {
            return XCTFail("Expected converted cards to keep conversion lineage metadata.")
        }
        XCTAssertEqual(metadata.sourceCardID, sourceCard.persistentModelID)
        XCTAssertEqual(metadata.sourceKind, .flashcard)
        XCTAssertEqual(metadata.targetKind, .match)
        XCTAssertEqual(metadata.batchID, batchID)
        XCTAssertEqual(metadata.convertedAt.timeIntervalSince1970, convertedAt.timeIntervalSince1970, accuracy: 0.001)
    }
}
