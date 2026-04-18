//
//  PlaySessionPersistenceServiceTests.swift
//  QuizFlashTests
//
//  Covers detached persistence for play-mode review writes.
//

import XCTest
import SwiftData
@testable import QuizFlash

@MainActor
final class PlaySessionPersistenceServiceTests: XCTestCase {
    func testPersistReviewsWritesReviewHistoryDailyLogAndUserProfile() async throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let setupContext = ModelContext(container)

        let deck = DeckModel(title: "Review Deck", colorHex: "#FFFFFF")
        let card = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.flashcard(front: "Front", back: "Back"),
            cardNumber: 1
        )

        setupContext.insert(deck)
        setupContext.insert(card)
        deck.cards = [card]
        card.deck = deck
        deck.cardCount = 1
        deck.lastAssignedCardNumber = 1

        try setupContext.save()

        let service = PlaySessionPersistenceService(container: container)
        await service.persistReviews([
            PlaySessionReviewWrite(
                cardID: card.persistentModelID,
                difficulty: .good,
                timeSpent: 4.5,
                xpAwarded: 12
            ),
            PlaySessionReviewWrite(
                cardID: card.persistentModelID,
                difficulty: .easy,
                timeSpent: 2.0,
                xpAwarded: 20
            )
        ])

        let verificationContext = ModelContext(container)
        let persistedCard = try XCTUnwrap(
            verificationContext.model(for: card.persistentModelID) as? CardModel
        )
        let logs = try verificationContext.fetchAll(DailyActivityLog.self)
        let profiles = try verificationContext.fetchAll(UserProfile.self)
        let dailyAggregates = try verificationContext.fetchAll(HomeDailyStudyAggregate.self)
        let deckAggregates = try verificationContext.fetchAll(HomeDailyDeckAggregate.self)
        let cardAggregates = try verificationContext.fetchAll(HomeDailyCardAggregate.self)

        XCTAssertEqual(persistedCard.reviewHistory.count, 2)
        XCTAssertEqual(persistedCard.reviewHistory.map(\.xpAwarded).sorted(), [12, 20])
        XCTAssertEqual(persistedCard.consecutiveCorrectAnswers, 2)
        XCTAssertEqual(persistedCard.interval, 6)
        XCTAssertGreaterThan(persistedCard.dueDate, Date().addingTimeInterval(5 * 24 * 60 * 60))

        let log = try XCTUnwrap(logs.first)
        XCTAssertEqual(log.cardsReviewed, 2)
        XCTAssertEqual(log.xpEarnedToday, 32)
        XCTAssertEqual(log.newCardsLearned, 1)

        let dailyAggregate = try XCTUnwrap(dailyAggregates.first)
        XCTAssertEqual(dailyAggregate.uniqueCardCount, 1)
        XCTAssertEqual(dailyAggregate.rawReviewCount, 2)
        XCTAssertEqual(dailyAggregate.landedCount, 1)
        XCTAssertEqual(dailyAggregate.retryCount, 0)
        XCTAssertEqual(dailyAggregate.xpEarned, 32)
        XCTAssertEqual(dailyAggregate.newCardsLearned, 1)

        let deckAggregate = try XCTUnwrap(deckAggregates.first)
        XCTAssertEqual(deckAggregate.uniqueCardCount, 1)
        XCTAssertEqual(deckAggregate.landedCount, 1)
        XCTAssertEqual(deckAggregate.retryCount, 0)
        XCTAssertEqual(deckAggregate.deckTitleSnapshot, "Review Deck")

        let cardAggregate = try XCTUnwrap(cardAggregates.first)
        XCTAssertEqual(cardAggregate.repeatCount, 2)
        XCTAssertEqual(cardAggregate.finalDifficulty, .easy)
        XCTAssertEqual(cardAggregate.cardTitleSnapshot, "Front")

        let profile = try XCTUnwrap(profiles.first)
        XCTAssertEqual(profile.totalXP, 32)
        XCTAssertNotNil(profile.lastActiveDate)
    }

    func testPersistReviewsAgainDifficultyResetsSRSState() async throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let setupContext = ModelContext(container)

        let deck = DeckModel(title: "Again Deck", colorHex: "#000000")
        let card = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.flashcard(front: "Q", back: "A"),
            cardNumber: 1
        )

        setupContext.insert(deck)
        setupContext.insert(card)
        deck.cards = [card]
        card.deck = deck
        card.easeFactor = 2.5
        card.interval = 10
        card.consecutiveCorrectAnswers = 4
        deck.cardCount = 1

        try setupContext.save()

        let service = PlaySessionPersistenceService(container: container)
        await service.persistReviews([
            PlaySessionReviewWrite(
                cardID: card.persistentModelID,
                difficulty: .again,
                timeSpent: 8.0,
                xpAwarded: 3
            )
        ])

        let verificationContext = ModelContext(container)
        let persistedCard = try XCTUnwrap(
            verificationContext.model(for: card.persistentModelID) as? CardModel
        )

        XCTAssertEqual(persistedCard.consecutiveCorrectAnswers, 0)
        XCTAssertEqual(persistedCard.interval, 1)
        XCTAssertEqual(persistedCard.easeFactor, 2.3, accuracy: 0.0001)
        XCTAssertEqual(persistedCard.reviewHistory.count, 1)
    }

    func testPersistReviewsReconcilesRetryToLandedWithinSameDay() async throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let setupContext = ModelContext(container)

        let deck = DeckModel(title: "Retry Deck", colorHex: "#334455")
        let card = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.flashcard(front: "Prompt", back: "Answer"),
            cardNumber: 1
        )

        setupContext.insert(deck)
        setupContext.insert(card)
        deck.cards = [card]
        card.deck = deck
        deck.cardCount = 1

        try setupContext.save()

        let service = PlaySessionPersistenceService(container: container)
        await service.persistReviews([
            PlaySessionReviewWrite(
                cardID: card.persistentModelID,
                difficulty: .again,
                timeSpent: 7.0,
                xpAwarded: 3
            ),
            PlaySessionReviewWrite(
                cardID: card.persistentModelID,
                difficulty: .good,
                timeSpent: 4.0,
                xpAwarded: 9
            )
        ])

        let verificationContext = ModelContext(container)
        let dailyAggregate = try XCTUnwrap(
            try verificationContext.fetchAll(HomeDailyStudyAggregate.self).first
        )
        let deckAggregate = try XCTUnwrap(
            try verificationContext.fetchAll(HomeDailyDeckAggregate.self).first
        )
        let cardAggregate = try XCTUnwrap(
            try verificationContext.fetchAll(HomeDailyCardAggregate.self).first
        )

        XCTAssertEqual(dailyAggregate.uniqueCardCount, 1)
        XCTAssertEqual(dailyAggregate.rawReviewCount, 2)
        XCTAssertEqual(dailyAggregate.landedCount, 1)
        XCTAssertEqual(dailyAggregate.retryCount, 0)

        XCTAssertEqual(deckAggregate.uniqueCardCount, 1)
        XCTAssertEqual(deckAggregate.landedCount, 1)
        XCTAssertEqual(deckAggregate.retryCount, 0)

        XCTAssertEqual(cardAggregate.repeatCount, 2)
        XCTAssertEqual(cardAggregate.finalDifficulty, .good)
    }
}
