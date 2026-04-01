//
//  DeckViewModelConversionTests.swift
//  QuizFlashTests
//
//  Covers deck-detail conversion entry points.
//

import XCTest
import SwiftData
@testable import QuizFlash

@MainActor
final class DeckViewModelConversionTests: XCTestCase {
    func testPresentSelectionConversionUsesOnlyCurrentlySelectedCards() throws {
        let context = try TestModelContainerFactory.makeContext()
        let deck = DeckModel(title: "Algorithms", icon: "book", colorHex: "#112233")
        let flash = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.flashcard(front: "BFS", back: "Breadth-first search"),
            cardNumber: 1
        )
        let match = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.match(prompt: "DFS", answer: "Depth-first search"),
            cardNumber: 2
        )
        let quiz = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.quiz(question: "What is Dijkstra?", correctAnswers: ["Shortest path"]),
            cardNumber: 3
        )

        context.insert(deck)
        context.insert(flash)
        context.insert(match)
        context.insert(quiz)
        deck.cards = [flash, match, quiz]
        deck.cardCount = 3
        deck.lastAssignedCardNumber = 3
        try context.save()

        let viewModel = DeckViewModel()
        viewModel.allCardInfos = [
            makeGridCardInfo(from: flash, frontText: "BFS", backText: "Breadth-first search"),
            makeGridCardInfo(from: match, frontText: "DFS", backText: "Depth-first search"),
            makeGridCardInfo(from: quiz, frontText: "What is Dijkstra?", backText: "Shortest path")
        ]
        viewModel.selectedCards = [match.persistentModelID, quiz.persistentModelID]

        let request = try XCTUnwrap(viewModel.presentSelectionConversion(for: deck))

        XCTAssertEqual(request.scope, .selectedCards)
        XCTAssertEqual(
            Set(request.selectedSources.map(\.id)),
            [match.persistentModelID, quiz.persistentModelID]
        )
        XCTAssertEqual(Set(request.currentScopeSources.map(\.id)), [match.persistentModelID, quiz.persistentModelID])
        XCTAssertEqual(Set(request.availableSourceKinds), [.match, .quiz])
    }

    func testPresentSingleCardConversionUsesOnlyTappedCard() throws {
        let context = try TestModelContainerFactory.makeContext()
        let deck = DeckModel(title: "Algorithms", icon: "book", colorHex: "#112233")
        let flash = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.flashcard(front: "Queue", back: "FIFO"),
            cardNumber: 1
        )
        let match = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.match(prompt: "Stack", answer: "LIFO"),
            cardNumber: 2
        )

        context.insert(deck)
        context.insert(flash)
        context.insert(match)
        deck.cards = [flash, match]
        deck.cardCount = 2
        deck.lastAssignedCardNumber = 2
        try context.save()

        let viewModel = DeckViewModel()
        viewModel.allCardInfos = [
            makeGridCardInfo(from: flash, frontText: "Queue", backText: "FIFO"),
            makeGridCardInfo(from: match, frontText: "Stack", backText: "LIFO")
        ]

        let request = try XCTUnwrap(
            viewModel.presentSingleCardConversion(
                for: match.persistentModelID,
                in: deck
            )
        )

        XCTAssertEqual(request.scope, .singleCard)
        XCTAssertEqual(request.singleSources.map(\.id), [match.persistentModelID])
        XCTAssertEqual(request.currentScopeSources.map(\.id), [match.persistentModelID])
        XCTAssertEqual(request.selectedSourceKind, .match)
    }

    private func makeGridCardInfo(
        from card: CardModel,
        frontText: String,
        backText: String
    ) -> GridCardInfo {
        GridCardInfo(
            id: card.persistentModelID,
            kind: card.cardContent.kind,
            creationSource: card.creationSource,
            conversionMetadata: card.conversionMetadata,
            cardNumber: card.cardNumber,
            interval: card.interval,
            reviewHistoryIsEmpty: card.reviewHistory.isEmpty,
            isPinned: card.isPinned,
            frontText: frontText,
            backText: backText,
            frontPreviewText: frontText,
            backPreviewText: backText,
            searchDocumentText: "\(frontText) \(backText)",
            createdAt: card.createdAt,
            editedAt: card.editedAt
        )
    }
}
