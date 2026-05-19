//
//  AppPreferences.swift
//  QuizFlash
//
//  App-wide lightweight preferences backed by UserDefaults.
//

import Foundation
import Observation
import SwiftUI

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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest:
            return "Newest First"
        case .oldest:
            return "Oldest First"
        }
    }

    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .newest:
            return AppLocalization.string("Newest First", locale: locale)
        case .oldest:
            return AppLocalization.string("Oldest First", locale: locale)
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

// MARK: - Study Session Progress Style

/// Controls how prominently study-session progress is rendered in supported play modes.
nonisolated enum AppStudySessionProgressStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case prominent
    case compact
    case hidden

    var id: String { rawValue }

    var title: String {
        switch self {
        case .prominent:
            return "Prominent"
        case .compact:
            return "Compact"
        case .hidden:
            return "Hidden"
        }
    }

    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .prominent:
            return AppLocalization.string("Prominent", locale: locale)
        case .compact:
            return AppLocalization.string("Compact", locale: locale)
        case .hidden:
            return AppLocalization.string("Hidden", locale: locale)
        }
    }
}

// MARK: - Study Haptics Preference

/// Controls how strongly supported play modes use haptics for feedback.
nonisolated enum AppStudyHapticsPreference: String, CaseIterable, Identifiable, Codable, Sendable {
    case off
    case subtle
    case standard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:
            return "Off"
        case .subtle:
            return "Subtle"
        case .standard:
            return "Standard"
        }
    }

    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .off:
            return AppLocalization.string("Off", locale: locale)
        case .subtle:
            return AppLocalization.string("Subtle", locale: locale)
        case .standard:
            return AppLocalization.string("Standard", locale: locale)
        }
    }
}

// MARK: - Match Card Font Size

/// Controls how large Match board cards render their mini preview content.
nonisolated enum AppMatchCardFontSizePreference: String, CaseIterable, Identifiable, Codable, Sendable {
    case small
    case standard
    case large
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small:
            return "Small"
        case .standard:
            return "Standard"
        case .large:
            return "Large"
        case .custom:
            return "Custom"
        }
    }

    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .small:
            return AppLocalization.string("Small", locale: locale)
        case .standard:
            return AppLocalization.string("Standard", locale: locale)
        case .large:
            return AppLocalization.string("Large", locale: locale)
        case .custom:
            return AppLocalization.string("Custom", locale: locale)
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
        static let autoCollapseEarlierCards = "preferences.createDeck.autoCollapseEarlierCards"
        static let padTabBarPosition = "preferences.navigation.padTabBarPosition"
        static let usesSystemTextSize = "preferences.text.usesSystemTextSize"
        static let appInterfaceTextScale = "preferences.text.appInterfaceScale"
        static let cardContentTextScale = "preferences.text.cardContentScale"
        static let flashcardsProgressStyle = "preferences.playMode.flashcards.progressStyle"
        static let flashcardsSwipeHaptics = "preferences.playMode.flashcards.swipeHaptics"
        static let flashcardsKeepsScreenAwake = "preferences.playMode.flashcards.keepsScreenAwake"
        static let quizAutoAdvanceCorrectAnswers = "preferences.playMode.quiz.autoAdvanceCorrectAnswers"
        static let quizShowsQuestionProgress = "preferences.playMode.quiz.showsQuestionProgress"
        static let quizUsesLargeChoiceButtons = "preferences.playMode.quiz.usesLargeChoiceButtons"
        static let matchShowsRoundCountdown = "preferences.playMode.match.showsRoundCountdown"
        static let matchHapticsPreference = "preferences.playMode.match.hapticsPreference"
        static let matchCardFontSize = "preferences.playMode.match.cardFontSize"
        static let matchCustomCardFontSizePixels = "preferences.playMode.match.customCardFontSizePixels"
        static let matchUsesReducedMotion = "preferences.playMode.match.usesReducedMotion"
        static let writeAutoFocusesAnswerField = "preferences.playMode.write.autoFocusesAnswerField"
        static let writeKeepsKeyboardVisibleBetweenPrompts = "preferences.playMode.write.keepsKeyboardVisibleBetweenPrompts"
        static let writeShowsAnswerLengthHint = "preferences.playMode.write.showsAnswerLengthHint"
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

    /// When enabled, AI sessions start with historical cards collapsed by default.
    var autoCollapseEarlierCardsInAISession: Bool {
        didSet {
            userDefaults.set(
                autoCollapseEarlierCardsInAISession,
                forKey: Keys.autoCollapseEarlierCards
            )
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

    /// When enabled, app chrome follows the device Dynamic Type setting.
    var usesSystemTextSize: Bool {
        didSet {
            userDefaults.set(
                usesSystemTextSize,
                forKey: Keys.usesSystemTextSize
            )
        }
    }

    /// Preferred scale for app-owned interface text when system text size is not used.
    var appInterfaceTextScale: Double {
        didSet {
            let clamped = Self.clampedAppInterfaceTextScale(appInterfaceTextScale)
            if abs(clamped - appInterfaceTextScale) > .ulpOfOne {
                appInterfaceTextScale = clamped
                return
            }

            userDefaults.set(
                clamped,
                forKey: Keys.appInterfaceTextScale
            )
        }
    }

    /// Preferred global scale for authored card content in editors and play modes.
    var cardContentTextScale: Double {
        didSet {
            let clamped = Self.clampedCardContentTextScale(cardContentTextScale)
            if abs(clamped - cardContentTextScale) > .ulpOfOne {
                cardContentTextScale = clamped
                return
            }

            userDefaults.set(
                clamped,
                forKey: Keys.cardContentTextScale
            )
        }
    }

    /// Preferred progress treatment for flashcard sessions.
    var flashcardsProgressStyle: AppStudySessionProgressStyle {
        didSet {
            userDefaults.set(
                flashcardsProgressStyle.rawValue,
                forKey: Keys.flashcardsProgressStyle
            )
        }
    }

    /// Preferred haptics level for flashcard swipe feedback.
    var flashcardsSwipeHaptics: AppStudyHapticsPreference {
        didSet {
            userDefaults.set(
                flashcardsSwipeHaptics.rawValue,
                forKey: Keys.flashcardsSwipeHaptics
            )
        }
    }

    /// Keeps the screen awake during flashcard review sessions when supported.
    var flashcardsKeepsScreenAwake: Bool {
        didSet {
            userDefaults.set(
                flashcardsKeepsScreenAwake,
                forKey: Keys.flashcardsKeepsScreenAwake
            )
        }
    }

    /// Advances to the next quiz question automatically after a correct answer when supported.
    var quizAutoAdvanceCorrectAnswers: Bool {
        didSet {
            userDefaults.set(
                quizAutoAdvanceCorrectAnswers,
                forKey: Keys.quizAutoAdvanceCorrectAnswers
            )
        }
    }

    /// Shows quiz progress chrome during supported quiz sessions.
    var quizShowsQuestionProgress: Bool {
        didSet {
            userDefaults.set(
                quizShowsQuestionProgress,
                forKey: Keys.quizShowsQuestionProgress
            )
        }
    }

    /// Prefers larger answer targets in quiz sessions when supported.
    var quizUsesLargeChoiceButtons: Bool {
        didSet {
            userDefaults.set(
                quizUsesLargeChoiceButtons,
                forKey: Keys.quizUsesLargeChoiceButtons
            )
        }
    }

    /// Shows a short countdown before each match round when supported.
    var matchShowsRoundCountdown: Bool {
        didSet {
            userDefaults.set(
                matchShowsRoundCountdown,
                forKey: Keys.matchShowsRoundCountdown
            )
        }
    }

    /// Preferred haptics level for match interactions.
    var matchHapticsPreference: AppStudyHapticsPreference {
        didSet {
            userDefaults.set(
                matchHapticsPreference.rawValue,
                forKey: Keys.matchHapticsPreference
            )
        }
    }

    /// Preferred text scale for Match board cards.
    var matchCardFontSize: AppMatchCardFontSizePreference {
        didSet {
            userDefaults.set(
                matchCardFontSize.rawValue,
                forKey: Keys.matchCardFontSize
            )
        }
    }

    /// Custom body-sized font in pixels used when Match card font size is set to Custom.
    var matchCustomCardFontSizePixels: Double {
        didSet {
            let clamped = Self.clampedMatchCardFontSize(matchCustomCardFontSizePixels)
            if abs(clamped - matchCustomCardFontSizePixels) > .ulpOfOne {
                matchCustomCardFontSizePixels = clamped
                return
            }

            userDefaults.set(
                clamped,
                forKey: Keys.matchCustomCardFontSizePixels
            )
        }
    }

    /// Reduces board motion in match mode when supported.
    var matchUsesReducedMotion: Bool {
        didSet {
            userDefaults.set(
                matchUsesReducedMotion,
                forKey: Keys.matchUsesReducedMotion
            )
        }
    }

    /// Focuses the answer field automatically in write sessions when supported.
    var writeAutoFocusesAnswerField: Bool {
        didSet {
            userDefaults.set(
                writeAutoFocusesAnswerField,
                forKey: Keys.writeAutoFocusesAnswerField
            )
        }
    }

    /// Keeps the keyboard visible between write prompts when supported.
    var writeKeepsKeyboardVisibleBetweenPrompts: Bool {
        didSet {
            userDefaults.set(
                writeKeepsKeyboardVisibleBetweenPrompts,
                forKey: Keys.writeKeepsKeyboardVisibleBetweenPrompts
            )
        }
    }

    /// Shows answer-length hints in write mode when supported.
    var writeShowsAnswerLengthHint: Bool {
        didSet {
            userDefaults.set(
                writeShowsAnswerLengthHint,
                forKey: Keys.writeShowsAnswerLengthHint
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
        self.autoCollapseEarlierCardsInAISession = userDefaults.object(
            forKey: Keys.autoCollapseEarlierCards
        ) as? Bool ?? true
        self.padTabBarPosition = AppPadTabBarPosition(
            rawValue: userDefaults.string(forKey: Keys.padTabBarPosition) ?? ""
        ) ?? .center
        self.usesSystemTextSize = userDefaults.object(
            forKey: Keys.usesSystemTextSize
        ) as? Bool ?? true
        self.appInterfaceTextScale = Self.clampedAppInterfaceTextScale(
            userDefaults.object(forKey: Keys.appInterfaceTextScale) as? Double ?? 1
        )
        self.cardContentTextScale = Self.clampedCardContentTextScale(
            userDefaults.object(forKey: Keys.cardContentTextScale) as? Double ?? 1
        )
        self.flashcardsProgressStyle = AppStudySessionProgressStyle(
            rawValue: userDefaults.string(forKey: Keys.flashcardsProgressStyle) ?? ""
        ) ?? .prominent
        self.flashcardsSwipeHaptics = AppStudyHapticsPreference(
            rawValue: userDefaults.string(forKey: Keys.flashcardsSwipeHaptics) ?? ""
        ) ?? .standard
        self.flashcardsKeepsScreenAwake = userDefaults.object(
            forKey: Keys.flashcardsKeepsScreenAwake
        ) as? Bool ?? true
        self.quizAutoAdvanceCorrectAnswers = userDefaults.object(
            forKey: Keys.quizAutoAdvanceCorrectAnswers
        ) as? Bool ?? false
        self.quizShowsQuestionProgress = userDefaults.object(
            forKey: Keys.quizShowsQuestionProgress
        ) as? Bool ?? true
        self.quizUsesLargeChoiceButtons = userDefaults.object(
            forKey: Keys.quizUsesLargeChoiceButtons
        ) as? Bool ?? false
        self.matchShowsRoundCountdown = userDefaults.object(
            forKey: Keys.matchShowsRoundCountdown
        ) as? Bool ?? true
        self.matchHapticsPreference = AppStudyHapticsPreference(
            rawValue: userDefaults.string(forKey: Keys.matchHapticsPreference) ?? ""
        ) ?? .standard
        self.matchCardFontSize = AppMatchCardFontSizePreference(
            rawValue: userDefaults.string(forKey: Keys.matchCardFontSize) ?? ""
        ) ?? .standard
        self.matchCustomCardFontSizePixels = Self.clampedMatchCardFontSize(
            userDefaults.object(forKey: Keys.matchCustomCardFontSizePixels) as? Double ?? 22
        )
        self.matchUsesReducedMotion = userDefaults.object(
            forKey: Keys.matchUsesReducedMotion
        ) as? Bool ?? false
        self.writeAutoFocusesAnswerField = userDefaults.object(
            forKey: Keys.writeAutoFocusesAnswerField
        ) as? Bool ?? true
        self.writeKeepsKeyboardVisibleBetweenPrompts = userDefaults.object(
            forKey: Keys.writeKeepsKeyboardVisibleBetweenPrompts
        ) as? Bool ?? true
        self.writeShowsAnswerLengthHint = userDefaults.object(
            forKey: Keys.writeShowsAnswerLengthHint
        ) as? Bool ?? true
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

    /// Dynamic Type bucket used by the app chrome when a custom text size is selected.
    var appInterfaceDynamicTypeSize: DynamicTypeSize {
        Self.dynamicTypeSize(for: appInterfaceTextScale)
    }

    /// Stable multiplier for authored card content.
    var cardContentFontScale: CGFloat {
        CGFloat(Self.clampedCardContentTextScale(cardContentTextScale))
    }

    /// Resolved scale applied to Match mini card typography.
    var matchCardFontScale: CGFloat {
        let matchScale: Double
        switch matchCardFontSize {
        case .small:
            matchScale = 0.84
        case .standard:
            matchScale = 1.0
        case .large:
            matchScale = 1.12
        case .custom:
            matchScale = Self.clampedMatchCardFontSize(matchCustomCardFontSizePixels) / 22.0
        }

        return CGFloat(matchScale * Self.clampedCardContentTextScale(cardContentTextScale))
    }

    private static func clampedMatchCardFontSize(_ value: Double) -> Double {
        min(max(value.rounded(), 14), 34)
    }

    private static func clampedAppInterfaceTextScale(_ value: Double) -> Double {
        min(max((value / 0.05).rounded() * 0.05, 0.85), 1.30)
    }

    private static func clampedCardContentTextScale(_ value: Double) -> Double {
        min(max((value / 0.05).rounded() * 0.05, 0.75), 1.40)
    }

    private static func dynamicTypeSize(for scale: Double) -> DynamicTypeSize {
        switch clampedAppInterfaceTextScale(scale) {
        case ..<0.90:
            return .small
        case ..<0.98:
            return .medium
        case ..<1.08:
            return .large
        case ..<1.18:
            return .xLarge
        case ..<1.26:
            return .xxLarge
        default:
            return .xxxLarge
        }
    }
}
