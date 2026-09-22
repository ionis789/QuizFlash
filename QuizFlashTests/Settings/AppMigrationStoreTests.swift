//
//  AppMigrationStoreTests.swift
//  QuizFlashTests
//
//  Covers one-time local migration flags backed by UserDefaults.
//

import XCTest
import SwiftData
@testable import QuizFlash

@MainActor
final class AppMigrationStoreTests: XCTestCase {
    func testLegacyCardCountCleanupRunsOnlyOnceAndPersistsCompletion() {
        let suiteName = "AppMigrationStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = AppMigrationStore(userDefaults: defaults)
        var invocationCount = 0

        store.runLegacyCardCountCleanupIfNeeded {
            invocationCount += 1
        }

        XCTAssertEqual(invocationCount, 1)
        XCTAssertTrue(store.didCompleteLegacyCardCountCleanup)

        let reloadedStore = AppMigrationStore(userDefaults: defaults)
        XCTAssertTrue(reloadedStore.didCompleteLegacyCardCountCleanup)

        reloadedStore.runLegacyCardCountCleanupIfNeeded {
            invocationCount += 1
        }

        XCTAssertEqual(invocationCount, 1)
    }

    func testLegacyCardCountCleanupRespectsPersistedShippedKey() {
        let suiteName = "AppMigrationStoreHydrationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(true, forKey: "didMigrateCardCount_v1")

        let store = AppMigrationStore(userDefaults: defaults)
        var invocationCount = 0

        store.runLegacyCardCountCleanupIfNeeded {
            invocationCount += 1
        }

        XCTAssertTrue(store.didCompleteLegacyCardCountCleanup)
        XCTAssertEqual(invocationCount, 0)
    }

    func testAccountIsolationCleanupDeletesUnownedRowsAndPreservesOwnedDecks() throws {
        let suiteName = "AccountIsolationCleanupTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let context = try TestModelContainerFactory.makeContext()

        let ownedDeck = DeckModel(title: "Owned", colorHex: "#111111")
        ownedDeck.ownerUID = "user-a"
        let ownedCard = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.flashcard(front: "Q", back: "A"),
            cardNumber: 1
        )
        ownedCard.deck = ownedDeck
        ownedDeck.cards = [ownedCard]
        let unownedDeck = DeckModel(title: "Unowned", colorHex: "#222222")
        context.insert(ownedDeck)
        context.insert(ownedCard)
        context.insert(unownedDeck)
        context.insert(UserProfile())
        try context.save()

        let store = AppMigrationStore(userDefaults: defaults)
        try store.runAccountIsolationCleanupIfNeeded(context: context)

        let decks = try context.fetch(FetchDescriptor<DeckModel>())
        XCTAssertEqual(decks.map(\.title), ["Owned"])
        XCTAssertEqual(ownedCard.ownerUID, "user-a")
        XCTAssertTrue(try context.fetch(FetchDescriptor<UserProfile>()).isEmpty)
        XCTAssertTrue(store.didCompleteAccountIsolationCleanup)
    }
}
