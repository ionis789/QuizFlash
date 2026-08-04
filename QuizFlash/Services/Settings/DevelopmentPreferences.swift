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
        static let partialSheetBackgroundHex = "preferences.development.partialSheetBackgroundHex"
        static let deckWorkspaceMockAIEnabled = "preferences.development.deckWorkspaceMockAIEnabled"
        static let deckGridTextLayoutDebugEnabled = "preferences.development.deckGridTextLayoutDebugEnabled"
        static let zoneContentLayoutDebugEnabled = "preferences.development.zoneContentLayoutDebugEnabled"
        static let zoneEditorDebugHUDEnabled = "preferences.development.zoneEditorDebugHUDEnabled"
        static let quizEditorDebugEnabled = "preferences.development.quizEditorDebugEnabled"
        static let playModeDeveloperModeEnabled = "preferences.development.playModeDeveloperModeEnabled"
        static let edgeShadowTuningEnabled = "preferences.development.edgeShadowTuningEnabled"
        static let edgeShadowDebugSettingsByScreen = "preferences.development.edgeShadowDebugSettingsByScreen"
        static let edgeShadowDebugDefaultsVersion = "preferences.development.edgeShadowDebugDefaultsVersion"
    }

    private static let currentEdgeShadowDebugDefaultsVersion = 2
    static let defaultPartialSheetBackgroundHex = "#18131F"

    private let userDefaults: UserDefaults
    @ObservationIgnored private var edgeShadowDebugSettingsPersistenceTask: Task<Void, Never>?

    /// Dedicated development color used only by non-full-screen custom sheets.
    private(set) var partialSheetBackgroundHex: String {
        didSet {
            userDefaults.set(partialSheetBackgroundHex, forKey: Keys.partialSheetBackgroundHex)
        }
    }

    /// Shows the mock AI generation shortcut in the deck workspace.
    var deckWorkspaceMockAIEnabled: Bool {
        didSet {
            userDefaults.set(
                deckWorkspaceMockAIEnabled,
                forKey: Keys.deckWorkspaceMockAIEnabled
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

    /// Shows the zone content text-block guides used during layout tuning.
    var zoneContentLayoutDebugEnabled: Bool {
        didSet {
            userDefaults.set(
                zoneContentLayoutDebugEnabled,
                forKey: Keys.zoneContentLayoutDebugEnabled
            )
        }
    }

    /// Shows the live zone editor diagnostics HUD on top of the authoring card.
    var zoneEditorDebugHUDEnabled: Bool {
        didSet {
            userDefaults.set(
                zoneEditorDebugHUDEnabled,
                forKey: Keys.zoneEditorDebugHUDEnabled
            )
        }
    }

    /// Shows quiz editor scroll and caret diagnostics.
    var quizEditorDebugEnabled: Bool {
        didSet {
            userDefaults.set(
                quizEditorDebugEnabled,
                forKey: Keys.quizEditorDebugEnabled
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
            scheduleEdgeShadowDebugSettingsPersistence()
        }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
#if DEBUG
        self.partialSheetBackgroundHex = userDefaults.string(
            forKey: Keys.partialSheetBackgroundHex
        ) ?? Self.defaultPartialSheetBackgroundHex
        self.deckWorkspaceMockAIEnabled = userDefaults.object(
            forKey: Keys.deckWorkspaceMockAIEnabled
        ) as? Bool ?? false
        self.deckGridTextLayoutDebugEnabled = userDefaults.object(
            forKey: Keys.deckGridTextLayoutDebugEnabled
        ) as? Bool ?? false
        self.zoneContentLayoutDebugEnabled = userDefaults.object(
            forKey: Keys.zoneContentLayoutDebugEnabled
        ) as? Bool ?? false
        self.zoneEditorDebugHUDEnabled = userDefaults.object(
            forKey: Keys.zoneEditorDebugHUDEnabled
        ) as? Bool ?? false
        self.quizEditorDebugEnabled = userDefaults.object(
            forKey: Keys.quizEditorDebugEnabled
        ) as? Bool ?? false
        self.playModeDeveloperModeEnabled = userDefaults.object(
            forKey: Keys.playModeDeveloperModeEnabled
        ) as? Bool ?? false
        self.edgeShadowTuningEnabled = userDefaults.object(
            forKey: Keys.edgeShadowTuningEnabled
        ) as? Bool ?? false
        Self.migrateEdgeShadowDebugDefaultsIfNeeded(in: userDefaults)
        self.edgeShadowDebugSettingsByScreen = Self.loadEdgeShadowDebugSettings(from: userDefaults)
#else
        self.partialSheetBackgroundHex = Self.defaultPartialSheetBackgroundHex
        self.deckWorkspaceMockAIEnabled = false
        self.deckGridTextLayoutDebugEnabled = false
        self.zoneContentLayoutDebugEnabled = false
        self.zoneEditorDebugHUDEnabled = false
        self.quizEditorDebugEnabled = false
        self.playModeDeveloperModeEnabled = false
        self.edgeShadowTuningEnabled = false
        self.edgeShadowDebugSettingsByScreen = [:]
#endif
    }

    func setPartialSheetBackgroundHex(_ hex: String) {
        guard Self.isValidHexColor(hex) else { return }
        partialSheetBackgroundHex = hex.uppercased()
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

    private func scheduleEdgeShadowDebugSettingsPersistence() {
        let settingsByScreen = edgeShadowDebugSettingsByScreen
        edgeShadowDebugSettingsPersistenceTask?.cancel()
        edgeShadowDebugSettingsPersistenceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            persistEdgeShadowDebugSettings(settingsByScreen)
        }
    }

    private func persistEdgeShadowDebugSettings(
        _ settingsByScreen: [String: EdgeShadowDebugSettings]
    ) {
        if settingsByScreen.isEmpty {
            userDefaults.removeObject(forKey: Keys.edgeShadowDebugSettingsByScreen)
            return
        }

        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(settingsByScreen) else { return }
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

    private static func migrateEdgeShadowDebugDefaultsIfNeeded(
        in userDefaults: UserDefaults
    ) {
        let storedVersion = userDefaults.integer(forKey: Keys.edgeShadowDebugDefaultsVersion)
        guard storedVersion < currentEdgeShadowDebugDefaultsVersion else { return }

        userDefaults.removeObject(forKey: Keys.edgeShadowDebugSettingsByScreen)
        userDefaults.set(
            currentEdgeShadowDebugDefaultsVersion,
            forKey: Keys.edgeShadowDebugDefaultsVersion
        )
    }

    private static func isValidHexColor(_ hex: String) -> Bool {
        let normalized = hex.replacingOccurrences(of: "#", with: "")
        guard normalized.count == 6 || normalized.count == 8 else { return false }
        return CharacterSet(charactersIn: normalized)
            .isSubset(of: CharacterSet(charactersIn: "0123456789ABCDEFabcdef"))
    }

}
