//
//  LibraryLayout.swift
//  QuizFlash

import SwiftUI
import SwiftData

// MARK: - LibraryLayout

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
    @State private var headerHeight: CGFloat = 0

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
            .spring(response: UIConstants.Animation.instant, dampingFraction: 0.92)
    }
    private var searchContentMaxWidth: CGFloat { UIConstants.Layout.librarySearchContentMaxWidth }
    private var searchPromptTopPadding: CGFloat {
        UIConstants.Layout.searchPromptTopPadding
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
                .allowsHitTesting(!viewModel.isSearching)
                .accessibilityHidden(viewModel.isSearching)

            searchOverlay
                .zIndex(4)

            // ── Edge shadows — top + bottom vignette ─────────────────────────
            // Tune kShadowRadius in EdgeShadowOverlay.swift to adjust both edges.
            EdgeShadowOverlay(
                topHeight: safeTop + UIConstants.Layout.topEdgeShadowHeight,
                bottomHeight: 60
            )
                .zIndex(5)

            // ── Header — above gradient, below selection bar ──────────────────
            VStack(spacing: 0) {
                LibraryTopBarView(
                    title: title,
                    deckCount: decks.count,
                    viewModel: viewModel,
                    isScrolled: viewModel.savedScrollOffset > 10,
                    onBack: onBack,
                    backLabel: backLabel
                )
                // Capture rendered height so the ScrollView spacer and blur
                // frame stay in sync. Guard prevents redundant state writes.
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { newHeight in
                    if headerHeight != newHeight { headerHeight = newHeight }
                }
                Spacer()
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(true)
                .zIndex(6)



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
            .animation(.bottomChromeSpring, value: viewModel.isSelecting)
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

                if !isSearching && decks.isEmpty && viewModel.cachedGroupedDecks.isEmpty {
                    Spacer().frame(height: 40)
                }

                stackContent
            }
                .safeAreaInset(edge: .bottom) {
                Color.clear
                    .frame(height: 100)
                    .animation(.bottomChromeSpring, value: viewModel.isSelecting)
            }
                .safeAreaInset(edge: .top) {
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
            .ignoresSafeArea(.container, edges: .top)
            .coordinateSpace(name: kLibraryScrollSpace)
            .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: headerHeight)
        }
            .onAppear { viewModel.updateGroupedDecks(from: decks) }
            .onChange(of: decks) { _, newDecks in viewModel.updateGroupedDecks(from: newDecks) }
            .onChange(of: viewModel.sortOrder) { _, _ in viewModel.updateGroupedDecks(from: decks) }
    }

    // MARK: - Scroll content

    @ViewBuilder
    private var stackContent: some View {
        LazyVStack(spacing: 0) {
            deckListContent
        }
    }

    @ViewBuilder
    private var deckListContent: some View {
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
            // Needed so ScrollViewReader can actually find the items:
            .id("LibraryList-\(viewModel.cachedGroupedDecks.count)")
        }
    }

    // MARK: - Search overlays

    private var searchOverlay: some View {
        ScrollView {
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: headerHeight + UIConstants.Layout.compactScreenEdgeInset)

                searchResultsLayer
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(.bottom, UIConstants.Layout.sectionSpacing)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .ignoresSafeArea(.container, edges: .top)
        .background {
            searchOverlayBackground
        }
        .compositingGroup()
        .opacity(viewModel.isSearching ? 1 : 0)
        .offset(y: viewModel.isSearching ? 0 : -UIConstants.Spacing.small)
        .allowsHitTesting(viewModel.isSearching)
        .accessibilityHidden(!viewModel.isSearching)
        .animation(searchTransition, value: viewModel.isSearching)
    }

    private var searchOverlayBackground: some View {
        backgroundTheme
            .ignoresSafeArea()
    }

    @ViewBuilder
    private var searchResultsLayer: some View {
        if viewModel.searchText.isEmpty {
            searchContentContainer {
                readyToSearchPrompt
            }
        } else if viewModel.searchResults.isEmpty && !viewModel.isSearchLoading {
            searchContentContainer {
                noResultsPrompt
            }
        } else {
            searchContentContainer {
                SearchResultsView(
                    results: viewModel.searchResults,
                    query: viewModel.searchText,
                    isSearchLoading: viewModel.isSearchLoading,
                    onCardTap: onCardTap
                )
            }
        }
    }

    private func searchContentContainer<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: searchContentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
    }

    private var readyToSearchPrompt: some View {
        VStack(alignment: .leading, spacing: UIConstants.Layout.searchPromptSectionSpacing) {



            VStack(
                alignment: .leading,
                spacing: UIConstants.Layout.sectionSpacing
            ) {
                SearchEntryBulletRow(
                    title: "Deck titles",
                    subtitle: "Jump straight to a topic, subject, or collection by name."
                )
                SearchEntryBulletRow(
                    title: "Card prompts",
                    subtitle: "Look for a phrase from the main prompt or question of any card."
                )
                SearchEntryBulletRow(
                    title: "Answers and explanations",
                    subtitle: "Search a keyword buried inside card content and study notes."
                )
            }

            Spacer(minLength: 0)
        }
        .padding(.top, searchPromptTopPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var noResultsPrompt: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            Text("No results for “\(viewModel.searchText)”")
                .font(.system(.title3, design: .rounded).weight(.bold))

            Text("Try a broader keyword, another phrase, or search by deck title.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                SearchEntryBulletRow(
                    title: "Broaden the term",
                    subtitle: "Remove extra words or search for the core subject."
                )
                SearchEntryBulletRow(
                    title: "Try the deck name",
                    subtitle: "Search first by title, then refine with card text."
                )
            }
        }
        .padding(.top, searchPromptTopPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - SearchEntryBulletRow

private struct SearchEntryBulletRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: UIConstants.Spacing.medium) {
            Circle()
                .fill(ThemeManager.shared.accentColor.color.opacity(0.9))
                .frame(width: 6, height: 6)
                .padding(.top, 7)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}
