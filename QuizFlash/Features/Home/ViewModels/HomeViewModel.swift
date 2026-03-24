// HomeViewModel.swift
// QuizFlash
//
// Manages UI state and business logic exclusively for the Home screen.
//
// Responsibilities:
//   - O(1) daily log lookups via a keyed cache dictionary
//   - Static date-formatting utilities consumed by Home Views
//   - Sheet presentation state (create folder)
//   - Folder creation coordinated with the SwiftData model context
//
// Explicitly NOT responsible for:
//   - Calendar navigation or date selection (owned by CalendarViewModel)
//   - Scroll geometry (computed inline in HomeView)

import SwiftUI
import SwiftData

// MARK: - Exam Goal Sheet Presentation

/// Modal presentation state for the reusable Home exam-goal editor.
enum ExamGoalSheetPresentation: Identifiable, Equatable {
    case create
    case edit(PersistentIdentifier)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .edit(let goalID):
            return "edit-\(goalID.hashValue)"
        }
    }
}

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
    let dailyGoal: Int
    let goalCompletionFraction: Double
    let remainingCardsToGoal: Int
    let xpEarnedToday: Int
    let newCardsLearned: Int
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

/// Seven-day momentum rollup that lets Home render weekly trend cards cheaply.
struct HomeWeeklyDaySummary: Identifiable, Equatable {
    let id: String
    let date: Date
    let shortWeekday: String
    let cardsReviewed: Int
    let xpEarned: Int
    let goal: Int
    let intensityFraction: Double
    let didStudy: Bool
    let didReachGoal: Bool
    let isSelectedDay: Bool
}

/// Seven-day momentum rollup that lets Home render weekly trend cards cheaply.
struct HomeWeeklyMomentumSummary: Equatable {
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
    let icon: String
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
    let examPressure: HomeExamPressureSummary?
    let selectedDayExamSummaries: [HomeExamGoalSummary]
    let upcomingExamSummaries: [HomeExamGoalSummary]
    let examNarrative: HomeDashboardNarrative?

    static func placeholder(referenceDate: Date = Date()) -> HomeDashboardSnapshot {
        let overview = HomeSelectedDayOverviewSummary(
            selectedDate: referenceDate,
            selectedDateLabel: "Today",
            cardsReviewed: 0,
            dailyGoal: 50,
            goalCompletionFraction: 0,
            remainingCardsToGoal: 50,
            xpEarnedToday: 0,
            newCardsLearned: 0,
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

        return HomeDashboardSnapshot(
            selectedDayOverview: overview,
            selectedDayInsight: selectedDayInsight,
            weeklyMomentum: weeklyMomentum,
            examPressure: nil,
            selectedDayExamSummaries: [],
            upcomingExamSummaries: [],
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
    let icon: String
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
    let icon: String
    let colorHex: String
    let primaryPill: String
    let secondaryPill: String?
    let progressFraction: Double
    let progressValueText: String
    let progressLabel: String
    let ctaTitle: String?
    let action: HomeGreetingAction?
}

// MARK: - Home View Model

/// The single source of truth for all business logic on the Home screen.
///
/// Instantiate once in `HomeView` with `@State` and pass to child views
/// as a plain `let` constant so SwiftUI can track observation automatically.
///
/// ```swift
/// @State private var viewModel = HomeViewModel()
/// ```
@Observable
@MainActor
final class HomeViewModel {

    // MARK: - Sheet State

    /// Controls the visibility of the Create Folder bottom sheet.
    var showCreateFolder: Bool = false

    /// Bound to the text field inside `CreateFolderSheet`.
    var newFolderTitle: String = ""

    /// The hex colour chosen in the Create Folder colour picker. Defaults to system green.
    var newFolderColorHex: String = "#34C759"

    /// Active Home exam-goal sheet presentation, reused for both create and edit flows.
    var examGoalSheetPresentation: ExamGoalSheetPresentation?

    /// Bound to the title field inside the reusable exam-goal editor sheet.
    var newExamGoalTitle: String = ""

    /// Bound to the optional notes field inside the reusable exam-goal editor sheet.
    var newExamGoalNote: String = ""

    /// Bound to the target date picker inside the reusable exam-goal editor sheet.
    var newExamGoalDate: Date = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()

    /// Bound to the daily workload stepper inside the reusable exam-goal editor sheet.
    var newExamGoalTargetWorkload: Int = 30

    /// Bound to the status picker when editing an existing exam goal.
    var newExamGoalStatus: ExamGoalStatus = .active

    /// Persistent identifiers of decks selected in the create/edit goal sheet.
    var newExamGoalLinkedDeckIDs: Set<PersistentIdentifier> = []

    // MARK: - Logs Cache

    /// Activity logs keyed by ISO-8601 date string (`yyyy-MM-dd`) for O(1) lookups.
    ///
    /// Rebuilt whenever the `dailyLogs` SwiftData query result changes in `HomeView`.
    var logsCache: [String: DailyActivityLog] = [:]

    /// Exam goals keyed by day string (`yyyy-MM-dd`) for Home calendar markers.
    var examGoalsCache: [String: [ExamGoalModel]] = [:]

    /// Signature of the latest cached daily-log input.
    private var logsCacheSignature: [String] = []

    /// Signature of the latest cached exam-goal input.
    private var examGoalsCacheSignature: [String] = []

    /// Cached Home analytics snapshot consumed by `HomeDashboardView`.
    private(set) var dashboardSnapshot: HomeDashboardSnapshot = .placeholder()

    /// Signature used to skip rebuilding Home dashboard summaries when inputs are unchanged.
    private var dashboardSnapshotSignature: String = ""

    /// Cached per-day insight payloads consumed by the Home calendar.
    private(set) var calendarInsightsCache: [String: HomeCalendarDayInsight] = [:]

    /// Signature used to skip rebuilding Home calendar insight payloads when inputs are unchanged.
    private var calendarInsightsSignature: String = ""

    /// Cached deck-health summaries shown on the Home dashboard.
    private(set) var deckHealthSummaries: [HomeDeckHealthSummary] = []

    /// Signature used to skip rebuilding deck-health summaries when the inputs are unchanged.
    private var deckHealthSignature: String = ""

    // MARK: - Static Formatters

    /// Converts a `Date` to the cache key format `yyyy-MM-dd`.
    ///
    /// Declared `static` so the formatter is allocated exactly once for the app's lifetime.
    static let dateKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - Cache Management

    /// Rebuilds `logsCache` from the latest SwiftData query results.
    ///
    /// The guard clause skips the rebuild when the count hasn't changed,
    /// preventing a forced re-render cycle on every tab return.
    ///
    /// - Parameter logs: The updated array from the `@Query` in `HomeView`.
    func updateLogsCache(logs: [DailyActivityLog]) {
        let signature = logs
            .map { "\($0.dateString)-\($0.cardsReviewed)-\($0.xpEarnedToday)-\($0.newCardsLearned)-\($0.dailyGoal)" }
            .sorted()
        guard logsCacheSignature != signature else { return }
        logsCacheSignature = signature

        var dict = [String: DailyActivityLog](minimumCapacity: logs.count)
        for log in logs {
            dict[log.dateString] = log
        }
        logsCache = dict
    }

    /// Rebuilds `examGoalsCache` so the Home calendar can mark exam days and notes in O(1).
    ///
    /// - Parameter goals: The current exam-goal query result from `HomeView`.
    func updateExamGoalsCache(goals: [ExamGoalModel]) {
        let signature = goals
            .map {
                [
                    "\($0.persistentModelID.hashValue)",
                    Self.dateKeyFormatter.string(from: $0.date),
                    $0.statusRaw,
                    $0.title,
                    $0.note,
                    "\($0.linkedDecks.count)",
                    "\($0.targetWorkload)"
                ].joined(separator: "|")
            }
            .sorted()
        guard examGoalsCacheSignature != signature else { return }
        examGoalsCacheSignature = signature

        var dict: [String: [ExamGoalModel]] = [:]
        for goal in goals {
            let key = Self.dateKeyFormatter.string(from: goal.date)
            dict[key, default: []].append(goal)
        }
        examGoalsCache = dict
    }

    /// Returns the activity log for a given date, or `nil` if none exists.
    ///
    /// - Parameter date: The date to look up.
    /// - Returns: The matching `DailyActivityLog`, or `nil`.
    func getFastLog(for date: Date) -> DailyActivityLog? {
        logsCache[HomeViewModel.dateKeyFormatter.string(from: date)]
    }

    /// Returns all exam goals that land on the provided calendar day.
    ///
    /// - Parameter date: The day shown in the Home calendar or dashboard.
    /// - Returns: The matching exam goals in stable time order.
    func examGoals(for date: Date) -> [ExamGoalModel] {
        let key = HomeViewModel.dateKeyFormatter.string(from: date)
        return (examGoalsCache[key] ?? [])
            .filter { $0.status != .archived }
            .sorted { $0.date < $1.date }
    }

    // MARK: - Formatting Utilities

    /// Returns a concise relative time label for a past date.
    ///
    /// Examples: `"just now"`, `"5m ago"`, `"3h ago"`, `"2d ago"`, `"1mo ago"`.
    ///
    /// The label is computed **once** at call time and does not update automatically.
    /// This is intentional — it avoids the `Text(.relative)` re-render trap where
    /// every card in a scroll view refreshes itself every second via SwiftUI's timer.
    ///
    /// - Parameter date: The past date to describe.
    /// - Returns: A human-readable relative time string.
    static func relativeTimeLabel(for date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        switch seconds {
        case ..<60:        return "just now"
        case ..<3_600:     return "\(seconds / 60)m ago"
        case ..<86_400:    return "\(seconds / 3_600)h ago"
        case ..<2_592_000: return "\(seconds / 86_400)d ago"
        default:           return "\(seconds / 2_592_000)mo ago"
        }
    }

    /// Human-readable label used in Home exam-goal cards.
    ///
    /// Examples: `"Today"`, `"In 5 days"`, `"Tomorrow"`, `"2 days ago"`.
    ///
    /// - Parameters:
    ///   - date: Goal date to describe.
    ///   - referenceDate: Clock used for the countdown. Defaults to now.
    /// - Returns: A short countdown label.
    static func countdownLabel(for date: Date, referenceDate: Date = Date()) -> String {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: referenceDate)
        let target = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: start, to: target).day ?? 0

        switch days {
        case 0:
            return "Today"
        case 1:
            return "Tomorrow"
        case let value where value > 1:
            return "In \(value) days"
        case -1:
            return "Yesterday"
        default:
            return "\(-days) days ago"
        }
    }

    /// Returns a medium-style date label for Home exam-goal cards.
    static func mediumDateLabel(for date: Date) -> String {
        mediumDateFormatter.string(from: date)
    }

    /// Builds Home-friendly summaries for the nearest active exam goals.
    ///
    /// - Parameters:
    ///   - goals: The full exam-goal query result.
    ///   - referenceDate: Clock used for countdown and workload calculations.
    ///   - limit: Maximum number of summaries to return.
    /// - Returns: The next active, non-archived exam-goal summaries.
    func upcomingExamGoalSummaries(
        from goals: [ExamGoalModel],
        referenceDate: Date = Date(),
        limit: Int = 3
    ) -> [HomeExamGoalSummary] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: referenceDate)

        return goals
            .filter { goal in
                goal.status == .active &&
                calendar.startOfDay(for: goal.date) >= today
            }
            .sorted {
                if $0.date != $1.date { return $0.date < $1.date }
                return $0.createdAt < $1.createdAt
            }
            .prefix(limit)
            .map { buildExamGoalSummary(for: $0, referenceDate: referenceDate) }
    }

    /// Builds summaries for all exam goals visible on the selected Home day.
    ///
    /// - Parameter date: The selected calendar day.
    /// - Returns: Stable summaries sorted by time within the day.
    func selectedDayExamGoalSummaries(for date: Date) -> [HomeExamGoalSummary] {
        examGoals(for: date)
            .map { buildExamGoalSummary(for: $0, referenceDate: date) }
    }

    /// Refreshes the cached dashboard snapshot that backs the Home screen.
    ///
    /// This keeps heavier summary work out of SwiftUI render passes while still
    /// reacting to the selected day, logs, goals, and profile changes.
    func refreshDashboardSnapshot(
        selectedDate: Date,
        dailyLogs: [DailyActivityLog],
        examGoals: [ExamGoalModel],
        userProfile: UserProfile?
    ) {
        let signature = buildDashboardSnapshotSignature(
            selectedDate: selectedDate,
            userProfile: userProfile
        )
        guard dashboardSnapshotSignature != signature else { return }
        dashboardSnapshotSignature = signature

        let selectedDayOverview = buildSelectedDayOverview(
            for: selectedDate,
            userProfile: userProfile
        )
        let weeklyMomentum = buildWeeklyMomentumSummary(
            selectedDate: selectedDate,
            dailyLogs: dailyLogs
        )
        let selectedDayExamSummaries = selectedDayExamGoalSummaries(for: selectedDate)
        let upcomingExamSummaries = upcomingExamGoalSummaries(from: examGoals)

        dashboardSnapshot = HomeDashboardSnapshot(
            selectedDayOverview: selectedDayOverview,
            selectedDayInsight: buildSelectedDayInsightSummary(
                selectedDate: selectedDate,
                selectedDayOverview: selectedDayOverview,
                selectedDayExamSummaries: selectedDayExamSummaries,
                upcomingExamSummaries: upcomingExamSummaries,
                weeklyMomentum: weeklyMomentum
            ),
            weeklyMomentum: weeklyMomentum,
            examPressure: buildExamPressureSummary(from: upcomingExamSummaries),
            selectedDayExamSummaries: selectedDayExamSummaries,
            upcomingExamSummaries: upcomingExamSummaries,
            examNarrative: buildDashboardNarrative(
                goals: examGoals,
                dailyLogs: dailyLogs,
                userProfile: userProfile
            )
        )
    }

    /// Refreshes cached insight payloads used by the Home calendar cells.
    ///
    /// The resulting dictionary is keyed by the same `yyyy-MM-dd` format as
    /// `logsCache`, allowing the sticky calendar header to render purely from
    /// O(1) lookups instead of deriving state inside each cell.
    func refreshCalendarInsights(
        dailyLogs: [DailyActivityLog],
        examGoals: [ExamGoalModel],
        userProfile: UserProfile?,
        referenceDate: Date = Date()
    ) {
        let signature = buildCalendarInsightsSignature(
            userProfile: userProfile,
            referenceDate: referenceDate
        )
        guard calendarInsightsSignature != signature else { return }
        calendarInsightsSignature = signature

        let streakDates = buildActiveStreakDateKeys(
            userProfile: userProfile,
            referenceDate: referenceDate
        )
        let activeGoalsByDay = Dictionary(grouping: examGoals.filter { $0.status != .archived }) {
            Self.dateKeyFormatter.string(from: $0.date)
        }

        var insights: [String: HomeCalendarDayInsight] = [:]
        insights.reserveCapacity(max(dailyLogs.count, examGoals.count))

        for log in dailyLogs {
            let key = log.dateString
            insights[key] = buildCalendarDayInsight(
                key: key,
                date: log.date,
                log: log,
                goals: activeGoalsByDay[key] ?? [],
                streakDates: streakDates
            )
        }

        for goal in examGoals where goal.status != .archived {
            let key = Self.dateKeyFormatter.string(from: goal.date)
            if insights[key] != nil { continue }
            insights[key] = buildCalendarDayInsight(
                key: key,
                date: goal.date,
                log: nil,
                goals: activeGoalsByDay[key] ?? [],
                streakDates: streakDates
            )
        }

        calendarInsightsCache = insights
    }

    /// Refreshes the Home deck-health summaries using the background play-mode repository.
    ///
    /// This keeps heavy card reads off the main actor while still surfacing a concise
    /// "what needs attention" list on Home.
    func refreshDeckHealthSummaries(
        decks: [DeckModel],
        recentDecks: [DeckModel],
        examGoals: [ExamGoalModel],
        container: ModelContainer,
        referenceDate: Date = Date()
    ) async {
        let signature = buildDeckHealthSignature(
            decks: decks,
            recentDecks: recentDecks,
            examGoals: examGoals,
            referenceDate: referenceDate
        )
        guard deckHealthSignature != signature else { return }
        deckHealthSignature = signature

        let goalCounts = activeExamGoalDeckCounts(
            from: examGoals,
            referenceDate: referenceDate
        )
        let recentDeckIDs = Set(recentDecks.map(\.persistentModelID))
        let candidates = prioritizedDeckHealthCandidates(
            from: decks,
            recentDeckIDs: recentDeckIDs,
            goalCounts: goalCounts
        )

        guard !candidates.isEmpty else {
            deckHealthSummaries = []
            return
        }

        let repository = PlayModeCardRepository(container: container)
        var ranked: [(summary: HomeDeckHealthSummary, riskScore: Double)] = []
        ranked.reserveCapacity(candidates.count)

        for deck in candidates {
            let report = await repository.loadLearnReport(for: deck.persistentModelID)
            guard report.totalCards > 0 else { continue }

            let summary = buildDeckHealthSummary(
                for: deck,
                report: report,
                linkedGoalCount: goalCounts[deck.persistentModelID] ?? 0,
                isRecentlyOpened: recentDeckIDs.contains(deck.persistentModelID)
            )
            ranked.append((summary, deckHealthRiskScore(for: summary)))
        }

        await repository.tearDown()

        deckHealthSummaries = ranked
            .sorted { lhs, rhs in
                if lhs.riskScore != rhs.riskScore { return lhs.riskScore > rhs.riskScore }
                if lhs.summary.linkedGoalCount != rhs.summary.linkedGoalCount {
                    return lhs.summary.linkedGoalCount > rhs.summary.linkedGoalCount
                }
                return lhs.summary.totalCards > rhs.summary.totalCards
            }
            .prefix(3)
            .map(\.summary)
    }

    /// Produces the short narrative lines shown above the Home exam-goal cards.
    ///
    /// The narrative intentionally stays short and action-oriented rather than
    /// motivational. It uses current goal pressure plus recent activity logs.
    func buildDashboardNarrative(
        goals: [ExamGoalModel],
        dailyLogs: [DailyActivityLog],
        userProfile: UserProfile?,
        referenceDate: Date = Date()
    ) -> HomeDashboardNarrative? {
        let summaries = upcomingExamGoalSummaries(from: goals, referenceDate: referenceDate, limit: 6)
        guard !summaries.isEmpty else { return nil }

        let riskGoal = summaries.max { lhs, rhs in
            riskScore(for: lhs) < riskScore(for: rhs)
        }
        let closestWinGoal = summaries.max { lhs, rhs in
            lhs.readinessFraction < rhs.readinessFraction
        }

        let sevenDayStart = Calendar.current.date(byAdding: .day, value: -6, to: referenceDate) ?? referenceDate
        let recentLogs = dailyLogs.filter { $0.date >= sevenDayStart }
        let recentStudyDays = recentLogs.filter { $0.cardsReviewed > 0 }.count

        let riskLine: String?
        if let riskGoal, let weakestDeck = riskGoal.weakestDeck {
            riskLine = "Risk deck: \(weakestDeck.title) for \(riskGoal.title) has \(weakestDeck.remainingCards) cards still needing work."
        } else {
            riskLine = nil
        }

        let closestWinLine: String?
        if let closestWinGoal {
            closestWinLine = "Closest win: \(closestWinGoal.title) is at \(Int((closestWinGoal.readinessFraction * 100).rounded()))% readiness."
        } else {
            closestWinLine = nil
        }

        let nextBestActionLine: String?
        if let riskGoal, let weakestDeck = riskGoal.weakestDeck {
            let streakText: String
            if let userProfile, userProfile.currentStreak > 0 {
                streakText = " Keep the \(userProfile.currentStreak)-day streak alive."
            } else {
                streakText = ""
            }

            nextBestActionLine = "Next best action: review \(max(riskGoal.dailyPaceNeeded, 1)) cards/day in \(weakestDeck.title). \(recentStudyDays)/7 recent study days.\(streakText)"
        } else {
            nextBestActionLine = nil
        }

        return HomeDashboardNarrative(
            riskDeckLine: riskLine,
            closestWinLine: closestWinLine,
            nextBestActionLine: nextBestActionLine
        )
    }

    /// Builds the lightweight greeting widget summary shown at the top of Home.
    ///
    /// The greeting prefers the most recent deck, then falls back to the highest-priority
    /// deck-health candidate, and finally uses today's dashboard context when no deck
    /// destination is available.
    func workspaceOnboardingState(
        allDeckCount: Int,
        folderCount: Int
    ) -> HomeWorkspaceOnboardingState {
        if allDeckCount == 0 {
            return .needsDeck
        }

        if folderCount == 0 && allDeckCount > 1 {
            return .needsFolders
        }

        return .ready
    }

    /// Builds the custom iPad companion summary that mirrors the sticky calendar behaviour.
    func todayFocusSummary(
        userProfile: UserProfile?,
        recentDecks: [DeckModel],
        allDeckCount: Int,
        folderCount: Int,
        referenceDate: Date = Date()
    ) -> HomeTodayFocusHeaderSummary {
        let overview = dashboardSnapshot.selectedDayOverview
        let workspaceState = workspaceOnboardingState(
            allDeckCount: allDeckCount,
            folderCount: folderCount
        )
        let greetingTitle = Self.greetingPhase(for: referenceDate).title

        if workspaceState == .needsDeck {
            return HomeTodayFocusHeaderSummary(
                introTitle: greetingTitle,
                introSubtitle: "Create your first deck to begin.",
                eyebrow: "Start",
                title: "No deck yet",
                detail: "Create a deck to start studying from Home.",
                compactTitle: "No deck yet",
                compactDetail: "Create Deck",
                icon: "rectangle.stack.badge.plus",
                colorHex: "",
                primaryPill: "",
                secondaryPill: nil,
                progressFraction: 0,
                progressValueText: "New",
                progressLabel: "Start",
                ctaTitle: "Create Deck",
                action: .switchTab(.create)
            )
        }

        if let recentDeck = recentDecks.first {
            let deckTitle = recentDeck.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedTitle = deckTitle.isEmpty ? "Untitled Deck" : deckTitle
            let matchingHealth = deckHealthSummaries.first { $0.id == recentDeck.persistentModelID }
            let remainingCards = max(overview.remainingCardsToGoal, 0)
            let detail: String

            if overview.didReachGoal {
                detail = "Today's goal is closed."
            } else if let lastOpenedAt = recentDeck.lastOpenedAt {
                detail = "Last opened \(Self.relativeTimeLabel(for: lastOpenedAt))."
            } else if let matchingHealth {
                let deckPressure = matchingHealth.dueCards + matchingHealth.newCards
                if deckPressure > 0 {
                    detail = "\(min(deckPressure, max(remainingCards, 1))) cards are ready."
                } else {
                    detail = "\(remainingCards) cards are still open today."
                }
            } else {
                detail = "\(remainingCards) cards are still open today."
            }

            return HomeTodayFocusHeaderSummary(
                introTitle: greetingTitle,
                introSubtitle: "Continue where you left off.",
                eyebrow: overview.didReachGoal ? "Today clear" : "Today goal",
                title: resolvedTitle,
                detail: detail,
                compactTitle: resolvedTitle,
                compactDetail: "Resume Deck",
                icon: recentDeck.icon,
                colorHex: recentDeck.colorHex,
                primaryPill: "",
                secondaryPill: nil,
                progressFraction: overview.goalCompletionFraction,
                progressValueText: overview.didReachGoal ? "Done" : "\(remainingCards)",
                progressLabel: overview.didReachGoal ? "Today" : "To goal",
                ctaTitle: "Resume Deck",
                action: .openDeck(recentDeck.persistentModelID)
            )
        }

        if let focusDeck = deckHealthSummaries.first {
            let remainingCards = max(overview.remainingCardsToGoal, 0)
            let focusTitle = focusDeck.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Focus deck"
                : focusDeck.title

            return HomeTodayFocusHeaderSummary(
                introTitle: greetingTitle,
                introSubtitle: overview.cardsReviewed == 0
                    ? "Start today's goal from this deck."
                    : "Continue where you left off.",
                eyebrow: overview.didReachGoal ? "Today clear" : "Today goal",
                title: focusTitle,
                detail: overview.cardsReviewed == 0
                    ? "Open this deck to start today's goal."
                    : "\(remainingCards) cards are still open today.",
                compactTitle: focusTitle,
                compactDetail: "Open Deck",
                icon: focusDeck.icon,
                colorHex: focusDeck.colorHex,
                primaryPill: "",
                secondaryPill: nil,
                progressFraction: overview.goalCompletionFraction,
                progressValueText: overview.didReachGoal ? "Done" : "\(remainingCards)",
                progressLabel: overview.didReachGoal ? "Today" : "To goal",
                ctaTitle: "Open Focus Deck",
                action: .openDeck(focusDeck.id)
            )
        }

        let totalXP = max(userProfile?.totalXP ?? 0, 0)
        let secondaryPill = totalXP > 0 ? "\(totalXP) XP" : nil

        return HomeTodayFocusHeaderSummary(
            introTitle: greetingTitle,
            introSubtitle: overview.didReachGoal
                ? "Today is already closed."
                : "Pick a deck and continue.",
            eyebrow: overview.didReachGoal ? "Today clear" : "Today goal",
            title: Self.greetingPhase(for: referenceDate) == .night ? "Pick a deck for tonight" : "Pick a deck for today",
            detail: overview.didReachGoal
                ? "Today's goal is already closed."
                : "\(overview.remainingCardsToGoal) cards are still open today.",
            compactTitle: overview.didReachGoal ? "Today is clear" : "Pick a deck",
            compactDetail: "Open Home",
            icon: "sparkles.rectangle.stack.fill",
            colorHex: "",
            primaryPill: overview.didReachGoal ? "Goal closed" : "\(overview.remainingCardsToGoal) left",
            secondaryPill: secondaryPill,
            progressFraction: overview.goalCompletionFraction,
            progressValueText: overview.didReachGoal ? "Done" : "\(overview.remainingCardsToGoal)",
            progressLabel: overview.didReachGoal ? "Today" : "To goal",
            ctaTitle: nil,
            action: nil
        )
    }

    func greetingSummary(
        userProfile: UserProfile?,
        recentDecks: [DeckModel],
        allDeckCount: Int,
        folderCount: Int,
        referenceDate: Date = Date()
    ) -> HomeGreetingSummary {
        let greetingTitle = Self.greetingPhase(for: referenceDate).title
        let overview = dashboardSnapshot.selectedDayOverview
        let workspaceState = workspaceOnboardingState(
            allDeckCount: allDeckCount,
            folderCount: folderCount
        )

        if workspaceState == .needsDeck {
            return HomeGreetingSummary(
                title: greetingTitle,
                subtitle: "Build your study space",
                contextTitle: "Create your first deck",
                contextLine: "Add one deck and Home will start surfacing progress, momentum and recall cues here.",
                icon: "rectangle.stack.badge.plus",
                colorHex: "",
                primaryPill: folderCount == 0
                    ? "New workspace"
                    : "\(folderCount) folder\(folderCount == 1 ? "" : "s") ready",
                secondaryPill: nil,
                progressFraction: 0,
                progressValueText: "New",
                progressLabel: "Setup",
                ctaTitle: "Open Create",
                action: .switchTab(.create)
            )
        }

        if let recentDeck = recentDecks.first {
            let deckTitle = recentDeck.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedTitle = deckTitle.isEmpty ? "Untitled Deck" : deckTitle
            let matchingHealth = deckHealthSummaries.first { $0.id == recentDeck.persistentModelID }
            let contextLine: String
            let progressFraction: Double
            let progressValueText: String
            let progressLabel: String

            if let matchingHealth {
                let remainingCards = matchingHealth.dueCards + matchingHealth.newCards
                contextLine = remainingCards == 0
                    ? "This deck looks stable right now. A short pass keeps recall warm."
                    : "\(remainingCards) cards still need attention in this deck."
                progressFraction = matchingHealth.masteryFraction
                progressValueText = "\(Int((matchingHealth.masteryFraction * 100).rounded()))%"
                progressLabel = "Mastery"
            } else if overview.didReachGoal {
                contextLine = "Today's target is already clear. A short review keeps the streak moving."
                progressFraction = overview.goalCompletionFraction
                progressValueText = "Done"
                progressLabel = "Today"
            } else {
                contextLine = "This deck is the cleanest way back into a focused pass without hunting around the library."
                progressFraction = overview.goalCompletionFraction
                progressValueText = "\(overview.remainingCardsToGoal)"
                progressLabel = "To goal"
            }

            return HomeGreetingSummary(
                title: greetingTitle,
                subtitle: "Continue where you left off",
                contextTitle: resolvedTitle,
                contextLine: contextLine,
                icon: recentDeck.icon,
                colorHex: recentDeck.colorHex,
                primaryPill: "\(recentDeck.cardCount) cards",
                secondaryPill: recentDeck.lastOpenedAt.map { "Opened \(Self.relativeTimeLabel(for: $0))" },
                progressFraction: progressFraction,
                progressValueText: progressValueText,
                progressLabel: progressLabel,
                ctaTitle: "Resume Deck",
                action: .openDeck(recentDeck.persistentModelID)
            )
        }

        if let focusDeck = deckHealthSummaries.first {
            return HomeGreetingSummary(
                title: greetingTitle,
                subtitle: "Pick up the deck that needs attention",
                contextTitle: focusDeck.title,
                contextLine: focusDeck.actionLine,
                icon: focusDeck.icon,
                colorHex: focusDeck.colorHex,
                primaryPill: "\(focusDeck.totalCards) cards",
                secondaryPill: focusDeck.lastOpenedLabel.map { "Opened \($0)" },
                progressFraction: focusDeck.masteryFraction,
                progressValueText: "\(Int((focusDeck.masteryFraction * 100).rounded()))%",
                progressLabel: "Mastery",
                ctaTitle: "Open Focus Deck",
                action: .openDeck(focusDeck.id)
            )
        }

        if workspaceState == .needsFolders {
            return HomeGreetingSummary(
                title: greetingTitle,
                subtitle: "Bring structure to your study space",
                contextTitle: "Group your decks into folders",
                contextLine: "Folders stay closer to the top of Home and make larger libraries easier to scan on both iPhone and iPad.",
                icon: "folder.badge.plus",
                colorHex: "",
                primaryPill: "\(allDeckCount) decks",
                secondaryPill: nil,
                progressFraction: overview.goalCompletionFraction,
                progressValueText: overview.didReachGoal ? "Done" : "\(overview.remainingCardsToGoal)",
                progressLabel: overview.didReachGoal ? "Today" : "To goal",
                ctaTitle: "Create Folder",
                action: .createFolder
            )
        }

        let totalXP = max(userProfile?.totalXP ?? 0, 0)
        let streakCount = max(userProfile?.currentStreak ?? 0, 0)
        let secondaryPill = streakCount > 0 ? "\(streakCount)-day streak" : nil

        return HomeGreetingSummary(
            title: greetingTitle,
            subtitle: "Start a focused study pass",
            contextTitle: overview.headline,
            contextLine: dashboardSnapshot.selectedDayInsight.recommendationLine,
            icon: "sparkles.rectangle.stack.fill",
            colorHex: "",
            primaryPill: "\(totalXP) XP",
            secondaryPill: secondaryPill,
            progressFraction: overview.goalCompletionFraction,
            progressValueText: overview.didReachGoal ? "Done" : "\(overview.remainingCardsToGoal)",
            progressLabel: overview.didReachGoal ? "Today" : "To goal",
            ctaTitle: nil,
            action: nil
        )
    }

    // MARK: - Actions

    /// Creates and persists a new `FolderModel` using the current form values,
    /// then resets all form state.
    ///
    /// Silently logs errors to the console. Production builds should route these
    /// to a centralised error reporter (e.g. Crashlytics / OSLog).
    ///
    /// - Parameter context: The SwiftData `ModelContext` from the view environment.
    func createFolder(context: ModelContext) {
        let title = newFolderTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        let folder = FolderModel(title: title, colorHex: newFolderColorHex)
        context.insert(folder)

        do {
            try context.save()
            newFolderTitle = ""
            showCreateFolder = false
        } catch {
            print("[HomeViewModel] Failed to create folder: \(error)")
        }
    }

    /// Toggles a deck selection inside the create-exam-goal sheet.
    ///
    /// - Parameter deckID: The deck identifier to add or remove.
    func toggleExamGoalDeckSelection(_ deckID: PersistentIdentifier) {
        if newExamGoalLinkedDeckIDs.contains(deckID) {
            newExamGoalLinkedDeckIDs.remove(deckID)
        } else {
            newExamGoalLinkedDeckIDs.insert(deckID)
        }
    }

    /// Opens the Home exam-goal sheet in create mode with a clean draft.
    func presentCreateExamGoal() {
        resetExamGoalDraft()
        examGoalSheetPresentation = .create
    }

    /// Opens the Home exam-goal sheet in edit mode, seeded from one persisted goal.
    ///
    /// - Parameter goal: The goal that should be edited.
    func presentExamGoalEditor(for goal: ExamGoalModel) {
        newExamGoalTitle = goal.title
        newExamGoalNote = goal.note
        newExamGoalDate = goal.date
        newExamGoalTargetWorkload = goal.targetWorkload
        newExamGoalStatus = goal.status
        newExamGoalLinkedDeckIDs = Set(goal.linkedDecks.map(\.persistentModelID))
        examGoalSheetPresentation = .edit(goal.persistentModelID)
    }

    /// Dismisses the Home exam-goal sheet and clears any in-flight draft state.
    func dismissExamGoalEditor() {
        examGoalSheetPresentation = nil
        resetExamGoalDraft()
    }

    /// Creates or updates an `ExamGoalModel`, linking the currently selected decks.
    ///
    /// - Parameters:
    ///   - context: The SwiftData model context from Home.
    ///   - availableDecks: Decks that can be attached to the goal.
    ///   - editingGoal: The goal being edited, or `nil` when creating.
    func saveExamGoal(
        context: ModelContext,
        availableDecks: [DeckModel],
        editingGoal: ExamGoalModel?
    ) {
        let title = newExamGoalTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !newExamGoalLinkedDeckIDs.isEmpty else { return }

        let selectedDecks = availableDecks.filter { newExamGoalLinkedDeckIDs.contains($0.persistentModelID) }
        guard !selectedDecks.isEmpty else { return }

        if let editingGoal {
            editingGoal.title = title
            editingGoal.note = newExamGoalNote.trimmingCharacters(in: .whitespacesAndNewlines)
            editingGoal.date = newExamGoalDate
            editingGoal.targetWorkload = newExamGoalTargetWorkload
            editingGoal.status = newExamGoalStatus
            editingGoal.linkedDecks = selectedDecks
            editingGoal.editedAt = Date()
        } else {
            let goal = ExamGoalModel(
                title: title,
                note: newExamGoalNote.trimmingCharacters(in: .whitespacesAndNewlines),
                date: newExamGoalDate,
                targetWorkload: newExamGoalTargetWorkload,
                status: .active,
                linkedDecks: selectedDecks
            )
            context.insert(goal)
        }

        do {
            try context.save()
            dismissExamGoalEditor()
        } catch {
            print("[HomeViewModel] Failed to save exam goal: \(error)")
        }
    }

    /// Updates one persisted exam-goal status directly from Home card menus.
    ///
    /// - Parameters:
    ///   - status: New lifecycle state to persist.
    ///   - goal: Goal being mutated.
    ///   - context: Home model context used for the save.
    func updateExamGoalStatus(
        _ status: ExamGoalStatus,
        for goal: ExamGoalModel,
        context: ModelContext
    ) {
        guard goal.status != status else { return }
        goal.status = status
        goal.editedAt = Date()

        do {
            try context.save()
        } catch {
            print("[HomeViewModel] Failed to update exam goal status: \(error)")
        }
    }

    /// Clears the in-progress exam-goal draft back to its defaults.
    func resetExamGoalDraft() {
        newExamGoalTitle = ""
        newExamGoalNote = ""
        newExamGoalDate = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()
        newExamGoalTargetWorkload = 30
        newExamGoalStatus = .active
        newExamGoalLinkedDeckIDs = []
    }

    // MARK: - Private

    /// Medium date formatter reused by Home exam-goal cards.
    private static let mediumDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    /// Weekday-aware label reused by the selected-day Home summary.
    private static let selectedDayLabelFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, d MMM"
        return formatter
    }()

    /// Compact weekday formatter used by the Home weekly momentum strip.
    private static let shortWeekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEEE"
        return formatter
    }()

    private func buildSelectedDayOverview(
        for selectedDate: Date,
        userProfile: UserProfile?
    ) -> HomeSelectedDayOverviewSummary {
        let log = getFastLog(for: selectedDate)
        let cardsReviewed = log?.cardsReviewed ?? 0
        let dailyGoal = max(log?.dailyGoal ?? 50, 1)
        let xpEarnedToday = log?.xpEarnedToday ?? 0
        let newCardsLearned = log?.newCardsLearned ?? 0
        let goalCompletionFraction = min(Double(cardsReviewed) / Double(dailyGoal), 1.0)
        let remainingCardsToGoal = max(dailyGoal - cardsReviewed, 0)
        let selectedDateLabel = Self.labelForSelectedDay(selectedDate)

        let headline: String
        let detailLine: String
        if cardsReviewed >= dailyGoal {
            headline = "Goal reached"
            detailLine = "You completed \(cardsReviewed) cards on \(selectedDateLabel.lowercased())."
        } else if cardsReviewed > 0 {
            headline = "\(remainingCardsToGoal) cards to target"
            detailLine = "You already reviewed \(cardsReviewed) cards and earned \(xpEarnedToday) XP."
        } else {
            headline = "Fresh study window"
            detailLine = "No study logged for \(selectedDateLabel.lowercased()) yet."
        }

        return HomeSelectedDayOverviewSummary(
            selectedDate: selectedDate,
            selectedDateLabel: selectedDateLabel,
            cardsReviewed: cardsReviewed,
            dailyGoal: dailyGoal,
            goalCompletionFraction: goalCompletionFraction,
            remainingCardsToGoal: remainingCardsToGoal,
            xpEarnedToday: xpEarnedToday,
            newCardsLearned: newCardsLearned,
            streakCount: userProfile?.currentStreak ?? 0,
            totalXP: userProfile?.totalXP ?? 0,
            level: userProfile?.level ?? 1,
            headline: headline,
            detailLine: detailLine
        )
    }

    private func buildWeeklyMomentumSummary(
        selectedDate: Date,
        dailyLogs: [DailyActivityLog]
    ) -> HomeWeeklyMomentumSummary {
        let calendar = AppPreferences.shared.resolvedCalendar
        let startOfSelectedDay = calendar.startOfDay(for: selectedDate)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: startOfSelectedDay)?.start
            ?? startOfSelectedDay

        let logsByDay = Dictionary(
            uniqueKeysWithValues: dailyLogs.map { log in
                (calendar.startOfDay(for: log.date), log)
            }
        )

        let daySummaries: [HomeWeeklyDaySummary] = (0..<7).compactMap { index in
            guard let day = calendar.date(byAdding: .day, value: index, to: weekStart) else { return nil }
            let log = logsByDay[day]
            let cardsReviewed = log?.cardsReviewed ?? 0
            let xpEarned = log?.xpEarnedToday ?? 0
            let goal = max(log?.dailyGoal ?? 50, 1)
            let intensityFraction = min(Double(cardsReviewed) / Double(goal), 1.0)

            return HomeWeeklyDaySummary(
                id: Self.dateKeyFormatter.string(from: day),
                date: day,
                shortWeekday: Self.shortWeekdayFormatter.string(from: day),
                cardsReviewed: cardsReviewed,
                xpEarned: xpEarned,
                goal: goal,
                intensityFraction: intensityFraction,
                didStudy: cardsReviewed > 0 || xpEarned > 0,
                didReachGoal: cardsReviewed >= goal,
                isSelectedDay: calendar.isDate(day, inSameDayAs: startOfSelectedDay)
            )
        }

        let weeklyLogs = dailyLogs
            .filter { log in
                let logDay = calendar.startOfDay(for: log.date)
                guard let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) else {
                    return false
                }
                return logDay >= weekStart && logDay <= weekEnd
            }
            .sorted { $0.date < $1.date }

        let totalCardsReviewed = weeklyLogs.map(\.cardsReviewed).reduce(0, +)
        let totalXPEarned = weeklyLogs.map(\.xpEarnedToday).reduce(0, +)
        let activeLogs = weeklyLogs.filter { $0.cardsReviewed > 0 || $0.xpEarnedToday > 0 }
        let activeDays = activeLogs.count
        let goalHitDays = weeklyLogs.filter(\.isPerfectDay).count
        let averageCardsPerActiveDay = activeDays > 0 ? Int(round(Double(totalCardsReviewed) / Double(activeDays))) : 0
        let averageXPPerActiveDay = activeDays > 0 ? Int(round(Double(totalXPEarned) / Double(activeDays))) : 0
        let consistencyFraction = Double(activeDays) / 7.0
        let bestDay = weeklyLogs.max { lhs, rhs in
            if lhs.cardsReviewed != rhs.cardsReviewed { return lhs.cardsReviewed < rhs.cardsReviewed }
            return lhs.xpEarnedToday < rhs.xpEarnedToday
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
            consistencyFraction: consistencyFraction,
            bestDayLabel: bestDay.map { Self.selectedDayLabelFormatter.string(from: $0.date) },
            headline: headline,
            detailLine: detailLine,
            daySummaries: daySummaries
        )
    }

    private func buildSelectedDayInsightSummary(
        selectedDate: Date,
        selectedDayOverview: HomeSelectedDayOverviewSummary,
        selectedDayExamSummaries: [HomeExamGoalSummary],
        upcomingExamSummaries: [HomeExamGoalSummary],
        weeklyMomentum: HomeWeeklyMomentumSummary
    ) -> HomeSelectedDayInsightSummary {
        let averageCardsPerActiveDay = weeklyMomentum.averageCardsPerActiveDay
        let cardsReviewed = selectedDayOverview.cardsReviewed

        let paceLine: String
        if averageCardsPerActiveDay == 0 && cardsReviewed == 0 {
            paceLine = "No recent study baseline yet."
        } else if averageCardsPerActiveDay == 0 {
            paceLine = "This day sets your first study pace."
        } else {
            let delta = cardsReviewed - averageCardsPerActiveDay
            if delta == 0 {
                paceLine = "Exactly on your 7-day average pace."
            } else if delta > 0 {
                paceLine = "\(delta) cards above your 7-day average."
            } else {
                paceLine = "\(-delta) cards below your 7-day average."
            }
        }

        let examContextLine: String
        if !selectedDayExamSummaries.isEmpty {
            examContextLine = selectedDayExamSummaries.count == 1
                ? "One exam goal lands on this day."
                : "\(selectedDayExamSummaries.count) exam goals land on this day."
        } else if let nextGoal = upcomingExamSummaries.first {
            examContextLine = "Nearest pressure point: \(nextGoal.title) is \(nextGoal.countdownLabel.lowercased())."
        } else {
            examContextLine = "No exam goals are pressuring this day."
        }

        let headline: String
        let detailLine: String
        if !selectedDayExamSummaries.isEmpty {
            headline = selectedDayExamSummaries.count == 1 ? "This day carries an exam target" : "This day is a study checkpoint"
            detailLine = selectedDayExamSummaries.first?.summaryLine ?? "Use this date to consolidate your strongest recall."
        } else if selectedDayOverview.didReachGoal {
            headline = "This day is already in good shape"
            detailLine = "You cleared the target and can use any extra time for due-card cleanup."
        } else if cardsReviewed > 0 {
            headline = "This day still has room to improve"
            detailLine = "You are \(selectedDayOverview.remainingCardsToGoal) cards away from the target."
        } else {
            headline = "This day is still open"
            detailLine = "No study has landed here yet, so it can absorb focused catch-up work."
        }

        let recommendationLine: String
        if let selectedGoal = selectedDayExamSummaries.first, let weakestDeck = selectedGoal.weakestDeck {
            recommendationLine = "Best next move: rehearse \(weakestDeck.title) and protect \(selectedGoal.countdownLabel.lowercased())."
        } else if let pressure = upcomingExamSummaries.first, let weakestDeck = pressure.weakestDeck {
            let suggestedCards = max(pressure.dailyPaceNeeded, selectedDayOverview.remainingCardsToGoal > 0 ? min(selectedDayOverview.remainingCardsToGoal, pressure.dailyPaceNeeded) : pressure.dailyPaceNeeded)
            recommendationLine = "Best next move: put \(suggestedCards) reviews into \(weakestDeck.title) to reduce upcoming pressure."
        } else if selectedDayOverview.didReachGoal {
            recommendationLine = "Best next move: keep the streak warm with a short due-card pass."
        } else {
            recommendationLine = "Best next move: finish the remaining \(selectedDayOverview.remainingCardsToGoal) cards and lock the day."
        }

        return HomeSelectedDayInsightSummary(
            headline: headline,
            detailLine: detailLine,
            recommendationLine: recommendationLine,
            paceLine: paceLine,
            examContextLine: examContextLine,
            xpEarned: selectedDayOverview.xpEarnedToday,
            newCardsLearned: selectedDayOverview.newCardsLearned,
            selectedDayExamCount: selectedDayExamSummaries.count
        )
    }

    private func buildExamPressureSummary(
        from upcomingExamSummaries: [HomeExamGoalSummary]
    ) -> HomeExamPressureSummary? {
        guard let topRiskGoal = upcomingExamSummaries.max(by: { riskScore(for: $0) < riskScore(for: $1) }) else {
            return nil
        }

        let headline: String
        if topRiskGoal.belowTargetDeckCount > 0 || topRiskGoal.overdueCount > 0 {
            headline = "Needs attention now"
        } else if topRiskGoal.readinessFraction >= 0.75 {
            headline = "On track"
        } else {
            headline = "Steady pressure"
        }

        let actionLine: String
        if let weakestDeck = topRiskGoal.weakestDeck {
            if topRiskGoal.dailyPaceNeeded > 0 {
                actionLine = "Focus \(topRiskGoal.dailyPaceNeeded) reviews/day in \(weakestDeck.title) to lift readiness."
            } else {
                actionLine = "Use \(weakestDeck.title) for quick reinforcement before the deadline."
            }
        } else if topRiskGoal.dailyPaceNeeded > 0 {
            actionLine = "Keep a pace of \(topRiskGoal.dailyPaceNeeded) reviews/day until the goal is stable."
        } else {
            actionLine = "Maintain light recall sessions to protect readiness."
        }

        return HomeExamPressureSummary(
            goalID: topRiskGoal.id,
            goalTitle: topRiskGoal.title,
            countdownLabel: topRiskGoal.countdownLabel,
            readinessFraction: topRiskGoal.readinessFraction,
            headline: headline,
            detailLine: topRiskGoal.summaryLine,
            actionLine: actionLine,
            overdueCards: topRiskGoal.overdueCount,
            dailyPaceNeeded: topRiskGoal.dailyPaceNeeded,
            belowTargetDeckCount: topRiskGoal.belowTargetDeckCount,
            weakestDeckTitle: topRiskGoal.weakestDeck?.title,
            weakestDeckReadinessFraction: topRiskGoal.weakestDeck?.readinessFraction
        )
    }

    private func activeExamGoalDeckCounts(
        from examGoals: [ExamGoalModel],
        referenceDate: Date
    ) -> [PersistentIdentifier: Int] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: referenceDate)

        var counts: [PersistentIdentifier: Int] = [:]
        for goal in examGoals where goal.status == .active && calendar.startOfDay(for: goal.date) >= today {
            for deck in goal.linkedDecks {
                counts[deck.persistentModelID, default: 0] += 1
            }
        }
        return counts
    }

    private func prioritizedDeckHealthCandidates(
        from decks: [DeckModel],
        recentDeckIDs: Set<PersistentIdentifier>,
        goalCounts: [PersistentIdentifier: Int]
    ) -> [DeckModel] {
        decks
            .filter { $0.cardCount > 0 }
            .sorted { lhs, rhs in
                let lhsGoalCount = goalCounts[lhs.persistentModelID] ?? 0
                let rhsGoalCount = goalCounts[rhs.persistentModelID] ?? 0
                if lhsGoalCount != rhsGoalCount { return lhsGoalCount > rhsGoalCount }

                let lhsRecent = recentDeckIDs.contains(lhs.persistentModelID)
                let rhsRecent = recentDeckIDs.contains(rhs.persistentModelID)
                if lhsRecent != rhsRecent { return lhsRecent && !rhsRecent }

                if lhs.cardCount != rhs.cardCount { return lhs.cardCount > rhs.cardCount }
                return (lhs.lastOpenedAt ?? .distantPast) > (rhs.lastOpenedAt ?? .distantPast)
            }
            .prefix(8)
            .map { $0 }
    }

    private func buildDeckHealthSummary(
        for deck: DeckModel,
        report: LearnModeReport,
        linkedGoalCount: Int,
        isRecentlyOpened: Bool
    ) -> HomeDeckHealthSummary {
        let masteryFraction = report.totalCards > 0
            ? Double(report.stableCards) / Double(report.totalCards)
            : 0

        let headline: String
        if linkedGoalCount > 0 && report.dueCards > 0 {
            headline = "Exam-linked and under pressure"
        } else if report.dueCards > 0 {
            headline = "\(report.dueCards) due right now"
        } else if report.newCards > 0 {
            headline = "\(report.newCards) new cards waiting"
        } else if report.stableCards == report.totalCards {
            headline = "Healthy deck"
        } else {
            headline = "Mostly stable, with room to tune"
        }

        let detailLine: String
        if linkedGoalCount > 0 {
            detailLine = "Supports \(linkedGoalCount) active exam goal\(linkedGoalCount == 1 ? "" : "s"). Accuracy is \(report.reviewAccuracy)%."
        } else if report.reviewedCards == 0 {
            detailLine = "No reviews logged yet across \(report.totalCards) cards."
        } else {
            detailLine = "\(report.stableCards) stable, \(report.buildingCards) building, \(report.dueCards) due. Accuracy is \(report.reviewAccuracy)%."
        }

        let primaryInsight = report.focusCards.first ?? report.newMaterialCards.first ?? report.stableHighlights.first
        let actionLine = primaryInsight?.recommendation
            ?? (report.dueCards > 0
                ? "Start with due cards before adding anything new."
                : report.newCards > 0
                    ? "Introduce a few new cards and build first-pass familiarity."
                    : "Use a short review pass to keep the deck warm.")

        return HomeDeckHealthSummary(
            id: deck.persistentModelID,
            title: deck.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Deck" : deck.title,
            icon: deck.icon,
            colorHex: deck.colorHex,
            totalCards: report.totalCards,
            dueCards: report.dueCards,
            newCards: report.newCards,
            buildingCards: report.buildingCards,
            stableCards: report.stableCards,
            reviewAccuracy: report.reviewAccuracy,
            masteryFraction: masteryFraction,
            linkedGoalCount: linkedGoalCount,
            isRecentlyOpened: isRecentlyOpened,
            lastOpenedLabel: deck.lastOpenedAt.map(Self.relativeTimeLabel(for:)),
            headline: headline,
            detailLine: detailLine,
            actionLine: actionLine,
            focusPrompt: primaryInsight?.promptPreview
        )
    }

    private func deckHealthRiskScore(for summary: HomeDeckHealthSummary) -> Double {
        guard summary.totalCards > 0 else { return 0 }

        let duePressure = min(Double(summary.dueCards) / Double(summary.totalCards), 1.0) * 0.45
        let newPressure = min(Double(summary.newCards) / Double(summary.totalCards), 1.0) * 0.12
        let buildingPressure = min(Double(summary.buildingCards) / Double(summary.totalCards), 1.0) * 0.18
        let accuracyPressure = (1.0 - (Double(summary.reviewAccuracy) / 100.0)) * 0.18
        let examPressure = min(Double(summary.linkedGoalCount) * 0.18, 0.36)
        let recentBoost = summary.isRecentlyOpened ? 0.05 : 0

        return duePressure + newPressure + buildingPressure + accuracyPressure + examPressure + recentBoost
    }

    private func buildCalendarDayInsight(
        key: String,
        date: Date,
        log: DailyActivityLog?,
        goals: [ExamGoalModel],
        streakDates: Set<String>
    ) -> HomeCalendarDayInsight {
        let cardsReviewed = log?.cardsReviewed ?? 0
        let xpEarned = log?.xpEarnedToday ?? 0
        let dailyGoal = max(log?.dailyGoal ?? 50, 1)
        let didStudy = cardsReviewed > 0 || xpEarned > 0
        let activityFraction = didStudy
            ? max(min(Double(cardsReviewed) / Double(dailyGoal), 1.0), xpEarned > 0 ? 0.22 : 0.12)
            : 0
        let activeGoals = goals.filter { $0.status != .archived }
        let hasGoalNote = activeGoals.contains { !$0.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        return HomeCalendarDayInsight(
            date: date,
            dateString: key,
            cardsReviewed: cardsReviewed,
            xpEarned: xpEarned,
            dailyGoal: dailyGoal,
            activityFraction: activityFraction,
            didStudy: didStudy,
            isPerfectDay: log?.isPerfectDay ?? false,
            isStreakDay: streakDates.contains(key),
            hasExamGoal: !activeGoals.isEmpty,
            hasGoalNote: hasGoalNote,
            examGoalCount: activeGoals.count
        )
    }

    private func buildDashboardSnapshotSignature(
        selectedDate: Date,
        userProfile: UserProfile?
    ) -> String {
        let selectedDateKey = Self.dateKeyFormatter.string(from: selectedDate)
        return [
            selectedDateKey,
            profileSignature(for: userProfile),
            logsCacheSignature.joined(separator: "~"),
            examGoalsCacheSignature.joined(separator: "~")
        ].joined(separator: "||")
    }

    private func buildCalendarInsightsSignature(
        userProfile: UserProfile?,
        referenceDate: Date
    ) -> String {
        [
            Self.dateKeyFormatter.string(from: referenceDate),
            profileSignature(for: userProfile),
            logsCacheSignature.joined(separator: "~"),
            examGoalsCacheSignature.joined(separator: "~")
        ].joined(separator: "||")
    }

    private func buildDeckHealthSignature(
        decks: [DeckModel],
        recentDecks: [DeckModel],
        examGoals: [ExamGoalModel],
        referenceDate: Date
    ) -> String {
        let deckSignature = decks
            .map {
                [
                    "\($0.persistentModelID.hashValue)",
                    $0.title,
                    $0.icon,
                    $0.colorHex,
                    "\($0.cardCount)",
                    "\($0.editedAt.timeIntervalSince1970)",
                    "\($0.lastOpenedAt?.timeIntervalSince1970 ?? 0)"
                ].joined(separator: "|")
            }
            .sorted()
            .joined(separator: "~")

        let recentSignature = recentDecks
            .map { "\($0.persistentModelID.hashValue)" }
            .joined(separator: "~")

        return [
            Self.dateKeyFormatter.string(from: referenceDate),
            deckSignature,
            recentSignature,
            examGoalsCacheSignature.joined(separator: "~")
        ].joined(separator: "||")
    }

    private func buildActiveStreakDateKeys(
        userProfile: UserProfile?,
        referenceDate: Date
    ) -> Set<String> {
        guard
            let userProfile,
            userProfile.currentStreak > 0,
            let lastActiveDate = userProfile.lastActiveDate
        else { return [] }

        let calendar = Calendar.current
        let normalizedReference = calendar.startOfDay(for: referenceDate)
        let normalizedLastActive = calendar.startOfDay(for: lastActiveDate)

        guard normalizedLastActive <= normalizedReference else { return [] }

        let streakLength = max(userProfile.currentStreak, 0)
        return Set((0..<streakLength).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: normalizedLastActive) else {
                return nil
            }
            return Self.dateKeyFormatter.string(from: date)
        })
    }

    private func profileSignature(for userProfile: UserProfile?) -> String {
        userProfile.map {
            [
                "\($0.totalXP)",
                "\($0.currentStreak)",
                "\($0.longestStreak)",
                "\($0.lastActiveDate?.timeIntervalSince1970 ?? 0)"
            ].joined(separator: "|")
        } ?? "no-profile"
    }

    private static func labelForSelectedDay(_ date: Date, referenceDate: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: referenceDate),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: referenceDate),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "Tomorrow"
        }
        return selectedDayLabelFormatter.string(from: date)
    }

    static func greetingPhase(for referenceDate: Date) -> HomeGreetingPhase {
        let hour = Calendar.current.component(.hour, from: referenceDate)
        switch hour {
        case 5..<12:
            return .morning
        case 12..<17:
            return .afternoon
        case 17..<22:
            return .evening
        default:
            return .night
        }
    }

    private func buildExamGoalSummary(
        for goal: ExamGoalModel,
        referenceDate: Date
    ) -> HomeExamGoalSummary {
        let calendar = Calendar.current
        let startOfReferenceDay = calendar.startOfDay(for: referenceDate)
        let startOfGoalDay = calendar.startOfDay(for: goal.date)
        let daysRemaining = max(calendar.dateComponents([.day], from: startOfReferenceDay, to: startOfGoalDay).day ?? 0, 0)
        let deckSummaries = goal.linkedDecks.map { buildDeckSummary(for: $0, now: referenceDate) }
        let readinessFraction = deckSummaries.isEmpty
            ? 0
            : deckSummaries.map(\.readinessFraction).reduce(0, +) / Double(deckSummaries.count)
        let overdueCount = deckSummaries.map(\.dueCards).reduce(0, +)
        let remainingCards = deckSummaries.map(\.remainingCards).reduce(0, +)
        let dailyPaceNeeded = remainingCards == 0 ? 0 : Int(ceil(Double(remainingCards) / Double(max(daysRemaining, 1))))
        let perDeckTarget = max(1, Int(ceil(Double(goal.targetWorkload) / Double(max(deckSummaries.count, 1)))))
        let belowTargetDeckCount = deckSummaries.filter {
            $0.remainingCards > perDeckTarget || $0.readinessFraction < readinessThreshold(daysRemaining: daysRemaining)
        }.count
        let weakestDeck = deckSummaries.min { lhs, rhs in
            if lhs.readinessFraction != rhs.readinessFraction {
                return lhs.readinessFraction < rhs.readinessFraction
            }
            return lhs.remainingCards > rhs.remainingCards
        }

        let summaryLine: String
        if daysRemaining == 0 {
            summaryLine = belowTargetDeckCount > 0
                ? "Exam day is here and \(belowTargetDeckCount) linked deck\(belowTargetDeckCount == 1 ? "" : "s") still need attention."
                : "Exam day is here. Focus on calm recall and quick due-card passes."
        } else if belowTargetDeckCount > 0 {
            summaryLine = "Exam in \(daysRemaining) day\(daysRemaining == 1 ? "" : "s") and \(belowTargetDeckCount) linked deck\(belowTargetDeckCount == 1 ? "" : "s") are below target."
        } else if dailyPaceNeeded > 0 {
            summaryLine = "On track if you keep roughly \(dailyPaceNeeded) review\(dailyPaceNeeded == 1 ? "" : "s") per day."
        } else {
            summaryLine = "Linked decks look healthy for this goal right now."
        }

        return HomeExamGoalSummary(
            id: goal.persistentModelID,
            title: goal.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Goal" : goal.title,
            note: goal.note,
            date: goal.date,
            status: goal.status,
            countdownLabel: Self.countdownLabel(for: goal.date, referenceDate: referenceDate),
            dateLabel: Self.mediumDateLabel(for: goal.date),
            targetWorkload: goal.targetWorkload,
            linkedDeckCount: deckSummaries.count,
            readinessFraction: readinessFraction,
            overdueCount: overdueCount,
            dailyPaceNeeded: dailyPaceNeeded,
            belowTargetDeckCount: belowTargetDeckCount,
            weakestDeck: weakestDeck,
            summaryLine: summaryLine,
            deckSummaries: deckSummaries
        )
    }

    private func buildDeckSummary(for deck: DeckModel, now: Date) -> HomeExamDeckSummary {
        let cards = deck.cards
        let totalCards = max(deck.cardCount, cards.count)
        let reviewedCards = cards.filter { !$0.reviewHistory.isEmpty }.count
        let dueCards = cards.filter { $0.dueDate <= now }.count
        let newCards = cards.filter { $0.reviewHistory.isEmpty }.count
        let stableCards = cards.filter { $0.interval >= 14 }.count
        let reviewEvents = cards.flatMap(\.reviewHistory)
        let successfulReviews = reviewEvents.filter { $0.difficultyRaw >= ReviewDifficulty.good.rawValue }.count
        let accuracyFraction = reviewEvents.isEmpty
            ? 0
            : Double(successfulReviews) / Double(reviewEvents.count)
        let coverageFraction = totalCards > 0
            ? Double(reviewedCards) / Double(totalCards)
            : 0
        let stabilityFraction = totalCards > 0
            ? Double(stableCards) / Double(totalCards)
            : 0
        let duePenalty = totalCards > 0
            ? Double(dueCards) / Double(totalCards)
            : 0
        let readinessFraction = min(
            1,
            max(
                0,
                (coverageFraction * 0.45)
                + (accuracyFraction * 0.35)
                + (stabilityFraction * 0.25)
                - (duePenalty * 0.20)
            )
        )

        return HomeExamDeckSummary(
            id: deck.persistentModelID,
            title: deck.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Deck" : deck.title,
            colorHex: deck.colorHex,
            totalCards: totalCards,
            reviewedCards: reviewedCards,
            dueCards: dueCards,
            newCards: newCards,
            accuracyFraction: accuracyFraction,
            readinessFraction: readinessFraction
        )
    }

    private func readinessThreshold(daysRemaining: Int) -> Double {
        switch daysRemaining {
        case 0...3:
            return 0.78
        case 4...7:
            return 0.68
        default:
            return 0.58
        }
    }

    private func riskScore(for summary: HomeExamGoalSummary) -> Double {
        let readinessPressure = 1 - summary.readinessFraction
        let workloadPressure = Double(summary.belowTargetDeckCount) * 0.25
        let overduePressure = summary.overdueCount > 0 ? min(Double(summary.overdueCount) / 40.0, 0.4) : 0
        return readinessPressure + workloadPressure + overduePressure
    }
}
