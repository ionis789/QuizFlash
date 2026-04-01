//
//  DeckCardConversionRequestTests.swift
//  QuizFlashTests
//
//  Covers source-type scoped conversion drafts for mixed decks.
//

import XCTest
import SwiftData
@testable import QuizFlash

@MainActor
final class DeckCardConversionRequestTests: XCTestCase {
    func testFilteredSourcesHonorSelectedSourceKindsAndExcludeTargetKind() throws {
        let context = try TestModelContainerFactory.makeContext()

        let flash = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.flashcard(front: "BFS", back: "Breadth-first search"),
            cardNumber: 1
        )
        let match = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.match(prompt: "DFS", answer: "Depth-first search"),
            cardNumber: 2
        )
        let quiz = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.quiz(question: "What is BFS?", correctAnswers: ["Breadth-first search"]),
            cardNumber: 3
        )

        context.insert(flash)
        context.insert(match)
        context.insert(quiz)

        let request = DeckCardConversionRequest(
            availableScopes: [.wholeDeck],
            wholeDeckSources: [
                .init(id: flash.persistentModelID, kind: .flashcard),
                .init(id: match.persistentModelID, kind: .match),
                .init(id: quiz.persistentModelID, kind: .quiz)
            ],
            recommendedSources: [],
            selectedSources: [],
            singleSources: [],
            scope: .wholeDeck,
            sourceKind: .flashcard,
            targetKind: .write,
            destination: .sameDeck,
            newDeckTitle: ""
        )

        XCTAssertEqual(request.availableSourceKinds, [.flashcard, .match, .quiz])
        XCTAssertEqual(request.selectedSourceKind, .flashcard)
        XCTAssertEqual(request.filteredSources.map(\.kind), [.flashcard])
        XCTAssertEqual(request.sourceCount, 1)
        XCTAssertEqual(request.resolvedCardIDs(), [flash.persistentModelID])
    }

    func testUpdateTargetKindPreservesSingleSourceKindSelection() throws {
        let context = try TestModelContainerFactory.makeContext()

        let flash = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.flashcard(front: "Queue", back: "FIFO"),
            cardNumber: 1
        )
        let match = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.match(prompt: "Stack", answer: "LIFO"),
            cardNumber: 2
        )

        context.insert(flash)
        context.insert(match)

        var request = DeckCardConversionRequest(
            availableScopes: [.wholeDeck],
            wholeDeckSources: [
                .init(id: flash.persistentModelID, kind: .flashcard),
                .init(id: match.persistentModelID, kind: .match)
            ],
            recommendedSources: [],
            selectedSources: [],
            singleSources: [],
            scope: .wholeDeck,
            sourceKind: .match,
            targetKind: .write,
            destination: .sameDeck,
            newDeckTitle: ""
        )

        request.updateTargetKind(.flashcard)

        XCTAssertEqual(request.targetKind, .flashcard)
        XCTAssertEqual(request.availableSourceKinds, [.flashcard, .match])
        XCTAssertEqual(request.selectedSourceKind, .match)
        XCTAssertEqual(request.filteredSources.map(\.kind), [.match])
        XCTAssertEqual(request.sourceCount, 1)
    }

    func testSelectingSourceKindUpdatesResolvedCardIDs() throws {
        let context = try TestModelContainerFactory.makeContext()

        let flash = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.flashcard(front: "A", back: "1"),
            cardNumber: 1
        )
        let quiz = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.quiz(question: "B?", correctAnswers: ["2"]),
            cardNumber: 2
        )
        let match = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.match(prompt: "C", answer: "3"),
            cardNumber: 3
        )

        context.insert(flash)
        context.insert(quiz)
        context.insert(match)

        var request = DeckCardConversionRequest(
            availableScopes: [.wholeDeck],
            wholeDeckSources: [
                .init(id: flash.persistentModelID, kind: .flashcard),
                .init(id: quiz.persistentModelID, kind: .quiz),
                .init(id: match.persistentModelID, kind: .match)
            ],
            recommendedSources: [],
            selectedSources: [],
            singleSources: [],
            scope: .wholeDeck,
            sourceKind: .flashcard,
            targetKind: .write,
            destination: .sameDeck,
            newDeckTitle: ""
        )

        request.selectSourceKind(.match)

        XCTAssertEqual(
            request.filteredSources.map(\.id),
            [match.persistentModelID]
        )
        XCTAssertEqual(request.sourceCount, 1)
    }

    func testSelectingSourceKindAutoMovesTargetAwayFromSameKind() throws {
        let context = try TestModelContainerFactory.makeContext()
        let flash = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.flashcard(front: "Queue", back: "FIFO"),
            cardNumber: 1
        )
        let match = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.match(prompt: "Stack", answer: "LIFO"),
            cardNumber: 2
        )

        context.insert(flash)
        context.insert(match)

        var request = DeckCardConversionRequest(
            availableScopes: [.wholeDeck],
            wholeDeckSources: [
                .init(id: flash.persistentModelID, kind: .flashcard),
                .init(id: match.persistentModelID, kind: .match)
            ],
            recommendedSources: [],
            selectedSources: [],
            singleSources: [],
            scope: .wholeDeck,
            sourceKind: .flashcard,
            targetKind: .quiz,
            destination: .sameDeck,
            newDeckTitle: ""
        )

        request.selectSourceKind(.quiz)

        XCTAssertEqual(request.selectedSourceKind, .flashcard)
        request.selectSourceKind(.match)
        request.updateTargetKind(.match)

        XCTAssertEqual(request.selectedSourceKind, .match)
        XCTAssertNotEqual(request.targetKind, .match)
        XCTAssertTrue(request.isTargetKindAvailable(.flashcard))
        XCTAssertFalse(request.isTargetKindAvailable(.match))
    }
}
