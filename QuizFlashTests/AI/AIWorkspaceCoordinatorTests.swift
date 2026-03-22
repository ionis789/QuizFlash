//
//  AIWorkspaceCoordinatorTests.swift
//  QuizFlashTests
//
//  Covers persisted AI workspace restore for floating status and resumable conversion UI.
//

import Foundation
import XCTest
import SwiftData
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

    func testRestorePersistedConversionSessionExposesResumeState() async throws {
        let directoryURL = try TestFileSystemFactory.makeTemporaryDirectory(prefix: "AIWorkspaceCoordinatorTests")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = AIJobSessionStore(fileManager: .default, rootDirectoryURL: directoryURL)
        let coordinator = AIWorkspaceCoordinator(jobSessionStore: store)
        let context = try TestModelContainerFactory.makeContext()
        let session = try makeConversionSession(context: context)

        try await store.saveSession(.conversion(session))
        await coordinator.restorePersistedJobIfNeeded(context: context)

        XCTAssertTrue(coordinator.canResumeConversion)
        XCTAssertEqual(coordinator.conversionProgress?.completedCount, 1)
        XCTAssertEqual(coordinator.conversionProgress?.totalCount, 2)
        XCTAssertEqual(coordinator.floatingStatus?.kind, .conversion)
        XCTAssertEqual(coordinator.floatingStatus?.phase, .paused)
        XCTAssertEqual(coordinator.workspaceDeckContext?.displayTitle, "Algorithms")
        XCTAssertEqual(coordinator.workspaceDeckContext?.liveDeckID, sourceDeckID(from: session))
    }

    func testDismissConversionConfigurationClearsSeedAndWorkspaceDeckContext() async throws {
        let directoryURL = try TestFileSystemFactory.makeTemporaryDirectory(prefix: "AIWorkspaceCoordinatorTests")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = AIJobSessionStore(fileManager: .default, rootDirectoryURL: directoryURL)
        let coordinator = AIWorkspaceCoordinator(jobSessionStore: store)
        let context = try TestModelContainerFactory.makeContext()
        let deck = DeckModel(title: "Graphs", icon: "book", colorHex: "#112233")
        context.insert(deck)
        try context.save()

        let request = DeckCardConversionRequest(
            availableScopes: [.wholeDeck],
            wholeDeckSources: [],
            recommendedSources: [],
            selectedSources: [],
            singleSources: [],
            scope: .wholeDeck,
            sourceKindFilters: [],
            targetKind: .write,
            destination: .newDeck,
            newDeckTitle: "Converted Graphs"
        )

        XCTAssertTrue(coordinator.seedConversion(request: request, sourceDeck: deck))
        XCTAssertNotNil(coordinator.workspaceDeckContext)
        XCTAssertNotNil(coordinator.conversionSeed)

        coordinator.dismissConversionConfiguration()

        XCTAssertNil(coordinator.workspaceDeckContext)
        XCTAssertNil(coordinator.conversionSeed)
    }

    func testSeedConversionCanKeepWorkspaceContextDetachedUntilStart() async throws {
        let directoryURL = try TestFileSystemFactory.makeTemporaryDirectory(prefix: "AIWorkspaceCoordinatorTests")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = AIJobSessionStore(fileManager: .default, rootDirectoryURL: directoryURL)
        let coordinator = AIWorkspaceCoordinator(jobSessionStore: store)
        let context = try TestModelContainerFactory.makeContext()
        let deck = DeckModel(title: "Geometry", icon: "book", colorHex: "#223344")
        context.insert(deck)
        try context.save()

        let request = DeckCardConversionRequest(
            availableScopes: [.wholeDeck],
            wholeDeckSources: [],
            recommendedSources: [],
            selectedSources: [],
            singleSources: [],
            scope: .wholeDeck,
            sourceKindFilters: [],
            targetKind: .quiz,
            destination: .sameDeck,
            newDeckTitle: ""
        )

        XCTAssertTrue(
            coordinator.seedConversion(
                request: request,
                sourceDeck: deck,
                activatesWorkspaceContext: false
            )
        )
        XCTAssertNotNil(coordinator.conversionSeed)
        XCTAssertNil(coordinator.workspaceDeckContext)
    }

    func testCancelConversionDiscardingCreatedCardsRemovesBatchOutputs() async throws {
        let directoryURL = try TestFileSystemFactory.makeTemporaryDirectory(prefix: "AIWorkspaceCoordinatorTests")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = AIJobSessionStore(fileManager: .default, rootDirectoryURL: directoryURL)
        let coordinator = AIWorkspaceCoordinator(jobSessionStore: store)
        let context = try TestModelContainerFactory.makeContext()
        let session = try makeConversionSession(context: context)

        try await store.saveSession(.conversion(session))
        await coordinator.restorePersistedJobIfNeeded(context: context)

        coordinator.cancelConversion(context: context, keepingCreatedCards: false)

        let deck = try XCTUnwrap(context.model(for: session.sourceDeckID) as? DeckModel)
        XCTAssertEqual(deck.cardCount, 2)
        XCTAssertEqual(deck.cards.count, 2)
        XCTAssertFalse(deck.cards.contains { $0.conversionMetadata?.batchID == session.batchID })
        XCTAssertNil(coordinator.workspaceDeckContext)
        XCTAssertFalse(coordinator.canCancelConversion)
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

    private func makeConversionSession(context: ModelContext) throws -> AIPausedConversionSession {
        let sourceDeck = DeckModel(title: "Algorithms", icon: "book", colorHex: "#112233")
        let flashCard = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.flashcard(front: "BFS", back: "Breadth-first search"),
            cardNumber: 1
        )
        let matchCard = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.match(prompt: "DFS", answer: "Depth-first search"),
            cardNumber: 2
        )

        let batchID = UUID()
        let convertedCard = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.write(prompt: "Queue traversal", answer: "BFS"),
            cardNumber: 3,
            creationSource: .ai,
            conversionMetadata: CardConversionMetadata(
                sourceCardID: matchCard.persistentModelID,
                sourceKind: .match,
                targetKind: .write,
                batchID: batchID,
                convertedAt: Date()
            )
        )

        context.insert(sourceDeck)
        context.insert(flashCard)
        context.insert(matchCard)
        context.insert(convertedCard)
        sourceDeck.cards = [flashCard, matchCard, convertedCard]
        sourceDeck.cardCount = 3
        sourceDeck.lastAssignedCardNumber = 3
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
            sourceKindFilters: [.match],
            targetKind: .write,
            destination: .sameDeck,
            newDeckTitle: ""
        )

        return AIPausedConversionSession(
            sourceDeckID: sourceDeck.persistentModelID,
            sourceDeckTitle: sourceDeck.title,
            request: request,
            destinationBaseCardIDs: [
                flashCard.persistentModelID,
                matchCard.persistentModelID
            ],
            remainingSources: [
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
            statusMessage: "Resume conversion in Create",
            destinationDeckID: sourceDeck.persistentModelID,
            providerProfileID: UUID(),
            batchID: batchID,
            convertedAt: Date()
        )
    }

    private func sourceDeckID(from session: AIPausedConversionSession) -> PersistentIdentifier {
        session.sourceDeckID
    }
}
