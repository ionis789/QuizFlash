//
//  LibraryLayout.swift
//  QuizFlash
//
//  ── iOS 17 scroll-position changes vs original ────────────────────────
//
//  1. `lastTappedDeckID` (@State) → removed.
//     @State can be silently reset when iOS 17's NavigationStack reconstructs
//     view struct identity during a pop. Replaced by `viewModel.savedScrollOffset`
//     (raw Y, lives in @Observable) which survives every body re-evaluation.
//
//  2. New `@State private var libraryScrollView: UIScrollView?`
//     Delivered by CollapsingScrollView.onScrollViewReady on iOS 17.
//     Used for programmatic scroll-to-top via UIKit instead of
//     SwiftUI's ScrollViewProxy (which requires rendered cells).
//
//  3. LazyVStack → VStack on iOS 17 via `stackContent` @ViewBuilder property.
//     Eager VStack gives UIHostingController the full intrinsic content height
//     after the very first layout pass — the prerequisite for iOS17ScrollHost
//     to set contentOffset synchronously in viewDidLayoutSubviews, before
//     the pop animation's first frame is drawn.
//
//  4. `onAppear` iOS 17 block simplified.
//     The old `scrollProxy?.scrollTo(targetID)` + 50 ms delay is gone.
//     iOS17ScrollHost handles restoration internally, before first paint.
//
//  5. Required addition to LibraryViewModel:
//
//       /// Raw UIScrollView contentOffset.y — persists across pops on iOS 17.
//       var savedScrollOffset: CGFloat = 0
//

import SwiftUI
import SwiftData

// MARK: - LibraryLayout

struct LibraryLayout: View {

    let decks: [DeckModel]
    @Bindable var viewModel: LibraryViewModel
    let router: NavigationManager

    let onCardTap: (PersistentIdentifier) -> Void
    let onDeckNavigate: (DeckModel) -> Void
    let onDeleteSelected: () -> Void

    @Binding var isSearching: Bool
    @Binding var searchText: String

    var folderContext: FolderModel?

    // ── State ──
    @State private var groupingTask: Task<Void, Never>? = nil
    @State private var inputDebounceTask: Task<Void, Never>? = nil

    /// Height of LibraryTopBarView measured live.
    @State private var headerHeight: CGFloat = 0

    /// safeAreaInsets.top captured from the root body context (non-zero here).
    @State private var safeTop: CGFloat = 0



    private var accent: Color { ThemeManager.shared.accentColor.color }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            mainScrollArea

            // ── Edge shadows — top + bottom vignette ─────────────────────────
            // Tune kShadowRadius in EdgeShadowOverlay.swift to adjust both edges.
            EdgeShadowOverlay(
//                topHeight: headerHeight + safeTop,
                topHeight: safeTop + 20,
                bottomHeight: 60
            )
                .zIndex(5)

            // ── Header — above gradient, below selection bar ──────────────────
            VStack(spacing: 0) {
                LibraryTopBarView(
                    title: folderContext?.title ?? "Library",
                    deckCount: decks.count,
                    viewModel: viewModel,
                    searchText: $searchText,
                    isSearching: $isSearching,
                    isScrolled: viewModel.savedScrollOffset > 10
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
                LibrarySelectionBarView(
                    viewModel: viewModel,
                    decks: decks,
                    onDeleteTap: { viewModel.showDeleteConfirmation = true }
                )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.isSelecting)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.isSearching)
            .background { Color.black.ignoresSafeArea() }
            .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { safeTop = geo.safeAreaInsets.top }
                    .onChange(of: geo.safeAreaInsets.top) { _, v in safeTop = v }
            }
        }
    }

    // MARK: - Main Scroll Area

    private var mainScrollArea: some View {
        ScrollView {
            VStack(spacing: 0) {
                // ── Scroll Position Restoration ───────────────────────────────
                // Must be first so its superview-chain walk reliably finds the
                // UIScrollView ancestor before any other content is laid out.
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
                    .contentShape(Rectangle())
                    .onTapGesture {
                    guard viewModel.isSelecting else { return }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        viewModel.exitSelectionMode()
                    }
                }
            }
                .safeAreaInset(edge: .bottom) {
                Color.clear
                    .frame(height: 100)
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.isSelecting)
            }
                .safeAreaInset(edge: .top) {
                Color.clear
                    .frame(height: 100)
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.isSelecting)
            }
        }
        // Extends the ScrollView frame edge-to-edge under the status bar so
        // deck rows physically pass behind the blur layer as the user scrolls.
        // .safeAreaInset below still reserves the correct top inset for content.
        .ignoresSafeArea(.container, edges: .top)
        // ── Scroll Coordinate Space ───────────────────────────────────────────
        // Named space consumed by ScrollProximityModifier in LibraryContentViews.
        // Each row reads its own minY from this space via .visualEffect to apply
        // the scale + blur + opacity dissolve as it approaches the header zone.
        // This is the ONLY change required in LibraryLayout for the effect.
        .coordinateSpace(name: kLibraryScrollSpace)
        // ── Frosted-Glass Blur Overlay ────────────────────────────────────────
        // Placed as a .overlay on the ScrollView — the only compositing position
        // where UIKit's blur renderer samples live, scrolling pixel data.
        //
        // A blur inside the content VStack (even with .visualEffect offset tricks)
        // renders in a child CALayer that gets composited AFTER the scroll content
        // layer, so it samples the static app background instead of deck rows.
        //
        // A .overlay on the ScrollView is rendered by UIKit as a sibling layer
        // ABOVE the UIScrollView's content layer but WITHIN the same parent
        // CALayer — exactly the compositing relationship the blur needs to see
        // the pixels that are moving underneath it in real time.
        //
        // .ignoresSafeArea(edges: .top) bleeds the blur into the status bar area,
        // so the header looks seamlessly fused to the top of the screen.
        // .allowsHitTesting(false) lets all touches fall through to the
        // LibraryTopBarView buttons rendered above it.

        // ── Content Inset Spacer ───────────────────────────────────────────────
        // Color.clear reserves the exact same top space that LibraryTopBarView
        // occupies, so deck rows start just below the header without the header
        // being a child of the ScrollView (which would place it under the blur).
        // LibraryTopBarView itself lives in the ZStack at zIndex(6) — above blur.
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear
                .frame(height: headerHeight)
        }
            .onAppear {
            updateGroupedDecks()
        }
            .onChange(of: decks) { _, _ in updateGroupedDecks() }
            .onChange(of: viewModel.sortOrder) { _, _ in updateGroupedDecks() }
            .onChange(of: searchText) { _, newValue in
            inputDebounceTask?.cancel()
            if newValue.isEmpty {
                viewModel.searchText = ""
                return
            }
            inputDebounceTask = Task { @MainActor in
                do {
                    try await Task.sleep(nanoseconds: 150_000_000)
                    guard !Task.isCancelled else { return }
                    viewModel.searchText = newValue
                } catch { }
            }
        }
            .onChange(of: isSearching) { _, active in
            if !active {
                inputDebounceTask?.cancel()
                viewModel.searchText = ""
            }
        }
            .onDisappear {
            groupingTask?.cancel()
            groupingTask = nil
            inputDebounceTask?.cancel()
            inputDebounceTask = nil
        }
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
        if viewModel.isSearching {
            searchResultsLayer.transition(.opacity)
        } else if viewModel.cachedGroupedDecks.isEmpty {
            LibraryEmptyStateView().transition(.opacity)
        } else {
            LibraryListView(
                groupedDecks: viewModel.cachedGroupedDecks,
                isSelecting: viewModel.isSelecting,
                selectedDeckIDs: viewModel.selectedDecks,
                onNavigate: { deck in
                    onDeckNavigate(deck)
                },
                onToggleSelection: { deck in
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                        viewModel.toggleSelection(for: deck)
                    }
                },
                onEditColor: { deck in viewModel.deckToEditColor = deck },
                onDelete: { deck in viewModel.deckToDelete = deck }
            )
            // Needed so ScrollViewReader can actually find the items:
            .id("LibraryList-\(viewModel.cachedGroupedDecks.count)")
        }
    }

    // MARK: - Grouping

    private func updateGroupedDecks() {
        groupingTask?.cancel()
        // Shield against 1-frame SwiftData empty-array glitch on iOS 17 pop.
        guard !decks.isEmpty else { return }

        let snapshot = decks
        let sortOrder = viewModel.sortOrder

        if viewModel.cachedGroupedDecks.isEmpty {
            viewModel.cachedGroupedDecks = LibraryGrouping.sections(decks: snapshot, sortOrder: sortOrder)
            return
        }

        groupingTask = Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled else { return }
            let sections = await MainActor.run {
                LibraryGrouping.sections(decks: snapshot, sortOrder: sortOrder)
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if !areSectionsStructurallyIdentical(old: viewModel.cachedGroupedDecks, new: sections) {
                    viewModel.cachedGroupedDecks = sections
                }
            }
        }
    }

    private func areSectionsStructurallyIdentical(old: [DeckSection], new: [DeckSection]) -> Bool {
        guard old.count == new.count else { return false }
        for i in 0..<old.count {
            if old[i].title != new[i].title { return false }
            let o = old[i].decks, n = new[i].decks
            guard o.count == n.count else { return false }
            for j in 0..<o.count { if o[j].id != n[j].id { return false } }
        }
        return true
    }

    // MARK: - Search overlays

    @ViewBuilder
    private var searchResultsLayer: some View {
        if viewModel.searchText.isEmpty {
            readyToSearchPrompt
        } else if viewModel.isSearchLoading && viewModel.searchResults.isEmpty {
            Color.clear.frame(height: 300)
        } else if viewModel.searchResults.isEmpty && !viewModel.isSearchLoading {
            noResultsPrompt
        } else {
            SearchResultsView(
                results: viewModel.searchResults,
                query: viewModel.searchText,
                isSearchLoading: viewModel.isSearchLoading,
                onCardTap: onCardTap
            )
        }
    }

    private var readyToSearchPrompt: some View {
        VStack(spacing: 18) {
            Spacer().frame(height: 80)
            ZStack {
                Circle()
                    .fill(accent.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 36, weight: .regular))
                    .foregroundStyle(accent)
            }
            Text("Ready to search?")
                .font(.system(.title2, design: .rounded).weight(.bold))
            Text("Type a keyword to find specific\ndecks, questions or answers.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
            .frame(maxWidth: .infinity)
            .transition(.opacity)
    }

    private var noResultsPrompt: some View {
        VStack(spacing: 14) {
            Spacer().frame(height: 80)
            Image(systemName: "magnifyingglass.circle.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No results found")
                .font(.system(.title3, design: .rounded).weight(.bold))
            Text("Try different keywords.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
            .frame(maxWidth: .infinity)
            .transition(.opacity)
    }
}
