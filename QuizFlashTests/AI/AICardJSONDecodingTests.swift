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

    func testDecodeCodeZoneDTOCreatesFencedCodeForMapper() async throws {
        let service = makeService()
        let json = #"""
        {
          "schemaVersion": 1,
          "cards": [
            {
              "type": "flashcard",
              "front": {
                "zones": [
                  { "type": "text", "text": "Ce face `map`?" }
                ]
              },
              "back": {
                "zones": [
                  {
                    "type": "code",
                    "text": "let names = users.map(\\.name)"
                  }
                ]
              }
            }
          ]
        }
        """#

        let cards = try await service.decodeGeneratedCards(from: json, contract: .flashcard)

        guard case .flashcard(let content) = cards[0].content else {
            return XCTFail("Expected flashcard payload")
        }
        XCTAssertEqual(content.answerZones, ["```\nlet names = users.map(\\.name)\n```"])

        let draft = try AIGeneratedCardContentMapper.map(cards[0])
        guard case .flashcard(let flashcard) = draft else {
            return XCTFail("Expected flashcard draft")
        }
        XCTAssertEqual(flashcard.backZone.contentType, .code)
        XCTAssertEqual(flashcard.backZone.text, "let names = users.map(\\.name)")
        XCTAssertNil(flashcard.backZone.codeLanguage)
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

    func testDecodePreservesRenderableFormalNotationAsText() async throws {
        let service = makeService()
        let json = #"""
        {
          "schemaVersion": 1,
          "cards": [
            {
              "type": "flashcard",
              "front": {
                "zones": [
                  { "type": "text", "text": "Ce reprezintă închiderea $X^+$?" }
                ]
              },
              "back": {
                "zones": [
                  { "type": "text", "text": "$R[U]$ este o schemă relațională." },
                  { "type": "text", "text": "$\\Sigma = \\{AB \\to C, C \\to A\\}$" },
                  { "type": "text", "text": "Dacă nu se poate deduce nimic nou, rezultatul poate fi $\\emptyset$." }
                ]
              }
            }
          ]
        }
        """#

        let cards = try await service.decodeGeneratedCards(from: json, contract: .flashcard)

        if case .flashcard(let content) = cards[0].content {
            XCTAssertEqual(content.questionZones, [#"Ce reprezintă închiderea $X^+$?"#])
            XCTAssertEqual(
                content.answerZones,
                [
                    #"$R[U]$ este o schemă relațională."#,
                    #"$\Sigma = \{AB \to C, C \to A\}$"#,
                    #"Dacă nu se poate deduce nimic nou, rezultatul poate fi $\emptyset$."#
                ]
            )
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
        XCTAssertTrue(prompt.contains("CONTENT DESIGN"))
        XCTAssertTrue(prompt.contains("Generate cards only from learnable substance"))
        XCTAssertTrue(prompt.contains("Skip source material that is only document scaffolding"))
        XCTAssertTrue(prompt.contains("If a source span has no durable study value by itself"))
        XCTAssertTrue(prompt.contains("small semantic zones"))
        XCTAssertTrue(prompt.contains("not from topic labels or keywords"))
        XCTAssertTrue(prompt.contains("Do not force a fixed number of zones"))
        XCTAssertTrue(prompt.contains("FORMAL / MATHEMATICAL NOTATION"))
        XCTAssertTrue(prompt.contains("FORMAL NOTATION IS NOT CODE"))
        XCTAssertTrue(prompt.contains("PROGRAMMING / CODE"))
        XCTAssertTrue(prompt.contains("Programming syntax is not math"))
        XCTAssertTrue(prompt.contains("no markdown fences"))
        XCTAssertTrue(prompt.contains("INLINE CODE: Use single backticks"))
        XCTAssertTrue(prompt.contains("standalone \"code\" zone"))
        XCTAssertTrue(prompt.contains("Do not use a \"code\" zone merely because notation contains brackets"))
        XCTAssertTrue(prompt.contains("Do not emit deck metadata"))
        XCTAssertTrue(prompt.contains(#""container""#))
        XCTAssertTrue(prompt.contains(#""codeLanguage""#))
        XCTAssertTrue(prompt.contains("DEPTH: PRO"))
        XCTAssertTrue(prompt.contains("All LaTeX must be inside JSON strings"))
        XCTAssertTrue(prompt.contains("JSON-escape only what JSON requires"))
        XCTAssertTrue(prompt.contains("INLINE MATH: Wrap formal notation and inline equations in single $ when they appear as part of a sentence or compact statement"))
        XCTAssertTrue(prompt.contains("Formal notation is any content whose meaning is carried primarily by symbolic structure rather than by ordinary prose"))
        XCTAssertTrue(prompt.contains("NOTATION JUDGMENT GUIDANCE"))
        XCTAssertTrue(prompt.contains("GENERAL EXAMPLES OF WHAT SHOULD STAY FORMAL"))
        XCTAssertTrue(prompt.contains("Use LaTeX when the learner must retain the notation itself"))
        XCTAssertTrue(prompt.contains("Treat logical notation, semantic notation, set expressions, symbolic mappings, indexed symbols, recursive definitions"))
        XCTAssertTrue(prompt.contains("Prefer notation-first rendering when the source teaches the concept symbolically"))
        XCTAssertTrue(prompt.contains("Formal algorithms, recursive definitions, syntax trees, grammars, truth tables, and inference schemas are not executable code"))
        XCTAssertTrue(prompt.contains("Avoid ASCII art for formal structures"))
        XCTAssertTrue(prompt.contains("preserve only what is reasonably clear and keep uncertain notation conservative"))
        XCTAssertFalse(prompt.contains("raw τ"))
        XCTAssertFalse(prompt.contains("raw Γ"))
        XCTAssertFalse(prompt.contains("Before returning JSON, audit every generated card for formal symbols"))
        XCTAssertFalse(prompt.contains("Do not leave raw formal notation like"))
        XCTAssertFalse(prompt.contains("Math, logic, programming, physics"))
        XCTAssertFalse(prompt.contains("History, literature"))
        XCTAssertFalse(prompt.contains("Infer the subject domain from the source itself"))
        XCTAssertFalse(prompt.contains("question" + "_zones"))
        XCTAssertFalse(prompt.contains("answer" + "_zones"))
        XCTAssertFalse(prompt.contains("correct" + "_indexes"))
    }

    func testTraceRequestPayloadKeepsExactPromptMessages() throws {
        let service = makeService()
        let messages: [[String: Any]] = [
            ["role": "system", "content": "System prompt with $\\varphi$."],
            ["role": "user", "content": "User prompt source text."]
        ]
        let body = service.requestBody(messages: messages, model: "test-text")
        let traceJSON = try XCTUnwrap(service.traceJSONString(forJSONObject: body))
        let traceData = try XCTUnwrap(traceJSON.data(using: .utf8))
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: traceData) as? [String: Any])
        let decodedMessages = try XCTUnwrap(decoded["messages"] as? [[String: Any]])

        XCTAssertEqual(decodedMessages.count, 2)
        XCTAssertEqual(decodedMessages[0]["role"] as? String, "system")
        XCTAssertEqual(decodedMessages[0]["content"] as? String, "System prompt with $\\varphi$.")
        XCTAssertEqual(decodedMessages[1]["role"] as? String, "user")
        XCTAssertEqual(decodedMessages[1]["content"] as? String, "User prompt source text.")

        let metadata = service.requestTraceMetadata(
            messages: messages,
            model: "test-text",
            url: try XCTUnwrap(URL(string: "https://example.com/v1/chat/completions"))
        )
        XCTAssertEqual(metadata["message_1_role"], "system")
        XCTAssertEqual(metadata["message_1_content_type"], "string")
        XCTAssertEqual(metadata["message_2_role"], "user")
        XCTAssertEqual(metadata["message_2_content_type"], "string")
        XCTAssertEqual(metadata["system_prompt_length"], "29")
        XCTAssertEqual(metadata["user_prompt_text_length"], "24")
        XCTAssertTrue(metadata["prompt_payload"]?.contains("exact sanitized provider JSON body") == true)
    }

    func testQuizPromptPrefersCompactChoicesForNamedTechnicalAnswers() {
        let service = makeService()
        let prompt = service.systemPrompt(
            targetCards: 3,
            isOCR: false,
            options: AIGenerationOptions(cardType: .quiz)
        )

        XCTAssertTrue(prompt.contains("named concept, keyword, convention, API, signature, formula, date, actor, work title, or other short recall surface"))
        XCTAssertTrue(prompt.contains("make all choices compact answers of that same kind"))
        XCTAssertTrue(prompt.contains("Do not wrap a simple term or construct in a full explanatory sentence"))
        XCTAssertTrue(prompt.contains("keep the choices compact instead of turning every choice into a paragraph"))
        XCTAssertTrue(prompt.contains("split setup prose, central formulas, and the actual question into separate question zones"))
        XCTAssertTrue(prompt.contains("long formulas in their own question zone"))
    }

    func testOCRPromptConstrainsNoisyFormalNotationRepair() {
        let service = makeService()
        let prompt = service.systemPrompt(
            targetCards: 2,
            isOCR: true,
            options: AIGenerationOptions(cardType: .flashcards)
        )

        XCTAssertTrue(prompt.contains("OCR CORRECTION MODE ENABLED"))
        XCTAssertTrue(prompt.contains("PDF/text extraction may split language-specific diacritics or formal symbols across lines"))
        XCTAssertTrue(prompt.contains("do not fabricate a full equation just to make the card look mathematical"))
    }

    func testNoisyPDFKitTextRequestsAICorrection() {
        let noisyText = """
        Logic˘a pentru informatic˘a
        Relat
        ,
        ia |= este definit˘a astfel: τ |= φ ddac˘aˆ
        τ φ = 1.
        Demonstrat
        ,
        ie: Consider˘am o atribuire τ : A→B oarecare.
        """
        let cleanText = """
        Logică pentru informatică.
        Relația de satisfacere este definită astfel: τ |= φ dacă valoarea formulei este 1.
        Considerăm o atribuire oarecare și păstrăm notația logică în text.
        """

        XCTAssertTrue(DocumentTextExtractor.needsAICorrectionForExtractedText([noisyText]))
        XCTAssertFalse(DocumentTextExtractor.needsAICorrectionForExtractedText([cleanText]))
    }

    func testAllocatedTextBatchesSplitLargeSourceRangeAcrossRequests() {
        let service = makeService()
        let segments = (1...10).map { index in
            AITextSourceSegment(
                index: index,
                label: "Page \(index)",
                text: "Page \(index) content"
            )
        }

        let plans = service.buildTextBatchPlans(
            segments: segments,
            allocations: [
                AISourceRangeAllocation(startIndex: 1, endIndex: 10, cardCount: 15)
            ],
            options: AIGenerationOptions(cardType: .quiz)
        )

        XCTAssertEqual(plans.map(\.targetCards), [3, 6, 6])
        XCTAssertEqual(plans.map(\.sourceLabel), ["Page 1 - Page 4", "Page 5 - Page 7", "Page 8 - Page 10"])
        XCTAssertTrue(plans[0].text.contains("Page 1 content"))
        XCTAssertFalse(plans[0].text.contains("Page 10 content"))
        XCTAssertTrue(plans[2].text.contains("Page 10 content"))
    }

    func testHighVolumeTextBatchingUsesUniformTenCardRequests() {
        let service = makeService()
        let text = (1...100)
            .map { "Page \($0)\nDense source paragraph \($0)." }
            .joined(separator: DocumentTextExtractor.pageSeparator)

        let plans = service.buildTextBatchPlans(
            text: text,
            targetCards: 100,
            options: AIGenerationOptions(cardType: .flashcards)
        )

        XCTAssertEqual(plans.count, 10)
        XCTAssertEqual(plans.map(\.targetCards), Array(repeating: 10, count: 10))
    }

    @MainActor
    func testHighVolumeAutomaticAllocationsPreferTenRangesCappedAtTenCards() {
        let viewModel = DeckWorkspaceViewModel(deckToEdit: nil)
        let characterCounts = Array(repeating: 1_000, count: 49)

        let allocations = viewModel.automaticAllocations(
            for: characterCounts,
            totalCards: 100
        )

        XCTAssertEqual(allocations.count, 10)
        XCTAssertEqual(allocations.reduce(0) { $0 + $1.cardCount }, 100)
        XCTAssertTrue(allocations.allSatisfy { $0.cardCount <= 10 })
    }

    func testRepeatedSourceBatchesRunSequentiallySoCoveredPromptsCanUpdate() {
        let service = makeService()
        let plans = service.buildTextBatchPlans(
            segments: [
                AITextSourceSegment(index: 1, label: "Page 1", text: "Only page")
            ],
            allocations: [
                AISourceRangeAllocation(startIndex: 1, endIndex: 1, cardCount: 15)
            ],
            options: AIGenerationOptions(cardType: .quiz)
        )

        XCTAssertEqual(plans.map(\.sourceLabel), ["Page 1", "Page 1", "Page 1"])
        XCTAssertEqual(
            service.effectiveMaxConcurrentRequestCount(for: plans, requestedMaxConcurrent: 6),
            1
        )
    }

    func testPromptSupportsSimpleDepthProfile() {
        let service = makeService()
        let prompt = service.systemPrompt(
            targetCards: 2,
            isOCR: false,
            options: AIGenerationOptions(cardType: .flashcards, cardLevel: .simple)
        )

        XCTAssertTrue(prompt.contains("DEPTH: SIMPLE"))
        XCTAssertTrue(prompt.contains("Do not dumb down the content"))
        XCTAssertTrue(prompt.contains("Do not remove notation or exact syntax"))
        XCTAssertTrue(prompt.contains("Use fewer zones when the idea is truly simple"))
        XCTAssertTrue(prompt.contains("let the back use only as many zones as the core answer needs"))
        XCTAssertTrue(prompt.contains("Do not force a fixed number of zones"))
        XCTAssertFalse(prompt.contains("For programming sources"))
    }

    func testTextPromptDoesNotInjectKeywordBasedProgrammingProfile() {
        let service = makeService()
        let prompt = service.buildTextUserMessage(
            text: """
            public class UserService {
                public User findById(String id) throws IOException {
                    return repository.load(id);
                }
            }
            """,
            targetCards: 3,
            options: AIGenerationOptions(cardType: .flashcards),
            cardType: .flashcards,
            sourceLabel: "test",
            batchIndex: 1,
            totalBatches: 1,
            passIndex: 1,
            coveredPrompts: []
        )

        XCTAssertFalse(prompt.contains("PROGRAMMING SOURCE PROFILE"))
    }

    func testCardGenerationLevelUsesSimpleAndProOnlyAndMigratesLegacyValues() throws {
        XCTAssertEqual(AICardGenerationLevel.allCases, [.simple, .pro])

        let decoder = JSONDecoder()
        XCTAssertEqual(try decoder.decode(AICardGenerationLevel.self, from: Data(#""simple""#.utf8)), .simple)
        XCTAssertEqual(try decoder.decode(AICardGenerationLevel.self, from: Data(#""pro""#.utf8)), .pro)
        XCTAssertEqual(try decoder.decode(AICardGenerationLevel.self, from: Data(#""balanced""#.utf8)), .pro)
        XCTAssertEqual(try decoder.decode(AICardGenerationLevel.self, from: Data(#""advanced""#.utf8)), .pro)
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
