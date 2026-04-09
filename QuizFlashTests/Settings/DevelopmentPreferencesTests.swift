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
        preferences.deckGridTextLayoutDebugEnabled = true

        let reloadedPreferences = DevelopmentPreferences(userDefaults: defaults)
        XCTAssertFalse(reloadedPreferences.aiDebugTracingEnabled)
        XCTAssertTrue(reloadedPreferences.deckGridTextLayoutDebugEnabled)
    }

    func testDevelopmentPreferencesHydrateFromPersistedKeys() {
        let suiteName = "DevelopmentPreferencesHydrationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(false, forKey: AIDebugTracePreferenceKeys.debugTracingEnabled)
        defaults.set(true, forKey: "preferences.development.deckGridTextLayoutDebugEnabled")

        let preferences = DevelopmentPreferences(userDefaults: defaults)

        XCTAssertFalse(preferences.aiDebugTracingEnabled)
        XCTAssertTrue(preferences.deckGridTextLayoutDebugEnabled)
    }
}
