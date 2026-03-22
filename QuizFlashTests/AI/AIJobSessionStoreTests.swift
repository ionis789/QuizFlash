//
//  AIJobSessionStoreTests.swift
//  QuizFlashTests
//
//  Covers unified AI job persistence for generation and conversion sessions.
//

import Foundation
import SwiftData
import UIKit
import XCTest
@testable import QuizFlash

@MainActor
final class AIJobSessionStoreTests: XCTestCase {
    func testSaveAndLoadGenerationSessionRoundTrip() async throws {
        let directoryURL = try TestFileSystemFactory.makeTemporaryDirectory(prefix: "AIJobSessionStoreTests")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = AIJobSessionStore(
            fileManager: .default,
            rootDirectoryURL: directoryURL,
            currentDate: { Date(timeIntervalSince1970: 500) }
        )
        let session = makeGenerationSession(timestamp: Date(timeIntervalSince1970: 100))

        try await store.saveSession(.generation(session))
        let loadedSession = await store.loadSession()

        XCTAssertEqual(loadedSession, .generation(session))
    }

    func testLoadLegacyGenerationPayloadMigratesToUnifiedEnvelope() async throws {
        let directoryURL = try TestFileSystemFactory.makeTemporaryDirectory(prefix: "AIJobSessionStoreTests")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = AIJobSessionStore(fileManager: .default, rootDirectoryURL: directoryURL)
        let legacySession = makeGenerationSession()
        let data = try JSONEncoder().encode(legacySession)
        try data.write(
            to: directoryURL.appendingPathComponent("paused_ai_session.json"),
            options: [.atomic]
        )

        let loadedSession = await store.loadSession()

        XCTAssertEqual(loadedSession, .generation(legacySession))
    }

    func testSaveAndLoadConversionSessionRoundTrip() async throws {
        let directoryURL = try TestFileSystemFactory.makeTemporaryDirectory(prefix: "AIJobSessionStoreTests")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = AIJobSessionStore(
            fileManager: .default,
            rootDirectoryURL: directoryURL,
            currentDate: { Date(timeIntervalSince1970: 900) }
        )
        let session = try makeConversionSession(timestamp: Date(timeIntervalSince1970: 300))

        try await store.saveSession(.conversion(session))
        let loadedSession = await store.loadSession()

        XCTAssertEqual(loadedSession, .conversion(session))
    }

    func testSavingSessionDoesNotDeleteStoredGenerationImages() async throws {
        let directoryURL = try TestFileSystemFactory.makeTemporaryDirectory(prefix: "AIJobSessionStoreTests")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = AIJobSessionStore(fileManager: .default, rootDirectoryURL: directoryURL)
        let savedURLs = try await store.saveImagesToDisk([
            makeImage(color: .red),
            makeImage(color: .blue)
        ])
        let session = AIPausedSession(
            sessionID: UUID(),
            deckTitle: "Photos",
            folderID: nil,
            deckID: nil,
            targetCardCount: 2,
            generatedCardCount: 0,
            baseCardCount: 0,
            options: AIGenerationOptions(cardType: .flashcards),
            remainingAllocations: [AISourceRangeAllocation(startIndex: 0, endIndex: 1, cardCount: 2)],
            sourceMode: .photos(fileURLs: savedURLs),
            draftCards: [],
            providerProfileID: UUID()
        )

        try await store.saveSession(.generation(session))

        XCTAssertTrue(savedURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        let reloadedImages = await store.loadImagesFromDisk(at: savedURLs)
        XCTAssertEqual(reloadedImages.count, 2)
    }

    private func makeGenerationSession(timestamp: Date = Date()) -> AIPausedSession {
        AIPausedSession(
            sessionID: UUID(),
            deckTitle: "Paused Deck",
            folderID: nil,
            deckID: nil,
            targetCardCount: 10,
            generatedCardCount: 4,
            baseCardCount: 2,
            options: AIGenerationOptions(
                cardType: .match,
                cardLevel: .advanced,
                cardsPerBatch: 5,
                sourceDistributionMode: .manual
            ),
            remainingAllocations: [
                AISourceRangeAllocation(startIndex: 0, endIndex: 2, cardCount: 3),
                AISourceRangeAllocation(startIndex: 3, endIndex: 4, cardCount: 2)
            ],
            sourceMode: .photos(fileURLs: [
                URL(fileURLWithPath: "/tmp/source-a.jpg"),
                URL(fileURLWithPath: "/tmp/source-b.jpg")
            ]),
            draftCards: [
                DraftCard(
                    cardNumber: 1,
                    content: TestMutationFactory.flashcard(front: "Question", back: "Answer"),
                    isPinned: true,
                    creationSource: .ai
                )
            ],
            providerProfileID: UUID(),
            timestamp: timestamp
        )
    }

    private func makeConversionSession(timestamp: Date = Date()) throws -> AIPausedConversionSession {
        let context = try TestModelContainerFactory.makeContext()
        let sourceDeck = DeckModel(title: "Algorithms", icon: "book", colorHex: "#112233")
        let flashCard = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.flashcard(front: "BFS", back: "Breadth-first search"),
            cardNumber: 1
        )
        let matchCard = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.match(prompt: "DFS", answer: "Depth-first search"),
            cardNumber: 2
        )

        context.insert(sourceDeck)
        context.insert(flashCard)
        context.insert(matchCard)
        sourceDeck.cards = [flashCard, matchCard]
        sourceDeck.cardCount = 2
        sourceDeck.lastAssignedCardNumber = 2
        try context.save()

        let descriptors = [
            DeckCardConversionSourceDescriptor(id: flashCard.persistentModelID, kind: .flashcard),
            DeckCardConversionSourceDescriptor(id: matchCard.persistentModelID, kind: .match)
        ]
        let request = DeckCardConversionRequest(
            availableScopes: [.wholeDeck],
            wholeDeckSources: descriptors,
            recommendedSources: [],
            selectedSources: [],
            singleSources: [],
            scope: .wholeDeck,
            sourceKindFilters: [.flashcard, .match],
            targetKind: .write,
            destination: .newDeck,
            newDeckTitle: "Algorithms Write"
        )

        return AIPausedConversionSession(
            sourceDeckID: sourceDeck.persistentModelID,
            sourceDeckTitle: sourceDeck.title,
            request: request,
            destinationBaseCardIDs: [],
            remainingSources: [
                CardConversionSourceSnapshot(
                    id: flashCard.persistentModelID,
                    kind: .flashcard,
                    content: flashCard.cardContent
                ),
                CardConversionSourceSnapshot(
                    id: matchCard.persistentModelID,
                    kind: .match,
                    content: matchCard.cardContent
                )
            ],
            totalCount: 2,
            completedCount: 1,
            createdCount: 1,
            skippedCount: 0,
            failedCount: 0,
            statusMessage: "Converting Match to Write",
            destinationDeckID: nil,
            providerProfileID: UUID(),
            batchID: UUID(),
            convertedAt: Date(timeIntervalSince1970: 200),
            timestamp: timestamp
        )
    }

    private func makeImage(color: UIColor) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }
}
