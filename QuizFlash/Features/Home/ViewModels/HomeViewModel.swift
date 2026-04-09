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
import OSLog

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
    private let logger = QuizFlashLog.make("HomeViewModel")

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

    /// Fingerprint of the latest cached daily-log input.
    var logsCacheFingerprint: Int = 0

    /// Fingerprint of the latest cached exam-goal input.
    var examGoalsCacheFingerprint: Int = 0

    /// Monotonic revision bumped whenever the daily-log cache changes.
    var logsCacheRevision: Int = 0

    /// Monotonic revision bumped whenever the exam-goal cache changes.
    var examGoalsCacheRevision: Int = 0

    /// Cached Home analytics snapshot consumed by `HomeDashboardView`.
    private(set) var dashboardSnapshot: HomeDashboardSnapshot = .placeholder()

    /// Signature used to skip rebuilding Home dashboard summaries when inputs are unchanged.
    private var dashboardSnapshotSignature: String = ""

    /// Cached Home dashboard payload that does not depend on the selected calendar day.
    var dashboardStaticSnapshot: HomeDashboardStaticSnapshot = .empty()

    /// Signature used to skip rebuilding dashboard payloads that are independent of date selection.
    var dashboardStaticSignature: String = ""

    /// Cached selected-day overview summaries keyed by date + input signature.
    var selectedDayOverviewCache: [String: HomeSelectedDayOverviewSummary] = [:]

    /// Cached weekly momentum summaries keyed by week start + input signature.
    var weeklyMomentumCache: [String: HomeWeeklyMomentumSummary] = [:]

    /// Cached selected-day exam summaries keyed by date + goal signature.
    var selectedDayExamSummariesCache: [String: [HomeExamGoalSummary]] = [:]

    /// Cached selected-day insight summaries keyed by date + local summary inputs.
    var selectedDayInsightCache: [String: HomeSelectedDayInsightSummary] = [:]

    /// Cached recent-study counters keyed by reference day + logs signature.
    var recentStudyDayCountCache: [String: Int] = [:]

    /// Cached goal summaries keyed by goal identity, linked deck revision, and reference day.
    var examGoalSummaryCache: [String: HomeExamGoalSummary] = [:]

    /// Cached deck summaries keyed by deck identity, revision, and reference day.
    var examDeckSummaryCache: [String: HomeExamDeckSummary] = [:]

    /// Cached per-day insight payloads consumed by the Home calendar.
    private(set) var calendarInsightsCache: [String: HomeCalendarDayInsight] = [:]

    /// Monotonic token used by Home calendar surfaces to detect real insight changes
    /// without diffing the full dictionary during scroll-driven updates.
    private(set) var calendarInsightsRevision: Int = 0

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
        let fingerprint = Self.logsFingerprint(for: logs)
        guard logsCacheFingerprint != fingerprint else { return }
        logsCacheFingerprint = fingerprint
        logsCacheRevision &+= 1

        var dict = [String: DailyActivityLog](minimumCapacity: logs.count)
        for log in logs {
            dict[log.dateString] = log
        }
        logsCache = dict
        invalidateDashboardDerivedCaches()
    }

    /// Rebuilds `examGoalsCache` so the Home calendar can mark exam days and notes in O(1).
    ///
    /// - Parameter goals: The current exam-goal query result from `HomeView`.
    func updateExamGoalsCache(goals: [ExamGoalModel]) {
        let fingerprint = Self.examGoalsFingerprint(for: goals)
        guard examGoalsCacheFingerprint != fingerprint else { return }
        examGoalsCacheFingerprint = fingerprint
        examGoalsCacheRevision &+= 1

        var dict: [String: [ExamGoalModel]] = [:]
        for goal in goals {
            let key = Self.dateKeyFormatter.string(from: goal.date)
            dict[key, default: []].append(goal)
        }
        examGoalsCache = dict
        invalidateDashboardDerivedCaches()
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
        let dateKey = HomeViewModel.dateKeyFormatter.string(from: date)
        let cacheKey = [
            dateKey,
            "\(examGoalsCacheRevision)"
        ].joined(separator: "||")

        if let cached = selectedDayExamSummariesCache[cacheKey] {
            return cached
        }

        let summaries = examGoals(for: date)
            .map { buildExamGoalSummary(for: $0, referenceDate: date) }
        selectedDayExamSummariesCache[cacheKey] = summaries
        return summaries
    }

    /// Refreshes the cached dashboard snapshot that backs the Home screen.
    ///
    /// This keeps heavier summary work out of SwiftUI render passes while still
    /// reacting to the selected day, logs, goals, and profile changes.
    func refreshDashboardSnapshot(
        selectedDate: Date,
        examGoals: [ExamGoalModel],
        userProfile: UserProfile?
    ) {
        refreshDashboardStaticSnapshot(
            examGoals: examGoals,
            userProfile: userProfile
        )

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
        let weeklyMomentum = buildWeeklyMomentumSummary(selectedDate: selectedDate)
        let selectedDayExamSummaries = selectedDayExamGoalSummaries(for: selectedDate)

        dashboardSnapshot = HomeDashboardSnapshot(
            selectedDayOverview: selectedDayOverview,
            selectedDayInsight: buildSelectedDayInsightSummary(
                selectedDate: selectedDate,
                selectedDayOverview: selectedDayOverview,
                selectedDayExamSummaries: selectedDayExamSummaries,
                upcomingExamSummaries: dashboardStaticSnapshot.upcomingExamSummaries,
                weeklyMomentum: weeklyMomentum
            ),
            weeklyMomentum: weeklyMomentum,
            examPressure: dashboardStaticSnapshot.examPressure,
            selectedDayExamSummaries: selectedDayExamSummaries,
            upcomingExamSummaries: dashboardStaticSnapshot.upcomingExamSummaries,
            examNarrative: dashboardStaticSnapshot.examNarrative
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
        calendarInsightsRevision &+= 1
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
            logger.error(
                "Failed to create folder: \(String(describing: error), privacy: .public)"
            )
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
            logger.error(
                "Failed to save exam goal: \(String(describing: error), privacy: .public)"
            )
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
            logger.error(
                "Failed to update exam goal status: \(String(describing: error), privacy: .public)"
            )
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

    func invalidateDashboardDerivedCaches() {
        dashboardSnapshotSignature = ""
        dashboardStaticSignature = ""
        dashboardStaticSnapshot = .empty()
        selectedDayOverviewCache.removeAll(keepingCapacity: true)
        weeklyMomentumCache.removeAll(keepingCapacity: true)
        selectedDayExamSummariesCache.removeAll(keepingCapacity: true)
        selectedDayInsightCache.removeAll(keepingCapacity: true)
        recentStudyDayCountCache.removeAll(keepingCapacity: true)
        examGoalSummaryCache.removeAll(keepingCapacity: true)
        examDeckSummaryCache.removeAll(keepingCapacity: true)
    }

    static func logsFingerprint(for logs: [DailyActivityLog]) -> Int {
        var aggregate = logs.count &* 1_000_003
        for log in logs {
            var hasher = Hasher()
            hasher.combine(log.dateString)
            hasher.combine(log.cardsReviewed)
            hasher.combine(log.xpEarnedToday)
            hasher.combine(log.newCardsLearned)
            hasher.combine(log.dailyGoal)
            aggregate ^= hasher.finalize()
        }
        return aggregate
    }

    static func examGoalsFingerprint(for goals: [ExamGoalModel]) -> Int {
        var aggregate = goals.count &* 1_000_033
        for goal in goals {
            var deckAggregate = goal.linkedDecks.count &* 97
            for deck in goal.linkedDecks {
                var deckHasher = Hasher()
                deckHasher.combine(deck.persistentModelID.hashValue)
                deckHasher.combine(deck.cardCount)
                deckHasher.combine(deck.editedAt.timeIntervalSince1970.bitPattern)
                deckAggregate ^= deckHasher.finalize()
            }

            var hasher = Hasher()
            hasher.combine(goal.persistentModelID.hashValue)
            hasher.combine(Self.dateKeyFormatter.string(from: goal.date))
            hasher.combine(goal.statusRaw)
            hasher.combine(goal.title)
            hasher.combine(goal.note)
            hasher.combine(goal.targetWorkload)
            hasher.combine(deckAggregate)
            aggregate ^= hasher.finalize()
        }
        return aggregate
    }

}
