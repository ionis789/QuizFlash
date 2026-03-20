//
//  StorageAndCleanupTests.swift
//  QuizFlashTests
//
//  Covers storage accounting and destructive cleanup flows.
//

import XCTest
import SwiftData
@testable import QuizFlash

    @MainActor
    final class StorageAndCleanupTests: XCTestCase {
        func testCalculateDeckStorageCountsTextAndEmbeddedImages() async throws {
            let context = try TestModelContainerFactory.makeContext()
            let deck = DeckModel(title: "Sized", icon: "tray", colorHex: "#FFFFFF")
            let imagePayload = Data(repeating: 7, count: 128)
            let front = ZoneModel.image(data: imagePayload)
            let back = ZoneModel.text("Answer")
            let card = CardModel(
                frontZone: front,
                backZone: back,
                cardNumber: 1
            )

            context.insert(deck)
            context.insert(card)
            deck.cards = [card]
            deck.cardCount = 1
            try context.save()

            let persistedDeck = try XCTUnwrap(context.model(for: deck.persistentModelID) as? DeckModel)
            let storage = await StorageManager.shared.calculateDeckStorage(persistedDeck)

            XCTAssertEqual(storage.cardCount, 1)
            XCTAssertEqual(storage.imageCount, 1)
            XCTAssertGreaterThan(storage.totalBytes, 128)
        }

    func testGarbageCollectorDeleteDeckRemovesDeckAndTracksFreedBytes() async throws {
        let context = try TestModelContainerFactory.makeContext()
        let deck = DeckModel(title: "Trash", icon: "trash", colorHex: "#000000")
        let imagePayload = Data(repeating: 5, count: 256)
        let card = CardModel(
            frontZone: .image(data: imagePayload),
            backZone: .image(data: imagePayload),
            cardNumber: 1
        )

        context.insert(deck)
        context.insert(card)
        deck.cards = [card]
        deck.cardCount = 1
        deck.lastAssignedCardNumber = 1
        try context.save()

        let collector = GarbageCollector.shared
        let previousBytesFreed = collector.bytesFreed

        try await collector.deleteDeck(deck, context: context)

        XCTAssertTrue(try context.fetchAll(DeckModel.self).isEmpty)
        XCTAssertTrue(try context.fetchAll(CardModel.self).isEmpty)
        XCTAssertGreaterThanOrEqual(collector.bytesFreed, previousBytesFreed + 512)
        XCTAssertNotNil(collector.lastCleanupDate)
        XCTAssertFalse(collector.isRunning)
    }
}
