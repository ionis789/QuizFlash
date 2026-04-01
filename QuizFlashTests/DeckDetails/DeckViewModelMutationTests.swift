//
//  DeckViewModelMutationTests.swift
//  QuizFlashTests
//
//  Covers local deck-detail persistence mutations.
//

import XCTest
import SwiftData
@testable import QuizFlash

@MainActor
final class DeckViewModelMutationTests: XCTestCase {
    func testUpdateGroupingModePersistsDeckPreference() throws {
        let context = try TestModelContainerFactory.makeContext()
        let deck = DeckModel(title: "Grouped", colorHex: "#FFFFFF")
        context.insert(deck)
        try context.save()

        let viewModel = DeckViewModel()
        viewModel.updateGroupingMode(.byCardType, for: deck, context: context)

        XCTAssertEqual(deck.cardGroupingMode, .byCardType)
    }

    func testAddCardPersistsCardAndIncrementsCounters() throws {
        let context = try TestModelContainerFactory.makeContext()
        let deck = DeckModel(title: "Add Card", colorHex: "#FFFFFF")
        context.insert(deck)
        try context.save()

        let viewModel = DeckViewModel()
        viewModel.addCard(
            content: TestMutationFactory.match(prompt: "Na", answer: "Sodium"),
            to: deck,
            context: context
        )
        viewModel.tearDown()

        XCTAssertEqual(deck.cardCount, 1)
        XCTAssertEqual(deck.lastAssignedCardNumber, 1)
        XCTAssertEqual(deck.cards.count, 1)
        XCTAssertEqual(deck.cards.first?.cardContent.kind, .match)
    }

    func testTogglePinnedStatePersistsCardPinning() throws {
        let context = try TestModelContainerFactory.makeContext()
        let deck = DeckModel(title: "Pins", colorHex: "#FFFFFF")
        let card = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.flashcard(front: "Q", back: "A"),
            cardNumber: 1
        )

        context.insert(deck)
        context.insert(card)
        deck.cards = [card]
        deck.cardCount = 1
        deck.lastAssignedCardNumber = 1
        try context.save()

        let viewModel = DeckViewModel()
        viewModel.togglePinnedState(for: card.persistentModelID, in: deck, context: context)
        viewModel.tearDown()

        XCTAssertTrue(card.isPinned)
    }

    func testDeleteCardRemovesCardAndDecrementsCount() throws {
        let context = try TestModelContainerFactory.makeContext()
        let deck = DeckModel(title: "Delete One", colorHex: "#FFFFFF")
        let card = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.flashcard(front: "Remove", back: "Me"),
            cardNumber: 1
        )

        context.insert(deck)
        context.insert(card)
        deck.cards = [card]
        deck.cardCount = 1
        deck.lastAssignedCardNumber = 1
        try context.save()

        let viewModel = DeckViewModel()
        viewModel.deleteCard(withID: card.persistentModelID, from: deck, context: context)
        viewModel.tearDown()

        XCTAssertEqual(deck.cardCount, 0)
        XCTAssertTrue(deck.cards.isEmpty)
        XCTAssertTrue(try context.fetchAll(CardModel.self).isEmpty)
    }

    func testDeleteSelectedCardsRemovesEntireSelection() throws {
        let context = try TestModelContainerFactory.makeContext()
        let deck = DeckModel(title: "Delete Many", colorHex: "#FFFFFF")

        let cards = [
            TestMutationFactory.makePersistedCard(
                content: TestMutationFactory.flashcard(front: "1", back: "1"),
                cardNumber: 1
            ),
            TestMutationFactory.makePersistedCard(
                content: TestMutationFactory.flashcard(front: "2", back: "2"),
                cardNumber: 2
            )
        ]

        for card in cards {
            context.insert(card)
        }

        deck.cards = cards
        deck.cardCount = cards.count
        deck.lastAssignedCardNumber = 2
        context.insert(deck)
        try context.save()

        let viewModel = DeckViewModel()
        viewModel.selectedCards = Set(cards.map(\.persistentModelID))
        viewModel.deleteSelectedCards(from: deck, context: context)
        viewModel.tearDown()

        XCTAssertEqual(deck.cardCount, 0)
        XCTAssertTrue(deck.cards.isEmpty)
        XCTAssertTrue(try context.fetchAll(CardModel.self).isEmpty)
        XCTAssertFalse(viewModel.isSelecting)
        XCTAssertTrue(viewModel.selectedCards.isEmpty)
    }
}
