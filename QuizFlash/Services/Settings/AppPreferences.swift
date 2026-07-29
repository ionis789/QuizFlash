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

// MARK: - Zone Surface Style

/// Controls whether zones draw their rounded visual surface.
nonisolated enum AppZoneSurfaceStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case simple
    case rounded

    var id: String { rawValue }

    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .simple:
            return AppLocalization.string("Simple", locale: locale)
        case .rounded:
            return AppLocalization.string("Rounded", locale: locale)
        }
    }

    var showsZoneSurfaces: Bool {
        self == .rounded
    }
}

// MARK: - Border Design

/// High-level border presets tuned by the global border design controls.
nonisolated enum AppBorderStylePreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case minimal
    case soft
    case defined
    case bold

    var id: String { rawValue }

    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .minimal:
            return AppLocalization.string("Minimal", locale: locale)
        case .soft:
            return AppLocalization.string("Soft", locale: locale)
        case .defined:
            return AppLocalization.string("Defined", locale: locale)
        case .bold:
            return AppLocalization.string("Strong", locale: locale)
        }
    }

    var lineScale: Double {
        switch self {
        case .minimal:
            return 0.62
        case .soft:
            return 0.84
        case .defined:
            return 1
        case .bold:
            return 1.22
        }
    }

    var opacityScale: Double {
        switch self {
        case .minimal:
            return 0.58
        case .soft:
            return 0.76
        case .defined:
            return 1
        case .bold:
            return 1.12
        }
    }
}

/// Stores the app-wide border tuning used by shared surfaces and Home cards.
nonisolated struct AppBorderDesignPreferences: Codable, Equatable, Sendable {
    static let defaultValue = AppBorderDesignPreferences(
        preset: .defined,
        thickness: 0.52,
        depth: 0.72,
        hue: 0.70
    )
    static let valueRange: ClosedRange<Double> = 0...1

    var preset: AppBorderStylePreset
    var thickness: Double
    var depth: Double
    var hue: Double

    init(
        preset: AppBorderStylePreset,
        thickness: Double,
        depth: Double,
        hue: Double
    ) {
        self.preset = preset
        self.thickness = Self.clamped(thickness)
        self.depth = Self.clamped(depth)
        self.hue = Self.clamped(hue)
    }

    var normalized: AppBorderDesignPreferences {
        AppBorderDesignPreferences(
            preset: preset,
            thickness: thickness,
            depth: depth,
            hue: hue
        )
    }

    func updating(_ update: (inout AppBorderDesignPreferences) -> Void) -> AppBorderDesignPreferences {
        var copy = self
        update(&copy)
        return copy.normalized
    }

    private static func clamped(_ value: Double) -> Double {
        min(max(value, valueRange.lowerBound), valueRange.upperBound)
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
        static let dailyCardsGoal = "preferences.home.dailyCardsGoal"
        static let createDeckSortOrder = "preferences.createDeck.sortOrder"
        static let padTabBarPosition = "preferences.navigation.padTabBarPosition"
        static let defaultTextSize = "preferences.editor.defaultTextSize"
        static let defaultTextSizeScaleVersion = "preferences.editor.defaultTextSizeScaleVersion"
        static let zoneSurfaceStyle = "preferences.editor.zoneSurfaceStyle"
        static let borderDesign = "preferences.design.borderDesign"
    }

    static let defaultDailyCardsGoal = 50
    static let dailyCardsGoalRange = 1...500
    static let dailyCardsGoalStep = 5

    private static let currentTextSizeScaleVersion = 3

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

    /// Optional Home cards target. `nil` disables goal-specific Home UI.
    var dailyCardsGoal: Int? {
        didSet {
            guard let dailyCardsGoal else {
                userDefaults.removeObject(forKey: Keys.dailyCardsGoal)
                return
            }

            let clampedGoal = Self.clampedDailyCardsGoal(dailyCardsGoal)
            if clampedGoal != dailyCardsGoal {
                self.dailyCardsGoal = clampedGoal
            } else {
                userDefaults.set(clampedGoal, forKey: Keys.dailyCardsGoal)
            }
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

    /// Default card text size used by editors and play modes before a deck overrides it.
    var defaultTextSize: FlashcardTextSize {
        didSet {
            userDefaults.set(defaultTextSize.rawValue, forKey: Keys.defaultTextSize)
            userDefaults.set(Self.currentTextSizeScaleVersion, forKey: Keys.defaultTextSizeScaleVersion)
        }
    }

    /// Visual style used by all zone renderers across editors, previews, and play modes.
    var zoneSurfaceStyle: AppZoneSurfaceStyle {
        didSet {
            userDefaults.set(zoneSurfaceStyle.rawValue, forKey: Keys.zoneSurfaceStyle)
        }
    }

    /// Global border tuning shared by app cards, widgets, controls, and Home surfaces.
    var borderDesign: AppBorderDesignPreferences {
        didSet {
            persistBorderDesign(borderDesign.normalized)
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
        if let storedGoal = userDefaults.object(forKey: Keys.dailyCardsGoal) as? Int {
            self.dailyCardsGoal = Self.clampedDailyCardsGoal(storedGoal)
        } else {
            self.dailyCardsGoal = nil
        }
        self.createDeckSortOrder = CreateDeckSortOrder(
            rawValue: userDefaults.string(forKey: Keys.createDeckSortOrder) ?? ""
        ) ?? .newest
        self.padTabBarPosition = AppPadTabBarPosition(
            rawValue: userDefaults.string(forKey: Keys.padTabBarPosition) ?? ""
        ) ?? .center
        self.defaultTextSize = Self.resolvedDefaultTextSize(from: userDefaults)
        self.zoneSurfaceStyle = AppZoneSurfaceStyle(
            rawValue: userDefaults.string(forKey: Keys.zoneSurfaceStyle) ?? ""
        ) ?? .simple
        self.borderDesign = Self.resolvedBorderDesign(from: userDefaults)
        userDefaults.set(defaultTextSize.rawValue, forKey: Keys.defaultTextSize)
        userDefaults.set(Self.currentTextSizeScaleVersion, forKey: Keys.defaultTextSizeScaleVersion)
        AppLocalization.applyLanguageOverride(appLanguage)
    }

    private static func clampedDailyCardsGoal(_ value: Int) -> Int {
        min(max(value, dailyCardsGoalRange.lowerBound), dailyCardsGoalRange.upperBound)
    }

    private static func resolvedDefaultTextSize(from userDefaults: UserDefaults) -> FlashcardTextSize {
        guard let storedStep = userDefaults.object(forKey: Keys.defaultTextSize) as? Int else {
            return .large
        }

        let scaleVersion = userDefaults.integer(forKey: Keys.defaultTextSizeScaleVersion)
        if scaleVersion < currentTextSizeScaleVersion {
            return FlashcardTextSize.migratedLegacyStep(storedStep)
        }

        return FlashcardTextSize(step: storedStep)
    }

    private static func resolvedBorderDesign(from userDefaults: UserDefaults) -> AppBorderDesignPreferences {
        guard
            let data = userDefaults.data(forKey: Keys.borderDesign),
            let decoded = try? JSONDecoder().decode(AppBorderDesignPreferences.self, from: data)
        else {
            return .defaultValue
        }

        return decoded.normalized
    }

    private func persistBorderDesign(_ borderDesign: AppBorderDesignPreferences) {
        guard let data = try? JSONEncoder().encode(borderDesign) else { return }
        userDefaults.set(data, forKey: Keys.borderDesign)
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
