//
//  DevelopmentPreferencesTests.swift
//  QuizFlashTests
//
//  Covers developer-only preferences backed by UserDefaults.
//

import XCTest
@testable import QuizFlash

@MainActor
final class DevelopmentPreferencesTests: XCTestCase {
    func testDevelopmentPreferencesPersistDebugToggles() {
        let suiteName = "DevelopmentPreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let preferences = DevelopmentPreferences(userDefaults: defaults)
        preferences.deckWorkspaceMockAIEnabled = true
        preferences.deckGridTextLayoutDebugEnabled = true
        preferences.zoneContentLayoutDebugEnabled = true
        preferences.playModeDeveloperModeEnabled = true
        preferences.libraryStickyHeaderDebugEnabled = true
        preferences.windowTouchProbeEnabled = true
        preferences.fullScreenSheetDiagnosticsEnabled = true
        preferences.authFlowDiagnosticsEnabled = true
        preferences.customContextMenuLoggingEnabled = true
        preferences.backendTraceEnabled = true
        preferences.aiGenerationTraceEnabled = true
        preferences.pdfImportTraceEnabled = true
        preferences.zoneEditorRuntimeTraceEnabled = true
        preferences.homeLayoutTraceEnabled = true
        preferences.setPartialSheetBackgroundHex("#221A2B")

        let reloadedPreferences = DevelopmentPreferences(userDefaults: defaults)
        XCTAssertTrue(reloadedPreferences.deckWorkspaceMockAIEnabled)
        XCTAssertTrue(reloadedPreferences.deckGridTextLayoutDebugEnabled)
        XCTAssertTrue(reloadedPreferences.zoneContentLayoutDebugEnabled)
        XCTAssertTrue(reloadedPreferences.playModeDeveloperModeEnabled)
        XCTAssertTrue(reloadedPreferences.libraryStickyHeaderDebugEnabled)
        XCTAssertTrue(reloadedPreferences.windowTouchProbeEnabled)
        XCTAssertTrue(reloadedPreferences.fullScreenSheetDiagnosticsEnabled)
        XCTAssertTrue(reloadedPreferences.authFlowDiagnosticsEnabled)
        XCTAssertTrue(reloadedPreferences.customContextMenuLoggingEnabled)
        XCTAssertTrue(reloadedPreferences.backendTraceEnabled)
        XCTAssertTrue(reloadedPreferences.aiGenerationTraceEnabled)
        XCTAssertTrue(reloadedPreferences.pdfImportTraceEnabled)
        XCTAssertTrue(reloadedPreferences.zoneEditorRuntimeTraceEnabled)
        XCTAssertTrue(reloadedPreferences.homeLayoutTraceEnabled)
        XCTAssertEqual(reloadedPreferences.partialSheetBackgroundHex, "#221A2B")
    }

    func testDevelopmentPreferencesHydrateFromPersistedKeys() {
        let suiteName = "DevelopmentPreferencesHydrationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(true, forKey: "preferences.development.deckWorkspaceMockAIEnabled")
        defaults.set(true, forKey: "preferences.development.deckGridTextLayoutDebugEnabled")
        defaults.set(true, forKey: "preferences.development.zoneContentLayoutDebugEnabled")
        defaults.set(true, forKey: "preferences.development.playModeDeveloperModeEnabled")

        let preferences = DevelopmentPreferences(userDefaults: defaults)

        XCTAssertTrue(preferences.deckWorkspaceMockAIEnabled)
        XCTAssertTrue(preferences.deckGridTextLayoutDebugEnabled)
        XCTAssertTrue(preferences.zoneContentLayoutDebugEnabled)
        XCTAssertTrue(preferences.playModeDeveloperModeEnabled)
    }

    func testDiagnosticsDefaultOffAndCanBeDisabledTogether() {
        let suiteName = "DevelopmentPreferencesDisableTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let preferences = DevelopmentPreferences(userDefaults: defaults)
        XCTAssertFalse(preferences.authFlowDiagnosticsEnabled)
        XCTAssertFalse(preferences.backendTraceEnabled)
        XCTAssertFalse(preferences.windowTouchProbeEnabled)
        XCTAssertFalse(preferences.zoneEditorRuntimeTraceEnabled)

        preferences.authFlowDiagnosticsEnabled = true
        preferences.backendTraceEnabled = true
        preferences.windowTouchProbeEnabled = true
        preferences.zoneEditorRuntimeTraceEnabled = true
        preferences.homeLayoutTraceEnabled = true
        preferences.disableAllDiagnostics()

        XCTAssertFalse(preferences.authFlowDiagnosticsEnabled)
        XCTAssertFalse(preferences.backendTraceEnabled)
        XCTAssertFalse(preferences.windowTouchProbeEnabled)
        XCTAssertFalse(preferences.zoneEditorRuntimeTraceEnabled)
        XCTAssertFalse(preferences.homeLayoutTraceEnabled)
    }
}
