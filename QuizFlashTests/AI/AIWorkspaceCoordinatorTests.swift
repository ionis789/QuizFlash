//
//  AIWorkspaceCoordinatorTests.swift
//  QuizFlashTests
//
//  Covers persisted AI workspace restore for floating status.
//

import Foundation
import XCTest
import SwiftData
import SwiftUI
@testable import QuizFlash

@MainActor
final class AIWorkspaceCoordinatorTests: XCTestCase {
    func testRestorePersistedGenerationSessionExposesPausedFloatingStatus() async throws {
        let directoryURL = try TestFileSystemFactory.makeTemporaryDirectory(prefix: "AIWorkspaceCoordinatorTests")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = AIJobSessionStore(fileManager: .default, rootDirectoryURL: directoryURL)
        let coordinator = AIWorkspaceCoordinator(jobSessionStore: store)
        let context = try TestModelContainerFactory.makeContext()

        try await store.saveSession(.generation(makeGenerationSession()))
        await coordinator.restorePersistedJobIfNeeded(context: context)

        XCTAssertEqual(coordinator.generationStatus?.phase, .paused)
        XCTAssertEqual(coordinator.floatingStatus?.kind, .generation)
        XCTAssertEqual(coordinator.floatingStatus?.phase, .paused)
    }

    func testOpenWorkspaceReturnsToCreateRootHostAndClearsExistingCreatePath() {
        let coordinator = AIWorkspaceCoordinator()
        let router = NavigationManager()

        coordinator.generationStatus = AIWorkspaceGenerationStatus(
            phase: .running,
            title: "Generating cards",
            foundCount: 3,
            targetCount: 10,
            progress: 0.3,
            message: "Biology",
            errorMessage: nil
        )

        router.createPath.append(AppRoute.generateDeck)
        router.activeTab = .home

        coordinator.openWorkspace(router: router)

        XCTAssertEqual(router.activeTab, .create)
        XCTAssertNil(router.createWorkspaceEditingDeckID)
        XCTAssertEqual(router.createPath.count, 0)
    }

    private func makeGenerationSession() -> AIPausedSession {
        AIPausedSession(
            sessionID: UUID(),
            deckTitle: "Graph Theory",
            folderID: nil,
            deckID: nil,
            targetCardCount: 8,
            generatedCardCount: 3,
            baseCardCount: 0,
            options: AIGenerationOptions(cardType: .quiz, cardLevel: .balanced),
            remainingAllocations: [
                AISourceRangeAllocation(startIndex: 0, endIndex: 2, cardCount: 5)
            ],
            sourceMode: .photos(fileURLs: [URL(fileURLWithPath: "/tmp/graph.jpg")]),
            draftCards: [],
            providerProfileID: UUID(),
            timestamp: Date()
        )
    }

}
