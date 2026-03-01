//
//  LibraryLayout.swift
//  QuizFlash
//

import SwiftUI
import SwiftData

// Configurații Scroll
private var isPad: Bool {
    UIDevice.current.userInterfaceIdiom == .pad
}
private var kLibraryCollapseDistance: CGFloat {
    isPad ? 140.0 : 110.0
}
private let kLibraryHeroFadeEnd: CGFloat = 0.85
private let kLibraryInlineTitleThreshold: CGFloat = 0.85

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

    // ── State managed here ──
    @State private var scrollProxy: ScrollViewProxy? = nil
    @State private var isMenuExpanded: Bool = false
    @State private var menuPosition: CGRect = .zero
    @State private var groupingTask: Task<Void, Never>? = nil
    @State private var inputDebounceTask: Task<Void, Never>? = nil
    
    // Natively tracks the top-most visible element on iOS 17+ to restore scroll position
    // or manually tracks the last interacted component for forced jumping.
    @State private var lastTappedDeckID: PersistentIdentifier?

    private let topAnchorID = "LIBRARY_TOP_ANCHOR"
    private var accent: Color { ThemeManager.shared.accentColor.color }

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
            .background { Color.black.ignoresSafeArea() }
    }

    // MARK: - Main Scroll Area
    private var mainScrollArea: some View {
        CollapsingScrollView { p in
            viewModel.collapseProgress = p
        } onScrollProxy: { proxy in
            scrollProxy = proxy
        } header: {
            LibraryTopBarView(
                viewModel: viewModel,
                isMenuExpanded: $isMenuExpanded,
                menuPosition: $menuPosition,
                isSearching: $isSearching,
                searchText: $searchText,
                title: folderContext?.title ?? "Library",
                decksCount: decks.count,
                onHeaderTap: {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                        scrollProxy?.scrollTo(topAnchorID, anchor: .top)
                    }
                }
            )
        } content: {
            VStack(spacing: 0) {
                Color.clear.frame(height: 0).id(topAnchorID)

                if !isSearching {
                    LibraryHeroSection(viewModel: viewModel, decks: decks, folderContext: folderContext)
                        .padding(.top, 20)
                        .padding(.bottom, -10)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                LazyVStack(spacing: 0) {
                    if viewModel.isSearching {
                        searchResultsLayer.transition(.opacity)
                    } else if viewModel.cachedGroupedDecks.isEmpty {
                        // ✅ FIX CRITIC: Folosim viewModel.cachedGroupedDecks.isEmpty în loc de decks.isEmpty
                        // Această listă este protejată de pâlpâirile SwiftData din timpul Navigation Pop-ului.
                        LibraryEmptyStateView().transition(.opacity)
                    } else {
                        LibraryListView(
                            groupedDecks: viewModel.cachedGroupedDecks,
                            isSelecting: viewModel.isSelecting,
                            selectedDeckIDs: viewModel.selectedDecks,
                            onNavigate: { deck in
                                if #available(iOS 18, *) {} else {
                                    lastTappedDeckID = deck.id
                                }
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
                    }
                }
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
                    .frame(height: viewModel.isSelecting ? 150 : 60)
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.isSelecting)
            }
        }
            .scrollDisabled(isMenuExpanded)
        // Revenim la logica ta robustă de lifecycle
        .onAppear {
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
            .onDisappear {
            groupingTask?.cancel()
            groupingTask = nil
            inputDebounceTask?.cancel()
            inputDebounceTask = nil
        }
    }

    /// Rebuilds the grouped deck sections with strict structural equality checking.
    private func updateGroupedDecks() {
        groupingTask?.cancel()

        // 🟢 FIX CRITIC ABSOLUT: Protecție agresivă împotriva golirii accidentale.
        // În iOS 17, pe parcursul animației de back (pop) din NavigationStack, 
        // interogările @Query din LibraryView pot returna temporar un array gol []
        // timp de 1 frame. Dacă lăsăm asta să ajungă în UI, ScrollView-ul își distruge complet
        // structura (LazyVStack-ul taie înălțimea la 0) și pierzi scrolul nativ.
        guard !decks.isEmpty else {
            // Dacă SwiftData ne zice brusc că avem 0 pachete dar noi deja desenasem
            // ceva, ignorăm complet acest frame!
            return
        }

        let snapshot = decks
        let sortOrder = viewModel.sortOrder

        // Fast path pe prima încărcare
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
                // Înlocuim datele doar dacă structura s-a schimbat!
                if !areSectionsStructurallyIdentical(old: self.viewModel.cachedGroupedDecks, new: sections) {
                    self.viewModel.cachedGroupedDecks = sections
                }
            }
        }
    }

    /// Compară conținutul secțiunilor ignorând UUID-urile instanțelor de DeckSection.
    private func areSectionsStructurallyIdentical(old: [DeckSection], new: [DeckSection]) -> Bool {
        guard old.count == new.count else { return false }

        for i in 0..<old.count {
            if old[i].title != new[i].title { return false }

            let oldDecks = old[i].decks
            let newDecks = new[i].decks

            guard oldDecks.count == newDecks.count else { return false }

            for j in 0..<oldDecks.count {
                // Verificăm identitatea deck-urilor (titlurile se updatează oricum prin @Model)
                if oldDecks[j].id != newDecks[j].id { return false }
            }
        }

        return true
    }

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

// MARK: - LibraryHeroSection
private struct LibraryHeroSection: View {
    let viewModel: LibraryViewModel
    let decks: [DeckModel]
    var folderContext: FolderModel?

    private var accent: Color { ThemeManager.shared.accentColor.color }

    private var t: CGFloat {
        CollapsingHeaderConfig.heroTransitionProgress(currentProgress: viewModel.collapseProgress)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Aplicăm titlul dinamic pe Hero Section
            Text(folderContext?.title ?? "Library")
                .font(.system(size: 38, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)

            Text(decks.isEmpty ? "No Decks" : "\(decks.count) Deck\(decks.count == 1 ? "" : "s")")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(accent.opacity(0.15), in: .capsule)
        }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(1.0 - t)
            .scaleEffect(1.0 - (t * 0.4), anchor: .topLeading)
            .offset(y: -(t * 20))
            .animation(
                .interactiveSpring(response: 0.22, dampingFraction: 0.85),
            value: viewModel.collapseProgress
        )
    }
}
