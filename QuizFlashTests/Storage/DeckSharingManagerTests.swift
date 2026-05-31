//
//  DeckSharingManagerTests.swift
//  QuizFlashTests
//
//  Covers export and import persistence round-trips for JSON decks.
//

import XCTest
import SwiftData
@testable import QuizFlash

@MainActor
final class DeckSharingManagerTests: XCTestCase {
    func testExportImportRoundTripPreservesSupportedCards() async throws {
        let exportContext = try TestModelContainerFactory.makeContext()

        let deck = DeckModel(title: "Round Trip", colorHex: "#ABCDEF")
        let flashcard = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.flashcard(front: "Base", back: "Source"),
            cardNumber: 1
        )

        exportContext.insert(deck)
        exportContext.insert(flashcard)

        let quizCard = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.quiz(
                question: "Largest planet?",
                correctAnswers: ["Jupiter"],
                incorrectAnswers: ["Mars", "Venus"],
                explanation: "Gas giant."
            ),
            cardNumber: 3
        )
        exportContext.insert(quizCard)

        deck.cards = [flashcard, quizCard]
        deck.cardCount = 2
        deck.lastAssignedCardNumber = 2

        try exportContext.save()

        let manager = DeckSharingManager.shared
        let fileURL = try await manager.exportDeck(deck)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        XCTAssertEqual(fileURL.pathExtension, "json")

        let importContext = try TestModelContainerFactory.makeContext()
        let importedDeck = try await manager.importDeck(from: fileURL, into: importContext)

        XCTAssertEqual(importedDeck.title, "Round Trip")
        XCTAssertEqual(importedDeck.colorHex, "#ABCDEF")
        XCTAssertEqual(importedDeck.cardCount, 2)

        XCTAssertEqual(importedDeck.cards.map(\.cardContent.kind).sorted(by: { $0.rawValue < $1.rawValue }), [
            .flashcard,
            .quiz
        ].sorted(by: { $0.rawValue < $1.rawValue }))

        let importedQuizCard = try XCTUnwrap(
            importedDeck.cards.first(where: { $0.cardContent.kind == .quiz })
        )
        if case .quiz(let quizContent) = importedQuizCard.cardContent {
            XCTAssertEqual(quizContent.choices.count, 3)
            XCTAssertEqual(quizContent.explanationZone?.text, "Gas giant.")
        } else {
            XCTFail("Expected imported quiz payload")
        }
    }

    func testExportImportRoundTripPreservesZoneTreesAndMedia() async throws {
        let exportContext = try TestModelContainerFactory.makeContext()
        let deck = DeckModel(title: "Rich JSON", colorHex: "#112233")
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        let sketchData = Data([0x01, 0x02, 0x03])

        let frontZone = ZoneModel.container(
            direction: .vertical,
            children: [
                .code("let answer = 42", language: "swift"),
                .image(data: imageData)
            ]
        )
        let backZone = ZoneModel.container(
            direction: .vertical,
            children: [
                .text("Explanation"),
                .sketch(data: sketchData)
            ]
        )
        let card = TestMutationFactory.makePersistedCard(
            content: .flashcard(
                FlashcardCardContent(
                    frontZone: frontZone,
                    backZone: backZone,
                    frontType: .text,
                    backType: .text
                )
            ),
            cardNumber: 1
        )

        exportContext.insert(deck)
        exportContext.insert(card)
        deck.cards = [card]
        deck.cardCount = 1
        deck.lastAssignedCardNumber = 1
        try exportContext.save()

        let fileURL = try await DeckSharingManager.shared.exportDeck(deck)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let importContext = try TestModelContainerFactory.makeContext()
        let importedDeck = try await DeckSharingManager.shared.importDeck(from: fileURL, into: importContext)
        let importedCard = try XCTUnwrap(importedDeck.cards.first)

        if case .flashcard(let content) = importedCard.cardContent {
            XCTAssertEqual(content.frontZone.children?.first?.contentType, .code)
            XCTAssertEqual(content.frontZone.children?.first?.codeLanguage, "swift")
            XCTAssertEqual(content.frontZone.children?.last?.imageData, imageData)
            XCTAssertEqual(content.backZone.children?.last?.contentType, .sketch)
            XCTAssertEqual(content.backZone.children?.last?.imageData, sketchData)
        } else {
            XCTFail("Expected imported flashcard payload")
        }
    }

    func testImportRejectsOldCustomExtension() async throws {
        let context = try TestModelContainerFactory.makeContext()
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("legacy." + "q" + "flash")
        try Data("{}".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        do {
            _ = try await DeckSharingManager.shared.importDeck(from: fileURL, into: context)
            XCTFail("Expected legacy custom deck import to fail")
        } catch DeckSharingError.invalidFormat {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testImportRejectsUnsupportedSchemaVersion() async throws {
        let context = try TestModelContainerFactory.makeContext()
        let document = DeckJSONDocument(
            schemaVersion: DeckJSONDocument.supportedSchemaVersion + 1,
            deck: DeckJSONDeckMetadata(
                title: "Future",
                colorHex: "#000000",
                createdAt: Date(),
                editedAt: Date()
            ),
            cards: []
        )
        let fileURL = try writeJSONDocument(document, filename: "future.json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        do {
            _ = try await DeckSharingManager.shared.importDeck(from: fileURL, into: context)
            XCTFail("Expected unsupported schema import to fail")
        } catch DeckSharingError.versionMismatch(let version) {
            XCTAssertEqual(version, DeckJSONDocument.supportedSchemaVersion + 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testImportRejectsUnknownCardType() async throws {
        let context = try TestModelContainerFactory.makeContext()
        let payload = """
        {
          "schemaVersion": 1,
          "app": { "name": "QuizFlash", "version": "1" },
          "deck": {
            "title": "Invalid",
            "colorHex": "#000000",
            "createdAt": "2026-05-31T00:00:00Z",
            "editedAt": "2026-05-31T00:00:00Z"
          },
          "cards": [
            {
              "id": "\(UUID().uuidString)",
              "creationSource": "manual",
              "createdAt": "2026-05-31T00:00:00Z",
              "editedAt": "2026-05-31T00:00:00Z",
              "card": { "type": "unknown" }
            }
          ]
        }
        """
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("unknown-type.json")
        try Data(payload.utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        do {
            _ = try await DeckSharingManager.shared.importDeck(from: fileURL, into: context)
            XCTFail("Expected unknown card type import to fail")
        } catch DeckSharingError.corruptedData {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func writeJSONDocument(_ document: DeckJSONDocument, filename: String) throws -> URL {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(document)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url)
        return url
    }
}
