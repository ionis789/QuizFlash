//
//  LibraryLayout.swift
//  QuizFlash

import SwiftUI
import SwiftData

// MARK: - LibraryLayout

let kLibraryChromeSpace = "libraryChrome"

/// Shared layout engine for `LibraryView` and `FolderView`.
/// Handles coordinate spaces, structural overlays, safe area computation,
/// and delegates all business logic to `LibraryViewModel`.
struct LibraryLayout: View {
    @Environment(ThemeManager.self) private var themeManager

    let decks: [DeckModel]
    let folders: [FolderModel]
    @Bindable var viewModel: LibraryViewModel
    let router: NavigationManager

    // The screen title displayed in LibraryTopBarView.
    // Passed as a plain String so LibraryLayout carries no navigation context knowledge —
    // it renders identically whether hosted by LibraryView ("Library") or FolderView
    // (the folder's title). The caller owns the semantic meaning of the title.
    let title: String

    let onCardTap: (PersistentIdentifier) -> Void
    let onDeckNavigate: (DeckModel) -> Void
    let onDeleteSelected: () -> Void
    /// Non-nil when the layout is hosted inside a pushed screen (e.g. FolderView).
    /// Wired to the host's dismiss action so LibraryTopBarView can render a back button.
    var onBack: (() -> Void)? = nil
    /// Label shown in the back button pill. Ignored when onBack is nil.
    var backLabel: String = "Library"

    @Binding var isSearching: Bool
    @Binding var searchText: String

    // ── State ──

    /// Height of LibraryTopBarView measured live.
    @State private var navigationBarBottomY: CGFloat = 0
    @State private var heroCollapsedTitleReady = false
    /// safeAreaInsets.top captured from the root body context (non-zero here).
    @State private var safeTop: CGFloat = 0

    /// Safe-area bottom reported by SwiftUI at the ZStack level.
    /// Inside TabView this includes the UITabBar height (~49 pt) on top of the
    /// physical home-indicator inset, regardless of whether UITabBar is hidden.
    @State private var viewSafeBottom: CGFloat = 0

    /// Physical screen safe-area bottom (home indicator only, ~34 pt).
    /// Read directly from UIWindow so it is never inflated by TabView's layout.
    @State private var physicalSafeBottom: CGFloat = 0

    private var backgroundTheme: Color { themeManager.screenBackground }
    private var searchTransition: Animation {
        .easeOut(duration: 0.16)
    }
    private var searchContentMaxWidth: CGFloat { UIConstants.Layout.librarySearchContentMaxWidth }
    private var topChromeInsetSpacing: CGFloat {
        switch viewModel.searchPresentation {
        case .browse, .searchEmpty:
            return -32
        case .searchResults:
            return 0
        }
    }
    private var libraryCollapsedTitleRevealClearance: CGFloat {
        UIConstants.Layout.deckHeroPillRevealClearance + 28
    }
    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottomTrailing) {

            // Full-bleed background. Empty-space tap-to-dismiss is handled
            // via a pure SwiftUI background gesture on the scroll content VStack.
            // Child view gestures (deck row Buttons) take priority — no UIKit needed.
            backgroundTheme
                .ignoresSafeArea()
                .zIndex(-1)

            mainScrollArea

            // ── Edge shadows — top + bottom vignette ─────────────────────────
            // Tune kShadowRadius in EdgeShadowOverlay.swift to adjust both edges.
            EdgeShadowOverlay(
                topHeight: safeTop + UIConstants.Layout.topEdgeShadowHeight,
                bottomHeight: 60
            )
                .zIndex(5)

            if viewModel.isSelecting && !isSearching {
                BottomChromeContainer(
                    kind: .selection,
                    bottomPadding: BottomChromeInsets.persistent
                ) {
                    LibrarySelectionBarView(
                        viewModel: viewModel,
                        decks: decks,
                        onDeleteTap: { viewModel.showDeleteConfirmation = true },
                        onMoveTap: { viewModel.showMoveConfirmation = true }
                    )
                }
                .transition(.bottomChrome)
                .zIndex(10)
            }

            if viewModel.isImporting || viewModel.isExporting {
                LibraryLoadingOverlay(
                    message: viewModel.isImporting
                        ? "Importing…"
                    : "Exporting \(viewModel.selectedDecks.count) deck\(viewModel.selectedDecks.count == 1 ? "" : "s")…"
                )
                    .zIndex(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .coordinateSpace(name: kLibraryChromeSpace)
            .animation(.bottomChromeSpring, value: viewModel.isSelecting)
            .safeAreaInset(edge: .top, spacing: topChromeInsetSpacing) {
            LibraryTopBarView(
                title: title,
                deckCount: decks.count,
                viewModel: viewModel,
                coordinateSpaceName: kLibraryChromeSpace,
                isCollapsedTitleVisible: heroCollapsedTitleReady,
                isScrolled: viewModel.savedScrollOffset > 10,
                onBack: onBack,
                backLabel: backLabel,
                onBottomChange: { newBottom in
                    if abs(navigationBarBottomY - newBottom) > 0.5 {
                        navigationBarBottomY = newBottom
                    }
                }
            )
            .zIndex(6)
        }
            .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                    safeTop = geo.safeAreaInsets.top
                    viewSafeBottom = geo.safeAreaInsets.bottom
                    physicalSafeBottom = UIApplication.shared
                        .connectedScenes
                        .compactMap { $0 as? UIWindowScene }
                        .first?.windows
                        .first(where: { $0.isKeyWindow })?
                        .safeAreaInsets.bottom ?? 0
                }
                    .onChange(of: geo.safeAreaInsets.top) { _, v in safeTop = v }
                    .onChange(of: geo.safeAreaInsets.bottom) { _, v in
                    viewSafeBottom = v
                    physicalSafeBottom = UIApplication.shared
                        .connectedScenes
                        .compactMap { $0 as? UIWindowScene }
                        .first?.windows
                        .first(where: { $0.isKeyWindow })?
                        .safeAreaInsets.bottom ?? 0
                }
            }
        }
    }

    // MARK: - Main Scroll Area

    private var mainScrollArea: some View {
        ScrollView {
            VStack(spacing: 0) {
                // ── Scroll Position Restoration ───────────────────────────────
                ScrollPositionRestorer(
                    getOffset: { viewModel.savedScrollOffset },
                    onOffsetChange: { offset in
                        guard !isSearching else { return }
                        viewModel.savedScrollOffset = offset
                    }
                )
                    .frame(width: 0, height: 0)

                if decks.isEmpty && viewModel.cachedGroupedDecks.isEmpty {
                    Spacer().frame(height: 40)
                }

                stackContent
            }
                .safeAreaInset(edge: .bottom) {
                Color.clear
                    .frame(height: 100)
                    .animation(.bottomChromeSpring, value: viewModel.isSelecting)
            }
        }
        // ── Selection mode dismiss on empty-space tap ─────────────────────
        // .gesture (not .simultaneousGesture, not .highPriorityGesture) on a
        // parent view loses to any gesture on a child view.
        //
        //   • Tap on a deck row → the row's Button (child of ScrollView) wins,
        //     this gesture never fires → only toggleSelection runs.
        //   • Tap on empty space between cards or below the last card → no
        //     child Button covers that point → this gesture fires → dismiss.
        //
        // Using .gesture on ScrollView instead of .background on VStack solves
        // the "short list" problem: the ScrollView always fills the full screen
        // area regardless of content height, so the gesture is reachable even
        // when 1–2 cards leave large empty space below them. No minHeight
        // inflation needed → no unwanted scroll created.
        .gesture(
            TapGesture().onEnded {
                guard viewModel.isSelecting && !isSearching else { return }
                withBottomChromeAnimation {
                    viewModel.exitSelectionMode()
                }
            }
        )
            .coordinateSpace(name: kLibraryScrollSpace)
            .onAppear { viewModel.updateGroupedDecks(from: decks) }
            .onChange(of: decks) { _, newDecks in viewModel.updateGroupedDecks(from: newDecks) }
            .onChange(of: viewModel.sortOrder) { _, _ in viewModel.updateGroupedDecks(from: decks) }
    }

    // MARK: - Scroll content

    @ViewBuilder
    private var stackContent: some View {
        switch viewModel.searchPresentation {
        case .browse, .searchEmpty:
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                if viewModel.searchPresentation == .browse {
                    libraryHeroTitle
                }
                contentList
            }
            .animation(searchTransition, value: viewModel.searchPresentation)
            .animation(searchTransition, value: viewModel.renderedSearchQuery)
        case .searchResults:
            LazyVStack(spacing: 0) {
                contentList
            }
            .animation(searchTransition, value: viewModel.searchPresentation)
            .animation(searchTransition, value: viewModel.renderedSearchQuery)
        }
    }

    private var libraryHeroTitle: some View {
        VStack(alignment: .leading, spacing: 6) {
            LargeScreenTitle(title: title)

            Text(decks.count == 0 ? "No Decks" : "\(decks.count) Deck\(decks.count == 1 ? "" : "s")")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, UIConstants.Layout.heroScreenEdgeInset)
        .padding(.top, UIConstants.Spacing.large + 8)
        .padding(.bottom, UIConstants.Spacing.extraLarge)
        .collapsibleTitleRevealAnchor(
            in: kLibraryChromeSpace,
            navigationBarBottomY: navigationBarBottomY,
            revealClearance: libraryCollapsedTitleRevealClearance,
            isVisible: $heroCollapsedTitleReady
        )
    }

    @ViewBuilder
    private var contentList: some View {
        switch viewModel.searchPresentation {
        case .browse, .searchEmpty:
            browseListContent
                .transition(.opacity)
        case .searchResults:
            SearchResultsView(
                results: viewModel.searchResults,
                query: viewModel.renderedSearchQuery,
                isSearchLoading: viewModel.isSearchLoading,
                onCardTap: onCardTap
            )
            .frame(maxWidth: searchContentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var browseListContent: some View {
        if viewModel.cachedGroupedDecks.isEmpty {
            LibraryEmptyStateView().transition(.opacity)
        } else {
            LibraryListView(
                groupedDecks: viewModel.cachedGroupedDecks,
                isSelecting: viewModel.isSelecting,
                selectedDeckIDs: viewModel.selectedDecks,
                activeActionMenuDeckID: viewModel.activeActionMenuDeckID,
                onNavigate: { deck in
                    onDeckNavigate(deck)
                },
                onToggleSelection: { deck in
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                        viewModel.toggleSelection(for: deck)
                    }
                },
                onToggleActionMenu: { id in
                    viewModel.activeActionMenuDeckID = id
                },
                onEditColor: { deck in viewModel.deckToEditColor = deck },
                onDelete: { deck in viewModel.deckToDelete = deck }
            )
            .id("LibraryList-\(viewModel.cachedGroupedDecks.count)")
        }
    }

}
