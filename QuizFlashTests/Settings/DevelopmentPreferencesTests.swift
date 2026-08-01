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
        preferences.setPartialSheetBackgroundHex("#221A2B")

        let reloadedPreferences = DevelopmentPreferences(userDefaults: defaults)
        XCTAssertTrue(reloadedPreferences.deckWorkspaceMockAIEnabled)
        XCTAssertTrue(reloadedPreferences.deckGridTextLayoutDebugEnabled)
        XCTAssertTrue(reloadedPreferences.zoneContentLayoutDebugEnabled)
        XCTAssertTrue(reloadedPreferences.playModeDeveloperModeEnabled)
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
}
