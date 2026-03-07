// HomeView.swift
// QuizFlash
//
// Root coordinator for the Home screen.
// Responsibilities:
//   - Injects SwiftData queries into child views
//   - Computes scroll geometry (extendedHeight, scrollDistance)
//   - Orchestrates CalendarSectionView and HomeDashboardView
//
// This view contains no business logic — all state is delegated
// to HomeViewModel and CalendarViewModel.

import SwiftUI
import SwiftData

struct HomeView: View {
    
    // MARK: - Environment
    
    @Environment(\.modelContext) private var context
    @Environment(NavigationManager.self) private var router
    
    
    // MARK: - SwiftData Queries
    
    @Query(sort: \FolderModel.createdAt) private var folders: [FolderModel]
    @Query private var userProfiles: [UserProfile]
    @Query private var dailyLogs: [DailyActivityLog]
    @Query(sort: \DeckModel.lastOpenedAt, order: .reverse) private var recentlyOpenedQuery: [DeckModel]
    
    // MARK: - View Models
    
    @State private var viewModel = HomeViewModel()
    @State private var calendarVM = CalendarViewModel()
    
    // MARK: - Derived Data
    
    private var profile: UserProfile? {
        userProfiles.first
    }
    
    /// Returns the 5 most recently opened decks.
    /// By querying sorted `lastOpenedAt` directly instead of fetching `allDecks`,
    /// SwiftData avoids faulting the entire database into memory on tab switch.
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
            
            // The full height of the calendar header when fully expanded.
            let extendedHeight = safeAreaTop
            + calendarVM.topPaddingExpanded
            + calendarVM.titleHeight
            + calendarVM.titleBottomSpacing
            + calendarVM.weekLabelHeight
            + CGFloat(calendarVM.monthRows.count) * calendarVM.rowHeight
            + calendarVM.bottomPadding
            
            // The height of the calendar header when collapsed to a single sticky row.
            let compactHeight = safeAreaTop
            + calendarVM.topPaddingCollapsed
            + calendarVM.weekLabelHeight
            + calendarVM.rowHeight
            + calendarVM.bottomPadding
            
            let scrollDistance = extendedHeight - compactHeight
            
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
            //MARK: HomeView Background
            .background(Color(.systemBackground).ignoresSafeArea())
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
    /// Prevents the calendar header from resting in an intermediate state.
    struct HomeScrollBehavior: ScrollTargetBehavior {
        let maxHeight: CGFloat
        
        func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
            if target.rect.minY < maxHeight {
                // Snap to fully collapsed if past halfway, otherwise snap back to fully expanded.
                if target.rect.minY > maxHeight / 2 {
                    target.rect.origin.y = maxHeight
                } else {
                    target.rect = .zero
                }
            }
        }
    }
}
