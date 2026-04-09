//
//  AppMigrationStoreTests.swift
//  QuizFlashTests
//
//  Covers one-time local migration flags backed by UserDefaults.
//

import XCTest
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
}
