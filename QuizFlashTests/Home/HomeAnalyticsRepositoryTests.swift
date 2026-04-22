//
//  HomeAnalyticsRepositoryTests.swift
//  QuizFlashTests
//
//  Covers background aggregate reads and historical rebuilds for Home.
//

import XCTest
import SwiftData
@testable import QuizFlash

@MainActor
final class HomeAnalyticsRepositoryTests: XCTestCase {
    func testRebuildAnalyticsFromReviewHistoryBuildsHistoricalBreakdown() async throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        let selectedDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 22, hour: 12)))
        let previousDate = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: selectedDate))

        let selectedLog = DailyActivityLog(date: selectedDate, dailyGoal: 30)
        let previousLog = DailyActivityLog(date: previousDate, dailyGoal: 18)
        context.insert(selectedLog)
        context.insert(previousLog)

        let deckA = DeckModel(title: "Biology", colorHex: "#FF6A55")
        let deckB = DeckModel(title: "History", colorHex: "#58C27D")
        context.insert(deckA)
        context.insert(deckB)

        let cardA = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.flashcard(front: "Cell", back: "Membrane"),
            cardNumber: 1
        )
        let cardB = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.flashcard(front: "Treaty", back: "Westphalia"),
            cardNumber: 1
        )
        context.insert(cardA)
        context.insert(cardB)

        deckA.cards = [cardA]
        deckB.cards = [cardB]
        cardA.deck = deckA
        cardB.deck = deckB
        deckA.cardCount = 1
        deckB.cardCount = 1

        let previousReview = ReviewEvent(timeSpent: 5.0, difficulty: .good, xpAwarded: 6)
        previousReview.timestamp = previousDate
        previousReview.card = cardA
        cardA.reviewHistory.append(previousReview)

        let selectedRetry = ReviewEvent(timeSpent: 7.0, difficulty: .again, xpAwarded: 3)
        selectedRetry.timestamp = selectedDate
        selectedRetry.card = cardA
        cardA.reviewHistory.append(selectedRetry)

        let selectedRecovery = ReviewEvent(timeSpent: 4.0, difficulty: .good, xpAwarded: 7)
        selectedRecovery.timestamp = calendar.date(byAdding: .minute, value: 12, to: selectedDate) ?? selectedDate
        selectedRecovery.card = cardA
        cardA.reviewHistory.append(selectedRecovery)

        let selectedHistoryReview = ReviewEvent(timeSpent: 3.0, difficulty: .easy, xpAwarded: 10)
        selectedHistoryReview.timestamp = calendar.date(byAdding: .minute, value: 25, to: selectedDate) ?? selectedDate
        selectedHistoryReview.card = cardB
        cardB.reviewHistory.append(selectedHistoryReview)

        try context.save()

        let repository = HomeAnalyticsRepository(container: container)
        try await repository.rebuildAnalyticsFromReviewHistory()

        let snapshot = await repository.loadDashboardSnapshot(
            selectedDate: selectedDate,
            weekStart: calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate
        )
        await repository.tearDown()

        XCTAssertEqual(snapshot.selectedDayStats.cardsReviewed, 2)
        XCTAssertEqual(snapshot.selectedDayStats.rawReviewCount, 3)
        XCTAssertEqual(snapshot.selectedDayStats.correctCardCount, 2)
        XCTAssertEqual(snapshot.selectedDayStats.retryCardCount, 0)
        XCTAssertEqual(snapshot.selectedDayStats.dailyGoal, 30)
        XCTAssertEqual(snapshot.selectedDayStats.newCardsLearned, 1)

        XCTAssertEqual(snapshot.weeklyMomentum.activeDays, 2)
        XCTAssertEqual(snapshot.weeklyMomentum.totalCardsReviewed, 3)
        XCTAssertEqual(snapshot.pastWeekPerformance.scorePercent, 68)
        XCTAssertEqual(snapshot.pastWeekPerformance.previousScorePercent, 0)
        XCTAssertEqual(snapshot.pastWeekPerformance.deltaPercent, 68)
        XCTAssertEqual(snapshot.pastWeekPerformance.trend, .improving)
        XCTAssertEqual(snapshot.pastWeekPerformance.activeDays, 2)
        XCTAssertEqual(snapshot.pastWeekPerformance.currentDaySummaries.count, 7)

        XCTAssertEqual(snapshot.selectedDayBreakdown.deckSummaries.count, 2)
        XCTAssertEqual(snapshot.selectedDayBreakdown.cardsReviewed, 2)
        XCTAssertEqual(snapshot.selectedDayBreakdown.retryCardCount, 0)
        XCTAssertEqual(snapshot.selectedDayBreakdown.deckSummaries.first?.cards.count, 1)
        XCTAssertTrue(
            snapshot.selectedDayBreakdown.deckSummaries.flatMap(\.cards).contains {
                $0.title == "Treaty" && $0.finalDifficulty == .easy
            }
        )
    }

    func testLoadDashboardSnapshotBuildsPastWeekPerformanceSummary() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        let selectedDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 18, hour: 12)))
        let weekStart = try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start)
        let previousWeekStart = try XCTUnwrap(calendar.date(byAdding: .day, value: -7, to: weekStart))

        let container = try makeDashboardContainer(
            with: [
                makeAggregate(
                    date: previousWeekStart,
                    uniqueCardCount: 5,
                    rawReviewCount: 10,
                    landedCount: 2,
                    retryCount: 3,
                    dailyGoal: 10
                ),
                makeAggregate(
                    date: try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: previousWeekStart)),
                    uniqueCardCount: 5,
                    rawReviewCount: 10,
                    landedCount: 2,
                    retryCount: 3,
                    dailyGoal: 10
                )
            ] + (0..<7).map { offset in
                makeAggregate(
                    date: calendar.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart,
                    uniqueCardCount: 10,
                    rawReviewCount: 10,
                    landedCount: 10,
                    retryCount: 0,
                    dailyGoal: 10
                )
            }
        )

        let repository = HomeAnalyticsRepository(container: container)
        let snapshot = await repository.loadDashboardSnapshot(selectedDate: selectedDate, weekStart: weekStart)
        await repository.tearDown()

        XCTAssertEqual(snapshot.pastWeekPerformance.scorePercent, 100)
        XCTAssertEqual(snapshot.pastWeekPerformance.previousScorePercent, 36)
        XCTAssertEqual(snapshot.pastWeekPerformance.deltaPercent, 64)
        XCTAssertEqual(snapshot.pastWeekPerformance.trend, .improving)
        XCTAssertEqual(snapshot.pastWeekPerformance.trendLine, "Improving day by day")
        XCTAssertEqual(snapshot.pastWeekPerformance.accuracyPercent, 100)
        XCTAssertEqual(snapshot.pastWeekPerformance.consistencyPercent, 100)
        XCTAssertEqual(snapshot.pastWeekPerformance.goalCoveragePercent, 100)
        XCTAssertEqual(snapshot.pastWeekPerformance.efficiencyPercent, 100)
        XCTAssertEqual(snapshot.pastWeekPerformance.weekStartDate, weekStart)
        XCTAssertEqual(snapshot.pastWeekPerformance.scoredDayCount, 6)
        XCTAssertEqual(snapshot.pastWeekPerformance.activeDays, 6)
        XCTAssertEqual(snapshot.pastWeekPerformance.goalHitDays, 6)
        XCTAssertEqual(snapshot.pastWeekPerformance.currentDaySummaries.count, 7)
        XCTAssertEqual(snapshot.pastWeekPerformance.previousDaySummaries.count, 7)
        XCTAssertTrue(snapshot.pastWeekPerformance.currentDaySummaries.dropLast().allSatisfy(\.didStudy))
        XCTAssertTrue(snapshot.pastWeekPerformance.currentDaySummaries.dropLast().allSatisfy(\.didReachGoal))
        XCTAssertEqual(snapshot.pastWeekPerformance.currentDaySummaries.last?.cardsReviewed, 0)
        XCTAssertEqual(snapshot.pastWeekPerformance.currentDaySummaries.last?.scorePercent, 0)
    }

    func testLoadDashboardSnapshotBlanksFutureCalendarWeekDays() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        let selectedDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 17, hour: 12)))
        let weekStart = try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start)

        let aggregates: [HomeDailyStudyAggregate] = (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
            if offset >= 5 {
                return makeAggregate(
                    date: date,
                    uniqueCardCount: 30,
                    rawReviewCount: 30,
                    landedCount: 30,
                    retryCount: 0,
                    dailyGoal: 10
                )
            }

            return makeAggregate(
                date: date,
                uniqueCardCount: 10,
                rawReviewCount: 10,
                landedCount: 10,
                retryCount: 0,
                dailyGoal: 10
            )
        }

        let container = try makeDashboardContainer(with: aggregates)
        let repository = HomeAnalyticsRepository(container: container)
        let snapshot = await repository.loadDashboardSnapshot(selectedDate: selectedDate, weekStart: weekStart)
        await repository.tearDown()

        XCTAssertEqual(snapshot.pastWeekPerformance.scorePercent, 100)
        XCTAssertEqual(snapshot.pastWeekPerformance.scoredDayCount, 5)
        XCTAssertEqual(snapshot.pastWeekPerformance.activeDays, 5)
        XCTAssertEqual(snapshot.pastWeekPerformance.currentDaySummaries.count, 7)
        XCTAssertEqual(snapshot.pastWeekPerformance.currentDaySummaries.prefix(5).filter(\.didStudy).count, 5)
        XCTAssertEqual(snapshot.pastWeekPerformance.currentDaySummaries.suffix(2).map(\.cardsReviewed), [0, 0])
        XCTAssertEqual(snapshot.pastWeekPerformance.currentDaySummaries.suffix(2).map(\.didStudy), [false, false])
    }

    func testLoadDashboardSnapshotReturnsEmptyPastWeekPerformanceWindowWithoutActivity() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        let selectedDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 18, hour: 12)))
        let weekStart = try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start)
        let container = try makeDashboardContainer(with: [])

        let repository = HomeAnalyticsRepository(container: container)
        let snapshot = await repository.loadDashboardSnapshot(selectedDate: selectedDate, weekStart: weekStart)
        await repository.tearDown()

        XCTAssertEqual(snapshot.pastWeekPerformance.scorePercent, 0)
        XCTAssertEqual(snapshot.pastWeekPerformance.previousScorePercent, 0)
        XCTAssertEqual(snapshot.pastWeekPerformance.deltaPercent, 0)
        XCTAssertEqual(snapshot.pastWeekPerformance.trendLine, "Needs attention")
        XCTAssertEqual(snapshot.pastWeekPerformance.activeDays, 0)
        XCTAssertEqual(snapshot.pastWeekPerformance.goalHitDays, 0)
        XCTAssertEqual(snapshot.pastWeekPerformance.currentDaySummaries.count, 7)
        XCTAssertEqual(snapshot.pastWeekPerformance.previousDaySummaries.count, 7)
        XCTAssertTrue(snapshot.pastWeekPerformance.currentDaySummaries.allSatisfy { !$0.didStudy && $0.scorePercent == 0 && $0.visualLevel == 0 })
        XCTAssertTrue(snapshot.pastWeekPerformance.previousDaySummaries.allSatisfy { !$0.didStudy && $0.scorePercent == 0 && $0.visualLevel == 0 })
    }

    private func makeDashboardContainer(
        with aggregates: [HomeDailyStudyAggregate]
    ) throws -> ModelContainer {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        for aggregate in aggregates {
            context.insert(aggregate)
        }
        try context.save()
        return container
    }

    private func makeAggregate(
        date: Date,
        uniqueCardCount: Int,
        rawReviewCount: Int,
        landedCount: Int,
        retryCount: Int,
        dailyGoal: Int
    ) -> HomeDailyStudyAggregate {
        HomeDailyStudyAggregate(
            dayDate: date,
            uniqueCardCount: uniqueCardCount,
            rawReviewCount: rawReviewCount,
            landedCount: landedCount,
            retryCount: retryCount,
            xpEarned: uniqueCardCount * 4,
            newCardsLearned: 0,
            dailyGoal: dailyGoal
        )
    }
}
