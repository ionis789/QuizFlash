//
//  MatchConversionPipelineTests.swift
//  QuizFlashTests
//
//  Covers Match conversion quality filtering without touching the network.
//

import XCTest
import SwiftData
@testable import QuizFlash

@MainActor
final class MatchConversionPipelineTests: XCTestCase {
    func testFilterAcceptedMatchConversionOutputsRejectsVerbosePairsAndPreservesSourceMapping() throws {
        let context = try TestModelContainerFactory.makeContext()
        let deck = DeckModel(title: "Algorithms", icon: "book", colorHex: "#112233")
        let compactSource = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.flashcard(front: "BFS", back: "Breadth-first search"),
            cardNumber: 1
        )
        let verboseSource = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.flashcard(front: "Adjacency matrix", back: "Dense graph representation"),
            cardNumber: 2
        )

        context.insert(deck)
        context.insert(compactSource)
        context.insert(verboseSource)
        deck.cards = [compactSource, verboseSource]
        deck.cardCount = 2
        deck.lastAssignedCardNumber = 2
        try context.save()

        let service = AIFlashcardService(provider: makeProvider())
        let result = service.filterAcceptedMatchConversionOutputs([
            AICardConversionOutput(
                sourceCardID: compactSource.persistentModelID,
                generatedCard: AIFlashcard(
                    matchPrompt: "  BFS  ",
                    matchAnswer: "Breadth-first search"
                )
            ),
            AICardConversionOutput(
                sourceCardID: verboseSource.persistentModelID,
                generatedCard: AIFlashcard(
                    matchPrompt: "Explain how the adjacency matrix representation behaves for dense directed graphs",
                    matchAnswer: "It stores every possible ordered pair and marks whether an arc exists, which makes access constant time but uses much more memory for sparse graphs."
                )
            )
        ])

        XCTAssertEqual(result.outputs.count, 1)
        XCTAssertEqual(result.outputs.first?.sourceCardID, compactSource.persistentModelID)
        XCTAssertTrue(result.rejectedSourceIDs.contains(verboseSource.persistentModelID))

        guard case .match(let acceptedContent) = result.outputs.first?.generatedCard.content else {
            return XCTFail("Expected the accepted conversion output to stay a Match card.")
        }

        XCTAssertEqual(acceptedContent.prompt, "BFS")
        XCTAssertEqual(acceptedContent.answer, "Breadth-first search")
        XCTAssertEqual(result.retryHints.count, 1)
        XCTAssertTrue(result.retryHints[0].contains("adjacency matrix"))
    }

    func testFilterAcceptedWriteConversionOutputsRejectsUnanchoredBlanksAndPreservesSourceMapping() throws {
        let context = try TestModelContainerFactory.makeContext()
        let deck = DeckModel(title: "Algorithms", icon: "book", colorHex: "#112233")
        let validSource = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.flashcard(front: "BFS", back: "Breadth-first search"),
            cardNumber: 1
        )
        let invalidSource = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.flashcard(front: "DFS", back: "Depth-first search"),
            cardNumber: 2
        )

        context.insert(deck)
        context.insert(validSource)
        context.insert(invalidSource)
        deck.cards = [validSource, invalidSource]
        deck.cardCount = 2
        deck.lastAssignedCardNumber = 2
        try context.save()

        let service = AIFlashcardService(provider: makeProvider())
        let result = service.filterAcceptedWriteConversionOutputs([
            AICardConversionOutput(
                sourceCardID: validSource.persistentModelID,
                generatedCard: AIFlashcard(
                    sourceText: "Breadth-first search explores nodes level by level.",
                    omittedText: "level by level"
                )
            ),
            AICardConversionOutput(
                sourceCardID: invalidSource.persistentModelID,
                generatedCard: AIFlashcard(
                    sourceText: "Depth-first search explores one branch deeply before backtracking.",
                    omittedText: "stack"
                )
            )
        ])

        XCTAssertEqual(result.outputs.count, 1)
        XCTAssertEqual(result.outputs.first?.sourceCardID, validSource.persistentModelID)
        XCTAssertTrue(result.rejectedSourceIDs.contains(invalidSource.persistentModelID))

        guard case .write(let acceptedContent) = result.outputs.first?.generatedCard.content else {
            return XCTFail("Expected the accepted conversion output to stay a Write card.")
        }

        XCTAssertEqual(acceptedContent.sourceText, "Breadth-first search explores nodes level by level.")
        XCTAssertEqual(acceptedContent.omittedText, "level by level")
        XCTAssertEqual(result.retryHints.count, 1)
        XCTAssertTrue(result.retryHints[0].contains("not present verbatim"))
    }

    private func makeProvider() -> AIProviderProfile {
        AIProviderProfile(
            name: "Tests",
            endpointURLString: "https://example.com/v1/chat/completions",
            apiKey: "test-key",
            textModel: "gpt-test",
            visionModel: "gpt-test"
        )
    }
}
