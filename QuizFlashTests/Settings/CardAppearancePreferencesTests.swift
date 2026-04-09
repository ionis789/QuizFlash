//
//  CardAppearancePreferencesTests.swift
//  QuizFlashTests
//
//  Covers card appearance preferences backed by UserDefaults.
//

import XCTest
@testable import QuizFlash

@MainActor
final class CardAppearancePreferencesTests: XCTestCase {
    func testCardAppearancePreferencesPersistCardContentMode() {
        let suiteName = "CardAppearancePreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let preferences = CardAppearancePreferences(userDefaults: defaults)
        preferences.cardContentMode = .scrollable

        let reloadedPreferences = CardAppearancePreferences(userDefaults: defaults)
        XCTAssertEqual(reloadedPreferences.cardContentMode, .scrollable)
    }
}
