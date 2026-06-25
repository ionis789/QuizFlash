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

    /// Controls the create-folder save error alert shown inside the folder sheet.
    var showCreateFolderError: Bool = false

    /// Human-readable message for the create-folder save error alert.
    var createFolderErrorMessage: String = ""

    /// Bound to the text field inside `CreateFolderSheet`.
    var newFolderTitle: String = ""

    /// The hex colour chosen in the Create Folder colour picker. Defaults to system green.
    var newFolderColorHex: String = "#34C759"

    /// Controls the custom sheet that expands the Home 7-day performance detail.
    var showPerformanceDetailSheet: Bool = false

    // MARK: - Logs Cache

    /// Activity logs keyed by ISO-8601 date string (`yyyy-MM-dd`) for O(1) lookups.
    ///
    /// Rebuilt whenever the `dailyLogs` SwiftData query result changes in `HomeView`.
    var logsCache: [String: DailyActivityLog] = [:]

    /// Fingerprint of the latest cached daily-log input.
    var logsCacheFingerprint: Int = 0

    /// Monotonic revision bumped whenever the daily-log cache changes.
    var logsCacheRevision: Int = 0

    /// Cached Home analytics snapshot consumed by `HomeDashboardView`.
    private(set) var dashboardSnapshot: HomeDashboardSnapshot = .placeholder()

    /// Signature used to skip rebuilding Home dashboard summaries when inputs are unchanged.
    private var dashboardSnapshotSignature: String = ""

    /// Cached selected-day overview summaries keyed by date + input signature.
    var selectedDayOverviewCache: [String: HomeSelectedDayOverviewSummary] = [:]

    /// Cached weekly momentum summaries keyed by week start + input signature.
    var weeklyMomentumCache: [String: HomeWeeklyMomentumSummary] = [:]

    /// Cached selected-day insight summaries keyed by date + local summary inputs.
    var selectedDayInsightCache: [String: HomeSelectedDayInsightSummary] = [:]

    /// Cached recent-study counters keyed by reference day + logs signature.
    var recentStudyDayCountCache: [String: Int] = [:]

    /// Persisted pixel scroll offset for Home scroll restoration.
    /// Kept out of observation so scroll probes do not invalidate the whole screen
    /// on every frame of user-driven motion.
    @ObservationIgnored
    var savedScrollOffset: CGFloat = 0

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

    /// Returns the activity log for a given date, or `nil` if none exists.
    ///
    /// - Parameter date: The date to look up.
    /// - Returns: The matching `DailyActivityLog`, or `nil`.
    func getFastLog(for date: Date) -> DailyActivityLog? {
        logsCache[HomeViewModel.dateKeyFormatter.string(from: date)]
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
    static func relativeTimeLabel(
        for date: Date,
        referenceDate: Date = Date()
    ) -> String {
        let locale = AppPreferences.shared.resolvedLocale
        let seconds = Int(referenceDate.timeIntervalSince(date))
        switch seconds {
        case ..<60:
            return AppLocalization.string("just now", locale: locale)
        case ..<3_600:
            return String.localizedStringWithFormat(
                AppLocalization.string("%dm ago", locale: locale),
                seconds / 60
            )
        case ..<86_400:
            return String.localizedStringWithFormat(
                AppLocalization.string("%dh ago", locale: locale),
                seconds / 3_600
            )
        case ..<2_592_000:
            return String.localizedStringWithFormat(
                AppLocalization.string("%dd ago", locale: locale),
                seconds / 86_400
            )
        default:
            return String.localizedStringWithFormat(
                AppLocalization.string("%dmo ago", locale: locale),
                seconds / 2_592_000
            )
        }
    }

    /// Refreshes the cached dashboard snapshot that backs the Home screen.
    ///
    /// This keeps heavier summary work out of SwiftUI render passes while still
    /// reacting to the selected day, logs, and profile changes.
    func refreshDashboardSnapshot(
        selectedDate: Date,
        weekStart: Date,
        userProfile: UserProfile?,
        container: ModelContainer,
        analyticsRevision: Int,
        deckRevision: Int,
        dailyCardsGoal: Int? = nil,
        referenceDate: Date = Date()
    ) async {
        let signature = buildDashboardSnapshotSignature(
            selectedDate: selectedDate,
            userProfile: userProfile,
            analyticsRevision: analyticsRevision,
            deckRevision: deckRevision,
            dailyCardsGoal: dailyCardsGoal
        )
        guard dashboardSnapshotSignature != signature else { return }

        let repository = HomeAnalyticsRepository(container: container)
        let analyticsSnapshot = await repository.loadDashboardSnapshot(
            selectedDate: selectedDate,
            weekStart: weekStart,
            dailyCardsGoal: dailyCardsGoal
        )
        await repository.tearDown()
        guard !Task.isCancelled else { return }

        let selectedDayStats = analyticsSnapshot.selectedDayStats
        let selectedDateLabel = Self.labelForSelectedDay(
            selectedDayStats.selectedDate,
            referenceDate: referenceDate
        )
        let goalCompletionFraction = selectedDayStats.dailyGoal.map {
            min(Double(selectedDayStats.cardsReviewed) / Double(max($0, 1)), 1.0)
        } ?? 0
        let remainingCardsToGoal = selectedDayStats.dailyGoal.map {
            max($0 - selectedDayStats.cardsReviewed, 0)
        } ?? 0

        let headline: String
        let detailLine: String
        if let dailyGoal = selectedDayStats.dailyGoal,
           selectedDayStats.cardsReviewed >= dailyGoal {
            headline = "Goal reached"
            detailLine = "You completed \(selectedDayStats.cardsReviewed) unique cards on \(selectedDateLabel.lowercased())."
        } else if selectedDayStats.dailyGoal != nil, selectedDayStats.cardsReviewed > 0 {
            headline = "\(remainingCardsToGoal) cards to target"
            if selectedDayStats.rawReviewCount > selectedDayStats.cardsReviewed {
                detailLine = "You already covered \(selectedDayStats.cardsReviewed) unique cards across \(selectedDayStats.rawReviewCount) review passes."
            } else {
                detailLine = "You already covered \(selectedDayStats.cardsReviewed) unique cards and earned \(selectedDayStats.xpEarnedToday) XP."
            }
        } else if selectedDayStats.cardsReviewed > 0 {
            headline = "\(selectedDayStats.cardsReviewed) cards reviewed"
            detailLine = "You already covered \(selectedDayStats.cardsReviewed) unique cards."
        } else {
            headline = "Fresh study window"
            detailLine = "No study logged for \(selectedDateLabel.lowercased()) yet."
        }

        let selectedDayOverview = HomeSelectedDayOverviewSummary(
            selectedDate: selectedDayStats.selectedDate,
            selectedDateLabel: selectedDateLabel,
            cardsReviewed: selectedDayStats.cardsReviewed,
            rawReviewCount: selectedDayStats.rawReviewCount,
            dailyGoal: selectedDayStats.dailyGoal,
            goalCompletionFraction: goalCompletionFraction,
            remainingCardsToGoal: remainingCardsToGoal,
            xpEarnedToday: selectedDayStats.xpEarnedToday,
            newCardsLearned: selectedDayStats.newCardsLearned,
            correctCardCount: selectedDayStats.correctCardCount,
            retryCardCount: selectedDayStats.retryCardCount,
            streakCount: userProfile?.currentStreak ?? 0,
            totalXP: userProfile?.totalXP ?? 0,
            headline: headline,
            detailLine: detailLine
        )
        let weeklyMomentum = analyticsSnapshot.weeklyMomentum

        dashboardSnapshot = HomeDashboardSnapshot(
            selectedDayOverview: selectedDayOverview,
            selectedDayInsight: buildSelectedDayInsightSummary(
                selectedDate: selectedDate,
                selectedDayOverview: selectedDayOverview,
                weeklyMomentum: weeklyMomentum
            ),
            weeklyMomentum: weeklyMomentum,
            pastWeekPerformance: analyticsSnapshot.pastWeekPerformance,
            selectedDayBreakdown: analyticsSnapshot.selectedDayBreakdown
        )
        dashboardSnapshotSignature = signature
    }

    /// Refreshes cached insight payloads used by the Home calendar cells.
    ///
    /// The resulting dictionary is keyed by the same `yyyy-MM-dd` format as
    /// `logsCache`, allowing the sticky calendar header to render purely from
    /// O(1) lookups instead of deriving state inside each cell.
    func refreshCalendarInsights(
        dailyLogs: [DailyActivityLog],
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

        var insights: [String: HomeCalendarDayInsight] = [:]
        insights.reserveCapacity(dailyLogs.count)

        for log in dailyLogs {
            let key = log.dateString
            insights[key] = buildCalendarDayInsight(
                key: key,
                date: log.date,
                log: log,
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
        container: ModelContainer,
        referenceDate: Date = Date()
    ) async {
        let signature = buildDeckHealthSignature(
            decks: decks,
            recentDecks: recentDecks,
            referenceDate: referenceDate
        )
        guard deckHealthSignature != signature else { return }
        deckHealthSignature = signature

        let recentDeckIDs = Set(recentDecks.map(\.persistentModelID))
        let candidates = prioritizedDeckHealthCandidates(
            from: decks,
            recentDeckIDs: recentDeckIDs
        )

        guard !candidates.isEmpty else {
            deckHealthSummaries = []
            return
        }

        let repository = PlayModeCardRepository(container: container)
        var ranked: [(summary: HomeDeckHealthSummary, riskScore: Double)] = []
        ranked.reserveCapacity(candidates.count)

        for deck in candidates {
            let report = await repository.loadDeckHealthReport(for: deck.persistentModelID)
            guard report.totalCards > 0 else { continue }

            let summary = buildDeckHealthSummary(
                for: deck,
                report: report,
                isRecentlyOpened: recentDeckIDs.contains(deck.persistentModelID),
                referenceDate: referenceDate
            )
            ranked.append((summary, deckHealthRiskScore(for: summary)))
        }

        await repository.tearDown()

        deckHealthSummaries = ranked
            .sorted { lhs, rhs in
                if lhs.summary.dueCards != rhs.summary.dueCards {
                    return lhs.summary.dueCards > rhs.summary.dueCards
                }
                if lhs.riskScore != rhs.riskScore { return lhs.riskScore > rhs.riskScore }
                if lhs.summary.newCards != rhs.summary.newCards {
                    return lhs.summary.newCards > rhs.summary.newCards
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
            context.delete(folder)
            logger.error(
                "Failed to create folder: \(String(describing: error), privacy: .public)"
            )
            presentCreateFolderError(error)
        }
    }

    /// Opens the Home performance detail sheet using the already-cached snapshot payload.
    func presentPerformanceDetail() {
        showPerformanceDetailSheet = true
    }

    /// Dismisses the Home performance detail sheet.
    func dismissPerformanceDetail() {
        showPerformanceDetailSheet = false
    }

    func invalidateDashboardDerivedCaches() {
        dashboardSnapshotSignature = ""
        selectedDayOverviewCache.removeAll(keepingCapacity: true)
        weeklyMomentumCache.removeAll(keepingCapacity: true)
        selectedDayInsightCache.removeAll(keepingCapacity: true)
        recentStudyDayCountCache.removeAll(keepingCapacity: true)
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

    static func homeAnalyticsFingerprint(for aggregates: [HomeDailyStudyAggregate]) -> Int {
        var aggregate = aggregates.count &* 1_000_211
        for entry in aggregates {
            var hasher = Hasher()
            hasher.combine(entry.dayKey)
            hasher.combine(entry.uniqueCardCount)
            hasher.combine(entry.rawReviewCount)
            hasher.combine(entry.landedCount)
            hasher.combine(entry.retryCount)
            hasher.combine(entry.xpEarned)
            hasher.combine(entry.newCardsLearned)
            hasher.combine(entry.dailyGoal)
            aggregate ^= hasher.finalize()
        }
        return aggregate
    }

    static func decksFingerprint(for decks: [DeckModel]) -> Int {
        var aggregate = decks.count &* 1_000_229
        for deck in decks {
            var hasher = Hasher()
            hasher.combine(deck.persistentModelID.hashValue)
            hasher.combine(deck.title)
            hasher.combine(deck.colorHex)
            hasher.combine(deck.cardCount)
            hasher.combine(deck.editedAt.timeIntervalSince1970.bitPattern)
            hasher.combine(deck.lastOpenedAt?.timeIntervalSince1970.bitPattern ?? 0)
            aggregate ^= hasher.finalize()
        }
        return aggregate
    }

    // MARK: - Error Surfacing

    private func presentCreateFolderError(_ error: Error) {
        let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        createFolderErrorMessage = description.isEmpty
            ? "Your folder couldn't be saved right now."
            : description
        showCreateFolderError = true
    }

}
