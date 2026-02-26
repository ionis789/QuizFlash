//
//  LibraryLayout.swift
//  QuizFlash
//
//  PERFORMANCE FIX — async updateGroupedDecks
//  ─────────────────────────────────────────────────────────────────────────────
//  updateGroupedDecks() called LibraryGrouping.sections() synchronously on the
//  MainActor. With 76 decks, this involves:
//    • Sorting the full array (O(n log n))
//    • Grouping by Calendar.startOfDay (O(n) with date math per deck)
//    • Building DeckSection structs
//  All blocking the main thread in onChange(of: decks).
//
//  Fix: the sort/group work runs on a background thread via Task.detached.
//  The MainActor only receives the finished [DeckSection] array.

import SwiftUI
import SwiftData

// MARK: - Scroll Offset Preference Key

struct LibraryScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value += nextValue()
    }
}

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

    @State private var scrollOffset: CGFloat = 0
    @State private var scrollProxy: ScrollViewProxy? = nil
    @State private var isMenuExpanded: Bool = false
    @State private var menuPosition: CGRect = .zero
    @State private var cachedGroupedDecks: [DeckSection] = []

    // Tracks in-flight grouping task so rapid changes cancel stale work.
    @State private var groupingTask: Task<Void, Never>? = nil

    // Input-side search debounce.
    @State private var inputDebounceTask: Task<Void, Never>? = nil

    private let topAnchorID = "LIBRARY_TOP_ANCHOR"
    private var accent: Color { ThemeManager.shared.accentColor.color }
    // 1. Mutăm punctul de apariție în header mai sus, abia după ce titlul mare e acoperit
    private var showInlineTitle: Bool { scrollOffset < -100 || isSearching }

    // 2. Modificăm fade-out-ul ca să fie mai lung și să nu mai dispară atât de brusc
    private var heroOpacity: Double {
        if isSearching { return 0.0 }

        // Începe să dispară la -30 (când atinge marginea de sus) și dispare complet la -90
        let maxOff: CGFloat = -30, minOff: CGFloat = -110
        guard scrollOffset <= maxOff else { return 1.0 }
        guard scrollOffset >= minOff else { return 0.0 }
        return 1.0 - Double((maxOff - scrollOffset) / (maxOff - minOff))
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            mainScrollArea

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
            .overlay(alignment: .topLeading) { menuOverlay }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.isSelecting)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.isSearching)
            .background {
            // MARK: Library Background
            Color.black
                .ignoresSafeArea() // Foarte important pentru a acoperi tot ecranul
        }
    }

    // MARK: - Main Scroll Area

    private var mainScrollArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {

                    GeometryReader { geo in
                        Color.clear.preference(
                            key: LibraryScrollOffsetKey.self,
                            value: geo.frame(in: .named("libraryScroll")).minY
                        )
                    }
                        .frame(height: 0)
                        .id(topAnchorID)

                    if !isSearching {
                        heroTitleArea
                            .padding(.top, 20)
                            .padding(.bottom, 4)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Am șters Section-ul și header-ul stickyToolBar care dădeau eroare
                    LazyVStack(spacing: 0) {
                        VStack(spacing: 0) {
                            if viewModel.isSearching {
                                searchResultsLayer.transition(.opacity)
                            } else if decks.isEmpty {
                                LibraryEmptyStateView().transition(.opacity)
                            } else {
                                LibraryListView(
                                    groupedDecks: cachedGroupedDecks,
                                    viewModel: viewModel,
                                    onNavigate: onDeckNavigate
                                )
                                    .transition(.opacity)
                            }
                        }
                    }
                }
                    .safeAreaInset(edge: .bottom) {
                    Color.clear
                        .frame(height: viewModel.isSelecting ? 150 : 60)
                        .animation(.spring(response: 0.35, dampingFraction: 0.85),
                                   value: viewModel.isSelecting)
                }
            }
                .coordinateSpace(name: "libraryScroll")
                .onPreferenceChange(LibraryScrollOffsetKey.self) { value in
                scrollOffset = value
            }
                .contentShape(Rectangle())
                .onTapGesture {
                guard viewModel.isSelecting else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    viewModel.exitSelectionMode()
                }
            }
                .safeAreaInset(edge: .top) {
                LibraryTopBarView(
                    viewModel: viewModel,
                    isMenuExpanded: $isMenuExpanded,
                    menuPosition: $menuPosition,
                    showInlineTitle: showInlineTitle,
                    isSearching: $isSearching,
                    searchText: $searchText,
                    decksCount: decks.count,
                    onHeaderTap: {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                            scrollProxy?.scrollTo(topAnchorID, anchor: .top)
                        }
                    }
                )
            }
                .onAppear {
                scrollProxy = proxy
                updateGroupedDecks()
            }
                .onChange(of: decks) { _, _ in updateGroupedDecks() }
                .onChange(of: viewModel.sortOrder) { _, _ in updateGroupedDecks() }

                .onChange(of: searchText) { _, newValue in
                inputDebounceTask?.cancel()

                if newValue.isEmpty {
                    viewModel.searchText = ""
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                        scrollProxy?.scrollTo(topAnchorID, anchor: .top)
                    }
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
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                    scrollProxy?.scrollTo(topAnchorID, anchor: .top)
                }
            }
        }
    }

    // MARK: - Async Grouping

    /// Cancels any in-flight grouping task and starts a fresh one.
    /// The sort + Calendar grouping runs on a background thread.
    private func updateGroupedDecks() {
        groupingTask?.cancel()

        // Capture the two value types needed before leaving the MainActor.
        let snapshot = decks // [DeckModel] — value-type array copy
        let sortOrder = viewModel.sortOrder

        groupingTask = Task {
            let sections = await MainActor.run {
                LibraryGrouping.sections(decks: snapshot, sortOrder: sortOrder)
            }

            guard !Task.isCancelled else { return }

            // Publish result. No animation — structural grouping changes
            // (date sections appearing/disappearing) should be instant.
            await MainActor.run {
                self.cachedGroupedDecks = sections
            }
        }
    }

    // MARK: - Menu Overlay

    @ViewBuilder
    private var menuOverlay: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .foregroundStyle(.clear)
                .contentShape(.rect)
                .ignoresSafeArea()
                .onTapGesture {
                withAnimation(.snappy(duration: 0.3, extraBounce: 0)) {
                    isMenuExpanded = false
                }
            }
                .allowsHitTesting(isMenuExpanded)

            if isMenuExpanded {
                VisionOSStyleView(cornerRadius: 24) {
                    LibraryMenuControls(viewModel: viewModel, isExpanded: $isMenuExpanded)
                        .frame(width: 240)
                }
                    .transition(.blurReplace)
                    .offset(x: menuPosition.maxX - 240, y: menuPosition.maxY + 12)
            }
        }
            .ignoresSafeArea()
    }

    // MARK: - Search Results Layer

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

    // MARK: - Prompt Views

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

// MARK: - Private Extensions


private extension LibraryLayout {

    var heroTitleArea: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Library")
                .font(.system(size: 38, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)

            // Badge-ul curat, lângă titlu
            Text(decks.isEmpty
                ? "No Decks"
            : "\(decks.count) Deck\(decks.count == 1 ? "" : "s")")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(accent.opacity(0.15), in: .capsule)

//            Spacer()
        }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(heroOpacity)
            .scaleEffect(
            scrollOffset < 0
            // 1. Am schimbat limita la 0.70 (poate ajunge la 70% din mărime)
            // 2. Am schimbat 400 cu 250 ca să se micșoreze un pic mai repede când faci scroll în sus
            ? max(0.70, 1 + (scrollOffset / 250))
            : 1 + (scrollOffset / 300), // Aici rămâne la fel pentru pull-down
            anchor: .bottomLeading
        )
    }
}
