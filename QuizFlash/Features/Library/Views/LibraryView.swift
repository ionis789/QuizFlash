//
//  LibraryView.swift
//  QuizFlash
//
//  PERFORMANCE FIX — smarter cache invalidation
//  ─────────────────────────────────────────────────────────────────────────────
//  Previous pattern:
//    .onAppear       → buildSearchCache(decks)   // fires on EVERY tab switch
//    .onChange(decks) → buildSearchCache(decks)  // fires on EVERY deck mutation
//
//  Problem: .onAppear fires every time the user swipes back to the Library tab.
//  With 76 decks, even an async build enqueues unnecessary work on every
//  tab-switch, and the snapshot construction (still on MainActor) added
//  visible frame drops.
//
//  Fix: Track a Set<PersistentIdentifier> of the last-cached deck IDs.
//  buildSearchCache is only called when the actual deck set has changed.
//  Tab switches (no deck mutations) skip the rebuild entirely.

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LibraryView: View {

    // MARK: - Data
    @Environment(\.modelContext) private var context
    @Query(sort: \DeckModel.createdAt, order: .reverse) private var decks: [DeckModel]
    @Environment(NavigationManager.self) private var router

    // MARK: - State
    @State private var viewModel = LibraryViewModel()
    @State private var isSearching: Bool = false
    @State private var searchText: String = ""

    /// Tracks which deck IDs were present when we last built the cache.
    /// Used to avoid redundant rebuilds on tab-switch (onAppear).
    @State private var cachedDeckIDs: Set<PersistentIdentifier> = []

    @Binding var isTabBarHidden: Bool

    // MARK: - Body

    var body: some View {
        mainContent
            .modifier(LibraryModalsAndDialogs(viewModel: viewModel, context: context, decks: decks))
            .modifier(LibraryAlerts(viewModel: viewModel))
    }

    // MARK: - Main Content

    private var mainContent: some View {
        LibraryLayout(
            decks: decks,
            viewModel: viewModel,
            router: router,
            onCardTap: { cardID in
                if let card = context.model(for: cardID) as? CardModel {
                    viewModel.editingCardFromSearch = card
                }
            },
            onDeckNavigate: { deck in
                router.path.append(deck)
            },
            onDeleteSelected: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    viewModel.deleteSelectedDecks(from: decks, context: context)
                }
            },
            isSearching: $isSearching,
            searchText: $searchText
        )
        // ── INITIAL CACHE BUILD ───────────────────────────────────────────────
        // Only runs once on first appear. Subsequent tab-switches hit the
        // guard in rebuildCacheIfNeeded and return immediately.
        .onAppear {
            rebuildCacheIfNeeded()
        }
        // ── INCREMENTAL CACHE INVALIDATION ───────────────────────────────────
        // Fires when SwiftData delivers a new deck array (add/edit/delete).
        // The Set comparison is O(n) but n ≤ ~200 and uses only IDs, so it's
        // negligible even on the MainActor.
        .onChange(of: decks) { _, newDecks in
            rebuildCacheIfNeeded(newDecks)
        }
        // ── SEARCH LIFECYCLE ─────────────────────────────────────────────────
        .onChange(of: isSearching) { _, active in
            viewModel.isSearching = active
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                isTabBarHidden = active || viewModel.isSelecting
            }
            if !active {
                searchText = ""
                viewModel.searchText = ""
                viewModel.searchResults = []
            }
        }
        .onChange(of: searchText) { _, newValue in
            viewModel.searchText = newValue
            if newValue.isEmpty {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.searchResults = []
                    viewModel.isSearchLoading = false
                }
            } else {
                viewModel.updateSearch(query: newValue)
            }
        }
        .onChange(of: viewModel.isSelecting) { _, selecting in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                isTabBarHidden = selecting || isSearching
            }
        }
    }

    // MARK: - Cache Guard

    /// Rebuilds the search cache only if the deck set has materially changed.
    /// Passing nil uses the current `decks` array (called from onAppear).
    private func rebuildCacheIfNeeded(_ newDecks: [DeckModel]? = nil) {
        let source = newDecks ?? decks
        let newIDs = Set(source.map { $0.id })

        // Skip rebuild if the set of deck IDs is identical.
        // This covers: tab-switch, scroll, sort change, search open/close.
        guard newIDs != cachedDeckIDs else { return }

        cachedDeckIDs = newIDs
        viewModel.buildSearchCache(decks: source)
    }
}

// MARK: - Modals & Dialogs

private struct LibraryModalsAndDialogs: ViewModifier {
    @Bindable var viewModel: LibraryViewModel
    var context: ModelContext
    var decks: [DeckModel]

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $viewModel.editingCardFromSearch) { card in
                NavigationStack {
                    CreateCardView(
                        frontZone: card.frontZone,
                        backZone: card.backZone,
                        searchQuery: viewModel.searchText
                    ) { frontZone, backZone in
                        if card.frontZone != frontZone || card.backZone != backZone {
                            card.frontZone = frontZone
                            card.backZone = backZone
                            card.editedAt = Date()
                            card.deck?.editedAt = Date()
                            try? context.save()
                            viewModel.updateSearch(query: viewModel.searchText)
                        }
                        viewModel.editingCardFromSearch = nil
                    }
                }
            }
            .sheet(item: $viewModel.deckToEditColor) { deck in
                DeckColorPickerSheet(deck: deck)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $viewModel.showShareSheet) {
                ShareSheet(items: viewModel.exportedURLs)
            }
            .fileImporter(
                isPresented: $viewModel.showFileImporter,
                allowedContentTypes: [.data],
                allowsMultipleSelection: true
            ) { result in
                viewModel.handleFileImport(result, context: context)
            }
            .confirmationDialog(
                "Delete \(viewModel.selectedDecks.count) deck\(viewModel.selectedDecks.count == 1 ? "" : "s")?",
                isPresented: $viewModel.showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        viewModel.deleteSelectedDecks(from: decks, context: context)
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This action cannot be undone.")
            }
            .confirmationDialog(
                "Delete \"\(viewModel.deckToDelete?.title ?? "")\"?",
                isPresented: Binding(
                    get: { viewModel.deckToDelete != nil },
                    set: { if !$0 { viewModel.deckToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        viewModel.confirmSingleDeletion(context: context)
                    }
                }
                Button("Cancel", role: .cancel) { viewModel.deckToDelete = nil }
            } message: {
                Text("This deck and all its cards will be deleted.")
            }
    }
}

// MARK: - Alerts

private struct LibraryAlerts: ViewModifier {
    @Bindable var viewModel: LibraryViewModel

    func body(content: Content) -> some View {
        content
            .alert("Import Error", isPresented: $viewModel.showImportError) {
                Button("OK", role: .cancel) { }
            } message: { Text(viewModel.importErrorMessage) }
            .alert("Import Successful", isPresented: $viewModel.showImportSuccess) {
                Button("OK", role: .cancel) { }
            } message: { Text("\(viewModel.importedDeckName) imported successfully.") }
            .alert("Export Error", isPresented: $viewModel.showExportError) {
                Button("OK", role: .cancel) { }
            } message: { Text(viewModel.exportErrorMessage) }
    }
}
