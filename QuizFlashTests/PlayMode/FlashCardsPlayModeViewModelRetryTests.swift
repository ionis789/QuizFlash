//
//  FlashCardsPlayModeViewModelRetryTests.swift
//  QuizFlashTests
//
//  Regression coverage for repeated flashcard retry rounds.
//

import SwiftData
import XCTest
@testable import QuizFlash

@MainActor
final class FlashCardsPlayModeViewModelRetryTests: XCTestCase {
    func testRetryCanRepeatUntilWrongCardsAreAnsweredCorrectly() throws {
        let fixture = try makeFlashcardFixture()
        let viewModel = FlashCardsPlayModeViewModel(
            deck: fixture.deck,
            settings: FlashcardModeSettings()
        )
        viewModel.cards = [fixture.playableCard]
        viewModel.totalCardCount = 1
        viewModel.hasLoadedAllCards = true
        viewModel.isSessionStarted = true

        viewModel.handleSwipe(.left)

        XCTAssertTrue(viewModel.isComplete)
        XCTAssertEqual(viewModel.wrongCards.map(\.id), [fixture.playableCard.id])

        viewModel.retryWrongCards()

        XCTAssertFalse(viewModel.isComplete)
        XCTAssertEqual(viewModel.playRunGeneration, 1)
        XCTAssertEqual(viewModel.cards.map(\.id), [fixture.playableCard.id])
        XCTAssertTrue(viewModel.wrongCards.isEmpty)

        viewModel.handleSwipe(.left)

        XCTAssertTrue(viewModel.isComplete)
        XCTAssertEqual(viewModel.wrongCards.map(\.id), [fixture.playableCard.id])

        viewModel.retryWrongCards()

        XCTAssertFalse(viewModel.isComplete)
        XCTAssertEqual(viewModel.playRunGeneration, 2)
        XCTAssertEqual(viewModel.cards.map(\.id), [fixture.playableCard.id])
        XCTAssertTrue(viewModel.wrongCards.isEmpty)
    }

    func testEmptyRetryDoesNotCreateAnActiveRunWithoutCards() throws {
        let fixture = try makeFlashcardFixture()
        let viewModel = FlashCardsPlayModeViewModel(
            deck: fixture.deck,
            settings: FlashcardModeSettings()
        )
        viewModel.isComplete = true
        viewModel.totalCardCount = 1

        viewModel.retryWrongCards()

        XCTAssertTrue(viewModel.isComplete)
        XCTAssertTrue(viewModel.cards.isEmpty)
        XCTAssertEqual(viewModel.totalCardCount, 1)
        XCTAssertEqual(viewModel.playRunGeneration, 0)
    }

    private func makeFlashcardFixture() throws -> (deck: DeckModel, playableCard: PlayableCard) {
        let context = try TestModelContainerFactory.makeContext()
        let deck = DeckModel(title: "Flashcards", colorHex: "#111111")
        let card = CardModel(
            content: .flashcard(
                FlashcardCardContent(
                    frontZone: .text("Front"),
                    backZone: .text("Back"),
                    frontType: .text,
                    backType: .text
                )
            ),
            cardNumber: 1
        )

        context.insert(deck)
        context.insert(card)
        card.deck = deck
        deck.cards = [card]
        deck.cardCount = 1
        try context.save()

        return (
            deck,
            PlayableCard(
                id: card.persistentModelID,
                cardNumber: card.cardNumber,
                frontZone: card.frontZone,
                backZone: card.backZone,
                interval: card.interval
            )
        )
    }
}
