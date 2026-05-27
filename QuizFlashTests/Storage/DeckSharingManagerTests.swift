//
//  DeckSharingManagerTests.swift
//  QuizFlashTests
//
//  Covers export and import persistence round-trips for .qflash decks.
//

import XCTest
import SwiftData
@testable import QuizFlash

@MainActor
final class DeckSharingManagerTests: XCTestCase {
    func testExportImportRoundTripPreservesMixedCardMetadata() async throws {
        let exportContext = try TestModelContainerFactory.makeContext()

        let deck = DeckModel(title: "Round Trip", colorHex: "#ABCDEF")
        let sourceCard = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.flashcard(front: "Base", back: "Source"),
            cardNumber: 1
        )

        exportContext.insert(deck)
        exportContext.insert(sourceCard)

        let convertedCard = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.match(prompt: "ATP", answer: "Energy"),
            cardNumber: 2,
            creationSource: .ai,
            conversionMetadata: CardConversionMetadata(
                sourceCardID: sourceCard.persistentModelID,
                sourceKind: .flashcard,
                targetKind: .match,
                batchID: UUID(),
                convertedAt: Date()
            )
        )
        exportContext.insert(convertedCard)

        let quizCard = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.quiz(
                question: "Largest planet?",
                correctAnswers: ["Jupiter"],
                incorrectAnswers: ["Mars", "Venus"],
                explanation: "Gas giant."
            ),
            cardNumber: 3
        )
        exportContext.insert(quizCard)

        let writeCard = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.write(prompt: "Chemical symbol for sodium is Na", answer: "Na"),
            cardNumber: 4
        )
        exportContext.insert(writeCard)

        deck.cards = [sourceCard, convertedCard, quizCard, writeCard]
        deck.cardCount = 4
        deck.lastAssignedCardNumber = 4

        try exportContext.save()

        let manager = DeckSharingManager.shared
        let fileURL = try await manager.exportDeck(deck)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let importContext = try TestModelContainerFactory.makeContext()
        let importedDeck = try await manager.importDeck(from: fileURL, into: importContext)

        XCTAssertEqual(importedDeck.title, "Round Trip")
        XCTAssertEqual(importedDeck.colorHex, "#ABCDEF")
        XCTAssertEqual(importedDeck.cardCount, 4)

        let importedCards = importedDeck.cards.sorted { $0.frontText < $1.frontText }
        XCTAssertEqual(importedCards.map(\.cardContent.kind).sorted(by: { $0.rawValue < $1.rawValue }), [
            .flashcard,
            .match,
            .quiz,
            .write
        ].sorted(by: { $0.rawValue < $1.rawValue }))

        let importedMatchCard = try XCTUnwrap(
            importedDeck.cards.first(where: { $0.cardContent.kind == .match })
        )
        XCTAssertEqual(importedMatchCard.creationSource, .ai)
        XCTAssertEqual(importedMatchCard.conversionMetadata?.sourceKind, .flashcard)
        XCTAssertEqual(importedMatchCard.conversionMetadata?.targetKind, .match)

        let importedQuizCard = try XCTUnwrap(
            importedDeck.cards.first(where: { $0.cardContent.kind == .quiz })
        )
        if case .quiz(let quizContent) = importedQuizCard.cardContent {
            XCTAssertEqual(quizContent.choices.count, 3)
            XCTAssertEqual(quizContent.explanationZone?.text, "Gas giant.")
        } else {
            XCTFail("Expected imported quiz payload")
        }
    }
}
