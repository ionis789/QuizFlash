// HomeDashboardSnapshot.swift
// QuizFlash
//
// Lightweight Home snapshot and summary payloads extracted from HomeViewModel.

import Foundation
import SwiftData

// MARK: - Home Exam Summaries

/// Lightweight readiness summary for one linked deck inside an exam goal.
struct HomeExamDeckSummary: Identifiable, Equatable {
    let id: PersistentIdentifier
    let title: String
    let colorHex: String
    let totalCards: Int
    let reviewedCards: Int
    let dueCards: Int
    let newCards: Int
    let accuracyFraction: Double
    let readinessFraction: Double

    /// Cards that still need active work before the linked goal feels healthy.
    var remainingCards: Int { dueCards + newCards }
}

/// Home-facing aggregate summary for one upcoming exam goal.
struct HomeExamGoalSummary: Identifiable, Equatable {
    let id: PersistentIdentifier
    let title: String
    let note: String
    let date: Date
    let status: ExamGoalStatus
    let countdownLabel: String
    let dateLabel: String
    let targetWorkload: Int
    let linkedDeckCount: Int
    let readinessFraction: Double
    let overdueCount: Int
    let dailyPaceNeeded: Int
    let belowTargetDeckCount: Int
    let weakestDeck: HomeExamDeckSummary?
    let summaryLine: String
    let deckSummaries: [HomeExamDeckSummary]

    var hasNote: Bool {
        !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Short narrative lines shown above the exam-goal cards on Home.
struct HomeDashboardNarrative: Equatable {
    let riskDeckLine: String?
    let closestWinLine: String?
    let nextBestActionLine: String?

    var visibleLines: [String] {
        [riskDeckLine, closestWinLine, nextBestActionLine].compactMap { $0 }
    }
}

/// Selected-day analytics shown in the top Home dashboard summary.
struct HomeSelectedDayOverviewSummary: Equatable {
    let selectedDate: Date
    let selectedDateLabel: String
    let cardsReviewed: Int
    let rawReviewCount: Int
    let dailyGoal: Int
    let goalCompletionFraction: Double
    let remainingCardsToGoal: Int
    let xpEarnedToday: Int
    let newCardsLearned: Int
    let correctCardCount: Int
    let retryCardCount: Int
    let streakCount: Int
    let totalXP: Int
    let level: Int
    let headline: String
    let detailLine: String

    /// `true` when the selected day reached or exceeded its target workload.
    var didReachGoal: Bool {
        cardsReviewed >= dailyGoal
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
    let goal: Int
    let correctCardCount: Int
    let retryCardCount: Int
    let intensityFraction: Double
    let didStudy: Bool
    let didReachGoal: Bool
    let isSelectedDay: Bool
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

/// Directional trend used by the Home 7-day performance card.
enum HomePastWeekPerformanceTrend: String, Equatable, Sendable {
    case improving
    case steady
    case slipping
}

/// One compact day column inside the Home 7-day performance comparison.
struct HomePastWeekPerformanceDaySummary: Identifiable, Equatable, Sendable {
    let id: String
    let date: Date
    let shortWeekday: String
    let cardsReviewed: Int
    let rawReviewCount: Int
    let landedCount: Int
    let retryCount: Int
    let dailyGoal: Int
    let scorePercent: Int
    let visualLevel: Int
    let didStudy: Bool
    let didReachGoal: Bool
}

/// Accuracy-first performance index for the selected 7-day window on Home.
struct HomePastWeekPerformanceSummary: Equatable, Sendable {
    let windowEndDate: Date
    let scorePercent: Int
    let previousScorePercent: Int
    let deltaPercent: Int
    let trend: HomePastWeekPerformanceTrend
    let trendLine: String
    let supportingLine: String
    let accuracyPercent: Int
    let consistencyPercent: Int
    let goalCoveragePercent: Int
    let efficiencyPercent: Int
    let activeDays: Int
    let goalHitDays: Int
    let bestDayLabel: String?
    let bestDayScorePercent: Int?
    let weakestDayLabel: String?
    let weakestDayScorePercent: Int?
    let currentDaySummaries: [HomePastWeekPerformanceDaySummary]
    let previousDaySummaries: [HomePastWeekPerformanceDaySummary]

    var hasActivity: Bool {
        activeDays > 0
    }

    static func placeholder(referenceDate: Date = Date()) -> HomePastWeekPerformanceSummary {
        HomePastWeekPerformanceSummary(
            windowEndDate: referenceDate,
            scorePercent: 0,
            previousScorePercent: 0,
            deltaPercent: 0,
            trend: .steady,
            trendLine: "Needs attention",
            supportingLine: "No activity landed in this 7-day window.",
            accuracyPercent: 0,
            consistencyPercent: 0,
            goalCoveragePercent: 0,
            efficiencyPercent: 0,
            activeDays: 0,
            goalHitDays: 0,
            bestDayLabel: nil,
            bestDayScorePercent: nil,
            weakestDayLabel: nil,
            weakestDayScorePercent: nil,
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
    let xpEarned: Int
    let dailyGoal: Int
    let activityFraction: Double
    let didStudy: Bool
    let isPerfectDay: Bool
    let isStreakDay: Bool
    let hasExamGoal: Bool
    let hasGoalNote: Bool
    let examGoalCount: Int
}

/// Action-oriented summary that explains why the selected calendar day matters.
struct HomeSelectedDayInsightSummary: Equatable {
    let headline: String
    let detailLine: String
    let recommendationLine: String
    let paceLine: String
    let examContextLine: String
    let xpEarned: Int
    let newCardsLearned: Int
    let selectedDayExamCount: Int
}

/// Condensed risk summary for the single exam goal that currently needs the most attention.
struct HomeExamPressureSummary: Equatable {
    let goalID: PersistentIdentifier
    let goalTitle: String
    let countdownLabel: String
    let readinessFraction: Double
    let headline: String
    let detailLine: String
    let actionLine: String
    let overdueCards: Int
    let dailyPaceNeeded: Int
    let belowTargetDeckCount: Int
    let weakestDeckTitle: String?
    let weakestDeckReadinessFraction: Double?
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
    let linkedGoalCount: Int
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
    let examPressure: HomeExamPressureSummary?
    let selectedDayExamSummaries: [HomeExamGoalSummary]
    let upcomingExamSummaries: [HomeExamGoalSummary]
    let examNarrative: HomeDashboardNarrative?

    static func placeholder(referenceDate: Date = Date()) -> HomeDashboardSnapshot {
        let overview = HomeSelectedDayOverviewSummary(
            selectedDate: referenceDate,
            selectedDateLabel: "Today",
            cardsReviewed: 0,
            rawReviewCount: 0,
            dailyGoal: 50,
            goalCompletionFraction: 0,
            remainingCardsToGoal: 50,
            xpEarnedToday: 0,
            newCardsLearned: 0,
            correctCardCount: 0,
            retryCardCount: 0,
            streakCount: 0,
            totalXP: 0,
            level: 1,
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
            examContextLine: "No exam goals scheduled around this date.",
            xpEarned: 0,
            newCardsLearned: 0,
            selectedDayExamCount: 0
        )
        let pastWeekPerformance = HomePastWeekPerformanceSummary.placeholder(referenceDate: referenceDate)

        return HomeDashboardSnapshot(
            selectedDayOverview: overview,
            selectedDayInsight: selectedDayInsight,
            weeklyMomentum: weeklyMomentum,
            pastWeekPerformance: pastWeekPerformance,
            selectedDayBreakdown: selectedDayBreakdown,
            examPressure: nil,
            selectedDayExamSummaries: [],
            upcomingExamSummaries: [],
            examNarrative: nil
        )
    }
}

/// Cached Home dashboard payload that does not depend on the currently selected day.
struct HomeDashboardStaticSnapshot: Equatable {
    let upcomingExamSummaries: [HomeExamGoalSummary]
    let examPressure: HomeExamPressureSummary?
    let examNarrative: HomeDashboardNarrative?

    static func empty() -> HomeDashboardStaticSnapshot {
        HomeDashboardStaticSnapshot(
            upcomingExamSummaries: [],
            examPressure: nil,
            examNarrative: nil
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
        switch self {
        case .morning:
            return "Good morning"
        case .afternoon:
            return "Good afternoon"
        case .evening:
            return "Good evening"
        case .night:
            return "Good night"
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
