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
        preferences.aiDebugTracingEnabled = false
        preferences.deckWorkspaceMockAIEnabled = true
        preferences.deckGridTextLayoutDebugEnabled = true
        preferences.zoneContentLayoutDebugEnabled = true
        preferences.playModeDeveloperModeEnabled = true

        let reloadedPreferences = DevelopmentPreferences(userDefaults: defaults)
        XCTAssertFalse(reloadedPreferences.aiDebugTracingEnabled)
        XCTAssertTrue(reloadedPreferences.deckWorkspaceMockAIEnabled)
        XCTAssertTrue(reloadedPreferences.deckGridTextLayoutDebugEnabled)
        XCTAssertTrue(reloadedPreferences.zoneContentLayoutDebugEnabled)
        XCTAssertTrue(reloadedPreferences.playModeDeveloperModeEnabled)
    }

    func testDevelopmentPreferencesHydrateFromPersistedKeys() {
        let suiteName = "DevelopmentPreferencesHydrationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(false, forKey: AIDebugTracePreferenceKeys.debugTracingEnabled)
        defaults.set(true, forKey: "preferences.development.deckWorkspaceMockAIEnabled")
        defaults.set(true, forKey: "preferences.development.deckGridTextLayoutDebugEnabled")
        defaults.set(true, forKey: "preferences.development.zoneContentLayoutDebugEnabled")
        defaults.set(true, forKey: "preferences.development.playModeDeveloperModeEnabled")

        let preferences = DevelopmentPreferences(userDefaults: defaults)

        XCTAssertFalse(preferences.aiDebugTracingEnabled)
        XCTAssertTrue(preferences.deckWorkspaceMockAIEnabled)
        XCTAssertTrue(preferences.deckGridTextLayoutDebugEnabled)
        XCTAssertTrue(preferences.zoneContentLayoutDebugEnabled)
        XCTAssertTrue(preferences.playModeDeveloperModeEnabled)
    }
}
