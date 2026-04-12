//
//  DevelopmentPreferences.swift
//  QuizFlash
//
//  Developer-only preferences backed by UserDefaults.
//

import Foundation
import Observation

/// Shared developer preferences consumed by labs, diagnostics, and debug overlays.
@Observable
@MainActor
final class DevelopmentPreferences {
    static let shared = DevelopmentPreferences()

    private enum Keys {
        static let aiDebugTracingEnabled = AIDebugTracePreferenceKeys.debugTracingEnabled
        static let deckGridTextLayoutDebugEnabled = "preferences.development.deckGridTextLayoutDebugEnabled"
        static let playModeDeveloperModeEnabled = "preferences.development.playModeDeveloperModeEnabled"
    }

    private let userDefaults: UserDefaults

    /// Enables verbose AI generation and conversion tracing for development builds.
    var aiDebugTracingEnabled: Bool {
        didSet {
            userDefaults.set(
                aiDebugTracingEnabled,
                forKey: Keys.aiDebugTracingEnabled
            )
        }
    }

    /// Shows the MiniCardPreview measurement guides used during deck-grid tuning.
    var deckGridTextLayoutDebugEnabled: Bool {
        didSet {
            userDefaults.set(
                deckGridTextLayoutDebugEnabled,
                forKey: Keys.deckGridTextLayoutDebugEnabled
            )
        }
    }

    /// Enables temporary play-mode developer controls and experiments.
    var playModeDeveloperModeEnabled: Bool {
        didSet {
            userDefaults.set(
                playModeDeveloperModeEnabled,
                forKey: Keys.playModeDeveloperModeEnabled
            )
        }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.aiDebugTracingEnabled = userDefaults.object(
            forKey: Keys.aiDebugTracingEnabled
        ) as? Bool ?? AppFeatures.current.enablesAITraceTooling
        self.deckGridTextLayoutDebugEnabled = userDefaults.object(
            forKey: Keys.deckGridTextLayoutDebugEnabled
        ) as? Bool ?? false
        self.playModeDeveloperModeEnabled = userDefaults.object(
            forKey: Keys.playModeDeveloperModeEnabled
        ) as? Bool ?? false
    }
}
