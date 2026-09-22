//
//  AppMigrationStore.swift
//  QuizFlash
//
//  One-time local migration flags backed by UserDefaults.
//

import Foundation
import Observation
import SwiftData

/// Tracks small local migration flags that should only run once per install.
@Observable
@MainActor
final class AppMigrationStore {
    static let shared = AppMigrationStore()

    private enum Keys {
        // Preserve the shipped key so existing installs do not re-run this cleanup.
        static let legacyCardCountCleanupCompleted = "didMigrateCardCount_v1"
        static let homeAnalyticsBackfillCompleted = "didBackfillHomeAnalytics_v1"
        static let accountIsolationCleanupCompleted = "didCleanUnownedAccountData_v2"
        static let accountAnalyticsBackfillUIDs = "didBackfillAccountAnalyticsUIDs_v1"
    }

    private let userDefaults: UserDefaults

    /// Marks whether the legacy card-count cleanup has already been applied.
    private(set) var didCompleteLegacyCardCountCleanup: Bool {
        didSet {
            userDefaults.set(
                didCompleteLegacyCardCountCleanup,
                forKey: Keys.legacyCardCountCleanupCompleted
            )
        }
    }

    /// Marks whether the one-time Home analytics aggregate rebuild has finished.
    private(set) var didCompleteHomeAnalyticsBackfill: Bool {
        didSet {
            userDefaults.set(
                didCompleteHomeAnalyticsBackfill,
                forKey: Keys.homeAnalyticsBackfillCompleted
            )
        }
    }

    private(set) var didCompleteAccountIsolationCleanup: Bool {
        didSet {
            userDefaults.set(
                didCompleteAccountIsolationCleanup,
                forKey: Keys.accountIsolationCleanupCompleted
            )
        }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.didCompleteLegacyCardCountCleanup = userDefaults.object(
            forKey: Keys.legacyCardCountCleanupCompleted
        ) as? Bool ?? false
        self.didCompleteHomeAnalyticsBackfill = userDefaults.object(
            forKey: Keys.homeAnalyticsBackfillCompleted
        ) as? Bool ?? false
        self.didCompleteAccountIsolationCleanup = userDefaults.object(
            forKey: Keys.accountIsolationCleanupCompleted
        ) as? Bool ?? false
    }

    /// Runs the legacy card-count cleanup once and persists completion when successful.
    func runLegacyCardCountCleanupIfNeeded(
        _ operation: () throws -> Void
    ) rethrows {
        guard !didCompleteLegacyCardCountCleanup else { return }
        try operation()
        didCompleteLegacyCardCountCleanup = true
    }

    /// Runs the one-time Home analytics backfill once and persists completion when successful.
    func runHomeAnalyticsBackfillIfNeeded(
        ownerUID: String,
        _ operation: () async throws -> Void
    ) async rethrows {
        var completedUIDs = Set(userDefaults.stringArray(forKey: Keys.accountAnalyticsBackfillUIDs) ?? [])
        guard !completedUIDs.contains(ownerUID) else { return }
        try await operation()
        completedUIDs.insert(ownerUID)
        userDefaults.set(Array(completedUIDs), forKey: Keys.accountAnalyticsBackfillUIDs)
    }

    /// Removes rows whose account cannot be determined and normalizes descendants
    /// from their already-owned parent before account-scoped queries are released.
    func runAccountIsolationCleanupIfNeeded(context: ModelContext) throws {
        guard !didCompleteAccountIsolationCleanup else { return }

        for card in try context.fetch(FetchDescriptor<CardModel>()) where card.ownerUID == nil {
            if let ownerUID = card.deck?.ownerUID {
                card.ownerUID = ownerUID
                if card.cloudID == nil { card.cloudID = UUID().uuidString }
            } else {
                context.delete(card)
            }
        }

        for event in try context.fetch(FetchDescriptor<ReviewEvent>()) where event.ownerUID == nil {
            if let ownerUID = event.card?.ownerUID {
                event.ownerUID = ownerUID
                if event.cloudID == nil { event.cloudID = UUID().uuidString }
            } else {
                context.delete(event)
            }
        }

        for deck in try context.fetch(FetchDescriptor<DeckModel>()) where deck.ownerUID == nil {
            context.delete(deck)
        }
        for folder in try context.fetch(FetchDescriptor<FolderModel>()) where folder.ownerUID == nil {
            context.delete(folder)
        }
        for profile in try context.fetch(FetchDescriptor<UserProfile>()) where profile.ownerUID == nil {
            context.delete(profile)
        }
        for log in try context.fetch(FetchDescriptor<DailyActivityLog>()) where log.ownerUID == nil {
            context.delete(log)
        }
        for aggregate in try context.fetch(FetchDescriptor<HomeDailyCardAggregate>()) where aggregate.ownerUID == nil {
            context.delete(aggregate)
        }
        for aggregate in try context.fetch(FetchDescriptor<HomeDailyDeckAggregate>()) where aggregate.ownerUID == nil {
            context.delete(aggregate)
        }
        for aggregate in try context.fetch(FetchDescriptor<HomeDailyStudyAggregate>()) where aggregate.ownerUID == nil {
            context.delete(aggregate)
        }

        try context.save()
        didCompleteAccountIsolationCleanup = true
    }
}
