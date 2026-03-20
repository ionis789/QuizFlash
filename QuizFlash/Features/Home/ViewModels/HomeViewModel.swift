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
