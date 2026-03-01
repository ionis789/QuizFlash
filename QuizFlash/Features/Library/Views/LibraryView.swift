//
//  LibraryView.swift
//  QuizFlash
//
//  Abstract:
//  The primary entry point for the Library tab and Folder detail views.
//  It intelligently manages its own presentation state (Root vs. Pushed),
//  coordinating custom tab bar visibility, search state, and cache invalidation.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LibraryView: View {

    // MARK: - Environment

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(NavigationManager.self) private var router

    // MARK: - SwiftData Queries

    @Query(sort: \DeckModel.createdAt, order: .reverse) private var decks: [DeckModel]

    // MARK: - View Model
    //
    // The root Library tab (folderContext == nil) uses the environment-injected
    // LibraryViewModel, which is created once in MainAppView and lives for the
    // lifetime of the app. This means:
    //   • cachedDeckIDs survives tab switches → no redundant cache rebuilds
    //   • search state is preserved when the user leaves and returns to the tab
    //
    // Folder views (folderContext != nil) use a local @State instance. This is
    // intentional — each folder has its own deck subset, so its cache is
    // independent and correctly scoped. Folder datasets are small enough that
    // a rebuild on each push is fast (~1-2ms on background thread).
    @Environment(LibraryViewModel.self) private var sharedViewModel
    @State private var localViewModel = LibraryViewModel()
    @State private var isSearching: Bool = false
    @State private var searchText: String = ""

    /// Tracks the persistent identifiers of the currently cached decks.
    /// Prevents redundant O(n) cache rebuilds during rapid tab switching.
    // Note: cachedDeckIDs has been moved into LibraryViewModel so it persists
    // alongside the cache itself, rather than resetting when the View is recreated.

    // MARK: - Context

    /// The contextual folder, if any.
    /// When non-nil, this view behaves as a pushed child view rather than a root tab.
    var folderContext: FolderModel?

    // MARK: - Resolved View Model

    /// Returns the appropriate LibraryViewModel for the current context:
    ///   - Root tab (no folder): the long-lived environment instance whose
    ///     cache persists across tab switches and navigation events.
    ///   - Folder view: a fresh local instance scoped to the folder's deck subset.
    private var viewModel: LibraryViewModel {
        folderContext == nil ? sharedViewModel : localViewModel
    }

    // MARK: - Computed Properties

    /// The dataset to display, scoped to the current context.
    private var displayedDecks: [DeckModel] {
        if let folder = folderContext {
            return folder.decks.sorted(by: { $0.createdAt > $1.createdAt })
        } else {
            return decks
        }
    }

    private var tabRule: TabBarVisibilityRule {
        if isSearching || viewModel.isSelecting { return .hidden }

        // If we are inside a folder, we are technically "pushed",
        // but we want the TabBar to remain visible.
        if folderContext != nil { return .visible }

        return .implicit
    }

    // MARK: - View Body

    var body: some View {
        Group {
            if folderContext != nil {
                // Child View Configuration (Pushed onto the NavigationStack)
                contentWithModifiers
                    .toolbar(.hidden, for: .navigationBar)
                    .swipeBack {
                    dismiss()
                }
            } else {
                // Root View Configuration (Base Tab)
                contentWithModifiers
            }
        }
        // Propagate the visibility preference up the view tree to MainAppView.
        .customTabBarVisibility(tabRule)
    }

    // MARK: - Content Modifiers

    /// Wraps the main layout with necessary operational overlays (Sheets, Alerts).
    private var contentWithModifiers: some View {
        mainContent
            .modifier(LibraryModalsAndDialogs(viewModel: viewModel, context: context, decks: displayedDecks))
            .modifier(LibraryAlerts(viewModel: viewModel))
    }

    // MARK: - Main Content

    private var mainContent: some View {
        LibraryLayout(
            decks: displayedDecks,
            viewModel: viewModel,
            router: router,
            onCardTap: { cardID in
                if let card = context.model(for: cardID) as? CardModel {
                    viewModel.editingCardFromSearch = card
                }
            },
            onDeckNavigate: { deck in
                // 🟢 iOS 17 fix: push the identifier instead of the model
                router.path.append(deck.persistentModelID)
            },
            onDeleteSelected: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    viewModel.deleteSelectedDecks(from: displayedDecks, context: context)
                }
            },
            isSearching: $isSearching,
            searchText: $searchText,
            folderContext: folderContext
        )
        // ── Lifecycle & Cache Invalidation ──
        .onAppear {
            rebuildCacheIfNeeded()
        }
            .onChange(of: displayedDecks) { _, newDecks in
            rebuildCacheIfNeeded(newDecks)
        }
        // ── Search State Management ──
        .onChange(of: isSearching) { _, active in
            viewModel.isSearching = active
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
        // ── Memory Leak Fix: Release cached model references on tab suspend ──
        .onDisappear {
            viewModel.tearDown()
        }
    }

    // MARK: - Search Cache Management

    /// Delegates to the viewModel's deduplication-aware cache builder.
    /// The ID check now lives in LibraryViewModel so it correctly persists
    /// across view re-creations for the shared root instance.
    private func rebuildCacheIfNeeded(_ newDecks: [DeckModel]? = nil) {
        let source = newDecks ?? displayedDecks
        viewModel.rebuildCacheIfNeeded(decks: source, container: context.container)
    }
}

// MARK: - Modals & Dialogs

/// Encapsulates all sheet, full-screen cover, and confirmation dialog modifiers.
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

/// Encapsulates all global alert modifiers for the Library domain.
private struct LibraryAlerts: ViewModifier {
    @Bindable var viewModel: LibraryViewModel

    func body(content: Content) -> some View {
        content
            .alert("Import Error", isPresented: $viewModel.showImportError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.importErrorMessage)
        }
            .alert("Import Successful", isPresented: $viewModel.showImportSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("\(viewModel.importedDeckName) imported successfully.")
        }
            .alert("Export Error", isPresented: $viewModel.showExportError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.exportErrorMessage)
        }
    }
}
