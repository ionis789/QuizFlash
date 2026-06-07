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

    // MARK: - View Models

    @State private var viewModel = HomeViewModel()
    @State private var calendarVM = CalendarViewModel()
    @State private var lastLoggedLayoutSignature = ""
    @State private var cachedFolderModels: [FolderModel] = []
    @State private var cachedFolderSnapshots: [HomeFolderSnapshot] = []
    @State private var cachedRecentlyOpenedDeckSnapshots: [LibraryDeckRowSnapshot] = []
    @State private var cachedAllDeckCount = 0

    private static let layoutLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "QuizFlash",
        category: "HomeLayout"
    )
    private static let edgeShadowDebugScreenID = EdgeShadowDebugScreenID.homeCalendar

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
            let selectedDate = calendarVM.selectedDate
            let weekStartDate = dashboardWeekStartDate

            ZStack(alignment: .bottomTrailing) {
                themeManager.screenBackground
                    .ignoresSafeArea()

                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        ScrollPositionRestorer(
                            getOffset: { viewModel.savedScrollOffset },
                            onOffsetChange: { offset in
                                viewModel.savedScrollOffset = offset
                            }
                        )
                        .frame(width: 0, height: 0)

                        calendarHeader(layout: calendarLayout)
                            .zIndex(100)

                        calendarTransitionBand(horizontalInset: calendarLayout.outerHorizontalInset)

                        HomeDashboardView(
                            viewModel: viewModel,
                            folderSnapshots: cachedFolderSnapshots,
                            recentDeckSnapshots: cachedRecentlyOpenedDeckSnapshots,
                            layoutContext: layoutContext,
                            allDeckCount: cachedAllDeckCount,
                            onOpenDeck: openDeck,
                            onOpenFolder: openFolder,
                            onCreateFolder: presentCreateFolder,
                            onCreateDeck: openCreateTab
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
                .fullScreenSheet(
                    isPresented: $viewModel.showPerformanceDetailSheet,
                    configuration: .sheet(
                        heightMode: .custom(0.75),
                        showsCloseButton: true
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

                HomeDataCoordinator(
                    viewModel: viewModel,
                    selectedDate: selectedDate,
                    weekStartDate: weekStartDate,
                    container: modelContext.container,
                    folderModels: $cachedFolderModels,
                    folderSnapshots: $cachedFolderSnapshots,
                    recentDeckSnapshots: $cachedRecentlyOpenedDeckSnapshots,
                    allDeckCount: $cachedAllDeckCount
                )
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)

                debugShadowControls(safeAreaTop: safeAreaTop)
            }
        }
    }

    private var dashboardWeekStartDate: Date {
        let calendar = appPreferences.resolvedCalendar
        let selectedDay = calendar.startOfDay(for: calendarVM.selectedDate)
        return calendar.dateInterval(of: .weekOfYear, for: selectedDay)?.start ?? selectedDay
    }

    private func openDeck(_ deckID: PersistentIdentifier) {
        router.append(
            DeckNavigationValue(
                deckID: deckID,
                backLabel: router.activeTab.localizedTitle(locale: appPreferences.resolvedLocale)
            )
        )
    }

    private func openFolder(_ folderID: PersistentIdentifier) {
        guard let folder = cachedFolderModels.first(where: { $0.persistentModelID == folderID }) else {
            return
        }

        router.append(
            AppRoute.folder(
                folder,
                backLabel: router.activeTab.localizedTitle(locale: appPreferences.resolvedLocale)
            )
        )
    }

    private func presentCreateFolder() {
        viewModel.showCreateFolder = true
    }

    private func openCreateTab() {
        router.activeTab = .create
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
            blurColor: homeBlurColor,
            blurEnabled: homeBlurEnabled
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

    private var homeBlurEnabled: Bool {
        homeShadowDebugSettings.topEnabled
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
                    supportsBottomEdge: false,
                    panelTitleOverride: "Header Blur",
                    showButtonTitleOverride: "Tune Header Blur",
                    hideButtonTitleOverride: "Hide Header Blur",
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
            roundedLayoutValue(calendarLayout.compactCapsuleWidth),
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

// MARK: - Home Data Coordinator

private struct HomeDataCoordinator: View {
    @Query(sort: \FolderModel.createdAt) private var folders: [FolderModel]
    @Query(sort: \DeckModel.title) private var allDecks: [DeckModel]
    @Query private var userProfiles: [UserProfile]
    @Query private var dailyLogs: [DailyActivityLog]
    @Query(sort: \HomeDailyStudyAggregate.dayDate, order: .reverse) private var homeStudyAggregates: [HomeDailyStudyAggregate]
    @Query(sort: \DeckModel.lastOpenedAt, order: .reverse) private var recentlyOpenedQuery: [DeckModel]

    let viewModel: HomeViewModel
    let selectedDate: Date
    let weekStartDate: Date
    let container: ModelContainer

    @Binding var folderModels: [FolderModel]
    @Binding var folderSnapshots: [HomeFolderSnapshot]
    @Binding var recentDeckSnapshots: [LibraryDeckRowSnapshot]
    @Binding var allDeckCount: Int

    @State private var homeDataSignatures = HomeDataSignatures()
    @State private var folderSignature = ""
    @State private var recentDeckSignature = ""

    private struct HomeDataSignatures: Equatable {
        var logs: Int = 0
        var analytics: Int = 0
        var decks: Int = 0
        var profile: String = "no-profile"

        var calendarInsightsTaskSignature: String {
            [
                "\(logs)",
                profile,
            ].joined(separator: "||")
        }

        func dashboardTaskSignature(selectedDateKey: String) -> String {
            [
                selectedDateKey,
                "\(logs)",
                profile,
                "\(analytics)",
                "\(decks)",
            ].joined(separator: "||")
        }
    }

    private var profile: UserProfile? {
        userProfiles.first
    }

    private var selectedDateKey: String {
        HomeViewModel.dateKeyFormatter.string(from: selectedDate)
    }

    private var calendarInsightsSignature: String {
        homeDataSignatures.calendarInsightsTaskSignature
    }

    private var dashboardSignature: String {
        homeDataSignatures.dashboardTaskSignature(selectedDateKey: selectedDateKey)
    }

    private var homeDataRefreshSignal: String {
        [
            "\(dailyLogs.count)",
            "\(homeStudyAggregates.count)",
            "\(allDecks.count)",
            "\(folders.count)",
            "\(recentlyOpenedQuery.count)",
            recentDecksPreviewSignature,
            userProfileDashboardSignature,
        ].joined(separator: "|")
    }

    private var recentDecksPreviewSignature: String {
        recentlyOpenedQuery
            .prefix(5)
            .map { deck in
                [
                    "\(deck.persistentModelID.hashValue)",
                    "\(deck.lastOpenedAt?.timeIntervalSince1970.bitPattern ?? 0)",
                ].joined(separator: ":")
            }
            .joined(separator: ",")
    }

    private var userProfileDashboardSignature: String {
        guard let profile else { return "no-profile" }
        return [
            "\(profile.totalXP)",
            "\(profile.currentStreak)",
            "\(profile.longestStreak)",
            "\(profile.lastActiveDate?.timeIntervalSince1970 ?? 0)",
        ].joined(separator: "|")
    }

    var body: some View {
        Color.clear
            .task(id: homeDataRefreshSignal) {
                refreshCachedHomeInputs()
            }
            .task(id: calendarInsightsSignature) {
                viewModel.updateLogsCache(logs: dailyLogs)
                viewModel.refreshCalendarInsights(
                    dailyLogs: dailyLogs,
                    userProfile: profile
                )
            }
            .task(id: dashboardSignature) {
                viewModel.updateLogsCache(logs: dailyLogs)
                await viewModel.refreshDashboardSnapshot(
                    selectedDate: selectedDate,
                    weekStart: weekStartDate,
                    userProfile: profile,
                    container: container,
                    analyticsRevision: homeDataSignatures.analytics,
                    deckRevision: homeDataSignatures.decks
                )
            }
    }

    private func refreshCachedHomeInputs() {
        let nextSignatures = HomeDataSignatures(
            logs: HomeViewModel.logsFingerprint(for: dailyLogs),
            analytics: HomeViewModel.homeAnalyticsFingerprint(for: homeStudyAggregates),
            decks: HomeViewModel.decksFingerprint(for: allDecks),
            profile: userProfileDashboardSignature
        )
        if homeDataSignatures != nextSignatures {
            homeDataSignatures = nextSignatures
        }

        refreshFolderCache()
        refreshRecentDeckCache()

        if allDeckCount != allDecks.count {
            allDeckCount = allDecks.count
        }
    }

    private func refreshFolderCache() {
        let nextSignature = folders
            .map { folder in
                [
                    "\(folder.persistentModelID.hashValue)",
                    folder.title,
                    folder.colorHex,
                    "\(folder.deckCount)",
                ].joined(separator: ":")
            }
            .joined(separator: "|")

        guard folderSignature != nextSignature else { return }
        folderSignature = nextSignature
        folderModels = folders
        folderSnapshots = folders.map { folder in
            HomeFolderSnapshot(
                id: folder.persistentModelID,
                title: folder.title,
                colorHex: folder.colorHex,
                deckCount: folder.deckCount
            )
        }
    }

    private func refreshRecentDeckCache() {
        let nextDecks = Array(recentlyOpenedQuery.lazy.filter { $0.lastOpenedAt != nil }.prefix(5))
        let nextSignature = nextDecks
            .map { deck in
                [
                    "\(deck.persistentModelID.hashValue)",
                    deck.title,
                    deck.colorHex,
                    "\(deck.cardCount)",
                    "\(deck.lastOpenedAt?.timeIntervalSince1970.bitPattern ?? 0)",
                ].joined(separator: ":")
            }
            .joined(separator: "|")

        guard recentDeckSignature != nextSignature else { return }
        recentDeckSignature = nextSignature
        recentDeckSnapshots = LibraryGrouping.makeDeckSnapshots(from: nextDecks)
    }
}
