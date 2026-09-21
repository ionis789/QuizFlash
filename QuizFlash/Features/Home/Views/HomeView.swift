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
    @State private var recentDeckActionViewModel = LibraryViewModel()
    @State private var lastLoggedLayoutSignature = ""
    @State private var cachedFolderModels: [FolderModel] = []
    @State private var cachedFolderSnapshots: [HomeFolderSnapshot] = []
    @State private var cachedRecentlyOpenedDeckSnapshots: [LibraryDeckRowSnapshot] = []
    @State private var cachedRecentlyOpenedDeckModels: [DeckModel] = []
    @State private var cachedAllDeckCount = 0
    @State private var folderSheetDestination: HomeFolderSheetDestination?
    @State private var folderToDelete: HomeFolderActionTarget?
    @State private var folderActionErrorMessage = ""
    @State private var showsFolderActionError = false

    private static let layoutLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "QuizFlash",
        category: "HomeLayout"
    )
    private static let edgeShadowDebugScreenID = EdgeShadowDebugScreenID.homeCalendar
    /// Keeps a black buffer below the short form while the keyboard enters.
    private static let createFolderSheetHeight: CGFloat = 360

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

                        calendarTransitionBand()

                        HomeDashboardView(
                            viewModel: viewModel,
                            folderSnapshots: cachedFolderSnapshots,
                            recentDeckSnapshots: cachedRecentlyOpenedDeckSnapshots,
                            layoutContext: layoutContext,
                            allDeckCount: cachedAllDeckCount,
                            onOpenDeck: openDeck,
                            onExportDeck: exportRecentDeck,
                            onMoveDeck: moveRecentDeck,
                            onDeleteDeck: deleteRecentDeck,
                            onOpenFolder: openFolder,
                            onRenameFolder: { folderSheetDestination = .rename($0) },
                            onChangeFolderColor: { folderSheetDestination = .changeColor($0) },
                            onMoveDecksToFolder: { folderSheetDestination = .moveDecks($0) },
                            onDeleteFolder: { folderToDelete = $0 },
                            onCreateFolder: presentCreateFolder,
                            onCreateDeck: openCreateTab
                        )
                        .frame(minHeight: proxy.size.height - calendarLayout.compactHeight)
                        .zIndex(1)
                    }
                    .tabBarAutoHideOnScroll()
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .scrollIndicators(.hidden)
                .ignoresSafeArea(.container, edges: .top)
                .toolbar(.hidden)
                .background(Color.clear)
                .onAppear {
                    AuthFlowDebugTrace.record(
                        "home.layout-log.begin",
                        layer: "home-view"
                    )
                    logLayoutIfNeeded(
                        containerWidth: proxy.size.width,
                        safeAreaTop: safeAreaTop,
                        layoutContext: layoutContext,
                        calendarLayout: calendarLayout
                    )
                    AuthFlowDebugTrace.record(
                        "home.layout-log.end",
                        layer: "home-view"
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
                    AuthFlowDebugTrace.record(
                        "home.calendar.preference.begin",
                        layer: "home-view"
                    )
                    calendarVM.applyWeekStartPreference(appPreferences.weekStartDay)
                    AuthFlowDebugTrace.record(
                        "home.calendar.preference.end",
                        layer: "home-view"
                    )
                    AuthFlowDebugTrace.record(
                        "home.calendar.setup.begin",
                        layer: "home-view"
                    )
                    calendarVM.setupIfNeeded()
                    AuthFlowDebugTrace.record(
                        "home.calendar.setup.end",
                        layer: "home-view"
                    )
                }
                .onChange(of: appPreferences.weekStartDay) { _, newValue in
                    calendarVM.applyWeekStartPreference(newValue)
                }
                .fullScreenSheet(
                    isPresented: $viewModel.showPerformanceDetailSheet,
                    configuration: .sheet(
                        heightMode: .adaptiveAbsolute(500, maxFraction: 0.64),
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
                .fullScreenSheet(
                    isPresented: $viewModel.showCreateFolder,
                    configuration: .sheet(
                        heightMode: .safeAreaAbsolute(Self.createFolderSheetHeight, maxFraction: 0.78),
                        showsDefaultTopProgressiveBlur: false,
                        showsCloseButton: false,
                        avoidsKeyboard: true
                    )
                ) { safeAreaInsets in
                    CreateFolderSheet(
                        viewModel: viewModel,
                        safeAreaInsets: safeAreaInsets
                    )
                } background: {
                    themeManager.screenBackground
                }
                .fullScreenSheet(
                    item: $folderSheetDestination,
                    configuration: .sheet(
                        heightMode: .fullScreen,
                        showsDefaultTopProgressiveBlur: false,
                        showsCloseButton: true,
                        avoidsKeyboard: true
                    )
                ) { destination, safeAreaInsets in
                    folderActionSheet(destination, safeAreaInsets: safeAreaInsets)
                } background: {
                    themeManager.screenBackground
                }

                HomeDataCoordinator(
                    viewModel: viewModel,
                    selectedDate: selectedDate,
                    weekStartDate: weekStartDate,
                    container: modelContext.container,
                    folderModels: $cachedFolderModels,
                    folderSnapshots: $cachedFolderSnapshots,
                    recentDeckSnapshots: $cachedRecentlyOpenedDeckSnapshots,
                    recentDeckModels: $cachedRecentlyOpenedDeckModels,
                    allDeckCount: $cachedAllDeckCount
                )
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)

                debugShadowControls(safeAreaTop: safeAreaTop)
            }
        }
        .onAppear {
            AuthFlowDebugTrace.record(
                "home.content.appear",
                layer: "home-view",
                details: ["activeTab": String(describing: router.activeTab)]
            )
        }
        .onDisappear {
            AuthFlowDebugTrace.record(
                "home.content.disappear",
                layer: "home-view",
                details: ["activeTab": String(describing: router.activeTab)]
            )
        }
        .modifier(LibraryModalsAndDialogs(
            viewModel: recentDeckActionViewModel,
            context: modelContext,
            decks: cachedRecentlyOpenedDeckModels,
            folders: cachedFolderModels
        ))
        .modifier(LibraryAlerts(viewModel: recentDeckActionViewModel))
        .confirmationDialog(
            AppLocalization.string("Delete Folder?", locale: appPreferences.resolvedLocale),
            isPresented: Binding(
                get: { folderToDelete != nil },
                set: { if !$0 { folderToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(AppLocalization.string("Delete", locale: appPreferences.resolvedLocale), role: .destructive) {
                deleteFolder()
            }
            Button(AppLocalization.string("Cancel", locale: appPreferences.resolvedLocale), role: .cancel) {
                folderToDelete = nil
            }
        } message: {
            Text(AppLocalization.string("Decks in this folder will remain in Library.", locale: appPreferences.resolvedLocale))
        }
        .alert(AppLocalization.string("Save Error", locale: appPreferences.resolvedLocale), isPresented: $showsFolderActionError) {
            Button(AppLocalization.string("OK", locale: appPreferences.resolvedLocale), role: .cancel) {}
        } message: {
            Text(folderActionErrorMessage)
        }
    }

    @ViewBuilder
    private func folderActionSheet(
        _ destination: HomeFolderSheetDestination,
        safeAreaInsets: UIEdgeInsets
    ) -> some View {
        switch destination {
        case .rename(let target):
            HomeFolderEditSheet(
                target: target,
                mode: .rename,
                safeAreaInsets: safeAreaInsets,
                onSave: { title, _ in updateFolder(target, title: title, colorHex: nil) }
            )
        case .changeColor(let target):
            HomeFolderEditSheet(
                target: target,
                mode: .changeColor,
                safeAreaInsets: safeAreaInsets,
                onSave: { _, colorHex in updateFolder(target, title: nil, colorHex: colorHex) }
            )
        case .moveDecks(let target):
            MoveDecksToFolderSheet(
                target: target,
                safeAreaInsets: safeAreaInsets,
                onMove: { selectedDeckIDs in
                    moveDecks(selectedDeckIDs, to: target)
                }
            )
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

    private func exportRecentDeck(_ target: LibraryDeckActionTarget) {
        recentDeckActionViewModel.exportSingleDeck(
            target,
            from: cachedRecentlyOpenedDeckModels
        )
    }

    private func moveRecentDeck(_ target: LibraryDeckActionTarget) {
        recentDeckActionViewModel.deckToMove = target
    }

    private func deleteRecentDeck(_ target: LibraryDeckActionTarget) {
        recentDeckActionViewModel.deckToDelete = target
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

    private func updateFolder(
        _ target: HomeFolderActionTarget,
        title: String?,
        colorHex: String?
    ) -> Bool {
        guard let folder = modelContext.safeModel(for: target.id, as: FolderModel.self) else {
            return false
        }

        let oldTitle = folder.title
        let oldColorHex = folder.colorHex
        let oldEditedAt = folder.editedAt
        if let title {
            folder.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let colorHex {
            folder.colorHex = colorHex
        }
        folder.editedAt = Date()

        do {
            try modelContext.save()
            CloudSyncCoordinator.shared.enqueueUpsert(for: folder, context: modelContext)
            refreshCachedFolderSnapshots()
            return true
        } catch {
            folder.title = oldTitle
            folder.colorHex = oldColorHex
            folder.editedAt = oldEditedAt
            presentFolderActionError(error)
            return false
        }
    }

    private func deleteFolder() {
        guard let target = folderToDelete,
              let folder = modelContext.safeModel(for: target.id, as: FolderModel.self) else {
            folderToDelete = nil
            return
        }

        let decks = folder.decks
        let now = Date()
        for deck in decks {
            deck.folder = nil
            deck.editedAt = now
        }
        CloudSyncCoordinator.shared.enqueueDelete(for: folder)
        modelContext.delete(folder)

        do {
            try modelContext.save()
            decks.forEach { CloudSyncCoordinator.shared.enqueueUpsert(for: $0, context: modelContext) }
            refreshCachedFolderSnapshots()
            folderToDelete = nil
        } catch {
            modelContext.rollback()
            folderToDelete = nil
            presentFolderActionError(error)
        }
    }

    private func presentFolderActionError(_ error: Error) {
        folderActionErrorMessage = error.localizedDescription
        showsFolderActionError = true
    }

    private func moveDecks(
        _ selectedDeckIDs: Set<PersistentIdentifier>,
        to target: HomeFolderActionTarget
    ) {
        guard !selectedDeckIDs.isEmpty,
              let destination = modelContext.safeModel(for: target.id, as: FolderModel.self) else {
            return
        }

        let decks = selectedDeckIDs.compactMap {
            modelContext.safeModel(for: $0, as: DeckModel.self)
        }
        guard !decks.isEmpty else { return }

        let sourceFolders = decks.compactMap(\.folder)
        let affectedFolders = Dictionary(
            grouping: sourceFolders + [destination],
            by: \.persistentModelID
        ).compactMap(\.value.first)
        let originalCounts = Dictionary(
            uniqueKeysWithValues: affectedFolders.map { ($0.persistentModelID, $0.deckCount) }
        )
        let originalFolders = Dictionary(uniqueKeysWithValues: decks.map { ($0.persistentModelID, $0.folder) })
        let originalEditedDates = Dictionary(uniqueKeysWithValues: decks.map { ($0.persistentModelID, $0.editedAt) })
        let now = Date()

        for deck in decks where deck.folder?.persistentModelID != destination.persistentModelID {
            deck.folder?.deckCount -= 1
            deck.folder?.editedAt = now
            destination.deckCount += 1
            destination.editedAt = now
            deck.folder = destination
            deck.editedAt = now
        }

        do {
            try modelContext.save()
            decks.forEach { CloudSyncCoordinator.shared.enqueueUpsert(for: $0, context: modelContext) }
            affectedFolders.forEach { CloudSyncCoordinator.shared.enqueueUpsert(for: $0, context: modelContext) }
            refreshCachedFolderSnapshots()
        } catch {
            for deck in decks {
                deck.folder = originalFolders[deck.persistentModelID] ?? nil
                if let editedAt = originalEditedDates[deck.persistentModelID] {
                    deck.editedAt = editedAt
                }
            }
            for folder in affectedFolders {
                if let count = originalCounts[folder.persistentModelID] {
                    folder.deckCount = count
                }
            }
            presentFolderActionError(error)
        }
    }

    private func refreshCachedFolderSnapshots() {
        cachedFolderModels.removeAll { $0.isDeleted }
        cachedFolderSnapshots = cachedFolderModels.map { folder in
            HomeFolderSnapshot(
                id: folder.persistentModelID,
                title: folder.title,
                colorHex: folder.colorHex,
                deckCount: folder.deckCount
            )
        }
    }

    private func presentCreateFolder() {
        viewModel.showCreateFolder = true
    }

    private func openCreateTab() {
        router.activeTab = .create
    }

    private func calendarTransitionBand() -> some View {
        Color.clear
            .frame(
                height: UIConstants.Layout.homeCalendarTransitionTopPadding
                    + UIConstants.Layout.homeCalendarTransitionBottomPadding
            )
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
    @Environment(AppPreferences.self) private var appPreferences

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
    @Binding var recentDeckModels: [DeckModel]
    @Binding var allDeckCount: Int

    @State private var homeDataSignatures = HomeDataSignatures()
    @State private var folderSignature = ""
    @State private var recentDeckSignature = ""

    private struct HomeDataSignatures: Equatable {
        var logs: Int = 0
        var analytics: Int = 0
        var decks: Int = 0
        var profile: String = "no-profile"
        var dailyCardsGoal: String = "no-goal"

        var calendarInsightsTaskSignature: String {
            [
                "\(logs)",
                "\(analytics)",
                profile,
                dailyCardsGoal,
            ].joined(separator: "||")
        }

        func dashboardTaskSignature(selectedDateKey: String) -> String {
            [
                selectedDateKey,
                "\(logs)",
                profile,
                "\(analytics)",
                "\(decks)",
                dailyCardsGoal,
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
            folderPreviewSignature,
            "\(recentlyOpenedQuery.count)",
            recentDecksPreviewSignature,
            userProfileDashboardSignature,
            dailyCardsGoalSignature,
        ].joined(separator: "|")
    }

    private var dailyCardsGoalSignature: String {
        appPreferences.dailyCardsGoal.map(String.init) ?? "no-goal"
    }

    private var folderPreviewSignature: String {
        folders.map { folder in
            [
                "\(folder.persistentModelID.hashValue)",
                folder.title,
                folder.colorHex,
                "\(folder.deckCount)",
            ].joined(separator: ":")
        }
        .joined(separator: "|")
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
                let currentSignatures = refreshCachedHomeInputs()
                viewModel.updateLogsCache(logs: dailyLogs)
                viewModel.refreshCalendarInsights(
                    dailyLogs: dailyLogs,
                    userProfile: profile,
                    studyAggregates: homeStudyAggregates,
                    analyticsRevision: currentSignatures.analytics,
                    dailyCardsGoal: appPreferences.dailyCardsGoal
                )
            }
            .task(id: dashboardSignature) {
                let currentSignatures = refreshCachedHomeInputs()
                viewModel.updateLogsCache(logs: dailyLogs)
                await viewModel.refreshDashboardSnapshot(
                    selectedDate: selectedDate,
                    weekStart: weekStartDate,
                    userProfile: profile,
                    container: container,
                    analyticsRevision: currentSignatures.analytics,
                    deckRevision: currentSignatures.decks,
                    dailyCardsGoal: appPreferences.dailyCardsGoal
                )
            }
    }

    @discardableResult
    private func refreshCachedHomeInputs() -> HomeDataSignatures {
        let nextSignatures = HomeDataSignatures(
            logs: HomeViewModel.logsFingerprint(for: dailyLogs),
            analytics: HomeViewModel.homeAnalyticsFingerprint(for: homeStudyAggregates),
            decks: HomeViewModel.decksFingerprint(for: allDecks),
            profile: userProfileDashboardSignature,
            dailyCardsGoal: dailyCardsGoalSignature
        )
        if homeDataSignatures != nextSignatures {
            homeDataSignatures = nextSignatures
        }

        refreshFolderCache()
        refreshRecentDeckCache()

        if allDeckCount != allDecks.count {
            allDeckCount = allDecks.count
        }

        return nextSignatures
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
                    "\(deck.editedAt.timeIntervalSince1970.bitPattern)",
                    "\(deck.lastOpenedAt?.timeIntervalSince1970.bitPattern ?? 0)",
                ].joined(separator: ":")
            }
            .joined(separator: "|")

        guard recentDeckSignature != nextSignature else { return }
        recentDeckSignature = nextSignature
        recentDeckModels = nextDecks
        recentDeckSnapshots = LibraryGrouping.makeDeckSnapshots(
            from: nextDecks
        )
    }
}
