//
//  AICardJSONDecodingTests.swift
//  QuizFlashTests
//

import XCTest
@testable import QuizFlash

final class AICardJSONDecodingTests: XCTestCase {
    func testDecodeFlashcardCardDTOBatch() async throws {
        let service = makeService()
        let json = """
        {
          "schemaVersion": 1,
          "cards": [
            {
              "type": "flashcard",
              "front": {
                "zones": [
                  { "type": "text", "text": "What is SwiftData?" }
                ]
              },
              "back": {
                "zones": [
                  { "type": "text", "text": "Apple's local persistence framework." }
                ]
              }
            }
          ]
        }
        """

        let cards = try await service.decodeGeneratedCards(from: json, contract: .flashcard)

        XCTAssertEqual(cards.count, 1)
        if case .flashcard(let content) = cards[0].content {
            XCTAssertEqual(content.questionZones, ["What is SwiftData?"])
            XCTAssertEqual(content.answerZones, ["Apple's local persistence framework."])
        } else {
            XCTFail("Expected flashcard payload")
        }
    }

    func testDecodeQuizCardDTOBatch() async throws {
        let service = makeService()
        let json = """
        {
          "schemaVersion": 1,
          "cards": [
            {
              "type": "quiz",
              "question": {
                "zones": [
                  { "type": "text", "text": "Which framework persists local models?" }
                ]
              },
              "choices": [
                {
                  "zones": [
                    { "type": "text", "text": "SwiftData" }
                  ],
                  "isCorrect": true
                },
                {
                  "zones": [
                    { "type": "text", "text": "SwiftUI" }
                  ],
                  "isCorrect": false
                },
                {
                  "zones": [
                    { "type": "text", "text": "MapKit" }
                  ],
                  "isCorrect": false
                }
              ],
              "explanation": {
                "zones": [
                  { "type": "text", "text": "SwiftData is the persistence layer." }
                ]
              }
            }
          ]
        }
        """

        let cards = try await service.decodeGeneratedCards(from: json, contract: .quiz)

        XCTAssertEqual(cards.count, 1)
        if case .quiz(let content) = cards[0].content {
            XCTAssertEqual(content.questionZones, ["Which framework persists local models?"])
            XCTAssertEqual(content.choices, ["SwiftData", "SwiftUI", "MapKit"])
            XCTAssertEqual(content.correctIndexes, [0])
            XCTAssertEqual(content.explanationZones, ["SwiftData is the persistence layer."])
        } else {
            XCTFail("Expected quiz payload")
        }
    }

    func testDecodeRejectsInvalidCardDTOBatch() async {
        let service = makeService()
        let json = """
        {
          "schemaVersion": 1,
          "cards": [
            {
              "type": "quiz",
              "question": { "zones": [{ "type": "text", "text": "Invalid?" }] },
              "choices": [
                { "zones": [{ "type": "text", "text": "Only choice" }], "isCorrect": false }
              ]
            }
          ]
        }
        """

        do {
            _ = try await service.decodeGeneratedCards(from: json, contract: .quiz)
            XCTFail("Expected invalid quiz payload to fail")
        } catch AIServiceError.parsingFailed {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDecodePreservesCompactUnicodeMathNotation() async throws {
        let service = makeService()
        let json = """
        {
          "schemaVersion": 1,
          "cards": [
            {
              "type": "flashcard",
              "front": {
                "zones": [
                  { "type": "text", "text": "Ce exprimă operatorul T: ℝⁿ → ℝᵐ?" }
                ]
              },
              "back": {
                "zones": [
                  { "type": "text", "text": "diag(λ₁,…,λₙ) = S⁻¹·A·S" }
                ]
              }
            }
          ]
        }
        """

        let cards = try await service.decodeGeneratedCards(from: json, contract: .flashcard)

        if case .flashcard(let content) = cards[0].content {
            XCTAssertEqual(content.questionZones, ["Ce exprimă operatorul T: ℝⁿ → ℝᵐ?"])
            XCTAssertEqual(content.answerZones, ["diag(λ₁,…,λₙ) = S⁻¹·A·S"])
        } else {
            XCTFail("Expected flashcard payload")
        }
    }

    func testDecodeRepairsSingleBackslashLatexInsideCardDTO() async throws {
        let service = makeService()
        let json = #"""
        {
          "schemaVersion": 1,
          "cards": [
            {
              "type": "flashcard",
              "front": {
                "zones": [
                  { "type": "text", "text": "Ce înseamnă $v \in V$?" }
                ]
              },
              "back": {
                "zones": [
                  { "type": "text", "text": "$A_{B,B'} \cdot S$" }
                ]
              }
            }
          ]
        }
        """#

        let cards = try await service.decodeGeneratedCards(from: json, contract: .flashcard)

        if case .flashcard(let content) = cards[0].content {
            XCTAssertEqual(content.questionZones, [#"Ce înseamnă $v \in V$?"#])
            XCTAssertEqual(content.answerZones, [#"$A_{B,B'} \cdot S$"#])
        } else {
            XCTFail("Expected flashcard payload")
        }
    }

    func testPromptUsesCanonicalCardDTOSchema() {
        let service = makeService()
        let prompt = service.systemPrompt(
            targetCards: 2,
            isOCR: false,
            options: AIGenerationOptions(cardType: .flashcards)
        )

        XCTAssertTrue(prompt.contains(#""schemaVersion": 1"#))
        XCTAssertTrue(prompt.contains(#""type": "flashcard""#))
        XCTAssertTrue(prompt.contains(#""front""#))
        XCTAssertTrue(prompt.contains(#""back""#))
        XCTAssertTrue(prompt.contains("Every math symbol, variable, and inline equation MUST be inside"))
        XCTAssertTrue(prompt.contains("Never output raw math notation"))
        XCTAssertTrue(prompt.contains("INLINE MATH: Wrap every math symbol"))
        XCTAssertFalse(prompt.contains("question" + "_zones"))
        XCTAssertFalse(prompt.contains("answer" + "_zones"))
        XCTAssertFalse(prompt.contains("correct" + "_indexes"))
    }

    private func makeService() -> AIFlashcardService {
        AIFlashcardService(
            provider: AIProviderProfile(
                name: "Test Provider",
                endpointURLString: "https://example.com/v1",
                apiKey: "test",
                textModel: "test-text",
                visionModel: "test-vision"
            )
        )
    }
}
