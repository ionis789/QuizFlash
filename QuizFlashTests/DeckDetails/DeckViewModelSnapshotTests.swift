//
//  DeckViewModelSnapshotTests.swift
//  QuizFlashTests
//
//  Covers deck-detail snapshot loading and derived daily activity state.
//

import XCTest
import SwiftData
@testable import QuizFlash

@MainActor
final class DeckViewModelSnapshotTests: XCTestCase {
    func testLoadSnapshotBuildsTodayActivitySummaryFromDeckReviewHistory() async throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let calendar = Calendar.current
        let today = calendar.date(
            bySettingHour: 9,
            minute: 0,
            second: 0,
            of: Date()
        ) ?? Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today

        let deck = DeckModel(title: "Chemistry", colorHex: "#8B7DFF")
        let recoveredCard = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.flashcard(front: "NaCl", back: "Salt"),
            cardNumber: 1
        )
        let retryCard = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.flashcard(front: "H2O", back: "Water"),
            cardNumber: 2
        )
        let previousDayCard = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.flashcard(front: "CO2", back: "Carbon dioxide"),
            cardNumber: 3
        )

        context.insert(deck)
        context.insert(recoveredCard)
        context.insert(retryCard)
        context.insert(previousDayCard)

        deck.cards = [recoveredCard, retryCard, previousDayCard]
        recoveredCard.deck = deck
        retryCard.deck = deck
        previousDayCard.deck = deck
        deck.cardCount = 3
        deck.lastAssignedCardNumber = 3

        let firstPass = ReviewEvent(timeSpent: 4.0, difficulty: .again, xpAwarded: 3)
        firstPass.timestamp = today
        firstPass.card = recoveredCard
        recoveredCard.reviewHistory.append(firstPass)

        let recoveryPass = ReviewEvent(timeSpent: 3.0, difficulty: .good, xpAwarded: 8)
        recoveryPass.timestamp = calendar.date(byAdding: .minute, value: 6, to: today) ?? today
        recoveryPass.card = recoveredCard
        recoveredCard.reviewHistory.append(recoveryPass)

        let retryPass = ReviewEvent(timeSpent: 5.0, difficulty: .again, xpAwarded: 2)
        retryPass.timestamp = calendar.date(byAdding: .minute, value: 13, to: today) ?? today
        retryPass.card = retryCard
        retryCard.reviewHistory.append(retryPass)

        let previousPass = ReviewEvent(timeSpent: 2.0, difficulty: .easy, xpAwarded: 12)
        previousPass.timestamp = yesterday
        previousPass.card = previousDayCard
        previousDayCard.reviewHistory.append(previousPass)

        try context.save()

        let viewModel = DeckViewModel()
        defer { viewModel.tearDown() }

        let stats = await viewModel.loadSnapshot(
            deckID: deck.persistentModelID,
            container: container
        )

        XCTAssertEqual(stats.totalCards, 3)
        XCTAssertEqual(stats.totalReviews, 4)
        XCTAssertEqual(viewModel.todayActivitySummary.uniqueCardsReviewed, 2)
        XCTAssertEqual(viewModel.todayActivitySummary.rawReviewCount, 3)
        XCTAssertEqual(viewModel.todayActivitySummary.landedCount, 1)
        XCTAssertEqual(viewModel.todayActivitySummary.retryCount, 1)
        XCTAssertEqual(viewModel.todayActivitySummary.headline, "2 cards moved today")
        XCTAssertEqual(
            viewModel.todayActivitySummary.detailLine,
            "3 passes folded into 2 cards. 1 still needs another pass."
        )

        let recoveredSummary = try XCTUnwrap(
            viewModel.todayActivitySummary.cards.first(where: { $0.id == recoveredCard.persistentModelID })
        )
        XCTAssertEqual(recoveredSummary.title, "NaCl")
        XCTAssertEqual(recoveredSummary.reviewCount, 2)
        XCTAssertEqual(recoveredSummary.finalDifficulty, .good)

        let retrySummary = try XCTUnwrap(
            viewModel.todayActivitySummary.cards.first(where: { $0.id == retryCard.persistentModelID })
        )
        XCTAssertEqual(retrySummary.title, "H2O")
        XCTAssertEqual(retrySummary.reviewCount, 1)
        XCTAssertEqual(retrySummary.finalDifficulty, .again)
    }

    func testLoadSnapshotReturnsEmptyTodayActivityWhenDeckHasNoReviewsToday() async throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()

        let deck = DeckModel(title: "History", colorHex: "#445566")
        let card = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.flashcard(front: "Treaty", back: "Versailles"),
            cardNumber: 1
        )

        context.insert(deck)
        context.insert(card)
        deck.cards = [card]
        card.deck = deck
        deck.cardCount = 1
        deck.lastAssignedCardNumber = 1

        let oldReview = ReviewEvent(timeSpent: 6.0, difficulty: .hard, xpAwarded: 5)
        oldReview.timestamp = yesterday
        oldReview.card = card
        card.reviewHistory.append(oldReview)

        try context.save()

        let viewModel = DeckViewModel()
        defer { viewModel.tearDown() }

        _ = await viewModel.loadSnapshot(
            deckID: deck.persistentModelID,
            container: container
        )

        XCTAssertFalse(viewModel.todayActivitySummary.hasActivity)
        XCTAssertEqual(viewModel.todayActivitySummary.uniqueCardsReviewed, 0)
        XCTAssertEqual(viewModel.todayActivitySummary.rawReviewCount, 0)
        XCTAssertEqual(viewModel.todayActivitySummary.cards, [])
        XCTAssertEqual(viewModel.todayActivitySummary.headline, "No cards moved today")
    }
}
