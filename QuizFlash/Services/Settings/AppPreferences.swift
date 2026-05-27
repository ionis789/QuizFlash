//
//  AppPreferences.swift
//  QuizFlash
//
//  App-wide lightweight preferences backed by UserDefaults.
//

import Foundation
import Observation

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
}

// MARK: - App Preferences Store

/// Shared app preferences consumed by Home, Create Deck, and Settings surfaces.
@Observable
@MainActor
final class AppPreferences {
    static let shared = AppPreferences()

    private enum Keys {
        static let weekStartDay = "preferences.calendar.weekStartDay"
        static let createDeckSortOrder = "preferences.createDeck.sortOrder"
        static let autoCollapseEarlierCards = "preferences.createDeck.autoCollapseEarlierCards"
        static let padTabBarPosition = "preferences.navigation.padTabBarPosition"
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
        static let aiDebugTracingEnabled = AIDebugTracePreferenceKeys.debugTracingEnabled
    }

    private let userDefaults: UserDefaults

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

    /// Enables verbose AI generation/conversion tracing for developer debugging.
    var aiDebugTracingEnabled: Bool {
        didSet {
            userDefaults.set(
                aiDebugTracingEnabled,
                forKey: Keys.aiDebugTracingEnabled
            )
        }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
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
        self.aiDebugTracingEnabled = userDefaults.object(
            forKey: Keys.aiDebugTracingEnabled
        ) as? Bool ?? true
    }

    /// Resolves the app's effective calendar based on the stored weekday preference.
    var resolvedCalendar: Calendar {
        weekStartDay.resolvedCalendar
    }

    /// Resolved scale applied to Match mini card typography.
    var matchCardFontScale: CGFloat {
        switch matchCardFontSize {
        case .small:
            return 0.84
        case .standard:
            return 1.0
        case .large:
            return 1.12
        case .custom:
            return CGFloat(Self.clampedMatchCardFontSize(matchCustomCardFontSizePixels) / 22.0)
        }
    }

    private static func clampedMatchCardFontSize(_ value: Double) -> Double {
        min(max(value.rounded(), 14), 34)
    }
}
