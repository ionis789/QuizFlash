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
import UIKit

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
    @Environment(DevelopmentPreferences.self) private var developmentPreferences
    @Environment(\.modelContext) private var modelContext

    // MARK: - SwiftData Queries

    @Query(sort: \FolderModel.createdAt) private var folders: [FolderModel]
    @Query(sort: \DeckModel.title) private var allDecks: [DeckModel]
    @Query private var userProfiles: [UserProfile]
    @Query private var dailyLogs: [DailyActivityLog]
    @Query(sort: \ExamGoalModel.date) private var examGoals: [ExamGoalModel]
    @Query(sort: \HomeDailyStudyAggregate.dayDate, order: .reverse) private var homeStudyAggregates: [HomeDailyStudyAggregate]

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
    private static let edgeShadowDebugScreenID = "home.calendar"

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
            let safeAreaTop = resolvedSafeAreaTop(from: proxy.safeAreaInsets.top)
            let layoutContext = HomeAdaptiveLayoutContext(containerWidth: proxy.size.width)
            let calendarLayout = HomeCalendarAdaptiveLayout(
                containerWidth: proxy.size.width,
                safeAreaTop: safeAreaTop,
                monthRowCount: calendarVM.monthRows.count,
                mode: layoutContext.mode,
                scaffold: layoutContext.headerScaffold
            )
            ZStack(alignment: .bottomTrailing) {
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
                }
                .onChange(of: appPreferences.weekStartDay) { _, newValue in
                    calendarVM.applyWeekStartPreference(newValue)
                }
                .task(id: calendarInsightsTaskSignature) {
                    viewModel.updateLogsCache(logs: dailyLogs)
                    viewModel.updateExamGoalsCache(goals: examGoals)
                    viewModel.refreshCalendarInsights(
                        dailyLogs: dailyLogs,
                        examGoals: examGoals,
                        userProfile: profile
                    )
                }
                .task(id: dashboardTaskSignature) {
                    viewModel.updateLogsCache(logs: dailyLogs)
                    viewModel.updateExamGoalsCache(goals: examGoals)
                    await viewModel.refreshDashboardSnapshot(
                        selectedDate: calendarVM.selectedDate,
                        weekStart: dashboardWeekStartDate,
                        examGoals: examGoals,
                        userProfile: profile,
                        container: modelContext.container,
                        analyticsRevision: homeAnalyticsTaskFingerprint,
                        deckRevision: decksTaskFingerprint
                    )
                }
                .fullScreenSheet(
                    isPresented: $viewModel.showPerformanceDetailSheet,
                    configuration: .sheet(
                        heightMode: .custom(0.75),
                        dragActivationArea: .fixed(180)
                    )
                ) { safeAreaInsets in
                    HomePerformanceDetailSheetView(
                        summary: viewModel.dashboardSnapshot.pastWeekPerformance,
                        safeAreaInsets: safeAreaInsets
                    )
                } background: {
                    themeManager.screenBackground
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
                .alert("Save Error", isPresented: $viewModel.showExamGoalActionError) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(viewModel.examGoalActionErrorMessage)
                }

                debugShadowControls(safeAreaTop: safeAreaTop)
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

    /// Stable signature used to refresh the Home dashboard when aggregate rows change.
    private var homeAnalyticsTaskFingerprint: Int {
        HomeViewModel.homeAnalyticsFingerprint(for: homeStudyAggregates)
    }

    /// Stable signature used to refresh selected-day deck snapshots when deck metadata changes.
    private var decksTaskFingerprint: Int {
        HomeViewModel.decksFingerprint(for: allDecks)
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

    /// Combined signature for calendar insight refreshes.
    private var calendarInsightsTaskSignature: String {
        [
            "\(dailyLogsTaskFingerprint)",
            "\(examGoalsTaskFingerprint)",
            userProfileDashboardSignature
        ].joined(separator: "||")
    }

    /// Combined signature for aggregate-backed Home dashboard reloads.
    private var dashboardTaskSignature: String {
        [
            HomeViewModel.dateKeyFormatter.string(from: calendarVM.selectedDate),
            "\(dailyLogsTaskFingerprint)",
            "\(examGoalsTaskFingerprint)",
            userProfileDashboardSignature,
            "\(homeAnalyticsTaskFingerprint)",
            "\(decksTaskFingerprint)"
        ].joined(separator: "||")
    }

    private var dashboardWeekStartDate: Date {
        let calendar = appPreferences.resolvedCalendar
        let selectedDay = calendar.startOfDay(for: calendarVM.selectedDate)
        return calendar.dateInterval(of: .weekOfYear, for: selectedDay)?.start ?? selectedDay
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
            calendarInsightsRevision: viewModel.calendarInsightsRevision,
            blurConfiguration: homeBlurConfiguration,
            blurHeightOffset: homeBlurHeightOffset,
            blurColor: homeBlurColor
        )
    }

    private var homeBlurConfiguration: ScreenTopProgressiveBlurConfiguration {
        homeShadowDebugSettings.progressiveBlurConfiguration
    }

    private var homeBlurHeightOffset: CGFloat {
        homeShadowDebugSettings.heightOffset
    }

    private var homeBlurColor: Color {
        homeShadowDebugSettings.resolvedColor
    }

    private var homeShadowDebugSettings: EdgeShadowDebugSettings {
        developmentPreferences.edgeShadowSettings(for: Self.edgeShadowDebugScreenID)
    }

    @ViewBuilder
    private func debugShadowControls(safeAreaTop: CGFloat) -> some View {
#if DEBUG
        if developmentPreferences.edgeShadowTuningEnabled {
            EdgeShadowDebugFloatingPanel(
                mode: .progressiveBlur,
                settings: Binding(
                    get: {
                        developmentPreferences.edgeShadowSettings(for: Self.edgeShadowDebugScreenID)
                    },
                    set: {
                        developmentPreferences.setEdgeShadowSettings(
                            $0,
                            for: Self.edgeShadowDebugScreenID
                        )
                    }
                ),
                onReset: {
                    developmentPreferences.resetEdgeShadowSettings(for: Self.edgeShadowDebugScreenID)
                }
            )
            .padding(.trailing, UIConstants.Spacing.medium)
            .padding(.bottom, 92)
            .padding(.top, safeAreaTop)
            .zIndex(200)
        }
#else
        EmptyView()
#endif
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

    private func resolvedSafeAreaTop(from proxySafeAreaTop: CGFloat) -> CGFloat {
        if proxySafeAreaTop > 0 {
            return proxySafeAreaTop
        }

        let activeWindowScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })

        return activeWindowScene?.windows.first(where: \.isKeyWindow)?.safeAreaInsets.top ?? 0
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
