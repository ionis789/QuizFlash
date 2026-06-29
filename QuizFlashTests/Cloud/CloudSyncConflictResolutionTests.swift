//
//  CloudSyncConflictResolutionTests.swift
//  QuizFlashTests
//

import Foundation
import SwiftData
import XCTest
@testable import QuizFlash

@MainActor
final class CloudSyncConflictResolutionTests: XCTestCase {
    func testSubMillisecondFirestoreTimestampDriftDoesNotCreateAnotherUpload() {
        let remote = Date(timeIntervalSince1970: 1_000)
        let local = remote.addingTimeInterval(0.0005)

        XCTAssertFalse(CloudSyncCoordinator.localEditIsMeaningfullyNewer(local, than: remote))
    }

    func testLaterLocalEditWinsConflict() {
        let remote = Date(timeIntervalSince1970: 1_000)
        let local = remote.addingTimeInterval(1)

        XCTAssertTrue(CloudSyncCoordinator.localEditIsMeaningfullyNewer(local, than: remote))
    }

    @MainActor
    func testRemoteImportActorAppliesSnapshotWithoutMainContextCardScan() async throws {
        let uid = "user-1"
        let deckID = "deck-1"
        let baseDate = Date(timeIntervalSince1970: 2_000)
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let deck = DeckModel(title: "Local", colorHex: "#111111")
        deck.ownerUID = uid
        deck.cloudID = deckID
        deck.editedAt = baseDate

        let keptCard = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.flashcard(front: "Old front", back: "Old back"),
            cardNumber: 1
        )
        keptCard.ownerUID = uid
        keptCard.cloudID = "card-kept"
        keptCard.editedAt = baseDate
        keptCard.deck = deck

        let deletedCard = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.flashcard(front: "Delete me", back: "Delete me"),
            cardNumber: 2
        )
        deletedCard.ownerUID = uid
        deletedCard.cloudID = "card-deleted"
        deletedCard.editedAt = baseDate
        deletedCard.deck = deck

        deck.cards.append(contentsOf: [keptCard, deletedCard])
        deck.cardCount = 2
        context.insert(deck)
        try context.save()

        let actor = CloudSyncRemoteImportActor(
            container: container,
            outbox: CloudSyncOutbox(fileURL: try temporaryOutboxURL())
        )
        let remoteEditedAt = baseDate.addingTimeInterval(10)
        let snapshot = CloudSyncRemoteDeckSnapshot(
            header: CloudSyncRemoteDeckHeader(
                deckID: deckID,
                title: "Remote",
                colorHex: "#222222",
                createdAt: baseDate,
                editedAt: remoteEditedAt,
                lastOpenedAt: nil,
                lastAssignedCardNumber: 3,
                syncRevision: 4,
                isNotFullySynced: false,
                isDeleted: false
            ),
            cards: [
                CloudSyncRemoteCardSnapshot(
                    cardID: "card-kept",
                    content: TestMutationFactory.flashcard(front: "New front", back: "New back"),
                    cardNumber: 1,
                    isPinned: true,
                    creationSourceRaw: CardCreationSource.ai.rawValue,
                    createdAt: baseDate,
                    editedAt: remoteEditedAt,
                    syncRevision: 7,
                    isDeleted: false
                ),
                CloudSyncRemoteCardSnapshot(
                    cardID: "card-deleted",
                    content: nil,
                    cardNumber: 2,
                    isPinned: false,
                    creationSourceRaw: CardCreationSource.manual.rawValue,
                    createdAt: baseDate,
                    editedAt: remoteEditedAt,
                    syncRevision: 2,
                    isDeleted: true
                ),
                CloudSyncRemoteCardSnapshot(
                    cardID: "card-new",
                    content: TestMutationFactory.flashcard(front: "Brand new", back: "Answer"),
                    cardNumber: 3,
                    isPinned: false,
                    creationSourceRaw: CardCreationSource.manual.rawValue,
                    createdAt: baseDate,
                    editedAt: remoteEditedAt,
                    syncRevision: 1,
                    isDeleted: false
                )
            ]
        )

        let result = try await actor.apply(snapshot, uid: uid)

        XCTAssertEqual(result, .noUploadNeeded)

        let verificationContext = ModelContext(container)
        let decks = try verificationContext.fetch(FetchDescriptor<DeckModel>())
        XCTAssertEqual(decks.count, 1)
        let remoteDeck = try XCTUnwrap(decks.first)
        XCTAssertEqual(remoteDeck.title, "Remote")
        XCTAssertEqual(remoteDeck.colorHex, "#222222")
        XCTAssertEqual(remoteDeck.cardCount, 2)

        let persistedCards = try verificationContext.fetch(FetchDescriptor<CardModel>())
        let cardsByCloudID = Dictionary(uniqueKeysWithValues: persistedCards.compactMap { card in
            card.cloudID.map { ($0, card) }
        })
        XCTAssertNil(cardsByCloudID["card-deleted"])
        XCTAssertEqual(cardsByCloudID["card-kept"]?.frontText, "New front")
        XCTAssertEqual(cardsByCloudID["card-kept"]?.isPinned, true)
        XCTAssertEqual(cardsByCloudID["card-new"]?.frontText, "Brand new")
    }

    @MainActor
    func testRemoteImportActorRequestsUploadWhenLocalDeckIsNewer() async throws {
        let uid = "user-1"
        let deckID = "deck-1"
        let remoteEditedAt = Date(timeIntervalSince1970: 3_000)
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let deck = DeckModel(title: "Local", colorHex: "#111111")
        deck.ownerUID = uid
        deck.cloudID = deckID
        deck.editedAt = remoteEditedAt.addingTimeInterval(60)
        context.insert(deck)
        try context.save()

        let actor = CloudSyncRemoteImportActor(
            container: container,
            outbox: CloudSyncOutbox(fileURL: try temporaryOutboxURL())
        )
        let snapshot = CloudSyncRemoteDeckSnapshot(
            header: CloudSyncRemoteDeckHeader(
                deckID: deckID,
                title: "Remote",
                colorHex: "#222222",
                createdAt: remoteEditedAt,
                editedAt: remoteEditedAt,
                lastOpenedAt: nil,
                lastAssignedCardNumber: nil,
                syncRevision: nil,
                isNotFullySynced: false,
                isDeleted: false
            ),
            cards: []
        )

        let result = try await actor.apply(snapshot, uid: uid)

        XCTAssertEqual(result, .enqueueLocalUpsert(deckID: deckID))

        let verificationContext = ModelContext(container)
        let decks = try verificationContext.fetch(FetchDescriptor<DeckModel>())
        XCTAssertEqual(decks.first?.title, "Local")
        XCTAssertEqual(decks.first?.colorHex, "#111111")
    }

    private func temporaryOutboxURL() throws -> URL {
        try TestFileSystemFactory.makeTemporaryDirectory(prefix: "CloudSyncImportTests")
            .appendingPathComponent("outbox.json", isDirectory: false)
    }
}
