// HomeDashboardSnapshot.swift
// QuizFlash
//
// Lightweight Home snapshot and summary payloads extracted from HomeViewModel.

import Foundation
import SwiftData

/// Selected-day analytics shown in the top Home dashboard summary.
struct HomeSelectedDayOverviewSummary: Equatable {
    let selectedDate: Date
    let selectedDateLabel: String
    let cardsReviewed: Int
    let rawReviewCount: Int
    let dailyGoal: Int?
    let goalCompletionFraction: Double
    let remainingCardsToGoal: Int
    let xpEarnedToday: Int
    let newCardsLearned: Int
    let correctCardCount: Int
    let retryCardCount: Int
    let streakCount: Int
    let totalXP: Int
    let headline: String
    let detailLine: String

    /// `true` when the selected day reached or exceeded its target workload.
    var didReachGoal: Bool {
        guard let dailyGoal else { return false }
        return cardsReviewed >= dailyGoal
    }

    var hasGoal: Bool {
        dailyGoal != nil
    }

    var goodRatePercent: Int {
        let outcomeCount = correctCardCount + retryCardCount
        guard outcomeCount > 0 else { return 0 }
        return Int((Double(correctCardCount) / Double(outcomeCount) * 100).rounded())
    }
}

/// Final outcome for one unique card reviewed on one Home dashboard day.
struct HomeWeeklyReviewedCardSummary: Identifiable, Equatable, @unchecked Sendable {
    let id: String
    let cardID: PersistentIdentifier?
    let deckID: PersistentIdentifier?
    let deckTitle: String
    let deckColorHex: String
    let title: String
    let finalDifficulty: ReviewDifficulty
    let reviewCount: Int
    let lastReviewedAt: Date

    /// `true` when the card finished the day in a correct/successful state.
    nonisolated var wasCorrectAtEndOfDay: Bool {
        finalDifficulty != .again
    }
}

/// Deck-scoped breakdown for one Home weekly chart day.
struct HomeWeeklyDeckActivitySummary: Identifiable, Equatable, @unchecked Sendable {
    let id: String
    let deckID: PersistentIdentifier?
    let title: String
    let colorHex: String
    let uniqueCardCount: Int
    let correctCardCount: Int
    let retryCardCount: Int
    let cards: [HomeWeeklyReviewedCardSummary]
}

/// Seven-day momentum rollup that lets Home render weekly trend cards cheaply.
struct HomeWeeklyDaySummary: Identifiable, Equatable, Sendable {
    let id: String
    let date: Date
    let shortWeekday: String
    /// Unique cards covered on this day. Repeated reviews of the same card count once.
    let cardsReviewed: Int
    let rawReviewCount: Int
    let xpEarned: Int
    let dailyGoal: Int?
    let correctCardCount: Int
    let retryCardCount: Int
    let intensityFraction: Double
    let didStudy: Bool
    let didReachGoal: Bool
    let isSelectedDay: Bool

    var hasGoal: Bool {
        dailyGoal != nil
    }

    var goodRatePercent: Int {
        let outcomeCount = correctCardCount + retryCardCount
        guard outcomeCount > 0 else { return 0 }
        return Int((Double(correctCardCount) / Double(outcomeCount) * 100).rounded())
    }
}

/// Seven-day momentum rollup that lets Home render weekly trend cards cheaply.
struct HomeWeeklyMomentumSummary: Equatable, Sendable {
    let totalCardsReviewed: Int
    let totalXPEarned: Int
    let activeDays: Int
    let goalHitDays: Int
    let averageCardsPerActiveDay: Int
    let averageXPPerActiveDay: Int
    let consistencyFraction: Double
    let bestDayLabel: String?
    let headline: String
    let detailLine: String
    let daySummaries: [HomeWeeklyDaySummary]
}

/// Directional trend used by the Home calendar-week performance card.
enum HomePastWeekPerformanceTrend: String, Equatable, Sendable {
    case improving
    case steady
    case slipping
}

/// One compact day column inside the Home calendar-week performance comparison.
struct HomePastWeekPerformanceDaySummary: Identifiable, Equatable, Sendable {
    let id: String
    let date: Date
    let shortWeekday: String
    let cardsReviewed: Int
    let rawReviewCount: Int
    let landedCount: Int
    let retryCount: Int
    let dailyGoal: Int?
    /// One-day quality score derived only from clean finishes and goal coverage.
    let scorePercent: Int
    let visualLevel: Int
    let didStudy: Bool
    let didReachGoal: Bool

    var hasGoal: Bool {
        dailyGoal != nil
    }

    var goodRatePercent: Int {
        let outcomeCount = landedCount + retryCount
        guard outcomeCount > 0 else { return 0 }
        return Int((Double(landedCount) / Double(outcomeCount) * 100).rounded())
    }
}

/// Accuracy-first performance index for the selected calendar week on Home.
struct HomePastWeekPerformanceSummary: Equatable, Sendable {
    let weekStartDate: Date
    let windowEndDate: Date
    let scorePercent: Int
    let previousScorePercent: Int
    let deltaPercent: Int
    let trend: HomePastWeekPerformanceTrend
    let trendLine: String
    let accuracyPercent: Int
    let consistencyPercent: Int
    let goalCoveragePercent: Int
    let efficiencyPercent: Int
    let activeDays: Int
    /// Number of days included in the score. Future days in the selected week stay blank and do not penalize the score.
    let scoredDayCount: Int
    let goalHitDays: Int
    let bestDayLabel: String?
    /// 7-day score for the checkpoint ending on `bestDayLabel`.
    let bestDayScorePercent: Int?
    /// One-day quality score for `bestDayLabel`.
    let bestDayDailyQualityPercent: Int?
    let weakestDayLabel: String?
    /// 7-day score for the checkpoint ending on `weakestDayLabel`.
    let weakestDayScorePercent: Int?
    /// One-day quality score for `weakestDayLabel`.
    let weakestDayDailyQualityPercent: Int?
    let currentDaySummaries: [HomePastWeekPerformanceDaySummary]
    let previousDaySummaries: [HomePastWeekPerformanceDaySummary]

    var hasActivity: Bool {
        activeDays > 0
    }

    var hasGoal: Bool {
        currentDaySummaries.contains(where: \.hasGoal)
    }

    var goodRatePercent: Int {
        accuracyPercent
    }

    nonisolated static func placeholder(referenceDate: Date = Date()) -> HomePastWeekPerformanceSummary {
        HomePastWeekPerformanceSummary(
            weekStartDate: referenceDate,
            windowEndDate: referenceDate,
            scorePercent: 0,
            previousScorePercent: 0,
            deltaPercent: 0,
            trend: .steady,
            trendLine: "Needs attention",
            accuracyPercent: 0,
            consistencyPercent: 0,
            goalCoveragePercent: 0,
            efficiencyPercent: 0,
            activeDays: 0,
            scoredDayCount: 1,
            goalHitDays: 0,
            bestDayLabel: nil,
            bestDayScorePercent: nil,
            bestDayDailyQualityPercent: nil,
            weakestDayLabel: nil,
            weakestDayScorePercent: nil,
            weakestDayDailyQualityPercent: nil,
            currentDaySummaries: [],
            previousDaySummaries: []
        )
    }
}

/// Dedicated selected-day breakdown payload rendered below the weekly chart.
struct HomeSelectedDayBreakdownSummary: Equatable, Sendable {
    let selectedDate: Date
    let cardsReviewed: Int
    let rawReviewCount: Int
    let correctCardCount: Int
    let retryCardCount: Int
    let headline: String
    let detailLine: String
    let deckSummaries: [HomeWeeklyDeckActivitySummary]
}

/// Lightweight insight payload for one Home calendar day cell.
struct HomeCalendarDayInsight: Equatable {
    let date: Date
    let dateString: String
    let cardsReviewed: Int
    let correctCardCount: Int
    let retryCardCount: Int
    let xpEarned: Int
    let dailyGoal: Int?
    let activityFraction: Double
    let didStudy: Bool
    let isPerfectDay: Bool
    let isStreakDay: Bool

    var outcomeCount: Int {
        correctCardCount + retryCardCount
    }

    var hasGoal: Bool {
        dailyGoal != nil
    }
}

/// Action-oriented summary that explains why the selected calendar day matters.
struct HomeSelectedDayInsightSummary: Equatable {
    let headline: String
    let detailLine: String
    let recommendationLine: String
    let paceLine: String
    let xpEarned: Int
    let newCardsLearned: Int
}

/// Prioritized deck-level health rollup used by Home to steer the user toward the right deck.
struct HomeDeckHealthSummary: Identifiable, Equatable {
    let id: PersistentIdentifier
    let title: String
    let colorHex: String
    let totalCards: Int
    let dueCards: Int
    let newCards: Int
    let buildingCards: Int
    let stableCards: Int
    let reviewAccuracy: Int
    let masteryFraction: Double
    let isRecentlyOpened: Bool
    let lastOpenedLabel: String?
    let headline: String
    let detailLine: String
    let actionLine: String
    let focusPrompt: String?
}

/// Cached Home snapshot derived from logs, goals, profile, and the selected day.
struct HomeDashboardSnapshot: Equatable {
    let selectedDayOverview: HomeSelectedDayOverviewSummary
    let selectedDayInsight: HomeSelectedDayInsightSummary
    let weeklyMomentum: HomeWeeklyMomentumSummary
    let pastWeekPerformance: HomePastWeekPerformanceSummary
    let selectedDayBreakdown: HomeSelectedDayBreakdownSummary

    nonisolated static func placeholder(referenceDate: Date = Date()) -> HomeDashboardSnapshot {
        let overview = HomeSelectedDayOverviewSummary(
            selectedDate: referenceDate,
            selectedDateLabel: "Today",
            cardsReviewed: 0,
            rawReviewCount: 0,
            dailyGoal: nil,
            goalCompletionFraction: 0,
            remainingCardsToGoal: 0,
            xpEarnedToday: 0,
            newCardsLearned: 0,
            correctCardCount: 0,
            retryCardCount: 0,
            streakCount: 0,
            totalXP: 0,
            headline: "Fresh study window",
            detailLine: "Start a session to build momentum today."
        )
        let weeklyMomentum = HomeWeeklyMomentumSummary(
            totalCardsReviewed: 0,
            totalXPEarned: 0,
            activeDays: 0,
            goalHitDays: 0,
            averageCardsPerActiveDay: 0,
            averageXPPerActiveDay: 0,
            consistencyFraction: 0,
            bestDayLabel: nil,
            headline: "No activity yet",
            detailLine: "Your weekly trend will appear as soon as you study.",
            daySummaries: []
        )
        let selectedDayBreakdown = HomeSelectedDayBreakdownSummary(
            selectedDate: referenceDate,
            cardsReviewed: 0,
            rawReviewCount: 0,
            correctCardCount: 0,
            retryCardCount: 0,
            headline: "No deck moved",
            detailLine: "Choose another day or start a short review block.",
            deckSummaries: []
        )
        let selectedDayInsight = HomeSelectedDayInsightSummary(
            headline: "Clear lane for study",
            detailLine: "Nothing is competing for this day yet.",
            recommendationLine: "Start with a short session to create momentum.",
            paceLine: "No recent pace to compare yet.",
            xpEarned: 0,
            newCardsLearned: 0
        )
        let pastWeekPerformance = HomePastWeekPerformanceSummary.placeholder(referenceDate: referenceDate)

        return HomeDashboardSnapshot(
            selectedDayOverview: overview,
            selectedDayInsight: selectedDayInsight,
            weeklyMomentum: weeklyMomentum,
            pastWeekPerformance: pastWeekPerformance,
            selectedDayBreakdown: selectedDayBreakdown
        )
    }
}

/// Resume-oriented greeting payload shown at the top of the Home dashboard.
enum HomeGreetingAction: Equatable {
    case openDeck(PersistentIdentifier)
    case switchTab(AppTabBar)
    case createFolder
}

/// Time-of-day phase used to select Home greetings and contextual copy.
enum HomeGreetingPhase: Equatable {
    case morning
    case afternoon
    case evening
    case night

    var title: String {
        let locale = AppPreferences.shared.resolvedLocale
        switch self {
        case .morning:
            return AppLocalization.string("Good morning", locale: locale)
        case .afternoon:
            return AppLocalization.string("Good afternoon", locale: locale)
        case .evening:
            return AppLocalization.string("Good evening", locale: locale)
        case .night:
            return AppLocalization.string("Good night", locale: locale)
        }
    }
}

/// Workspace readiness state used to avoid empty-zero analytics on Home.
enum HomeWorkspaceOnboardingState: Equatable {
    case needsDeck
    case needsFolders
    case ready
}

/// Resume-oriented greeting payload shown at the top of the Home dashboard.
struct HomeGreetingSummary: Equatable {
    let title: String
    let subtitle: String
    let contextTitle: String
    let contextLine: String
    let colorHex: String
    let primaryPill: String
    let secondaryPill: String?
    let progressFraction: Double
    let progressValueText: String
    let progressLabel: String
    let ctaTitle: String?
    let action: HomeGreetingAction?
}

/// Sticky companion summary shown in the custom iPad Home top header.
struct HomeTodayFocusHeaderSummary: Equatable {
    let introTitle: String
    let introSubtitle: String
    let eyebrow: String
    let title: String
    let detail: String
    let compactTitle: String
    let compactDetail: String
    let colorHex: String
    let primaryPill: String
    let secondaryPill: String?
    let progressFraction: Double
    let progressValueText: String
    let progressLabel: String
    let ctaTitle: String?
    let action: HomeGreetingAction?
}
