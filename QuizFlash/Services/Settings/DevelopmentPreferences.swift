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

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.aiDebugTracingEnabled = userDefaults.object(
            forKey: Keys.aiDebugTracingEnabled
        ) as? Bool ?? AppFeatures.current.enablesAITraceTooling
        self.deckGridTextLayoutDebugEnabled = userDefaults.object(
            forKey: Keys.deckGridTextLayoutDebugEnabled
        ) as? Bool ?? false
    }
}
