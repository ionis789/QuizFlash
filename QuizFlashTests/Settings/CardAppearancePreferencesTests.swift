//
//  EditorAppearancePreferencesTests.swift
//  QuizFlashTests
//
//  Covers editor appearance preferences backed by UserDefaults.
//

import XCTest
@testable import QuizFlash

@MainActor
final class EditorAppearancePreferencesTests: XCTestCase {
    func testEditorAppearancePreferencesPersistZoneSurfaceStyle() {
        let suiteName = "EditorAppearancePreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let preferences = AppPreferences(userDefaults: defaults)
        preferences.zoneSurfaceStyle = .rounded

        let reloadedPreferences = AppPreferences(userDefaults: defaults)
        XCTAssertEqual(reloadedPreferences.zoneSurfaceStyle, .rounded)
    }
}
