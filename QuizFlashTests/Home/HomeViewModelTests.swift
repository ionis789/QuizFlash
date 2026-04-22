//
//  HomeViewModelTests.swift
//  QuizFlashTests
//
//  Covers folder and exam-goal persistence mutations from Home.
//

import XCTest
import SwiftData
@testable import QuizFlash

@MainActor
final class HomeViewModelTests: XCTestCase {
    func testRefreshDashboardSnapshotBuildsSelectedDayAndWeeklyMomentum() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        let selectedDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 22)))
        let previousDate = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: selectedDate))
        let selectedAggregate = HomeDailyStudyAggregate(
            dayDate: selectedDate,
            uniqueCardCount: 30,
            rawReviewCount: 34,
            landedCount: 24,
            retryCount: 6,
            xpEarned: 120,
            newCardsLearned: 6,
            dailyGoal: 40
        )
        let previousAggregate = HomeDailyStudyAggregate(
            dayDate: previousDate,
            uniqueCardCount: 24,
            rawReviewCount: 24,
            landedCount: 20,
            retryCount: 4,
            xpEarned: 80,
            newCardsLearned: 3,
            dailyGoal: 20
        )

        let profile = UserProfile(totalXP: 1250, currentStreak: 4, longestStreak: 8, lastActiveDate: selectedDate)
        let viewModel = HomeViewModel()
        let container = try makeDashboardContainer(with: [selectedAggregate, previousAggregate])

        viewModel.updateLogsCache(logs: [])
        viewModel.updateExamGoalsCache(goals: [])
        await viewModel.refreshDashboardSnapshot(
            selectedDate: selectedDate,
            weekStart: calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate,
            examGoals: [],
            userProfile: profile,
            container: container,
            analyticsRevision: HomeViewModel.homeAnalyticsFingerprint(for: [selectedAggregate, previousAggregate]),
            deckRevision: 0,
            referenceDate: selectedDate
        )

        XCTAssertEqual(viewModel.dashboardSnapshot.selectedDayOverview.cardsReviewed, 30)
        XCTAssertEqual(viewModel.dashboardSnapshot.selectedDayOverview.dailyGoal, 40)
        XCTAssertEqual(viewModel.dashboardSnapshot.selectedDayOverview.remainingCardsToGoal, 10)
        XCTAssertEqual(viewModel.dashboardSnapshot.selectedDayOverview.xpEarnedToday, 120)
        XCTAssertEqual(viewModel.dashboardSnapshot.selectedDayOverview.streakCount, 4)
        XCTAssertEqual(viewModel.dashboardSnapshot.selectedDayOverview.level, 3)
        XCTAssertEqual(viewModel.dashboardSnapshot.weeklyMomentum.totalCardsReviewed, 54)
        XCTAssertEqual(viewModel.dashboardSnapshot.weeklyMomentum.totalXPEarned, 200)
        XCTAssertEqual(viewModel.dashboardSnapshot.weeklyMomentum.activeDays, 2)
        XCTAssertEqual(viewModel.dashboardSnapshot.weeklyMomentum.goalHitDays, 1)
        XCTAssertEqual(viewModel.dashboardSnapshot.weeklyMomentum.averageCardsPerActiveDay, 27)
        XCTAssertEqual(viewModel.dashboardSnapshot.weeklyMomentum.daySummaries.count, 7)
        XCTAssertEqual(viewModel.dashboardSnapshot.weeklyMomentum.daySummaries.filter(\.isSelectedDay).count, 1)
        XCTAssertEqual(viewModel.dashboardSnapshot.weeklyMomentum.daySummaries.last?.cardsReviewed, 30)
        XCTAssertEqual(viewModel.dashboardSnapshot.pastWeekPerformance.scorePercent, 64)
        XCTAssertEqual(viewModel.dashboardSnapshot.pastWeekPerformance.previousScorePercent, 0)
        XCTAssertEqual(viewModel.dashboardSnapshot.pastWeekPerformance.deltaPercent, 64)
        XCTAssertEqual(viewModel.dashboardSnapshot.pastWeekPerformance.trend, .improving)
        XCTAssertEqual(viewModel.dashboardSnapshot.pastWeekPerformance.trendLine, "Improving day by day")
        XCTAssertEqual(viewModel.dashboardSnapshot.pastWeekPerformance.accuracyPercent, 81)
        XCTAssertEqual(viewModel.dashboardSnapshot.pastWeekPerformance.consistencyPercent, 29)
        XCTAssertEqual(viewModel.dashboardSnapshot.pastWeekPerformance.goalCoveragePercent, 25)
        XCTAssertEqual(viewModel.dashboardSnapshot.pastWeekPerformance.efficiencyPercent, 93)
        XCTAssertEqual(viewModel.dashboardSnapshot.pastWeekPerformance.goalHitDays, 1)
        XCTAssertEqual(viewModel.dashboardSnapshot.pastWeekPerformance.currentDaySummaries.count, 7)
        XCTAssertEqual(viewModel.dashboardSnapshot.selectedDayBreakdown.cardsReviewed, 30)
        XCTAssertEqual(viewModel.dashboardSnapshot.selectedDayInsight.xpEarned, 120)
        XCTAssertEqual(viewModel.dashboardSnapshot.selectedDayInsight.newCardsLearned, 6)
        XCTAssertTrue(viewModel.dashboardSnapshot.selectedDayInsight.paceLine.contains("3"))
    }

    func testRefreshDashboardSnapshotKeepsCalendarWeekAndRevealsSelectedDayWindow() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        let firstSelectedDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 17)))
        let secondSelectedDate = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: firstSelectedDate))
        let weekStart = try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: firstSelectedDate)?.start)

        let aggregates: [HomeDailyStudyAggregate] = (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
            if offset == 5 {
                return HomeDailyStudyAggregate(
                    dayDate: date,
                    uniqueCardCount: 4,
                    rawReviewCount: 10,
                    landedCount: 1,
                    retryCount: 3,
                    xpEarned: 12,
                    newCardsLearned: 0,
                    dailyGoal: 10
                )
            }

            return HomeDailyStudyAggregate(
                dayDate: date,
                uniqueCardCount: 10,
                rawReviewCount: 10,
                landedCount: 10,
                retryCount: 0,
                xpEarned: 40,
                newCardsLearned: 0,
                dailyGoal: 10
            )
        }

        let viewModel = HomeViewModel()
        let container = try makeDashboardContainer(with: aggregates)
        viewModel.updateLogsCache(logs: [])
        viewModel.updateExamGoalsCache(goals: [])

        await viewModel.refreshDashboardSnapshot(
            selectedDate: firstSelectedDate,
            weekStart: weekStart,
            examGoals: [],
            userProfile: nil,
            container: container,
            analyticsRevision: HomeViewModel.homeAnalyticsFingerprint(for: aggregates),
            deckRevision: 0,
            referenceDate: firstSelectedDate
        )

        let firstSummary = viewModel.dashboardSnapshot.pastWeekPerformance

        await viewModel.refreshDashboardSnapshot(
            selectedDate: secondSelectedDate,
            weekStart: weekStart,
            examGoals: [],
            userProfile: nil,
            container: container,
            analyticsRevision: HomeViewModel.homeAnalyticsFingerprint(for: aggregates),
            deckRevision: 0,
            referenceDate: secondSelectedDate
        )

        let secondSummary = viewModel.dashboardSnapshot.pastWeekPerformance

        XCTAssertEqual(firstSummary.windowEndDate, firstSelectedDate)
        XCTAssertEqual(firstSummary.weekStartDate, weekStart)
        XCTAssertEqual(firstSummary.scorePercent, 100)
        XCTAssertEqual(firstSummary.scoredDayCount, 5)
        XCTAssertEqual(firstSummary.activeDays, 5)
        XCTAssertEqual(firstSummary.currentDaySummaries.map(\.cardsReviewed), [10, 10, 10, 10, 10, 0, 0])
        XCTAssertEqual(secondSummary.windowEndDate, secondSelectedDate)
        XCTAssertEqual(secondSummary.weekStartDate, weekStart)
        XCTAssertEqual(secondSummary.scorePercent, 94)
        XCTAssertEqual(secondSummary.scoredDayCount, 6)
        XCTAssertEqual(secondSummary.activeDays, 6)
        XCTAssertLessThan(secondSummary.scorePercent, firstSummary.scorePercent)
        XCTAssertEqual(secondSummary.currentDaySummaries.first?.cardsReviewed, 10)
        XCTAssertEqual(secondSummary.currentDaySummaries.last?.cardsReviewed, 0)
        XCTAssertEqual(secondSummary.currentDaySummaries.map(\.cardsReviewed), [10, 10, 10, 10, 10, 4, 0])
    }

    func testPerformanceDetailSheetPresentationStateTogglesWithoutMutatingSnapshot() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        let selectedDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 18)))
        let aggregate = HomeDailyStudyAggregate(
            dayDate: selectedDate,
            uniqueCardCount: 18,
            rawReviewCount: 20,
            landedCount: 15,
            retryCount: 3,
            xpEarned: 72,
            newCardsLearned: 2,
            dailyGoal: 20
        )

        let viewModel = HomeViewModel()
        let container = try makeDashboardContainer(with: [aggregate])
        viewModel.updateLogsCache(logs: [])
        viewModel.updateExamGoalsCache(goals: [])

        await viewModel.refreshDashboardSnapshot(
            selectedDate: selectedDate,
            weekStart: calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate,
            examGoals: [],
            userProfile: nil,
            container: container,
            analyticsRevision: HomeViewModel.homeAnalyticsFingerprint(for: [aggregate]),
            deckRevision: 0,
            referenceDate: selectedDate
        )

        let snapshotBeforePresentation = viewModel.dashboardSnapshot

        XCTAssertFalse(viewModel.showPerformanceDetailSheet)

        viewModel.presentPerformanceDetail()
        XCTAssertTrue(viewModel.showPerformanceDetailSheet)
        XCTAssertEqual(viewModel.dashboardSnapshot, snapshotBeforePresentation)

        viewModel.dismissPerformanceDetail()
        XCTAssertFalse(viewModel.showPerformanceDetailSheet)
        XCTAssertEqual(viewModel.dashboardSnapshot, snapshotBeforePresentation)
    }

    func testRefreshDashboardSnapshotTracksSelectedDayExamSummaries() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        let selectedDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 10)))
        let goal = ExamGoalModel(
            title: "Bio Quiz",
            note: "Focus on recall",
            date: selectedDate,
            targetWorkload: 25,
            status: .active,
            linkedDecks: []
        )

        let viewModel = HomeViewModel()
        viewModel.updateLogsCache(logs: [])
        viewModel.updateExamGoalsCache(goals: [goal])
        let container = try makeDashboardContainer(with: [])
        await viewModel.refreshDashboardSnapshot(
            selectedDate: selectedDate,
            weekStart: calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate,
            examGoals: [goal],
            userProfile: nil,
            container: container,
            analyticsRevision: 0,
            deckRevision: 0,
            referenceDate: selectedDate
        )

        XCTAssertEqual(viewModel.dashboardSnapshot.selectedDayExamSummaries.count, 1)
        XCTAssertEqual(viewModel.dashboardSnapshot.upcomingExamSummaries.count, 1)
        XCTAssertEqual(viewModel.dashboardSnapshot.selectedDayExamSummaries.first?.title, "Bio Quiz")
        XCTAssertEqual(viewModel.dashboardSnapshot.selectedDayInsight.selectedDayExamCount, 1)
        XCTAssertEqual(viewModel.dashboardSnapshot.examPressure?.goalTitle, "Bio Quiz")
    }

    func testRefreshCalendarInsightsBuildsActivityAndStreakMarkers() throws {
        let calendar = Calendar(identifier: .gregorian)
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 22)))
        let previousDay = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        let twoDaysAgo = try XCTUnwrap(calendar.date(byAdding: .day, value: -2, to: today))

        let todayLog = DailyActivityLog(date: today, dailyGoal: 40)
        todayLog.cardsReviewed = 40
        todayLog.xpEarnedToday = 140

        let previousLog = DailyActivityLog(date: previousDay, dailyGoal: 40)
        previousLog.cardsReviewed = 10
        previousLog.xpEarnedToday = 35

        let goal = ExamGoalModel(
            title: "Chemistry",
            note: "Review formulas",
            date: previousDay,
            targetWorkload: 12,
            status: .active,
            linkedDecks: []
        )

        let profile = UserProfile(
            totalXP: 1500,
            currentStreak: 3,
            longestStreak: 6,
            lastActiveDate: today
        )

        let viewModel = HomeViewModel()
        viewModel.updateLogsCache(logs: [todayLog, previousLog])
        viewModel.updateExamGoalsCache(goals: [goal])
        viewModel.refreshCalendarInsights(
            dailyLogs: [todayLog, previousLog],
            examGoals: [goal],
            userProfile: profile,
            referenceDate: today
        )

        let todayKey = HomeViewModel.dateKeyFormatter.string(from: today)
        let previousKey = HomeViewModel.dateKeyFormatter.string(from: previousDay)
        let twoDaysAgoKey = HomeViewModel.dateKeyFormatter.string(from: twoDaysAgo)

        XCTAssertEqual(viewModel.calendarInsightsCache[todayKey]?.isPerfectDay, true)
        XCTAssertEqual(viewModel.calendarInsightsCache[todayKey]?.isStreakDay, true)
        XCTAssertEqual(viewModel.calendarInsightsCache[previousKey]?.hasExamGoal, true)
        XCTAssertEqual(viewModel.calendarInsightsCache[previousKey]?.hasGoalNote, true)
        XCTAssertEqual(viewModel.calendarInsightsCache[previousKey]?.examGoalCount, 1)
        XCTAssertEqual(viewModel.calendarInsightsCache[twoDaysAgoKey]?.isStreakDay, nil)
    }

    func testGreetingSummaryPrefersRecentDeckResumeContext() async throws {
        let calendar = Calendar(identifier: .gregorian)
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 22, hour: 9)))
        let aggregate = HomeDailyStudyAggregate(
            dayDate: today,
            uniqueCardCount: 18,
            rawReviewCount: 18,
            landedCount: 14,
            retryCount: 4,
            xpEarned: 70,
            newCardsLearned: 0,
            dailyGoal: 40
        )

        let recentDeck = DeckModel(title: "Neuro", colorHex: "#4C8DFF")
        recentDeck.cardCount = 48
        recentDeck.lastOpenedAt = calendar.date(byAdding: .hour, value: -2, to: today)

        let viewModel = HomeViewModel()
        let container = try makeDashboardContainer(with: [aggregate])
        viewModel.updateLogsCache(logs: [])
        viewModel.updateExamGoalsCache(goals: [])
        await viewModel.refreshDashboardSnapshot(
            selectedDate: today,
            weekStart: calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today,
            examGoals: [],
            userProfile: nil,
            container: container,
            analyticsRevision: HomeViewModel.homeAnalyticsFingerprint(for: [aggregate]),
            deckRevision: HomeViewModel.decksFingerprint(for: [recentDeck]),
            referenceDate: today
        )

        let summary = viewModel.greetingSummary(
            userProfile: nil,
            recentDecks: [recentDeck],
            allDeckCount: 1,
            folderCount: 0,
            referenceDate: today
        )
        let locale = AppPreferences.shared.resolvedLocale

        XCTAssertEqual(summary.title, AppLocalization.string("Good morning", locale: locale))
        XCTAssertEqual(summary.subtitle, "Continue where you left off")
        XCTAssertEqual(summary.contextTitle, "Neuro")
        XCTAssertEqual(summary.primaryPill, "48 cards")
        XCTAssertEqual(summary.ctaTitle, "Resume Deck")
        XCTAssertEqual(summary.action, .openDeck(recentDeck.persistentModelID))
        XCTAssertEqual(summary.progressValueText, "22")
        XCTAssertEqual(summary.progressLabel, "To goal")
    }

    func testGreetingSummaryUsesWorkspaceSetupStateWithoutDecks() {
        let viewModel = HomeViewModel()

        let summary = viewModel.greetingSummary(
            userProfile: nil,
            recentDecks: [],
            allDeckCount: 0,
            folderCount: 0,
            referenceDate: Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 3, day: 22, hour: 20)) ?? Date()
        )
        let locale = AppPreferences.shared.resolvedLocale

        XCTAssertEqual(summary.title, AppLocalization.string("Good evening", locale: locale))
        XCTAssertEqual(summary.subtitle, "Build your study space")
        XCTAssertEqual(summary.contextTitle, "Create your first deck")
        XCTAssertEqual(summary.primaryPill, "New workspace")
        XCTAssertEqual(summary.ctaTitle, "Open Create")
        XCTAssertEqual(summary.action, .switchTab(.create))
    }

    func testGreetingSummaryUsesNightGreetingForLateHours() {
        let viewModel = HomeViewModel()

        let summary = viewModel.greetingSummary(
            userProfile: nil,
            recentDecks: [],
            allDeckCount: 0,
            folderCount: 1,
            referenceDate: Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 3, day: 23, hour: 2)) ?? Date()
        )
        let locale = AppPreferences.shared.resolvedLocale

        XCTAssertEqual(summary.title, AppLocalization.string("Good night", locale: locale))
        XCTAssertEqual(summary.primaryPill, "1 folder ready")
    }

    func testGreetingPhaseCoversAllDaySegments() {
        let calendar = Calendar(identifier: .gregorian)

        XCTAssertEqual(
            HomeViewModel.greetingPhase(
                for: calendar.date(from: DateComponents(year: 2026, month: 3, day: 23, hour: 8)) ?? Date()
            ),
            .morning
        )
        XCTAssertEqual(
            HomeViewModel.greetingPhase(
                for: calendar.date(from: DateComponents(year: 2026, month: 3, day: 23, hour: 14)) ?? Date()
            ),
            .afternoon
        )
        XCTAssertEqual(
            HomeViewModel.greetingPhase(
                for: calendar.date(from: DateComponents(year: 2026, month: 3, day: 23, hour: 19)) ?? Date()
            ),
            .evening
        )
        XCTAssertEqual(
            HomeViewModel.greetingPhase(
                for: calendar.date(from: DateComponents(year: 2026, month: 3, day: 23, hour: 1)) ?? Date()
            ),
            .night
        )
    }

    func testTodayFocusSummaryUsesActionFirstSetupWithoutDecks() {
        let viewModel = HomeViewModel()
        let locale = AppPreferences.shared.resolvedLocale

        let summary = viewModel.todayFocusSummary(
            userProfile: nil,
            recentDecks: [],
            allDeckCount: 0,
            folderCount: 0,
            referenceDate: Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 3, day: 23, hour: 9)) ?? Date()
        )

        XCTAssertEqual(summary.eyebrow, AppLocalization.string("Start", locale: locale))
        XCTAssertEqual(summary.title, AppLocalization.string("No deck yet", locale: locale))
        XCTAssertEqual(summary.compactTitle, AppLocalization.string("No deck yet", locale: locale))
        XCTAssertEqual(summary.progressValueText, AppLocalization.string("New", locale: locale))
        XCTAssertEqual(summary.progressLabel, AppLocalization.string("Start", locale: locale))
        XCTAssertEqual(summary.compactDetail, AppLocalization.string("Create Deck", locale: locale))
        XCTAssertEqual(summary.ctaTitle, AppLocalization.string("Create Deck", locale: locale))
        XCTAssertEqual(summary.action, .switchTab(.create))
    }

    func testWorkspaceOnboardingStateRequiresFoldersForMultiDeckWorkspace() {
        let viewModel = HomeViewModel()

        XCTAssertEqual(viewModel.workspaceOnboardingState(allDeckCount: 0, folderCount: 0), .needsDeck)
        XCTAssertEqual(viewModel.workspaceOnboardingState(allDeckCount: 3, folderCount: 0), .needsFolders)
        XCTAssertEqual(viewModel.workspaceOnboardingState(allDeckCount: 1, folderCount: 0), .ready)
        XCTAssertEqual(viewModel.workspaceOnboardingState(allDeckCount: 3, folderCount: 2), .ready)
    }

    func testTodayFocusSummaryPrioritizesResumeDeckWhenRecentDeckExists() async throws {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())
        let aggregate = HomeDailyStudyAggregate(
            dayDate: today,
            uniqueCardCount: 12,
            rawReviewCount: 12,
            landedCount: 10,
            retryCount: 2,
            xpEarned: 50,
            newCardsLearned: 0,
            dailyGoal: 40
        )

        let recentDeck = DeckModel(title: "Roman Law", colorHex: "#4C8DFF")
        recentDeck.cardCount = 86
        recentDeck.lastOpenedAt = calendar.date(byAdding: .hour, value: -11, to: today)

        let viewModel = HomeViewModel()
        let container = try makeDashboardContainer(with: [aggregate])
        viewModel.updateLogsCache(logs: [])
        viewModel.updateExamGoalsCache(goals: [])
        await viewModel.refreshDashboardSnapshot(
            selectedDate: today,
            weekStart: calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today,
            examGoals: [],
            userProfile: nil,
            container: container,
            analyticsRevision: HomeViewModel.homeAnalyticsFingerprint(for: [aggregate]),
            deckRevision: HomeViewModel.decksFingerprint(for: [recentDeck]),
            referenceDate: today
        )

        let summary = viewModel.todayFocusSummary(
            userProfile: nil,
            recentDecks: [recentDeck],
            allDeckCount: 1,
            folderCount: 0,
            referenceDate: today
        )
        let locale = AppPreferences.shared.resolvedLocale
        let expectedDetail = String.localizedStringWithFormat(
            AppLocalization.string("Last opened %@.", locale: locale),
            HomeViewModel.relativeTimeLabel(for: recentDeck.lastOpenedAt ?? today, referenceDate: today)
        )

        XCTAssertEqual(summary.eyebrow, AppLocalization.string("Today goal", locale: locale))
        XCTAssertEqual(summary.title, "Roman Law")
        XCTAssertEqual(summary.compactTitle, "Roman Law")
        XCTAssertEqual(summary.compactDetail, AppLocalization.string("Resume Deck", locale: locale))
        XCTAssertEqual(summary.detail, expectedDetail)
        XCTAssertEqual(summary.ctaTitle, AppLocalization.string("Resume Deck", locale: locale))
        XCTAssertEqual(summary.action, .openDeck(recentDeck.persistentModelID))
    }

    func testRefreshDeckHealthSummariesPrioritizesExamLinkedDecksUnderPressure() async throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let calendar = Calendar(identifier: .gregorian)
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 22)))
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))

        let pressuredDeck = DeckModel(title: "Biology Sprint", colorHex: "#FF7A59")
        pressuredDeck.lastOpenedAt = yesterday

        let healthyDeck = DeckModel(title: "History Stable", colorHex: "#58C27D")
        healthyDeck.lastOpenedAt = today

        let warmupDeck = DeckModel(title: "Spanish Warmup", colorHex: "#4C8DFF")

        context.insert(pressuredDeck)
        context.insert(healthyDeck)
        context.insert(warmupDeck)

        let pressuredDueCard = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.flashcard(front: "Cell", back: "Membrane"),
            cardNumber: 1
        )
        pressuredDueCard.interval = 2
        pressuredDueCard.dueDate = yesterday
        let pressuredReview = ReviewEvent(timeSpent: 3.0, difficulty: .hard, xpAwarded: 8)
        pressuredReview.timestamp = yesterday
        pressuredReview.card = pressuredDueCard

        let pressuredNewCard = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.flashcard(front: "DNA", back: "Replication"),
            cardNumber: 2
        )

        let healthyStableCard = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.flashcard(front: "1918", back: "WWI"),
            cardNumber: 1
        )
        healthyStableCard.interval = 10
        healthyStableCard.dueDate = tomorrow
        let healthyReview = ReviewEvent(timeSpent: 2.0, difficulty: .easy, xpAwarded: 15)
        healthyReview.timestamp = yesterday
        healthyReview.card = healthyStableCard

        let warmupBuildingCard = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.flashcard(front: "Hola", back: "Hello"),
            cardNumber: 1
        )
        warmupBuildingCard.interval = 3
        warmupBuildingCard.dueDate = tomorrow
        let warmupReview = ReviewEvent(timeSpent: 4.0, difficulty: .good, xpAwarded: 10)
        warmupReview.timestamp = yesterday
        warmupReview.card = warmupBuildingCard

        let warmupNewCard = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.flashcard(front: "Gracias", back: "Thank you"),
            cardNumber: 2
        )

        for card in [pressuredDueCard, pressuredNewCard, healthyStableCard, warmupBuildingCard, warmupNewCard] {
            context.insert(card)
        }

        pressuredDeck.cards = [pressuredDueCard, pressuredNewCard]
        pressuredDeck.cardCount = 2
        pressuredDeck.lastAssignedCardNumber = 2

        healthyDeck.cards = [healthyStableCard]
        healthyDeck.cardCount = 1
        healthyDeck.lastAssignedCardNumber = 1

        warmupDeck.cards = [warmupBuildingCard, warmupNewCard]
        warmupDeck.cardCount = 2
        warmupDeck.lastAssignedCardNumber = 2

        let goal = ExamGoalModel(
            title: "Biology Exam",
            note: "High urgency",
            date: tomorrow,
            targetWorkload: 20,
            status: .active,
            linkedDecks: [pressuredDeck]
        )
        context.insert(goal)

        try context.save()

        let viewModel = HomeViewModel()
        viewModel.updateLogsCache(logs: [])
        viewModel.updateExamGoalsCache(goals: [goal])

        await viewModel.refreshDeckHealthSummaries(
            decks: [pressuredDeck, healthyDeck, warmupDeck],
            recentDecks: [healthyDeck],
            examGoals: [goal],
            container: container,
            referenceDate: today
        )

        XCTAssertEqual(viewModel.deckHealthSummaries.count, 3)
        XCTAssertEqual(viewModel.deckHealthSummaries.first?.title, "Biology Sprint")
        XCTAssertEqual(viewModel.deckHealthSummaries.first?.linkedGoalCount, 1)
        XCTAssertEqual(viewModel.deckHealthSummaries.first?.dueCards, 1)
        XCTAssertEqual(viewModel.deckHealthSummaries.first?.newCards, 1)
        XCTAssertEqual(viewModel.deckHealthSummaries.first?.headline, "Exam-linked and under pressure")

        let stableSummary = try XCTUnwrap(
            viewModel.deckHealthSummaries.first(where: { $0.title == "History Stable" })
        )
        XCTAssertEqual(stableSummary.title, "History Stable")
    }

    func testCreateFolderPersistsFolderAndResetsDraftState() throws {
        let context = try TestModelContainerFactory.makeContext()
        let viewModel = HomeViewModel()

        viewModel.newFolderTitle = "  Medical  "
        viewModel.newFolderColorHex = "#123456"
        viewModel.showCreateFolder = true
        viewModel.createFolder(context: context)

        let folders = try context.fetchAll(FolderModel.self)
        XCTAssertEqual(folders.count, 1)
        XCTAssertEqual(folders.first?.title, "Medical")
        XCTAssertEqual(folders.first?.colorHex, "#123456")
        XCTAssertEqual(viewModel.newFolderTitle, "")
        XCTAssertFalse(viewModel.showCreateFolder)
    }

    func testSaveExamGoalCreatesLinkedGoal() throws {
        let context = try TestModelContainerFactory.makeContext()
        let firstDeck = DeckModel(title: "Deck A", colorHex: "#AAA111")
        let secondDeck = DeckModel(title: "Deck B", colorHex: "#BBB222")
        context.insert(firstDeck)
        context.insert(secondDeck)
        try context.save()

        let viewModel = HomeViewModel()
        viewModel.presentCreateExamGoal()
        viewModel.newExamGoalTitle = "Final Exam"
        viewModel.newExamGoalNote = "High priority"
        viewModel.newExamGoalTargetWorkload = 45
        viewModel.toggleExamGoalDeckSelection(firstDeck.persistentModelID)
        viewModel.toggleExamGoalDeckSelection(secondDeck.persistentModelID)

        viewModel.saveExamGoal(
            context: context,
            availableDecks: [firstDeck, secondDeck],
            editingGoal: nil
        )

        let goals = try context.fetchAll(ExamGoalModel.self)
        XCTAssertEqual(goals.count, 1)

        let goal = try XCTUnwrap(goals.first)
        XCTAssertEqual(goal.title, "Final Exam")
        XCTAssertEqual(goal.note, "High priority")
        XCTAssertEqual(goal.status, .active)
        XCTAssertEqual(goal.targetWorkload, 45)
        XCTAssertEqual(Set(goal.linkedDecks.map(\.persistentModelID)), [firstDeck.persistentModelID, secondDeck.persistentModelID])
        XCTAssertNil(viewModel.examGoalSheetPresentation)
        XCTAssertTrue(viewModel.newExamGoalLinkedDeckIDs.isEmpty)
    }

    func testSaveExamGoalEditsExistingGoalAndStatus() throws {
        let context = try TestModelContainerFactory.makeContext()
        let originalDeck = DeckModel(title: "Original", colorHex: "#AAAAAA")
        let replacementDeck = DeckModel(title: "Replacement", colorHex: "#BBBBBB")
        let goal = ExamGoalModel(
            title: "Exam",
            note: "Old note",
            date: Date(),
            targetWorkload: 20,
            status: .active,
            linkedDecks: []
        )
        context.insert(originalDeck)
        context.insert(replacementDeck)
        context.insert(goal)
        goal.linkedDecks = [originalDeck]
        try context.save()

        let viewModel = HomeViewModel()
        viewModel.presentExamGoalEditor(for: goal)
        viewModel.newExamGoalTitle = "Edited Exam"
        viewModel.newExamGoalNote = "Updated note"
        viewModel.newExamGoalTargetWorkload = 60
        viewModel.newExamGoalStatus = .completed
        viewModel.newExamGoalLinkedDeckIDs = [replacementDeck.persistentModelID]

        viewModel.saveExamGoal(
            context: context,
            availableDecks: [originalDeck, replacementDeck],
            editingGoal: goal
        )

        XCTAssertEqual(goal.title, "Edited Exam")
        XCTAssertEqual(goal.note, "Updated note")
        XCTAssertEqual(goal.targetWorkload, 60)
        XCTAssertEqual(goal.status, .completed)
        XCTAssertEqual(goal.linkedDecks.map(\.persistentModelID), [replacementDeck.persistentModelID])
    }

    func testUpdateExamGoalStatusPersistsStatusMutation() throws {
        let context = try TestModelContainerFactory.makeContext()
        let deck = DeckModel(title: "Deck", colorHex: "#111111")
        let goal = ExamGoalModel(
            title: "Status Goal",
            note: "",
            date: Date(),
            targetWorkload: 15,
            status: .active,
            linkedDecks: []
        )
        context.insert(deck)
        context.insert(goal)
        goal.linkedDecks = [deck]
        try context.save()

        let viewModel = HomeViewModel()
        viewModel.updateExamGoalStatus(.archived, for: goal, context: context)

        XCTAssertEqual(goal.status, .archived)
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
}
