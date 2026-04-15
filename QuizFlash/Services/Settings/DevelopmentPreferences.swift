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
        static let edgeShadowTuningEnabled = "preferences.development.edgeShadowTuningEnabled"
        static let edgeShadowDebugSettingsByScreen = "preferences.development.edgeShadowDebugSettingsByScreen"
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

    /// Shows per-screen floating controls used to tune edge-shadow overlays.
    var edgeShadowTuningEnabled: Bool {
        didSet {
            userDefaults.set(
                edgeShadowTuningEnabled,
                forKey: Keys.edgeShadowTuningEnabled
            )
        }
    }

    private var edgeShadowDebugSettingsByScreen: [String: EdgeShadowDebugSettings] {
        didSet {
            persistEdgeShadowDebugSettings()
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
        self.edgeShadowTuningEnabled = userDefaults.object(
            forKey: Keys.edgeShadowTuningEnabled
        ) as? Bool ?? false
        self.edgeShadowDebugSettingsByScreen = Self.loadEdgeShadowDebugSettings(from: userDefaults)
    }

    func edgeShadowSettings(for screenID: String) -> EdgeShadowDebugSettings {
        edgeShadowDebugSettingsByScreen[screenID] ?? .default
    }

    func setEdgeShadowSettings(_ settings: EdgeShadowDebugSettings, for screenID: String) {
        if settings == .default {
            edgeShadowDebugSettingsByScreen.removeValue(forKey: screenID)
        } else {
            edgeShadowDebugSettingsByScreen[screenID] = settings
        }
    }

    func resetEdgeShadowSettings(for screenID: String) {
        edgeShadowDebugSettingsByScreen.removeValue(forKey: screenID)
    }

    private func persistEdgeShadowDebugSettings() {
        if edgeShadowDebugSettingsByScreen.isEmpty {
            userDefaults.removeObject(forKey: Keys.edgeShadowDebugSettingsByScreen)
            return
        }

        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(edgeShadowDebugSettingsByScreen) else { return }
        userDefaults.set(data, forKey: Keys.edgeShadowDebugSettingsByScreen)
    }

    private static func loadEdgeShadowDebugSettings(
        from userDefaults: UserDefaults
    ) -> [String: EdgeShadowDebugSettings] {
        guard let data = userDefaults.data(forKey: Keys.edgeShadowDebugSettingsByScreen) else {
            return [:]
        }

        let decoder = JSONDecoder()
        return (try? decoder.decode([String: EdgeShadowDebugSettings].self, from: data)) ?? [:]
    }
}
