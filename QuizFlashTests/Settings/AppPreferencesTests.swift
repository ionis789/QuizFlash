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

    func testPreferencesPersistWeekStartSortOrderAndAutoCollapse() {
        let suiteName = "AppPreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let preferences = AppPreferences(userDefaults: defaults)
        preferences.weekStartDay = .monday
        preferences.createDeckSortOrder = .oldest
        preferences.autoCollapseEarlierCardsInAISession = false

        let reloadedPreferences = AppPreferences(userDefaults: defaults)
        XCTAssertEqual(reloadedPreferences.weekStartDay, .monday)
        XCTAssertEqual(reloadedPreferences.createDeckSortOrder, .oldest)
        XCTAssertFalse(reloadedPreferences.autoCollapseEarlierCardsInAISession)
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
