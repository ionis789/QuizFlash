// HomeView.swift
// QuizFlash
//
// Root coordinator for the Home screen.
//
// Responsibilities:
//   - Injects SwiftData queries as plain data into child views.
//   - Computes scroll geometry from `HomeCalendarAdaptiveLayout`.
//   - Orchestrates HomeCalendarSectionView and HomeDashboardView inside a single ScrollView.
//
// This view contains no business logic — all state is owned by
// HomeViewModel and CalendarViewModel, both instantiated with @State.

import SwiftUI
import SwiftData
import OSLog

// MARK: - Home View

/// The root view of the **Home** tab.
///
/// `HomeView` is a pure coordinator: it owns two `@Observable` view models,
/// feeds them with SwiftData query results, and passes derived data down to
/// its child views as immutable `let` constants.
///
/// Child views (`HomeCalendarSectionView`, `HomeDashboardView`) never hold
/// their own `@Query` — all data flows from here, keeping the fetch logic
/// centralised and testable.
struct HomeView: View {

    // MARK: - Environment

    @Environment(\.modelContext) private var context
    @Environment(NavigationManager.self) private var router
    @Environment(AppPreferences.self) private var appPreferences

    // MARK: - SwiftData Queries

    @Query(sort: \FolderModel.createdAt) private var folders: [FolderModel]
    @Query(sort: \DeckModel.title) private var allDecks: [DeckModel]
    @Query private var userProfiles: [UserProfile]
    @Query private var dailyLogs: [DailyActivityLog]
    @Query(sort: \ExamGoalModel.date) private var examGoals: [ExamGoalModel]

    /// Sorted by `lastOpenedAt` descending so we can slice the top 5 without
    /// sorting a second time in Swift — SwiftData handles this on the store side.
    @Query(sort: \DeckModel.lastOpenedAt, order: .reverse) private var recentlyOpenedQuery: [DeckModel]

    // MARK: - View Models

    @State private var viewModel = HomeViewModel()
    @State private var calendarVM = CalendarViewModel()
    @State private var lastLoggedLayoutSignature = ""

    private static let layoutLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "QuizFlash",
        category: "HomeLayout"
    )

    // MARK: - Derived Data

    /// The first (and only expected) user profile record.
    private var profile: UserProfile? {
        userProfiles.first
    }

    /// The 5 most recently opened decks that have a recorded `lastOpenedAt`.
    ///
    /// Slicing here rather than in the query avoids faulting the full deck
    /// list into memory on every tab switch.
    private var recentlyOpenedDecks: [DeckModel] {
        recentlyOpenedQuery
            .filter { $0.lastOpenedAt != nil }
            .prefix(5)
            .map { $0 }
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { proxy in
            let safeAreaTop = proxy.safeAreaInsets.top == 0 ? 47.0 : proxy.safeAreaInsets.top
            let layoutContext = HomeAdaptiveLayoutContext(containerWidth: proxy.size.width)
            let calendarLayout = HomeCalendarAdaptiveLayout(
                containerWidth: proxy.size.width,
                safeAreaTop: safeAreaTop,
                monthRowCount: calendarVM.monthRows.count,
                mode: layoutContext.mode,
                scaffold: layoutContext.headerScaffold
            )
            let greetingSummary = viewModel.greetingSummary(
                userProfile: profile,
                recentDecks: recentlyOpenedDecks,
                allDeckCount: allDecks.count,
                folderCount: folders.count
            )
            // MARK: Scroll Geometry

            // MARK: Content

            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    calendarHeader(layout: calendarLayout)
                        .zIndex(100)

                    calendarTransitionBand(horizontalInset: calendarLayout.outerHorizontalInset)

                    HomeDashboardView(
                        viewModel: viewModel,
                        folders: folders,
                        recentDecks: recentlyOpenedDecks,
                        layoutContext: layoutContext,
                        greetingSummary: greetingSummary,
                        allDeckCount: allDecks.count,
                        examGoals: examGoals,
                        router: router
                    )
                    .frame(minHeight: proxy.size.height - calendarLayout.compactHeight)
                    .zIndex(1)
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(.container, edges: .top)
            .toolbar(.hidden)
            .background(Color(.systemBackground).ignoresSafeArea())
            .onAppear {
                logLayoutIfNeeded(
                    containerWidth: proxy.size.width,
                    safeAreaTop: safeAreaTop,
                    layoutContext: layoutContext,
                    calendarLayout: calendarLayout
                )
            }
            .onChange(
                of: homeLayoutSignature(
                    containerWidth: proxy.size.width,
                    safeAreaTop: safeAreaTop,
                    layoutContext: layoutContext,
                    calendarLayout: calendarLayout
                )
            ) { _, _ in
                logLayoutIfNeeded(
                    containerWidth: proxy.size.width,
                    safeAreaTop: safeAreaTop,
                    layoutContext: layoutContext,
                    calendarLayout: calendarLayout
                )
            }

            // MARK: Lifecycle

            .onAppear {
                calendarVM.applyWeekStartPreference(appPreferences.weekStartDay)
                calendarVM.setupIfNeeded()
                viewModel.updateLogsCache(logs: dailyLogs)
                viewModel.updateExamGoalsCache(goals: examGoals)
                viewModel.refreshCalendarInsights(
                    dailyLogs: dailyLogs,
                    examGoals: examGoals,
                    userProfile: profile
                )
                viewModel.refreshDashboardSnapshot(
                    selectedDate: calendarVM.selectedDate,
                    dailyLogs: dailyLogs,
                    examGoals: examGoals,
                    userProfile: profile
                )
            }
            .onChange(of: appPreferences.weekStartDay) { _, newValue in
                calendarVM.applyWeekStartPreference(newValue)
            }
            .onChange(of: calendarVM.selectedDate) { _, newValue in
                viewModel.refreshDashboardSnapshot(
                    selectedDate: newValue,
                    dailyLogs: dailyLogs,
                    examGoals: examGoals,
                    userProfile: profile
                )
            }
            .task(id: dailyLogsCacheSignature) {
                viewModel.updateLogsCache(logs: dailyLogs)
                viewModel.refreshCalendarInsights(
                    dailyLogs: dailyLogs,
                    examGoals: examGoals,
                    userProfile: profile
                )
                viewModel.refreshDashboardSnapshot(
                    selectedDate: calendarVM.selectedDate,
                    dailyLogs: dailyLogs,
                    examGoals: examGoals,
                    userProfile: profile
                )
            }
            .task(id: examGoalsCacheSignature) {
                viewModel.updateExamGoalsCache(goals: examGoals)
                viewModel.refreshCalendarInsights(
                    dailyLogs: dailyLogs,
                    examGoals: examGoals,
                    userProfile: profile
                )
                viewModel.refreshDashboardSnapshot(
                    selectedDate: calendarVM.selectedDate,
                    dailyLogs: dailyLogs,
                    examGoals: examGoals,
                    userProfile: profile
                )
            }
            .task(id: userProfileDashboardSignature) {
                viewModel.refreshCalendarInsights(
                    dailyLogs: dailyLogs,
                    examGoals: examGoals,
                    userProfile: profile
                )
                viewModel.refreshDashboardSnapshot(
                    selectedDate: calendarVM.selectedDate,
                    dailyLogs: dailyLogs,
                    examGoals: examGoals,
                    userProfile: profile
                )
            }
            .task(id: deckHealthRefreshSignature) {
                await viewModel.refreshDeckHealthSummaries(
                    decks: allDecks,
                    recentDecks: recentlyOpenedDecks,
                    examGoals: examGoals,
                    container: context.container
                )
            }
            .sheet(isPresented: $viewModel.showCreateFolder) {
                CreateFolderSheet(viewModel: viewModel)
            }
            .sheet(item: $viewModel.examGoalSheetPresentation, onDismiss: viewModel.resetExamGoalDraft) { presentation in
                CreateExamGoalSheet(
                    viewModel: viewModel,
                    decks: allDecks,
                    editingGoal: editingExamGoal(for: presentation)
                )
            }
        }
    }

    private func editingExamGoal(for presentation: ExamGoalSheetPresentation) -> ExamGoalModel? {
        switch presentation {
        case .create:
            return nil
        case .edit(let goalID):
            return examGoals.first(where: { $0.persistentModelID == goalID })
        }
    }

    /// Stable signature used to refresh the daily-log cache when Home data changes.
    private var dailyLogsCacheSignature: [String] {
        dailyLogs
            .map { "\($0.dateString)-\($0.cardsReviewed)-\($0.xpEarnedToday)-\($0.newCardsLearned)-\($0.dailyGoal)" }
            .sorted()
    }

    /// Stable signature used to refresh the exam-goal cache when goal data changes.
    private var examGoalsCacheSignature: [String] {
        examGoals
            .map {
                [
                    "\($0.persistentModelID.hashValue)",
                    HomeViewModel.dateKeyFormatter.string(from: $0.date),
                    $0.statusRaw,
                    $0.title,
                    $0.note,
                    "\($0.targetWorkload)",
                    "\($0.linkedDecks.count)"
                ].joined(separator: "|")
            }
            .sorted()
    }

    /// Stable signature used to refresh Home dashboard summaries when profile stats change.
    private var userProfileDashboardSignature: String {
        guard let profile else { return "no-profile" }
        return [
            "\(profile.totalXP)",
            "\(profile.currentStreak)",
            "\(profile.longestStreak)",
            "\(profile.lastActiveDate?.timeIntervalSince1970 ?? 0)"
        ].joined(separator: "|")
    }

    /// Stable signature used to refresh Home deck-health summaries when deck-facing inputs change.
    private var deckHealthRefreshSignature: String {
        let todayKey = HomeViewModel.dateKeyFormatter.string(from: Date())
        let deckSignature = allDecks
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

        let recentSignature = recentlyOpenedDecks
            .map { "\($0.persistentModelID.hashValue)" }
            .joined(separator: "~")

        return [
            todayKey,
            deckSignature,
            recentSignature,
            examGoalsCacheSignature.joined(separator: "~")
        ].joined(separator: "||")
    }

    private func calendarTransitionBand(horizontalInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: UIConstants.Layout.homeCalendarTransitionTopPadding)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.12), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
                .padding(.horizontal, horizontalInset)

            Color.clear
                .frame(height: UIConstants.Layout.homeCalendarTransitionBottomPadding)
        }
    }

    @ViewBuilder
    private func calendarHeader(
        layout: HomeCalendarAdaptiveLayout
    ) -> some View {
        HomeCalendarSectionView(
            calendarVM: calendarVM,
            layout: layout,
            calendarInsightsCache: viewModel.calendarInsightsCache
        )
    }

    private func handleHomeAction(_ action: HomeGreetingAction) {
        switch action {
        case .openDeck(let deckID):
            router.append(
                DeckNavigationValue(
                    deckID: deckID,
                    backLabel: router.activeTab.rawValue
                )
            )
        case .switchTab(let tab):
            router.activeTab = tab
        case .createFolder:
            viewModel.showCreateFolder = true
        }
    }

    private func homeLayoutSignature(
        containerWidth: CGFloat,
        safeAreaTop: CGFloat,
        layoutContext: HomeAdaptiveLayoutContext,
        calendarLayout: HomeCalendarAdaptiveLayout
    ) -> String {
        [
            roundedLayoutValue(containerWidth),
            roundedLayoutValue(safeAreaTop),
            String(describing: layoutContext.mode),
            String(describing: layoutContext.headerScaffold),
            roundedLayoutValue(layoutContext.calendarContext.contentWidth),
            roundedLayoutValue(layoutContext.dashboardContext.contentWidth),
            roundedLayoutValue(calendarLayout.expandedCalendarWidth),
            roundedLayoutValue(calendarLayout.expandedCompanionWidth),
            roundedLayoutValue(calendarLayout.compactCapsuleWidth)
        ].joined(separator: "|")
    }

    private func logLayoutIfNeeded(
        containerWidth: CGFloat,
        safeAreaTop: CGFloat,
        layoutContext: HomeAdaptiveLayoutContext,
        calendarLayout: HomeCalendarAdaptiveLayout
    ) {
#if DEBUG
        let signature = homeLayoutSignature(
            containerWidth: containerWidth,
            safeAreaTop: safeAreaTop,
            layoutContext: layoutContext,
            calendarLayout: calendarLayout
        )

        guard lastLoggedLayoutSignature != signature else { return }
        lastLoggedLayoutSignature = signature

        Self.layoutLogger.notice(
            """
            home_layout \
            container=\(Double(containerWidth), format: .fixed(precision: 1)) \
            safeTop=\(Double(safeAreaTop), format: .fixed(precision: 1)) \
            mode=\(String(describing: layoutContext.mode), privacy: .public) \
            header=\(String(describing: layoutContext.headerScaffold), privacy: .public) \
            calendarContent=\(Double(layoutContext.calendarContext.contentWidth), format: .fixed(precision: 1)) \
            dashboardContent=\(Double(layoutContext.dashboardContext.contentWidth), format: .fixed(precision: 1)) \
            expandedCalendar=\(Double(calendarLayout.expandedCalendarWidth), format: .fixed(precision: 1)) \
            companion=\(Double(calendarLayout.expandedCompanionWidth), format: .fixed(precision: 1)) \
            compactCapsule=\(Double(calendarLayout.compactCapsuleWidth), format: .fixed(precision: 1))
            """
        )
#endif
    }

    private func roundedLayoutValue(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
    }
}
