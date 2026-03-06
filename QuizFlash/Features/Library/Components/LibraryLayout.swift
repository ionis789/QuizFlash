//
//  LibraryLayout.swift
//  QuizFlash

import SwiftUI
import SwiftData

// MARK: - LibraryLayout

struct LibraryLayout: View {

    let decks: [DeckModel]
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
    @State private var groupingTask: Task<Void, Never>? = nil
    @State private var inputDebounceTask: Task<Void, Never>? = nil

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

    /// Extra bottom offset introduced by TabView for its native UITabBar.
    /// When the tab bar is hidden (selection / search mode), the SwiftUI layout
    /// system still reserves this space. Applying a negative bottom padding equal
    /// to tabBarOffset moves the selection bar down to the correct visual position.
    private var tabBarOffset: CGFloat {
        max(0, viewSafeBottom - physicalSafeBottom)
    }



    private var accent: Color { ThemeManager.shared.accentColor.color }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottomTrailing) {

            // Full-bleed background. Empty-space tap-to-dismiss is handled
            // via a pure SwiftUI background gesture on the scroll content VStack.
            // Child view gestures (deck row Buttons) take priority — no UIKit needed.
            Color.black
                .ignoresSafeArea()
                .zIndex(-1)

            mainScrollArea

            // ── Edge shadows — top + bottom vignette ─────────────────────────
            // Tune kShadowRadius in EdgeShadowOverlay.swift to adjust both edges.
            EdgeShadowOverlay(
//                topHeight: headerHeight + safeTop,
                topHeight: safeTop + 40,
                bottomHeight: 60
            )
                .zIndex(5)

            // ── Header — above gradient, below selection bar ──────────────────
            VStack(spacing: 0) {
                LibraryTopBarView(
                    title: title,
                    deckCount: decks.count,
                    viewModel: viewModel,
                    searchText: $searchText,
                    isSearching: $isSearching,
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
                LibrarySelectionBarView(
                    viewModel: viewModel,
                    decks: decks,
                    onDeleteTap: { viewModel.showDeleteConfirmation = true }
                )
                // TabView inflates the ZStack's safe-area bottom by UITabBar height
                // even when the bar is hidden. tabBarOffset = that extra inset.
                // A negative bottom padding shifts the bar down by exactly that
                // amount so it sits above the home indicator, not above the tab bar.
                .padding(.bottom, -tabBarOffset)
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
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        safeTop         = geo.safeAreaInsets.top
                        viewSafeBottom  = geo.safeAreaInsets.bottom
                        physicalSafeBottom = UIApplication.shared
                            .connectedScenes
                            .compactMap { $0 as? UIWindowScene }
                            .first?.windows
                            .first(where: { $0.isKeyWindow })?
                            .safeAreaInsets.bottom ?? 0
                    }
                    .onChange(of: geo.safeAreaInsets.top)    { _, v in safeTop = v }
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
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.isSelecting)
            }
            .safeAreaInset(edge: .top) {
                Color.clear
                    .frame(height: 100)
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.isSelecting)
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
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    viewModel.exitSelectionMode()
                }
            }
        )
        .ignoresSafeArea(.container, edges: .top)
        .coordinateSpace(name: kLibraryScrollSpace)
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: headerHeight)
        }
        .onAppear { updateGroupedDecks() }
        .onChange(of: decks) { _, _ in updateGroupedDecks() }
        .onChange(of: viewModel.sortOrder) { _, _ in updateGroupedDecks() }
        .onChange(of: searchText) { _, newValue in
            inputDebounceTask?.cancel()
            if newValue.isEmpty { viewModel.searchText = ""; return }
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
