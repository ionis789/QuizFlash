//
//  DevelopmentPreferences.swift
//  QuizFlash
//
//  Developer-only preferences backed by UserDefaults.
//

import Foundation
import Observation

#if QUIZFLASH_DEVELOPMENT
/// Thread-safe lookup used by diagnostic code that cannot depend on the main-actor settings model.
nonisolated enum DevelopmentDiagnosticPreference {
    enum Key {
        static let libraryStickyHeader = "preferences.development.libraryStickyHeaderDebugEnabled"
        static let windowTouchProbe = "preferences.development.windowTouchProbeEnabled"
        static let fullScreenSheet = "preferences.development.fullScreenSheetDiagnosticsEnabled"
        static let authFlow = "preferences.development.authFlowDiagnosticsEnabled"
        static let customContextMenu = "preferences.development.customContextMenuLoggingEnabled"
        static let backendTrace = "preferences.development.backendTraceEnabled"
        static let aiGenerationTrace = "preferences.development.aiGenerationTraceEnabled"
        static let pdfImportTrace = "preferences.development.pdfImportTraceEnabled"
        static let zoneEditorRuntimeTrace = "preferences.development.zoneEditorRuntimeTraceEnabled"
        static let homeLayoutTrace = "preferences.development.homeLayoutTraceEnabled"
    }

    static func isEnabled(_ key: String, userDefaults: UserDefaults = .standard) -> Bool {
        userDefaults.bool(forKey: key)
    }
}

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
        static let libraryHeaderLayoutDebugEnabled = "preferences.development.libraryHeaderLayoutDebugEnabled"
        static let libraryStickyHeaderDebugEnabled = DevelopmentDiagnosticPreference.Key.libraryStickyHeader
        static let windowTouchProbeEnabled = DevelopmentDiagnosticPreference.Key.windowTouchProbe
        static let fullScreenSheetDiagnosticsEnabled = DevelopmentDiagnosticPreference.Key.fullScreenSheet
        static let authFlowDiagnosticsEnabled = DevelopmentDiagnosticPreference.Key.authFlow
        static let customContextMenuLoggingEnabled = DevelopmentDiagnosticPreference.Key.customContextMenu
        static let backendTraceEnabled = DevelopmentDiagnosticPreference.Key.backendTrace
        static let aiGenerationTraceEnabled = DevelopmentDiagnosticPreference.Key.aiGenerationTrace
        static let pdfImportTraceEnabled = DevelopmentDiagnosticPreference.Key.pdfImportTrace
        static let zoneEditorRuntimeTraceEnabled = DevelopmentDiagnosticPreference.Key.zoneEditorRuntimeTrace
        static let homeLayoutTraceEnabled = DevelopmentDiagnosticPreference.Key.homeLayoutTrace
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

    /// Shows the copyable Library header layout diagnostics control.
    var libraryHeaderLayoutDebugEnabled: Bool {
        didSet {
            userDefaults.set(
                libraryHeaderLayoutDebugEnabled,
                forKey: Keys.libraryHeaderLayoutDebugEnabled
            )
        }
    }

    /// Logs the sticky Library section-header handoff and pinning geometry.
    var libraryStickyHeaderDebugEnabled: Bool {
        didSet {
            userDefaults.set(
                libraryStickyHeaderDebugEnabled,
                forKey: Keys.libraryStickyHeaderDebugEnabled
            )
        }
    }

    /// Installs the global passthrough touch probe used for delivery investigations.
    var windowTouchProbeEnabled: Bool {
        didSet {
            userDefaults.set(windowTouchProbeEnabled, forKey: Keys.windowTouchProbeEnabled)
        }
    }

    /// Records bounded custom-sheet lifecycle and touch diagnostics.
    var fullScreenSheetDiagnosticsEnabled: Bool {
        didSet {
            userDefaults.set(
                fullScreenSheetDiagnosticsEnabled,
                forKey: Keys.fullScreenSheetDiagnosticsEnabled
            )
        }
    }

    /// Records authentication and authenticated-root handoff diagnostics.
    var authFlowDiagnosticsEnabled: Bool {
        didSet {
            userDefaults.set(authFlowDiagnosticsEnabled, forKey: Keys.authFlowDiagnosticsEnabled)
        }
    }

    /// Emits the custom context-menu interaction timeline.
    var customContextMenuLoggingEnabled: Bool {
        didSet {
            userDefaults.set(
                customContextMenuLoggingEnabled,
                forKey: Keys.customContextMenuLoggingEnabled
            )
        }
    }

    /// Records Firebase, subscription, and backend communication events.
    var backendTraceEnabled: Bool {
        didSet {
            userDefaults.set(backendTraceEnabled, forKey: Keys.backendTraceEnabled)
        }
    }

    /// Records structured AI generation runs and payload metadata.
    var aiGenerationTraceEnabled: Bool {
        didSet {
            userDefaults.set(aiGenerationTraceEnabled, forKey: Keys.aiGenerationTraceEnabled)
        }
    }

    /// Records PDF picker, copy, and extraction stages.
    var pdfImportTraceEnabled: Bool {
        didSet {
            userDefaults.set(pdfImportTraceEnabled, forKey: Keys.pdfImportTraceEnabled)
        }
    }

    /// Records the bounded editor focus, keyboard, scroll, and layout timeline.
    var zoneEditorRuntimeTraceEnabled: Bool {
        didSet {
            userDefaults.set(
                zoneEditorRuntimeTraceEnabled,
                forKey: Keys.zoneEditorRuntimeTraceEnabled
            )
        }
    }

    /// Logs adaptive Home layout decisions when geometry changes.
    var homeLayoutTraceEnabled: Bool {
        didSet {
            userDefaults.set(homeLayoutTraceEnabled, forKey: Keys.homeLayoutTraceEnabled)
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
        self.libraryHeaderLayoutDebugEnabled = userDefaults.object(
            forKey: Keys.libraryHeaderLayoutDebugEnabled
        ) as? Bool ?? false
        self.libraryStickyHeaderDebugEnabled = userDefaults.object(
            forKey: Keys.libraryStickyHeaderDebugEnabled
        ) as? Bool ?? false
        self.windowTouchProbeEnabled = userDefaults.object(
            forKey: Keys.windowTouchProbeEnabled
        ) as? Bool ?? false
        self.fullScreenSheetDiagnosticsEnabled = userDefaults.object(
            forKey: Keys.fullScreenSheetDiagnosticsEnabled
        ) as? Bool ?? false
        self.authFlowDiagnosticsEnabled = userDefaults.object(
            forKey: Keys.authFlowDiagnosticsEnabled
        ) as? Bool ?? false
        self.customContextMenuLoggingEnabled = userDefaults.object(
            forKey: Keys.customContextMenuLoggingEnabled
        ) as? Bool ?? false
        self.backendTraceEnabled = userDefaults.object(
            forKey: Keys.backendTraceEnabled
        ) as? Bool ?? false
        self.aiGenerationTraceEnabled = userDefaults.object(
            forKey: Keys.aiGenerationTraceEnabled
        ) as? Bool ?? false
        self.pdfImportTraceEnabled = userDefaults.object(
            forKey: Keys.pdfImportTraceEnabled
        ) as? Bool ?? false
        self.zoneEditorRuntimeTraceEnabled = userDefaults.object(
            forKey: Keys.zoneEditorRuntimeTraceEnabled
        ) as? Bool ?? false
        self.homeLayoutTraceEnabled = userDefaults.object(
            forKey: Keys.homeLayoutTraceEnabled
        ) as? Bool ?? false
        self.edgeShadowTuningEnabled = userDefaults.object(
            forKey: Keys.edgeShadowTuningEnabled
        ) as? Bool ?? false
        Self.migrateEdgeShadowDebugDefaultsIfNeeded(in: userDefaults)
        self.edgeShadowDebugSettingsByScreen = Self.loadEdgeShadowDebugSettings(from: userDefaults)
    }

    /// Turns every runtime diagnostic off without changing saved tuner values.
    func disableAllDiagnostics() {
        deckWorkspaceMockAIEnabled = false
        deckGridTextLayoutDebugEnabled = false
        zoneContentLayoutDebugEnabled = false
        zoneEditorDebugHUDEnabled = false
        quizEditorDebugEnabled = false
        playModeDeveloperModeEnabled = false
        libraryHeaderLayoutDebugEnabled = false
        libraryStickyHeaderDebugEnabled = false
        windowTouchProbeEnabled = false
        fullScreenSheetDiagnosticsEnabled = false
        authFlowDiagnosticsEnabled = false
        customContextMenuLoggingEnabled = false
        backendTraceEnabled = false
        aiGenerationTraceEnabled = false
        pdfImportTraceEnabled = false
        zoneEditorRuntimeTraceEnabled = false
        homeLayoutTraceEnabled = false
        edgeShadowTuningEnabled = false
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
#endif
