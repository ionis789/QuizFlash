//
//  AIJobSessionStoreTests.swift
//  QuizFlashTests
//
//  Covers AI generation job persistence.
//

import Foundation
import UIKit
import XCTest
@testable import QuizFlash

@MainActor
final class AIJobSessionStoreTests: XCTestCase {
    private let ownerUID = "test-user"
    func testSaveAndLoadGenerationSessionRoundTrip() async throws {
        let directoryURL = try TestFileSystemFactory.makeTemporaryDirectory(prefix: "AIJobSessionStoreTests")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = AIJobSessionStore(
            fileManager: .default,
            rootDirectoryURL: directoryURL,
            currentDate: { Date(timeIntervalSince1970: 500) }
        )
        let session = makeGenerationSession(timestamp: Date(timeIntervalSince1970: 100))

        try await store.saveSession(.generation(session), ownerUID: ownerUID)
        let loadedSession = await store.loadSession(ownerUID: ownerUID)

        XCTAssertEqual(loadedSession, .generation(session))
    }

    func testLegacyUnscopedGenerationPayloadIsNotLoaded() async throws {
        let directoryURL = try TestFileSystemFactory.makeTemporaryDirectory(prefix: "AIJobSessionStoreTests")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = AIJobSessionStore(fileManager: .default, rootDirectoryURL: directoryURL)
        let legacySession = makeGenerationSession()
        let data = try JSONEncoder().encode(legacySession)
        try data.write(
            to: directoryURL.appendingPathComponent("paused_ai_session.json"),
            options: [.atomic]
        )

        try await store.removeLegacyUnscopedDataIfNeeded()
        let loadedSession = await store.loadSession(ownerUID: ownerUID)

        XCTAssertNil(loadedSession)
    }

    func testSavingSessionDoesNotDeleteStoredGenerationImages() async throws {
        let directoryURL = try TestFileSystemFactory.makeTemporaryDirectory(prefix: "AIJobSessionStoreTests")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = AIJobSessionStore(fileManager: .default, rootDirectoryURL: directoryURL)
        let savedURLs = try await store.saveImagesToDisk([
            makeImage(color: .red),
            makeImage(color: .blue)
        ], ownerUID: ownerUID)
        let session = AIPausedSession(
            ownerUID: ownerUID,
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

        try await store.saveSession(.generation(session), ownerUID: ownerUID)

        XCTAssertTrue(savedURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        let reloadedImages = await store.loadImagesFromDisk(at: savedURLs)
        XCTAssertEqual(reloadedImages.count, 2)
    }

    func testSessionsAreIsolatedByOwnerUID() async throws {
        let directoryURL = try TestFileSystemFactory.makeTemporaryDirectory(prefix: "AIJobSessionStoreTests")
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let store = AIJobSessionStore(fileManager: .default, rootDirectoryURL: directoryURL)
        let session = makeGenerationSession()

        try await store.saveSession(.generation(session), ownerUID: ownerUID)

        let matchingSession = await store.loadSession(ownerUID: ownerUID)
        let otherSession = await store.loadSession(ownerUID: "different-user")
        XCTAssertEqual(matchingSession, .generation(session))
        XCTAssertNil(otherSession)
    }

    private func makeGenerationSession(timestamp: Date = Date()) -> AIPausedSession {
        AIPausedSession(
            ownerUID: ownerUID,
            sessionID: UUID(),
            deckTitle: "Paused Deck",
            folderID: nil,
            deckID: nil,
            targetCardCount: 10,
            generatedCardCount: 4,
            baseCardCount: 2,
            options: AIGenerationOptions(
                cardType: .quiz,
                cardLevel: .pro,
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

    private func makeImage(color: UIColor) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }
}
