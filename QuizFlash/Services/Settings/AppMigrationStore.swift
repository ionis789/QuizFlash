//
//  AppMigrationStore.swift
//  QuizFlash
//
//  One-time local migration flags backed by UserDefaults.
//

import Foundation
import Observation

/// Tracks small local migration flags that should only run once per install.
@Observable
@MainActor
final class AppMigrationStore {
    static let shared = AppMigrationStore()

    private enum Keys {
        // Preserve the shipped key so existing installs do not re-run this cleanup.
        static let legacyCardCountCleanupCompleted = "didMigrateCardCount_v1"
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

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.didCompleteLegacyCardCountCleanup = userDefaults.object(
            forKey: Keys.legacyCardCountCleanupCompleted
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
}
