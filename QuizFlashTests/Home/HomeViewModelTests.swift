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
    func testRefreshDashboardSnapshotBuildsSelectedDayAndWeeklyMomentum() throws {
        let calendar = Calendar(identifier: .gregorian)
        let selectedDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 22)))
        let previousDate = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: selectedDate))

        let selectedLog = DailyActivityLog(date: selectedDate, dailyGoal: 40)
        selectedLog.cardsReviewed = 30
        selectedLog.xpEarnedToday = 120
        selectedLog.newCardsLearned = 6

        let previousLog = DailyActivityLog(date: previousDate, dailyGoal: 20)
        previousLog.cardsReviewed = 24
        previousLog.xpEarnedToday = 80
        previousLog.newCardsLearned = 3

        let profile = UserProfile(totalXP: 1250, currentStreak: 4, longestStreak: 8, lastActiveDate: selectedDate)
        let viewModel = HomeViewModel()

        viewModel.updateLogsCache(logs: [selectedLog, previousLog])
        viewModel.updateExamGoalsCache(goals: [])
        viewModel.refreshDashboardSnapshot(
            selectedDate: selectedDate,
            dailyLogs: [selectedLog, previousLog],
            examGoals: [],
            userProfile: profile
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
        XCTAssertEqual(viewModel.dashboardSnapshot.selectedDayInsight.xpEarned, 120)
        XCTAssertEqual(viewModel.dashboardSnapshot.selectedDayInsight.newCardsLearned, 6)
        XCTAssertTrue(viewModel.dashboardSnapshot.selectedDayInsight.paceLine.contains("3"))
    }

    func testRefreshDashboardSnapshotTracksSelectedDayExamSummaries() throws {
        let calendar = Calendar(identifier: .gregorian)
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
        viewModel.refreshDashboardSnapshot(
            selectedDate: selectedDate,
            dailyLogs: [],
            examGoals: [goal],
            userProfile: nil
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

    func testRefreshDeckHealthSummariesPrioritizesExamLinkedDecksUnderPressure() async throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let calendar = Calendar(identifier: .gregorian)
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 22)))
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))

        let pressuredDeck = DeckModel(title: "Biology Sprint", icon: "cross.case", colorHex: "#FF7A59")
        pressuredDeck.lastOpenedAt = yesterday

        let healthyDeck = DeckModel(title: "History Stable", icon: "books.vertical", colorHex: "#58C27D")
        healthyDeck.lastOpenedAt = today

        let warmupDeck = DeckModel(title: "Spanish Warmup", icon: "character.book.closed", colorHex: "#4C8DFF")

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
        XCTAssertEqual(viewModel.deckHealthSummaries.last?.title, "History Stable")
        XCTAssertEqual(viewModel.deckHealthSummaries.last?.stableCards, 1)
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
        let firstDeck = DeckModel(title: "Deck A", icon: "book", colorHex: "#AAA111")
        let secondDeck = DeckModel(title: "Deck B", icon: "book", colorHex: "#BBB222")
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
        let originalDeck = DeckModel(title: "Original", icon: "book", colorHex: "#AAAAAA")
        let replacementDeck = DeckModel(title: "Replacement", icon: "book", colorHex: "#BBBBBB")
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
        let deck = DeckModel(title: "Deck", icon: "book", colorHex: "#111111")
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
}
