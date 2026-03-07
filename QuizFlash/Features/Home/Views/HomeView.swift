// HomeView.swift
// QuizFlash
//
// Root coordinator for the Home screen.
//
// Responsibilities:
//   - Injects SwiftData queries as plain data into child views.
//   - Computes scroll geometry (extendedHeight, scrollDistance) from CalendarViewModel constants.
//   - Orchestrates HomeCalendarSectionView and HomeDashboardView inside a single ScrollView.
//
// This view contains no business logic — all state is owned by
// HomeViewModel and CalendarViewModel, both instantiated with @State.

import SwiftUI
import SwiftData

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

    // MARK: - SwiftData Queries

    @Query(sort: \FolderModel.createdAt) private var folders: [FolderModel]
    @Query private var userProfiles: [UserProfile]
    @Query private var dailyLogs: [DailyActivityLog]

    /// Sorted by `lastOpenedAt` descending so we can slice the top 5 without
    /// sorting a second time in Swift — SwiftData handles this on the store side.
    @Query(sort: \DeckModel.lastOpenedAt, order: .reverse) private var recentlyOpenedQuery: [DeckModel]

    // MARK: - View Models

    @State private var viewModel = HomeViewModel()
    @State private var calendarVM = CalendarViewModel()

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

            // MARK: Scroll Geometry

            // Total height of the calendar header when fully expanded.
            let extendedHeight = safeAreaTop
                + calendarVM.topPaddingExpanded
                + calendarVM.titleHeight
                + calendarVM.titleBottomSpacing
                + calendarVM.weekLabelHeight
                + CGFloat(calendarVM.monthRows.count) * calendarVM.rowHeight
                + calendarVM.bottomPadding

            // Height of the calendar header when collapsed to a single sticky row.
            let compactHeight = safeAreaTop
                + calendarVM.topPaddingCollapsed
                + calendarVM.weekLabelHeight
                + calendarVM.rowHeight
                + calendarVM.bottomPadding

            let scrollDistance = extendedHeight - compactHeight

            // MARK: Content

            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    HomeCalendarSectionView(
                        calendarVM: calendarVM,
                        extendedHeight: extendedHeight,
                        scrollDistance: scrollDistance,
                        safeAreaTop: safeAreaTop,
                        logsCache: viewModel.logsCache,
                        router: router
                    )
                    .zIndex(100)

                    HomeDashboardView(
                        viewModel: viewModel,
                        folders: folders,
                        recentDecks: recentlyOpenedDecks,
                        userProfile: profile,
                        calendarVM: calendarVM,
                        router: router
                    )
                    .frame(minHeight: proxy.size.height - compactHeight)
                    .background(
                        Color(.systemGroupedBackground)
                            .clipShape(UnevenRoundedRectangle(
                                topLeadingRadius: 30,
                                topTrailingRadius: 30,
                                style: .continuous
                            ))
                            .shadow(color: .black.opacity(0.05), radius: 10, y: -5)
                    )
                    .zIndex(1)
                }
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(HomeScrollBehavior(maxHeight: scrollDistance))
            .ignoresSafeArea(.container, edges: .top)
            .toolbar(.hidden)
            .background(Color(.systemBackground).ignoresSafeArea())

            // MARK: Lifecycle

            .onAppear {
                calendarVM.setupIfNeeded()
                // Only rebuild the cache when empty to prevent a forced re-render
                // cycle on every tab return that would reset child @State variables.
                if viewModel.logsCache.isEmpty {
                    viewModel.updateLogsCache(logs: dailyLogs)
                }
            }
            .sheet(isPresented: $viewModel.showCreateFolder) {
                CreateFolderSheet(viewModel: viewModel)
            }
        }
    }

    // MARK: - Scroll Behavior

    /// Snaps the scroll position to either fully expanded or fully collapsed.
    ///
    /// Prevents the calendar header from resting in an intermediate (partially expanded) state,
    /// mirroring the snap behaviour used by Calendar.app and native iOS date pickers.
    struct HomeScrollBehavior: ScrollTargetBehavior {

        /// The maximum scroll distance before the header is fully collapsed.
        let maxHeight: CGFloat

        func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
            if target.rect.minY < maxHeight {
                // Past the halfway point → snap to fully collapsed.
                // Below halfway → snap back to fully expanded.
                if target.rect.minY > maxHeight / 2 {
                    target.rect.origin.y = maxHeight
                } else {
                    target.rect = .zero
                }
            }
        }
    }
}
