//
//  MatchPromptingTests.swift
//  QuizFlashTests
//
//  Covers Match-specific prompt structure for direct generation and conversion.
//

import XCTest
import SwiftData
@testable import QuizFlash

@MainActor
final class MatchPromptingTests: XCTestCase {
    func testBuildTextMessagesIncludesApprovedExamplesForLaterMatchBatches() {
        let service = AIFlashcardService(provider: makeProvider())
        let messages = service.buildTextMessages(
            text: "Negation and implication rules.",
            targetCards: 3,
            needsOCRCorrection: false,
            options: AIGenerationOptions(cardType: .match, cardLevel: .balanced),
            sourceLabel: "Page 2",
            batchIndex: 2,
            totalBatches: 4,
            passIndex: 1,
            coveredPrompts: ["Negation of φ"],
            approvedMatchExamples: ["\"¬φ\" -> \"negation of φ\""],
            matchOverlapHints: ["Negation of φ -> \"nu φ\""]
        )

        guard
            let system = messages.first?["content"] as? String,
            let user = messages.last?["content"] as? String
        else {
            return XCTFail("Expected text Match messages to contain string content.")
        }

        XCTAssertTrue(system.contains("Keep the relation family consistent across the batch whenever possible."))
        XCTAssertTrue(user.contains("Earlier approved Match pairs in this same run"))
        XCTAssertTrue(user.contains("\"¬φ\" -> \"negation of φ\""))
        XCTAssertTrue(user.contains("Avoid repeating or overlapping these earlier Match pairs"))
    }

    func testBuildConversionMessagesForMatchUsesSubsetTargetAndSkipLanguage() {
        let service = AIFlashcardService(provider: makeProvider())
        let context = try! TestModelContainerFactory.makeContext()
        let firstCard = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.flashcard(front: "¬φ", back: "Negation of φ"),
            cardNumber: 1
        )
        let secondCard = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.flashcard(front: "⊥", back: "Contradiction"),
            cardNumber: 2
        )
        context.insert(firstCard)
        context.insert(secondCard)

        let sourceCards = [
            AICardConversionSource(
                id: firstCard.persistentModelID,
                kind: .flashcard,
                content: TestMutationFactory.flashcard(front: "¬φ", back: "Negation of φ")
            ),
            AICardConversionSource(
                id: secondCard.persistentModelID,
                kind: .flashcard,
                content: TestMutationFactory.flashcard(front: "⊥", back: "Contradiction")
            )
        ]

        let messages = service.buildConversionMessages(
            sourceCards: sourceCards,
            targetType: .match,
            level: .balanced,
            targetCount: 1,
            approvedMatchExamples: ["\"⊥\" -> \"contradiction\""],
            matchOverlapHints: ["¬φ -> negation of φ"]
        )

        guard
            let system = messages.first?["content"] as? String,
            let user = messages.last?["content"] as? String
        else {
            return XCTFail("Expected conversion Match messages to contain string content.")
        }

        XCTAssertTrue(system.contains("UP TO 1 results"))
        XCTAssertTrue(system.contains("You MAY omit a source_index"))
        XCTAssertTrue(system.contains("\"results\" MUST contain UP TO 1 objects"))
        XCTAssertTrue(user.contains("UP TO 1 Match Cards outputs"))
        XCTAssertTrue(user.contains("You MAY skip a source card"))
        XCTAssertTrue(user.contains("EARLIER APPROVED MATCH PAIRS"))
        XCTAssertFalse(user.contains("return one result for every SOURCE_INDEX"))
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
