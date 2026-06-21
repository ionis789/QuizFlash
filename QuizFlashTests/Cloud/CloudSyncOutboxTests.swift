//
//  CloudSyncOutboxTests.swift
//  QuizFlashTests
//

import Foundation
import XCTest
@testable import QuizFlash

@MainActor
final class CloudSyncOutboxTests: XCTestCase {
    func testLatestOperationForDeckReplacesEarlierOperation() async throws {
        let fileURL = try makeOutboxFileURL()
        let outbox = CloudSyncOutbox(fileURL: fileURL)

        try await outbox.enqueue(ownerUID: "user-a", deckID: "deck-1", kind: .upsertDeck)
        try await outbox.enqueue(ownerUID: "user-a", deckID: "deck-1", kind: .deleteDeck)

        let operations = try await outbox.operations(for: "user-a")
        let containsDelete = try await outbox.containsDelete(ownerUID: "user-a", deckID: "deck-1")

        XCTAssertEqual(operations.count, 1)
        XCTAssertEqual(operations.first?.kind, .deleteDeck)
        XCTAssertTrue(containsDelete)
    }

    func testReloadKeepsOperationsSeparatedByUser() async throws {
        let fileURL = try makeOutboxFileURL()
        let firstOutbox = CloudSyncOutbox(fileURL: fileURL)
        try await firstOutbox.enqueue(ownerUID: "user-a", deckID: "deck-a", kind: .upsertDeck)
        try await firstOutbox.enqueue(ownerUID: "user-b", deckID: "deck-b", kind: .upsertDeck)

        let reloadedOutbox = CloudSyncOutbox(fileURL: fileURL)
        let userAOperations = try await reloadedOutbox.operations(for: "user-a")
        let userBOperations = try await reloadedOutbox.operations(for: "user-b")

        XCTAssertEqual(userAOperations.map(\.deckID), ["deck-a"])
        XCTAssertEqual(userBOperations.map(\.deckID), ["deck-b"])
    }

    func testRemovingCompletedOperationLeavesOtherDeckWorkQueued() async throws {
        let fileURL = try makeOutboxFileURL()
        let outbox = CloudSyncOutbox(fileURL: fileURL)
        try await outbox.enqueue(ownerUID: "user-a", deckID: "deck-1", kind: .upsertDeck)
        try await outbox.enqueue(ownerUID: "user-a", deckID: "deck-2", kind: .upsertDeck)

        let queuedOperations = try await outbox.operations(for: "user-a")
        let firstOperation = try XCTUnwrap(queuedOperations.first)
        try await outbox.remove(firstOperation)
        let remainingOperations = try await outbox.operations(for: "user-a")

        XCTAssertEqual(remainingOperations.map(\.deckID), ["deck-2"])
    }

    private func makeOutboxFileURL() throws -> URL {
        let directoryURL = try TestFileSystemFactory.makeTemporaryDirectory(prefix: "CloudSyncOutboxTests")
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        return directoryURL.appendingPathComponent("outbox.json")
    }
}
