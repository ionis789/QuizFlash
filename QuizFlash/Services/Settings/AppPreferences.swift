//
//  AppPreferences.swift
//  QuizFlash
//
//  App-wide lightweight preferences backed by UserDefaults.
//

import Foundation
import Observation

// MARK: - App Language Preference

/// Controls which UI language QuizFlash uses for app-owned chrome and system-localized text.
nonisolated enum AppLanguagePreference: String, CaseIterable, Identifiable, Codable, Sendable {
    case system
    case english
    case romanian
    case russian

    var id: String { rawValue }

    var localeIdentifier: String {
        switch self {
        case .system:
            return Locale.autoupdatingCurrent.identifier
        case .english:
            return "en"
        case .romanian:
            return "ro"
        case .russian:
            return "ru"
        }
    }

    var resolvedLocale: Locale {
        Locale(identifier: localeIdentifier)
    }

    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .system:
            return AppLocalization.string("System", locale: locale)
        case .english:
            return AppLocalization.string("English", locale: locale)
        case .romanian:
            return AppLocalization.string("Romanian", locale: locale)
        case .russian:
            return AppLocalization.string("Russian", locale: locale)
        }
    }
}

// MARK: - Week Start Preference

/// Controls which weekday anchors the Home calendar grid.
nonisolated enum AppWeekStartDayPreference: String, CaseIterable, Identifiable, Codable, Sendable {
    case system
    case monday
    case sunday

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "System Default"
        case .monday:
            return "Monday"
        case .sunday:
            return "Sunday"
        }
    }

    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .system:
            return AppLocalization.string("System Default", locale: locale)
        case .monday:
            return AppLocalization.string("Monday", locale: locale)
        case .sunday:
            return AppLocalization.string("Sunday", locale: locale)
        }
    }

    var resolvedCalendar: Calendar {
        var calendar = Calendar.autoupdatingCurrent
        switch self {
        case .system:
            break
        case .monday:
            calendar.firstWeekday = 2
        case .sunday:
            calendar.firstWeekday = 1
        }
        return calendar
    }
}

// MARK: - Create Deck Sort Preference

/// Persists the default presentation order for draft cards in Create Deck.
nonisolated enum CreateDeckSortOrder: String, CaseIterable, Identifiable, Codable, Sendable {
    case newest
    case oldest
    case type

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest:
            return "Newest First"
        case .oldest:
            return "Oldest First"
        case .type:
            return "Type"
        }
    }

    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .newest:
            return AppLocalization.string("Newest First", locale: locale)
        case .oldest:
            return AppLocalization.string("Oldest First", locale: locale)
        case .type:
            return AppLocalization.string("Type", locale: locale)
        }
    }
}

// MARK: - iPad Tab Bar Position

/// Persists how the floating tab bar is anchored on iPad layouts.
nonisolated enum AppPadTabBarPosition: String, CaseIterable, Identifiable, Codable, Sendable {
    case center
    case left
    case right

    var id: String { rawValue }

    var title: String {
        switch self {
        case .center:
            return "Center"
        case .left:
            return "Left"
        case .right:
            return "Right"
        }
    }

    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .center:
            return AppLocalization.string("Center", locale: locale)
        case .left:
            return AppLocalization.string("Left", locale: locale)
        case .right:
            return AppLocalization.string("Right", locale: locale)
        }
    }
}

// MARK: - App Preferences Store

/// Shared app preferences consumed by Home, Create Deck, and Settings surfaces.
@Observable
@MainActor
final class AppPreferences {
    static let shared = AppPreferences()
    nonisolated private static let languageUserDefaultsKey = "preferences.app.language"

    private enum Keys {
        static let language = "preferences.app.language"
        static let weekStartDay = "preferences.calendar.weekStartDay"
        static let createDeckSortOrder = "preferences.createDeck.sortOrder"
        static let padTabBarPosition = "preferences.navigation.padTabBarPosition"
    }

    private let userDefaults: UserDefaults

    nonisolated static var persistedAppLanguage: AppLanguagePreference {
        guard
            let rawValue = UserDefaults.standard.string(forKey: languageUserDefaultsKey),
            let preference = AppLanguagePreference(rawValue: rawValue)
        else {
            return .system
        }

        return preference
    }

    nonisolated static var persistedResolvedLocale: Locale {
        persistedAppLanguage.resolvedLocale
    }

    /// Preferred UI language for app-owned chrome.
    var appLanguage: AppLanguagePreference {
        didSet {
            userDefaults.set(appLanguage.rawValue, forKey: Keys.language)
            AppLocalization.applyLanguageOverride(appLanguage)
        }
    }

    /// Preferred first day of the week for calendar surfaces.
    var weekStartDay: AppWeekStartDayPreference {
        didSet {
            userDefaults.set(weekStartDay.rawValue, forKey: Keys.weekStartDay)
        }
    }

    /// Default sort applied when the Create Deck editor renders draft cards.
    var createDeckSortOrder: CreateDeckSortOrder {
        didSet {
            userDefaults.set(createDeckSortOrder.rawValue, forKey: Keys.createDeckSortOrder)
        }
    }

    /// Preferred iPad anchor position for the floating tab bar.
    var padTabBarPosition: AppPadTabBarPosition {
        didSet {
            userDefaults.set(
                padTabBarPosition.rawValue,
                forKey: Keys.padTabBarPosition
            )
        }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.appLanguage = AppLanguagePreference(
            rawValue: userDefaults.string(forKey: Keys.language) ?? ""
        ) ?? .system
        self.weekStartDay = AppWeekStartDayPreference(
            rawValue: userDefaults.string(forKey: Keys.weekStartDay) ?? ""
        ) ?? .system
        self.createDeckSortOrder = CreateDeckSortOrder(
            rawValue: userDefaults.string(forKey: Keys.createDeckSortOrder) ?? ""
        ) ?? .newest
        self.padTabBarPosition = AppPadTabBarPosition(
            rawValue: userDefaults.string(forKey: Keys.padTabBarPosition) ?? ""
        ) ?? .center
        AppLocalization.applyLanguageOverride(appLanguage)
    }

    /// Resolves the app's effective calendar based on the stored weekday preference.
    var resolvedCalendar: Calendar {
        var calendar = weekStartDay.resolvedCalendar
        calendar.locale = resolvedLocale
        return calendar
    }

    /// Resolved UI locale used by the root app environment and copy builders.
    var resolvedLocale: Locale {
        appLanguage.resolvedLocale
    }

    /// Stable refresh key used to rebuild language-sensitive view hierarchies.
    var languageRefreshKey: String {
        "language:\(appLanguage.rawValue):\(resolvedLocale.identifier)"
    }
}
