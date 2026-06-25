//
//  HomeAnalyticsRepository.swift
//  QuizFlash
//
//  Background Home analytics reads and one-time historical rebuilds.
//

import Foundation
import SwiftData

// MARK: - Repository Payloads

/// Background Home analytics payload consumed by `HomeViewModel`.
struct HomeAnalyticsDashboardSnapshot: Sendable {
    let selectedDayStats: HomeAnalyticsSelectedDayStats
    let weeklyMomentum: HomeWeeklyMomentumSummary
    let pastWeekPerformance: HomePastWeekPerformanceSummary
    let selectedDayBreakdown: HomeSelectedDayBreakdownSummary
}

/// Aggregate-backed selected-day metrics loaded before profile and exam overlays.
struct HomeAnalyticsSelectedDayStats: Sendable {
    let selectedDate: Date
    let cardsReviewed: Int
    let rawReviewCount: Int
    let dailyGoal: Int?
    let xpEarnedToday: Int
    let newCardsLearned: Int
    let correctCardCount: Int
    let retryCardCount: Int
}

// MARK: - Home Analytics Repository

/// Background repository that serves Home from lightweight persisted aggregates.
actor HomeAnalyticsRepository {

    // MARK: - Accumulators

    private struct DailyAccumulator {
        let dayDate: Date
        let dayKey: String
        var uniqueCardCount: Int
        var rawReviewCount: Int
        var landedCount: Int
        var retryCount: Int
        var xpEarned: Int
        var newCardsLearned: Int
        var dailyGoal: Int
    }

    private struct DeckAccumulator {
        let dayDate: Date
        let dayKey: String
        let deckIdentifier: String
        let deck: DeckModel?
        var deckTitleSnapshot: String
        var deckColorHexSnapshot: String
        var uniqueCardCount: Int
        var landedCount: Int
        var retryCount: Int
    }

    private struct CardAccumulator {
        let dayDate: Date
        let dayKey: String
        let cardIdentifier: String
        let deckIdentifier: String
        let card: CardModel?
        let deck: DeckModel?
        var deckTitleSnapshot: String
        var deckColorHexSnapshot: String
        var cardTitleSnapshot: String
        var finalDifficulty: ReviewDifficulty
        var repeatCount: Int
        var lastReviewedAt: Date
    }

    private struct PerformanceWindowMetrics {
        let scorePercent: Int
        let accuracyPercent: Int
        let consistencyPercent: Int
        let goalCoveragePercent: Int
        let efficiencyPercent: Int
        let activeDays: Int
        let goalHitDays: Int
        let bestDayLabel: String?
        let bestDayScorePercent: Int?
        let bestDayDailyQualityPercent: Int?
        let weakestDayLabel: String?
        let weakestDayScorePercent: Int?
        let weakestDayDailyQualityPercent: Int?
        let daySummaries: [HomePastWeekPerformanceDaySummary]
        let scoredDayCount: Int
    }

    private struct PerformanceCheckpointSummary {
        let date: Date
        let windowScorePercent: Int
        let dailyQualityPercent: Int
        let cardsReviewed: Int
    }

    // MARK: - State

    private let container: ModelContainer
    private var activeContext: ModelContext

    private static let shortWeekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEEE"
        return formatter
    }()

    private static let selectedDayLabelFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, d MMM"
        return formatter
    }()

    private static let performanceInsightLabelFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, d MMM"
        return formatter
    }()

    // MARK: - Init

    init(container: ModelContainer) {
        self.container = container
        let context = ModelContext(container)
        context.autosaveEnabled = false
        self.activeContext = context
    }

    // MARK: - Public

    /// Loads the Home weekly chart, selected-day overview inputs, and detail breakdown.
    func loadDashboardSnapshot(
        selectedDate: Date,
        weekStart: Date,
        dailyCardsGoal: Int? = nil
    ) -> HomeAnalyticsDashboardSnapshot {
        let calendar = Calendar.current
        let normalizedSelectedDate = HomeAnalyticsDayKey.normalizedDay(for: selectedDate)
        let normalizedWeekStart = HomeAnalyticsDayKey.normalizedDay(for: weekStart)
        let selectedDayKey = HomeAnalyticsDayKey.make(from: normalizedSelectedDate)

        let selectedDayAggregate = fetchDailyStudyAggregate(dayKey: selectedDayKey)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: normalizedWeekStart) ?? normalizedSelectedDate

        let weeklyAggregates = fetchDailyStudyAggregates(
            start: normalizedWeekStart,
            end: weekEnd
        )
        let aggregatesByKey = Dictionary(uniqueKeysWithValues: weeklyAggregates.map { ($0.dayKey, $0) })

        let daySummaries: [HomeWeeklyDaySummary] = (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: normalizedWeekStart) else {
                return nil
            }

            let dayKey = HomeAnalyticsDayKey.make(from: day)
            let aggregate = aggregatesByKey[dayKey]
            let cardsReviewed = aggregate?.uniqueCardCount ?? 0
            let xpEarned = aggregate?.xpEarned ?? 0
            let dayGoal = dailyCardsGoal.map { max($0, 1) }
            let intensityFraction = dayGoal.map { min(Double(cardsReviewed) / Double($0), 1.0) }
                ?? (cardsReviewed > 0 ? 1.0 : 0.0)

            return HomeWeeklyDaySummary(
                id: dayKey,
                date: day,
                shortWeekday: Self.shortWeekdayFormatter.string(from: day),
                cardsReviewed: cardsReviewed,
                rawReviewCount: aggregate?.rawReviewCount ?? 0,
                xpEarned: xpEarned,
                dailyGoal: dayGoal,
                correctCardCount: aggregate?.landedCount ?? 0,
                retryCardCount: aggregate?.retryCount ?? 0,
                intensityFraction: intensityFraction,
                didStudy: cardsReviewed > 0 || xpEarned > 0,
                didReachGoal: dayGoal.map { cardsReviewed >= $0 } ?? false,
                isSelectedDay: calendar.isDate(day, inSameDayAs: normalizedSelectedDate)
            )
        }

        let weeklyMomentum = buildWeeklyMomentumSummary(daySummaries: daySummaries)
        let pastWeekPerformance = buildPastWeekPerformanceSummary(
            selectedDate: normalizedSelectedDate,
            weekStart: normalizedWeekStart,
            dailyCardsGoal: dailyCardsGoal
        )
        let selectedDayBreakdown = buildSelectedDayBreakdown(
            selectedDate: normalizedSelectedDate,
            selectedDayAggregate: selectedDayAggregate
        )
        let selectedDayStats = HomeAnalyticsSelectedDayStats(
            selectedDate: normalizedSelectedDate,
            cardsReviewed: selectedDayAggregate?.uniqueCardCount ?? 0,
            rawReviewCount: selectedDayAggregate?.rawReviewCount ?? 0,
            dailyGoal: dailyCardsGoal.map { max($0, 1) },
            xpEarnedToday: selectedDayAggregate?.xpEarned ?? 0,
            newCardsLearned: selectedDayAggregate?.newCardsLearned ?? 0,
            correctCardCount: selectedDayAggregate?.landedCount ?? 0,
            retryCardCount: selectedDayAggregate?.retryCount ?? 0
        )

        let snapshot = HomeAnalyticsDashboardSnapshot(
            selectedDayStats: selectedDayStats,
            weeklyMomentum: weeklyMomentum,
            pastWeekPerformance: pastWeekPerformance,
            selectedDayBreakdown: selectedDayBreakdown
        )
        flushContext()
        return snapshot
    }

    /// Rebuilds all Home analytics aggregates from persisted card review history.
    func rebuildAnalyticsFromReviewHistory() throws {
        let cards = try activeContext.fetch(FetchDescriptor<CardModel>())
        let dailyLogs = try activeContext.fetch(FetchDescriptor<DailyActivityLog>())
        let dailyGoalsByKey = Dictionary(uniqueKeysWithValues: dailyLogs.map {
            ($0.dateString, max($0.dailyGoal, 1))
        })

        var dailyAccumulators: [String: DailyAccumulator] = [:]
        var deckAccumulators: [String: DeckAccumulator] = [:]
        var cardAccumulators: [String: CardAccumulator] = [:]

        for card in cards {
            let orderedHistory = card.reviewHistory.sorted { $0.timestamp < $1.timestamp }
            guard !orderedHistory.isEmpty else { continue }

            let firstReviewDayKey = HomeAnalyticsDayKey.make(from: orderedHistory[0].timestamp)
            let groupedHistory = Dictionary(grouping: orderedHistory) { event in
                HomeAnalyticsDayKey.make(from: event.timestamp)
            }

            for (dayKey, events) in groupedHistory {
                guard let finalEvent = events.max(by: { $0.timestamp < $1.timestamp }) else {
                    continue
                }

                let dayDate = HomeAnalyticsDayKey.normalizedDay(
                    for: finalEvent.timestamp
                )
                let deck = card.deck
                let deckIdentifier = encode(deck?.persistentModelID)
                let cardIdentifier = encode(card.persistentModelID)
                let deckAggregateKey = "\(dayKey)|\(deckIdentifier)"
                let reviewCount = events.count
                let xpEarned = events.reduce(0) { $0 + $1.xpAwarded }
                let finalWasCorrect = finalEvent.difficulty != .again

                let cardTitle = normalizedCardTitle(for: card)
                let deckTitle = normalizedDeckTitle(for: deck)
                let deckColorHex = normalizedDeckColorHex(for: deck)

                dailyAccumulators[dayKey, default: DailyAccumulator(
                    dayDate: dayDate,
                    dayKey: dayKey,
                    uniqueCardCount: 0,
                    rawReviewCount: 0,
                    landedCount: 0,
                    retryCount: 0,
                    xpEarned: 0,
                    newCardsLearned: 0,
                    dailyGoal: dailyGoalsByKey[dayKey] ?? 50
                )].uniqueCardCount += 1
                dailyAccumulators[dayKey]?.rawReviewCount += reviewCount
                dailyAccumulators[dayKey]?.xpEarned += xpEarned
                if finalWasCorrect {
                    dailyAccumulators[dayKey]?.landedCount += 1
                } else {
                    dailyAccumulators[dayKey]?.retryCount += 1
                }
                if dayKey == firstReviewDayKey {
                    dailyAccumulators[dayKey]?.newCardsLearned += 1
                }

                deckAccumulators[deckAggregateKey, default: DeckAccumulator(
                    dayDate: dayDate,
                    dayKey: dayKey,
                    deckIdentifier: deckIdentifier,
                    deck: deck,
                    deckTitleSnapshot: deckTitle,
                    deckColorHexSnapshot: deckColorHex,
                    uniqueCardCount: 0,
                    landedCount: 0,
                    retryCount: 0
                )].uniqueCardCount += 1
                if finalWasCorrect {
                    deckAccumulators[deckAggregateKey]?.landedCount += 1
                } else {
                    deckAccumulators[deckAggregateKey]?.retryCount += 1
                }
                deckAccumulators[deckAggregateKey]?.deckTitleSnapshot = deckTitle
                deckAccumulators[deckAggregateKey]?.deckColorHexSnapshot = deckColorHex

                cardAccumulators["\(dayKey)|\(cardIdentifier)"] = CardAccumulator(
                    dayDate: dayDate,
                    dayKey: dayKey,
                    cardIdentifier: cardIdentifier,
                    deckIdentifier: deckIdentifier,
                    card: card,
                    deck: deck,
                    deckTitleSnapshot: deckTitle,
                    deckColorHexSnapshot: deckColorHex,
                    cardTitleSnapshot: cardTitle,
                    finalDifficulty: finalEvent.difficulty,
                    repeatCount: reviewCount,
                    lastReviewedAt: finalEvent.timestamp
                )
            }
        }

        try deleteAllAggregates()

        for accumulator in dailyAccumulators.values {
            activeContext.insert(
                HomeDailyStudyAggregate(
                    dayDate: accumulator.dayDate,
                    uniqueCardCount: accumulator.uniqueCardCount,
                    rawReviewCount: accumulator.rawReviewCount,
                    landedCount: accumulator.landedCount,
                    retryCount: accumulator.retryCount,
                    xpEarned: accumulator.xpEarned,
                    newCardsLearned: accumulator.newCardsLearned,
                    dailyGoal: accumulator.dailyGoal
                )
            )
        }

        for accumulator in deckAccumulators.values {
            activeContext.insert(
                HomeDailyDeckAggregate(
                    dayDate: accumulator.dayDate,
                    deckIdentifier: accumulator.deckIdentifier,
                    deck: accumulator.deck,
                    deckTitleSnapshot: accumulator.deckTitleSnapshot,
                    deckColorHexSnapshot: accumulator.deckColorHexSnapshot,
                    uniqueCardCount: accumulator.uniqueCardCount,
                    landedCount: accumulator.landedCount,
                    retryCount: accumulator.retryCount
                )
            )
        }

        for accumulator in cardAccumulators.values {
            activeContext.insert(
                HomeDailyCardAggregate(
                    dayDate: accumulator.dayDate,
                    cardIdentifier: accumulator.cardIdentifier,
                    deckIdentifier: accumulator.deckIdentifier,
                    card: accumulator.card,
                    deck: accumulator.deck,
                    deckTitleSnapshot: accumulator.deckTitleSnapshot,
                    deckColorHexSnapshot: accumulator.deckColorHexSnapshot,
                    cardTitleSnapshot: accumulator.cardTitleSnapshot,
                    finalDifficulty: accumulator.finalDifficulty,
                    repeatCount: accumulator.repeatCount,
                    lastReviewedAt: accumulator.lastReviewedAt
                )
            )
        }

        try activeContext.save()
        flushContext()
    }

    /// Drops the current row cache after a Home analytics operation completes.
    func tearDown() {
        flushContext()
    }

    // MARK: - Fetches

    private func fetchDailyStudyAggregate(dayKey: String) -> HomeDailyStudyAggregate? {
        let descriptor = FetchDescriptor<HomeDailyStudyAggregate>(
            predicate: #Predicate { $0.dayKey == dayKey }
        )
        return (try? activeContext.fetch(descriptor))?.first
    }

    private func fetchDailyStudyAggregates(start: Date, end: Date) -> [HomeDailyStudyAggregate] {
        let descriptor = FetchDescriptor<HomeDailyStudyAggregate>(
            predicate: #Predicate {
                $0.dayDate >= start && $0.dayDate < end
            }
        )
        return (try? activeContext.fetch(descriptor)) ?? []
    }

    private func fetchDailyDeckAggregates(dayKey: String) -> [HomeDailyDeckAggregate] {
        let descriptor = FetchDescriptor<HomeDailyDeckAggregate>(
            predicate: #Predicate { $0.dayKey == dayKey }
        )
        return (try? activeContext.fetch(descriptor)) ?? []
    }

    private func fetchDailyCardAggregates(dayKey: String) -> [HomeDailyCardAggregate] {
        let descriptor = FetchDescriptor<HomeDailyCardAggregate>(
            predicate: #Predicate { $0.dayKey == dayKey }
        )
        return (try? activeContext.fetch(descriptor)) ?? []
    }

    // MARK: - Builders

    private func buildWeeklyMomentumSummary(
        daySummaries: [HomeWeeklyDaySummary]
    ) -> HomeWeeklyMomentumSummary {
        let totalCardsReviewed = daySummaries.map(\.cardsReviewed).reduce(0, +)
        let totalXPEarned = daySummaries.map(\.xpEarned).reduce(0, +)
        let activeDays = daySummaries.filter(\.didStudy).count
        let goalHitDays = daySummaries.filter(\.didReachGoal).count
        let averageCardsPerActiveDay = activeDays > 0
            ? Int(round(Double(totalCardsReviewed) / Double(activeDays)))
            : 0
        let averageXPPerActiveDay = activeDays > 0
            ? Int(round(Double(totalXPEarned) / Double(activeDays)))
            : 0
        let bestDay = daySummaries.max { lhs, rhs in
            if lhs.cardsReviewed != rhs.cardsReviewed {
                return lhs.cardsReviewed < rhs.cardsReviewed
            }
            return lhs.xpEarned < rhs.xpEarned
        }

        let headline: String
        let detailLine: String
        if activeDays == 0 {
            headline = "No activity yet"
            detailLine = "Your weekly trend will appear as soon as you study."
        } else if goalHitDays > 0 {
            headline = "\(goalHitDays)/7 goal days"
            detailLine = "Average pace is \(averageCardsPerActiveDay) cards on active study days."
        } else {
            headline = "\(activeDays)/7 active days"
            detailLine = "You averaged \(averageCardsPerActiveDay) cards and \(averageXPPerActiveDay) XP when active."
        }

        return HomeWeeklyMomentumSummary(
            totalCardsReviewed: totalCardsReviewed,
            totalXPEarned: totalXPEarned,
            activeDays: activeDays,
            goalHitDays: goalHitDays,
            averageCardsPerActiveDay: averageCardsPerActiveDay,
            averageXPPerActiveDay: averageXPPerActiveDay,
            consistencyFraction: Double(activeDays) / 7.0,
            bestDayLabel: bestDay.map { Self.selectedDayLabelFormatter.string(from: $0.date) },
            headline: headline,
            detailLine: detailLine,
            daySummaries: daySummaries
        )
    }

    private func buildPastWeekPerformanceSummary(
        selectedDate: Date,
        weekStart: Date,
        dailyCardsGoal: Int?
    ) -> HomePastWeekPerformanceSummary {
        let calendar = Calendar.current
        let normalizedSelectedDate = HomeAnalyticsDayKey.normalizedDay(for: selectedDate)
        let normalizedWeekStart = HomeAnalyticsDayKey.normalizedDay(for: weekStart)
        let selectedDayOffset = min(
            max(calendar.dateComponents([.day], from: normalizedWeekStart, to: normalizedSelectedDate).day ?? 0, 0),
            6
        )
        guard
            let previousWeekStart = calendar.date(byAdding: .day, value: -7, to: normalizedWeekStart),
            let currentWeekEnd = calendar.date(byAdding: .day, value: 7, to: normalizedWeekStart),
            let currentScoringEndDate = calendar.date(byAdding: .day, value: selectedDayOffset, to: normalizedWeekStart),
            let previousScoringEndDate = calendar.date(byAdding: .day, value: selectedDayOffset, to: previousWeekStart)
        else {
            return .placeholder(referenceDate: normalizedSelectedDate)
        }

        let aggregates = fetchDailyStudyAggregates(start: previousWeekStart, end: currentWeekEnd)
        let aggregatesByKey = Dictionary(uniqueKeysWithValues: aggregates.map { ($0.dayKey, $0) })

        let previousMetrics = buildPerformanceWindowMetrics(
            start: previousWeekStart,
            aggregatesByKey: aggregatesByKey,
            scoringEndDate: previousScoringEndDate,
            dailyCardsGoal: dailyCardsGoal
        )
        let currentMetrics = buildPerformanceWindowMetrics(
            start: normalizedWeekStart,
            aggregatesByKey: aggregatesByKey,
            scoringEndDate: currentScoringEndDate,
            displayEndDate: currentScoringEndDate,
            dailyCardsGoal: dailyCardsGoal
        )
        let deltaPercent = currentMetrics.scorePercent - previousMetrics.scorePercent
        let trend: HomePastWeekPerformanceTrend
        if deltaPercent >= 3 {
            trend = .improving
        } else if deltaPercent <= -3 {
            trend = .slipping
        } else {
            trend = .steady
        }

        return HomePastWeekPerformanceSummary(
            weekStartDate: normalizedWeekStart,
            windowEndDate: normalizedSelectedDate,
            scorePercent: currentMetrics.scorePercent,
            previousScorePercent: previousMetrics.scorePercent,
            deltaPercent: deltaPercent,
            trend: trend,
            trendLine: performanceTrendLine(
                activeDays: currentMetrics.activeDays,
                trend: trend
            ),
            accuracyPercent: currentMetrics.accuracyPercent,
            consistencyPercent: currentMetrics.consistencyPercent,
            goalCoveragePercent: currentMetrics.goalCoveragePercent,
            efficiencyPercent: currentMetrics.efficiencyPercent,
            activeDays: currentMetrics.activeDays,
            scoredDayCount: currentMetrics.scoredDayCount,
            goalHitDays: currentMetrics.goalHitDays,
            bestDayLabel: currentMetrics.bestDayLabel,
            bestDayScorePercent: currentMetrics.bestDayScorePercent,
            bestDayDailyQualityPercent: currentMetrics.bestDayDailyQualityPercent,
            weakestDayLabel: currentMetrics.weakestDayLabel,
            weakestDayScorePercent: currentMetrics.weakestDayScorePercent,
            weakestDayDailyQualityPercent: currentMetrics.weakestDayDailyQualityPercent,
            currentDaySummaries: currentMetrics.daySummaries,
            previousDaySummaries: previousMetrics.daySummaries
        )
    }

    private func buildPerformanceWindowMetrics(
        start: Date,
        aggregatesByKey: [String: HomeDailyStudyAggregate],
        scoringEndDate: Date,
        displayEndDate: Date? = nil,
        dailyCardsGoal: Int?
    ) -> PerformanceWindowMetrics {
        let locale = AppPreferences.persistedResolvedLocale
        Self.performanceInsightLabelFormatter.locale = locale

        let daySummaries = buildPerformanceDaySummaries(
            start: start,
            aggregatesByKey: aggregatesByKey,
            displayEndDate: displayEndDate,
            dailyCardsGoal: dailyCardsGoal
        )
        let normalizedScoringEndDate = HomeAnalyticsDayKey.normalizedDay(for: scoringEndDate)
        let scoringDaySummaries = daySummaries.filter { $0.date <= normalizedScoringEndDate }
        let scoringDayCount = max(scoringDaySummaries.count, 1)

        let totalLanded = scoringDaySummaries.map(\.landedCount).reduce(0, +)
        let totalRetry = scoringDaySummaries.map(\.retryCount).reduce(0, +)
        let totalCardsReviewed = scoringDaySummaries.map(\.cardsReviewed).reduce(0, +)
        let totalRawReviewCount = scoringDaySummaries.map(\.rawReviewCount).reduce(0, +)
        let activeDays = scoringDaySummaries.filter(\.didStudy).count
        let goalHitDays = scoringDaySummaries.filter(\.didReachGoal).count
        let cleanFinishRate = (totalLanded + totalRetry) > 0
            ? Double(totalLanded) / Double(totalLanded + totalRetry)
            : 0
        let consistencyRate = Double(activeDays) / Double(scoringDayCount)
        let goalCoverageRate = scoringDaySummaries
            .compactMap { day -> Double? in
                guard let dailyGoal = day.dailyGoal else { return nil }
                return min(Double(day.cardsReviewed) / Double(max(dailyGoal, 1)), 1.0)
            }
            .reduce(0, +) / Double(scoringDayCount)
        let efficiencyRate = totalCardsReviewed > 0
            ? Double(totalCardsReviewed) / Double(max(totalRawReviewCount, 1))
            : 0
        let weightedScore: Double
        if dailyCardsGoal == nil {
            weightedScore = (cleanFinishRate * 0.65)
                + (consistencyRate * 0.25)
                + (efficiencyRate * 0.10)
        } else {
            weightedScore = (cleanFinishRate * 0.55)
                + (consistencyRate * 0.20)
                + (goalCoverageRate * 0.15)
                + (efficiencyRate * 0.10)
        }
        let scorePercent = min(max(Int((weightedScore * 100).rounded()), 0), 100)
        let accuracyPercent = min(max(Int((cleanFinishRate * 100).rounded()), 0), 100)
        let consistencyPercent = min(max(Int((consistencyRate * 100).rounded()), 0), 100)
        let goalCoveragePercent = min(max(Int((goalCoverageRate * 100).rounded()), 0), 100)
        let efficiencyPercent = min(max(Int((efficiencyRate * 100).rounded()), 0), 100)

        let checkpointSummaries = buildPerformanceCheckpointSummaries(
            daySummaries: scoringDaySummaries,
            aggregatesByKey: aggregatesByKey
        )
        let bestDay = checkpointSummaries.max { lhs, rhs in
            if lhs.windowScorePercent != rhs.windowScorePercent {
                return lhs.windowScorePercent < rhs.windowScorePercent
            }
            if lhs.dailyQualityPercent != rhs.dailyQualityPercent {
                return lhs.dailyQualityPercent < rhs.dailyQualityPercent
            }
            return lhs.cardsReviewed < rhs.cardsReviewed
        }
        let weakestDay = checkpointSummaries.min { lhs, rhs in
            if lhs.windowScorePercent != rhs.windowScorePercent {
                return lhs.windowScorePercent < rhs.windowScorePercent
            }
            if lhs.dailyQualityPercent != rhs.dailyQualityPercent {
                return lhs.dailyQualityPercent < rhs.dailyQualityPercent
            }
            return lhs.cardsReviewed < rhs.cardsReviewed
        }

        return PerformanceWindowMetrics(
            scorePercent: scorePercent,
            accuracyPercent: accuracyPercent,
            consistencyPercent: consistencyPercent,
            goalCoveragePercent: goalCoveragePercent,
            efficiencyPercent: efficiencyPercent,
            activeDays: activeDays,
            goalHitDays: goalHitDays,
            bestDayLabel: bestDay.map { Self.performanceInsightLabelFormatter.string(from: $0.date) },
            bestDayScorePercent: bestDay?.windowScorePercent,
            bestDayDailyQualityPercent: bestDay?.dailyQualityPercent,
            weakestDayLabel: weakestDay.map { Self.performanceInsightLabelFormatter.string(from: $0.date) },
            weakestDayScorePercent: weakestDay?.windowScorePercent,
            weakestDayDailyQualityPercent: weakestDay?.dailyQualityPercent,
            daySummaries: daySummaries,
            scoredDayCount: scoringDayCount
        )
    }

    private func buildPerformanceDaySummaries(
        start: Date,
        aggregatesByKey: [String: HomeDailyStudyAggregate],
        displayEndDate: Date? = nil,
        dailyCardsGoal: Int?
    ) -> [HomePastWeekPerformanceDaySummary] {
        let calendar = Calendar.current
        let normalizedDisplayEndDate = displayEndDate.map { HomeAnalyticsDayKey.normalizedDay(for: $0) }
        Self.shortWeekdayFormatter.locale = AppPreferences.persistedResolvedLocale

        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else {
                return nil
            }

            let dayKey = HomeAnalyticsDayKey.make(from: day)
            let shouldDisplayAggregate = normalizedDisplayEndDate.map { day <= $0 } ?? true
            let aggregate = shouldDisplayAggregate ? aggregatesByKey[dayKey] : nil
            let cardsReviewed = aggregate?.uniqueCardCount ?? 0
            let rawReviewCount = aggregate?.rawReviewCount ?? 0
            let landedCount = aggregate?.landedCount ?? 0
            let retryCount = aggregate?.retryCount ?? 0
            let dayGoal = dailyCardsGoal.map { max($0, 1) }
            let didStudy = cardsReviewed > 0 || rawReviewCount > 0 || (aggregate?.xpEarned ?? 0) > 0
            let didReachGoal = dayGoal.map { cardsReviewed >= $0 } ?? false
            let cleanFinishRate = (landedCount + retryCount) > 0
                ? Double(landedCount) / Double(landedCount + retryCount)
                : 0
            let goalCoverageRate = dayGoal.map { min(Double(cardsReviewed) / Double($0), 1.0) } ?? 0
            let scoreFraction = dayGoal == nil
                ? cleanFinishRate
                : (cleanFinishRate * 0.6) + (goalCoverageRate * 0.4)
            let scorePercent = Int((scoreFraction * 100).rounded())
            let visualLevel = min(max(Int((scoreFraction * 5).rounded()), 0), 5)

            return HomePastWeekPerformanceDaySummary(
                id: dayKey,
                date: day,
                shortWeekday: Self.shortWeekdayFormatter.string(from: day),
                cardsReviewed: cardsReviewed,
                rawReviewCount: rawReviewCount,
                landedCount: landedCount,
                retryCount: retryCount,
                dailyGoal: dayGoal,
                scorePercent: scorePercent,
                visualLevel: visualLevel,
                didStudy: didStudy,
                didReachGoal: didReachGoal
            )
        }
    }

    private func buildPerformanceCheckpointSummaries(
        daySummaries: [HomePastWeekPerformanceDaySummary],
        aggregatesByKey: [String: HomeDailyStudyAggregate]
    ) -> [PerformanceCheckpointSummary] {
        let calendar = Calendar.current

        return daySummaries.compactMap { day in
            guard
                day.didStudy,
                let checkpointStart = calendar.date(byAdding: .day, value: -6, to: day.date)
            else {
                return nil
            }

            let checkpointDaySummaries = buildPerformanceDaySummaries(
                start: checkpointStart,
                aggregatesByKey: aggregatesByKey,
                dailyCardsGoal: day.dailyGoal
            )

            let totalLanded = checkpointDaySummaries.map(\.landedCount).reduce(0, +)
            let totalRetry = checkpointDaySummaries.map(\.retryCount).reduce(0, +)
            let totalCardsReviewed = checkpointDaySummaries.map(\.cardsReviewed).reduce(0, +)
            let totalRawReviewCount = checkpointDaySummaries.map(\.rawReviewCount).reduce(0, +)
            let activeDays = checkpointDaySummaries.filter(\.didStudy).count
            let cleanFinishRate = (totalLanded + totalRetry) > 0
                ? Double(totalLanded) / Double(totalLanded + totalRetry)
                : 0
            let consistencyRate = Double(activeDays) / 7.0
            let goalCoverageRate = checkpointDaySummaries
                .compactMap { day -> Double? in
                    guard let dailyGoal = day.dailyGoal else { return nil }
                    return min(Double(day.cardsReviewed) / Double(max(dailyGoal, 1)), 1.0)
                }
                .reduce(0, +) / 7.0
            let efficiencyRate = totalCardsReviewed > 0
                ? Double(totalCardsReviewed) / Double(max(totalRawReviewCount, 1))
                : 0
            let weightedScore: Double
            if day.dailyGoal == nil {
                weightedScore = (cleanFinishRate * 0.65)
                    + (consistencyRate * 0.25)
                    + (efficiencyRate * 0.10)
            } else {
                weightedScore = (cleanFinishRate * 0.55)
                    + (consistencyRate * 0.20)
                    + (goalCoverageRate * 0.15)
                    + (efficiencyRate * 0.10)
            }
            let windowScorePercent = min(max(Int((weightedScore * 100).rounded()), 0), 100)

            return PerformanceCheckpointSummary(
                date: day.date,
                windowScorePercent: windowScorePercent,
                dailyQualityPercent: day.scorePercent,
                cardsReviewed: day.cardsReviewed
            )
        }
    }

    private func performanceTrendLine(
        activeDays: Int,
        trend: HomePastWeekPerformanceTrend
    ) -> String {
        guard activeDays > 0 else {
            return "Needs attention"
        }

        switch trend {
        case .improving:
            return "Improving day by day"
        case .steady:
            return "Stable this week"
        case .slipping:
            return "Needs attention"
        }
    }

    private func buildSelectedDayBreakdown(
        selectedDate: Date,
        selectedDayAggregate: HomeDailyStudyAggregate?
    ) -> HomeSelectedDayBreakdownSummary {
        let dayKey = HomeAnalyticsDayKey.make(from: selectedDate)
        let cardAggregates = fetchDailyCardAggregates(dayKey: dayKey)
        let cardAggregatesByDeck = Dictionary(grouping: cardAggregates, by: \.deckAggregateKey)
        let deckAggregates = fetchDailyDeckAggregates(dayKey: dayKey)

        let deckSummaries = deckAggregates
            .map { aggregate in
                let cards = (cardAggregatesByDeck[aggregate.aggregateKey] ?? [])
                    .map {
                        HomeWeeklyReviewedCardSummary(
                            id: $0.aggregateKey,
                            cardID: nil,
                            deckID: nil,
                            deckTitle: resolvedSnapshotDeckTitle($0.deckTitleSnapshot),
                            deckColorHex: resolvedSnapshotDeckColorHex($0.deckColorHexSnapshot),
                            title: resolvedSnapshotCardTitle($0.cardTitleSnapshot),
                            finalDifficulty: $0.finalDifficulty,
                            reviewCount: $0.repeatCount,
                            lastReviewedAt: $0.lastReviewedAt
                        )
                    }
                    .sorted { lhs, rhs in
                        if lhs.wasCorrectAtEndOfDay != rhs.wasCorrectAtEndOfDay {
                            return !lhs.wasCorrectAtEndOfDay && rhs.wasCorrectAtEndOfDay
                        }
                        return lhs.lastReviewedAt > rhs.lastReviewedAt
                    }

                return HomeWeeklyDeckActivitySummary(
                    id: aggregate.aggregateKey,
                    deckID: nil,
                    title: resolvedSnapshotDeckTitle(aggregate.deckTitleSnapshot),
                    colorHex: resolvedSnapshotDeckColorHex(aggregate.deckColorHexSnapshot),
                    uniqueCardCount: aggregate.uniqueCardCount,
                    correctCardCount: aggregate.landedCount,
                    retryCardCount: aggregate.retryCount,
                    cards: cards
                )
            }
            .sorted { lhs, rhs in
                if lhs.retryCardCount != rhs.retryCardCount {
                    return lhs.retryCardCount > rhs.retryCardCount
                }
                if lhs.uniqueCardCount != rhs.uniqueCardCount {
                    return lhs.uniqueCardCount > rhs.uniqueCardCount
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }

        let cardsReviewed = selectedDayAggregate?.uniqueCardCount ?? 0
        let retryCount = selectedDayAggregate?.retryCount ?? 0

        let headline: String
        let detailLine: String
        if cardsReviewed == 0 {
            headline = "No deck moved"
            detailLine = "Choose another day or start a short review block."
        } else if retryCount == 0 {
            headline = "Everything landed cleanly"
            detailLine = "\(cardsReviewed) unique cards moved across \(deckSummaries.count) deck\(deckSummaries.count == 1 ? "" : "s")."
        } else {
            headline = "\(retryCount) card\(retryCount == 1 ? "" : "s") still need a retry"
            detailLine = "\(cardsReviewed) unique cards moved across \(deckSummaries.count) deck\(deckSummaries.count == 1 ? "" : "s")."
        }

        return HomeSelectedDayBreakdownSummary(
            selectedDate: selectedDate,
            cardsReviewed: cardsReviewed,
            rawReviewCount: selectedDayAggregate?.rawReviewCount ?? 0,
            correctCardCount: selectedDayAggregate?.landedCount ?? 0,
            retryCardCount: retryCount,
            headline: headline,
            detailLine: detailLine,
            deckSummaries: deckSummaries
        )
    }

    // MARK: - Storage Helpers

    private func deleteAllAggregates() throws {
        for aggregate in try activeContext.fetch(FetchDescriptor<HomeDailyCardAggregate>()) {
            activeContext.delete(aggregate)
        }
        for aggregate in try activeContext.fetch(FetchDescriptor<HomeDailyDeckAggregate>()) {
            activeContext.delete(aggregate)
        }
        for aggregate in try activeContext.fetch(FetchDescriptor<HomeDailyStudyAggregate>()) {
            activeContext.delete(aggregate)
        }
    }

    private func flushContext() {
        let freshContext = ModelContext(container)
        freshContext.autosaveEnabled = false
        activeContext = freshContext
    }

    // MARK: - Snapshot Helpers

    private func encode(_ id: PersistentIdentifier?) -> String {
        guard let id else { return "unassigned" }
        return HomeAnalyticsIdentifierCodec.encode(id)
    }

    private func normalizedDeckTitle(for deck: DeckModel?) -> String {
        let trimmed = deck?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Untitled Deck" : trimmed
    }

    private func normalizedDeckColorHex(for deck: DeckModel?) -> String {
        let color = deck?.colorHex.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return color.isEmpty ? "#70707A" : color
    }

    private func normalizedCardTitle(for card: CardModel?) -> String {
        let preferred = card?.frontText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !preferred.isEmpty {
            return preferred
        }

        let fallback = card?.backText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return fallback.isEmpty ? "Untitled Card" : fallback
    }

    private func resolvedSnapshotDeckTitle(_ snapshot: String) -> String {
        let fallback = snapshot.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? "Untitled Deck" : fallback
    }

    private func resolvedSnapshotDeckColorHex(_ snapshot: String) -> String {
        let fallback = snapshot.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? "#70707A" : fallback
    }

    private func resolvedSnapshotCardTitle(_ snapshot: String) -> String {
        let fallback = snapshot.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? "Untitled Card" : fallback
    }

}
