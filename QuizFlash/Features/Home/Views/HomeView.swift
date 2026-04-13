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

    @Environment(NavigationManager.self) private var router
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager

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
            // MARK: Scroll Geometry

            // MARK: Content
            ZStack {
                themeManager.screenBackground
                    .ignoresSafeArea()

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
                            allDeckCount: allDecks.count,
                            examGoals: examGoals,
                            router: router
                        )
                        .frame(minHeight: proxy.size.height - calendarLayout.compactHeight)
                        .zIndex(1)
                    }
                    .animation(.snappy(duration: 0.28, extraBounce: 0.04), value: calendarVM.monthRows.count)
                    .tabBarAutoHideOnScroll()
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .scrollIndicators(.hidden)
                .ignoresSafeArea(.container, edges: .top)
                .toolbar(.hidden)
                .background(Color.clear)
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
                        examGoals: examGoals,
                        userProfile: profile
                    )
                }
                .task(id: dailyLogsTaskFingerprint) {
                    viewModel.updateLogsCache(logs: dailyLogs)
                    viewModel.refreshCalendarInsights(
                        dailyLogs: dailyLogs,
                        examGoals: examGoals,
                        userProfile: profile
                    )
                    viewModel.refreshDashboardSnapshot(
                        selectedDate: calendarVM.selectedDate,
                        examGoals: examGoals,
                        userProfile: profile
                    )
                }
                .task(id: examGoalsTaskFingerprint) {
                    viewModel.updateExamGoalsCache(goals: examGoals)
                    viewModel.refreshCalendarInsights(
                        dailyLogs: dailyLogs,
                        examGoals: examGoals,
                        userProfile: profile
                    )
                    viewModel.refreshDashboardSnapshot(
                        selectedDate: calendarVM.selectedDate,
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
                        examGoals: examGoals,
                        userProfile: profile
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
    private var dailyLogsTaskFingerprint: Int {
        HomeViewModel.logsFingerprint(for: dailyLogs)
    }

    /// Stable signature used to refresh the exam-goal cache when goal data changes.
    private var examGoalsTaskFingerprint: Int {
        HomeViewModel.examGoalsFingerprint(for: examGoals)
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
            calendarInsightsCache: viewModel.calendarInsightsCache,
            calendarInsightsRevision: viewModel.calendarInsightsRevision
        )
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
