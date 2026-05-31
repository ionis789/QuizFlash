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
    func testExportImportRoundTripPreservesSupportedCards() async throws {
        let exportContext = try TestModelContainerFactory.makeContext()

        let deck = DeckModel(title: "Round Trip", colorHex: "#ABCDEF")
        let flashcard = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.flashcard(front: "Base", back: "Source"),
            cardNumber: 1
        )

        exportContext.insert(deck)
        exportContext.insert(flashcard)

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

        deck.cards = [flashcard, quizCard]
        deck.cardCount = 2
        deck.lastAssignedCardNumber = 2

        try exportContext.save()

        let manager = DeckSharingManager.shared
        let fileURL = try await manager.exportDeck(deck)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let importContext = try TestModelContainerFactory.makeContext()
        let importedDeck = try await manager.importDeck(from: fileURL, into: importContext)

        XCTAssertEqual(importedDeck.title, "Round Trip")
        XCTAssertEqual(importedDeck.colorHex, "#ABCDEF")
        XCTAssertEqual(importedDeck.cardCount, 2)

        XCTAssertEqual(importedDeck.cards.map(\.cardContent.kind).sorted(by: { $0.rawValue < $1.rawValue }), [
            .flashcard,
            .quiz
        ].sorted(by: { $0.rawValue < $1.rawValue }))

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
