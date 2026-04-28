//
//  PlayModeCardRepositoryTests.swift
//  QuizFlashTests
//
//  Covers staged play-mode payload loading.
//

import SwiftData
import XCTest
@testable import QuizFlash

@MainActor
final class PlayModeCardRepositoryTests: XCTestCase {
    func testPlayableCardBatchLoadsLimitedStudyOrderWithoutLosingTotalCount() async throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let deck = DeckModel(title: "Batch Deck", colorHex: "#111111")
        let first = makeFlashcard(number: 1, interval: 10)
        let second = makeFlashcard(number: 2, interval: 0)
        let third = makeFlashcard(number: 3, interval: 3)
        let fourth = makeFlashcard(number: 4, interval: 0)
        let fifth = makeFlashcard(number: 5, interval: 6)
        let quiz = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.quiz(
                question: "Ignored?",
                correctAnswers: ["Yes"],
                incorrectAnswers: ["No"]
            ),
            cardNumber: 6
        )

        context.insert(deck)
        [first, second, third, fourth, fifth, quiz].forEach {
            context.insert($0)
            $0.deck = deck
        }
        deck.cards = [first, second, third, fourth, fifth, quiz]
        deck.cardCount = 6
        try context.save()

        let repository = PlayModeCardRepository(container: container)
        let batch = await repository.loadPlayableCardBatch(
            for: deck.persistentModelID,
            order: .studyPriority,
            limit: 2
        )

        XCTAssertEqual(batch.totalCount, 5)
        XCTAssertFalse(batch.loadedAll)
        XCTAssertEqual(batch.cards.map(\.cardNumber), [2, 4])
    }

    func testPlayableCardBatchCanLoadRemainingCardsExcludingInitialBatch() async throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let deck = DeckModel(title: "Remaining Deck", colorHex: "#222222")
        let cards = [
            makeFlashcard(number: 1, interval: 8),
            makeFlashcard(number: 2, interval: 0),
            makeFlashcard(number: 3, interval: 2),
            makeFlashcard(number: 4, interval: 0)
        ]

        context.insert(deck)
        cards.forEach {
            context.insert($0)
            $0.deck = deck
        }
        deck.cards = cards
        deck.cardCount = cards.count
        try context.save()

        let repository = PlayModeCardRepository(container: container)
        let initialBatch = await repository.loadPlayableCardBatch(
            for: deck.persistentModelID,
            order: .studyPriority,
            limit: 2
        )
        let remainingBatch = await repository.loadPlayableCardBatch(
            for: deck.persistentModelID,
            order: .studyPriority,
            excludingIDs: Set(initialBatch.cards.map(\.id))
        )

        XCTAssertEqual(initialBatch.cards.map(\.cardNumber), [2, 4])
        XCTAssertEqual(remainingBatch.totalCount, 4)
        XCTAssertTrue(remainingBatch.loadedAll)
        XCTAssertEqual(remainingBatch.cards.map(\.cardNumber), [3, 1])
    }

    private func makeFlashcard(number: Int, interval: Int) -> CardModel {
        let card = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.flashcard(front: "Front \(number)", back: "Back \(number)"),
            cardNumber: number
        )
        card.interval = interval
        return card
    }
}
