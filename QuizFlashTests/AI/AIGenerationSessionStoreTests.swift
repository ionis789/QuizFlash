//
//  AIGenerationSessionStoreTests.swift
//  QuizFlashTests
//
//  Covers paused AI generation persistence, expiry, and temporary image storage.
//

import Foundation
import UIKit
import XCTest
@testable import QuizFlash

@MainActor
final class AIGenerationSessionStoreTests: XCTestCase {
    func testSaveAndLoadSessionRoundTripPreservesDraftState() async throws {
        let directoryURL = try TestFileSystemFactory.makeTemporaryDirectory(prefix: "AIGenerationSessionStoreTests")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = AIGenerationSessionStore(
            fileManager: .default,
            rootDirectoryURL: directoryURL,
            currentDate: { Date(timeIntervalSince1970: 500) }
        )
        let session = makePausedSession(timestamp: Date(timeIntervalSince1970: 100))

        try await store.saveSession(session)
        let loadedSession = await store.loadSession()

        XCTAssertEqual(loadedSession, session)
    }

    func testExpiredSessionReturnsNilAndDeletesPersistedFile() async throws {
        let directoryURL = try TestFileSystemFactory.makeTemporaryDirectory(prefix: "AIGenerationSessionStoreTests")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = AIGenerationSessionStore(
            fileManager: .default,
            rootDirectoryURL: directoryURL,
            currentDate: { Date(timeIntervalSince1970: 86400 * 9) }
        )
        let session = makePausedSession(timestamp: Date(timeIntervalSince1970: 0))

        try await store.saveSession(session)
        let loadedSession = await store.loadSession()

        XCTAssertNil(loadedSession)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directoryURL.appendingPathComponent("paused_ai_session.json").path
            )
        )
    }

    func testClearSessionRemovesPersistedSessionAndStoredImages() async throws {
        let directoryURL = try TestFileSystemFactory.makeTemporaryDirectory(prefix: "AIGenerationSessionStoreTests")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = AIGenerationSessionStore(fileManager: .default, rootDirectoryURL: directoryURL)
        let session = makePausedSession()

        try await store.saveSession(session)
        let savedURLs = try await store.saveImagesToDisk([makeImage(color: .red), makeImage(color: .blue)])
        XCTAssertEqual(savedURLs.count, 2)

        try await store.clearSession()

        let loadedSession = await store.loadSession()
        let imagesDirectoryURL = directoryURL.appendingPathComponent("ai_session_images", isDirectory: true)
        let remainingImageFiles = try FileManager.default.contentsOfDirectory(
            at: imagesDirectoryURL,
            includingPropertiesForKeys: nil
        )

        XCTAssertNil(loadedSession)
        XCTAssertTrue(remainingImageFiles.isEmpty)
    }

    func testSavedImagesLoadBackFromDisk() async throws {
        let directoryURL = try TestFileSystemFactory.makeTemporaryDirectory(prefix: "AIGenerationSessionStoreTests")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = AIGenerationSessionStore(fileManager: .default, rootDirectoryURL: directoryURL)
        let sourceImages = [makeImage(color: .green), makeImage(color: .orange)]

        let savedURLs = try await store.saveImagesToDisk(sourceImages)
        let reloadedImages = await store.loadImagesFromDisk(at: savedURLs)

        XCTAssertEqual(savedURLs.count, 2)
        XCTAssertEqual(reloadedImages.count, 2)
        XCTAssertTrue(savedURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        XCTAssertTrue(reloadedImages.allSatisfy { $0.size.width > 0 && $0.size.height > 0 })
    }

    private func makePausedSession(timestamp: Date = Date()) -> AIPausedSession {
        let draftCards = [
            DraftCard(
                cardNumber: 1,
                content: TestMutationFactory.flashcard(front: "Question", back: "Answer"),
                isPinned: true,
                creationSource: .ai
            ),
            DraftCard(
                cardNumber: 2,
                content: TestMutationFactory.quiz(
                    question: "What does ATP store?",
                    correctAnswers: ["Energy"]
                ),
                creationSource: .manual
            )
        ]

        return AIPausedSession(
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
                sourceDistributionMode: .manual,
                userInstructions: "Keep the requested source-supported angle."
            ),
            remainingAllocations: [
                AISourceRangeAllocation(startIndex: 0, endIndex: 2, cardCount: 3),
                AISourceRangeAllocation(startIndex: 3, endIndex: 4, cardCount: 2)
            ],
            sourceMode: .photos(fileURLs: [
                URL(fileURLWithPath: "/tmp/source-a.jpg"),
                URL(fileURLWithPath: "/tmp/source-b.jpg")
            ]),
            draftCards: draftCards,
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
