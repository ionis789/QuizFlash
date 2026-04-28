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

        XCTAssertTrue(system.contains("MATCH PAIR QUALITY RULES"))
        XCTAssertTrue(user.contains("Earlier strong Match pairs from this run"))
        XCTAssertTrue(user.contains("\"¬φ\" -> \"negation of φ\""))
        XCTAssertTrue(user.contains("Avoid repeating or overlapping these earlier Match pairs"))
    }

    func testDirectGenerationPromptsIncludeMobileLayoutGuidanceForAllCardTypes() {
        let service = AIFlashcardService(provider: makeProvider())

        let expectations: [(AICardGenerationType, String)] = [
            (.flashcards, "FLASHCARD MOBILE BUDGET"),
            (.match, "MATCH MOBILE BUDGET"),
            (.quiz, "QUIZ MOBILE BUDGET"),
            (.write, "WRITE MOBILE BUDGET")
        ]

        for (cardType, budgetHeading) in expectations {
            let messages = service.buildTextMessages(
                text: "Compact source about notation, definitions, and examples.",
                targetCards: 2,
                needsOCRCorrection: false,
                options: AIGenerationOptions(cardType: cardType, cardLevel: .balanced),
                sourceLabel: "Page 1",
                batchIndex: 1,
                totalBatches: 1,
                passIndex: 1,
                coveredPrompts: []
            )

            guard let system = messages.first?["content"] as? String else {
                return XCTFail("Expected \(cardType) direct-generation system prompt to be a string.")
            }

            XCTAssertTrue(system.contains("MOBILE CARD LAYOUT — IPHONE/IPAD FIRST"), "Missing shared mobile guidance for \(cardType).")
            XCTAssertTrue(system.contains(budgetHeading), "Missing \(budgetHeading) for \(cardType).")
        }
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
        XCTAssertTrue(system.contains("You MAY skip a source card"))
        XCTAssertTrue(system.contains("\"results\" MUST contain UP TO 1 objects"))
        XCTAssertTrue(user.contains("UP TO 1 Match Cards outputs"))
        XCTAssertTrue(user.contains("You MAY skip a source card"))
        XCTAssertTrue(user.contains("EARLIER STRONG MATCH PAIRS"))
        XCTAssertFalse(user.contains("return one result for every SOURCE_INDEX"))
    }

    func testConversionPromptsIncludeMobileLayoutGuidanceForAllTargetTypes() {
        let service = AIFlashcardService(provider: makeProvider())
        let context = try! TestModelContainerFactory.makeContext()
        let card = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.flashcard(front: "λ", back: "Lambda abstraction"),
            cardNumber: 1
        )
        context.insert(card)

        let sourceCards = [
            AICardConversionSource(
                id: card.persistentModelID,
                kind: .flashcard,
                content: TestMutationFactory.flashcard(front: "λ", back: "Lambda abstraction")
            )
        ]

        let expectations: [(AICardGenerationType, String)] = [
            (.flashcards, "FLASHCARD MOBILE BUDGET"),
            (.match, "MATCH MOBILE BUDGET"),
            (.quiz, "QUIZ MOBILE BUDGET"),
            (.write, "WRITE MOBILE BUDGET")
        ]

        for (targetType, budgetHeading) in expectations {
            let messages = service.buildConversionMessages(
                sourceCards: sourceCards,
                targetType: targetType,
                level: .balanced,
                targetCount: 1
            )

            guard let system = messages.first?["content"] as? String else {
                return XCTFail("Expected \(targetType) conversion system prompt to be a string.")
            }

            XCTAssertTrue(system.contains("MOBILE CARD LAYOUT — IPHONE/IPAD FIRST"), "Missing shared mobile guidance for \(targetType) conversion.")
            XCTAssertTrue(system.contains(budgetHeading), "Missing \(budgetHeading) for \(targetType) conversion.")
        }
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
