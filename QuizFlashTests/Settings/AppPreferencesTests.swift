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
        XCTAssertEqual(preferences.defaultZoneGroupAlignment, .center)
        XCTAssertEqual(preferences.defaultInnerZoneAlignment, .leading)
        preferences.weekStartDay = .monday
        preferences.createDeckSortOrder = .oldest
        preferences.defaultTextSize = FlashcardTextSize(step: 5)
        preferences.defaultZoneGroupAlignment = .trailing
        preferences.defaultInnerZoneAlignment = .center
        preferences.zoneSurfaceStyle = .rounded
        preferences.borderDesign = AppBorderDesignPreferences(
            preset: .bold,
            thickness: 0.9,
            depth: 0.8,
            hue: 0.2
        )

        let reloadedPreferences = AppPreferences(userDefaults: defaults)
        XCTAssertEqual(reloadedPreferences.weekStartDay, .monday)
        XCTAssertEqual(reloadedPreferences.createDeckSortOrder, .oldest)
        XCTAssertEqual(reloadedPreferences.defaultTextSize, FlashcardTextSize(step: 5))
        XCTAssertEqual(reloadedPreferences.defaultZoneGroupAlignment, .trailing)
        XCTAssertEqual(reloadedPreferences.defaultInnerZoneAlignment, .center)
        XCTAssertEqual(reloadedPreferences.zoneSurfaceStyle, .rounded)
        XCTAssertEqual(
            reloadedPreferences.borderDesign,
            AppBorderDesignPreferences(
                preset: .bold,
                thickness: 0.9,
                depth: 0.8,
                hue: 0.2
            )
        )
    }

    func testGlobalZoneAlignmentsNeverPersistInheritanceToken() {
        let suiteName = "AppPreferencesZoneAlignmentTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set("auto", forKey: "preferences.editor.defaultZoneGroupAlignment")
        defaults.set("auto", forKey: "preferences.editor.defaultInnerZoneAlignment")

        let preferences = AppPreferences(userDefaults: defaults)

        XCTAssertEqual(preferences.defaultZoneGroupAlignment, .center)
        XCTAssertEqual(preferences.defaultInnerZoneAlignment, .leading)
        XCTAssertEqual(
            defaults.string(forKey: "preferences.editor.defaultZoneGroupAlignment"),
            ZoneBlockAlignment.center.rawValue
        )
        XCTAssertEqual(
            defaults.string(forKey: "preferences.editor.defaultInnerZoneAlignment"),
            ZoneBlockAlignment.leading.rawValue
        )
    }

    func testLegacyZoneAlignmentMigratesToInnerZonesOnly() {
        let suiteName = "AppPreferencesLegacyZoneAlignmentTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set("trailing", forKey: "preferences.editor.defaultZoneAlignment")

        let preferences = AppPreferences(userDefaults: defaults)

        XCTAssertEqual(preferences.defaultZoneGroupAlignment, .center)
        XCTAssertEqual(preferences.defaultInnerZoneAlignment, .trailing)
    }

    func testDailyCardsGoalDefaultsToNilAndPersistsOptionalValue() {
        let suiteName = "AppPreferencesDailyCardsGoalTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let preferences = AppPreferences(userDefaults: defaults)
        XCTAssertNil(preferences.dailyCardsGoal)

        preferences.dailyCardsGoal = 55
        XCTAssertEqual(AppPreferences(userDefaults: defaults).dailyCardsGoal, 55)

        preferences.dailyCardsGoal = 700
        XCTAssertEqual(AppPreferences(userDefaults: defaults).dailyCardsGoal, 500)

        preferences.dailyCardsGoal = nil
        XCTAssertNil(AppPreferences(userDefaults: defaults).dailyCardsGoal)
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
