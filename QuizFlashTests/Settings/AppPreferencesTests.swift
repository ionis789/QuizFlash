//
//  AppPreferencesTests.swift
//  QuizFlashTests
//
//  Covers app-wide lightweight preferences backed by UserDefaults.
//

import XCTest
@testable import QuizFlash

@MainActor
final class AppPreferencesTests: XCTestCase {
    func testResolvedCalendarUsesMondayWhenRequested() {
        XCTAssertEqual(AppWeekStartDayPreference.monday.resolvedCalendar.firstWeekday, 2)
        XCTAssertEqual(AppWeekStartDayPreference.sunday.resolvedCalendar.firstWeekday, 1)
    }

    func testPreferencesPersistWeekStartSortOrderAndEditorDefaults() {
        let suiteName = "AppPreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let preferences = AppPreferences(userDefaults: defaults)
        preferences.weekStartDay = .monday
        preferences.createDeckSortOrder = .oldest
        preferences.defaultTextSize = FlashcardTextSize(step: 8)
        preferences.zoneSurfaceStyle = .rounded

        let reloadedPreferences = AppPreferences(userDefaults: defaults)
        XCTAssertEqual(reloadedPreferences.weekStartDay, .monday)
        XCTAssertEqual(reloadedPreferences.createDeckSortOrder, .oldest)
        XCTAssertEqual(reloadedPreferences.defaultTextSize, FlashcardTextSize(step: 8))
        XCTAssertEqual(reloadedPreferences.zoneSurfaceStyle, .rounded)
    }

    func testAppLanguagePreferenceDrivesAppLocalizationHelper() {
        let suiteName = "AppPreferencesLanguageTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        defer {
            AppLocalization.applyLanguageOverride(AppPreferences.shared.appLanguage)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let preferences = AppPreferences(userDefaults: defaults)
        preferences.appLanguage = .romanian

        XCTAssertEqual(
            AppLocalization.string("Home", locale: preferences.resolvedLocale),
            "Acasă"
        )

        preferences.appLanguage = .russian

        XCTAssertEqual(
            AppLocalization.string("Settings", locale: preferences.resolvedLocale),
            "Настройки"
        )
    }
}
