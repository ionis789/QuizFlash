//
//  FolderView.swift
//  QuizFlash
//
//  Abstract:
//  Dedicated screen for browsing decks inside a single folder.
//
//  Architectural context:
//  FolderView is a first-class navigation destination, not a mode of LibraryView.
//  The previous design used LibraryView(folderContext: folder) — a single view with
//  conditional logic branching on folderContext != nil throughout its body, init,
//  view model selection, tab bar rules, and lifecycle callbacks. This created fragile
//  coupling between two conceptually distinct screens and was the root cause of the
//  back-button label bug (shared router.deckBackLabel overwritten across tabs).
//
//  Separation of concerns:
//  • LibraryView  — root Library tab, uses the long-lived environment LibraryViewModel.
//  • FolderView   — pushed folder screen, owns a scoped local LibraryViewModel that is
//                   torn down when the view is popped, freeing cached model references.
//
//  Shared infrastructure (no duplication):
//  • LibraryLayout       — context-agnostic content area, receives title as a plain String.
//  • LibraryTopBarView   — already parameterised with onBack / backLabel.
//  • LibraryModalsAndDialogs / LibraryAlerts — applied identically here.
//  • LibraryViewModel    — same class, different instance lifetime.
//

import SwiftUI
import SwiftData

struct FolderView: View {

    // MARK: - Environment

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(NavigationManager.self) private var router

    // MARK: - Input

    let folder: FolderModel

    // The label shown in the back button, e.g. "Home" or "Library".
    // Passed at push time via AppRoute.folder(backLabel:) and stored as a constant.
    // This prevents FolderView from reading router.activeTab reactively — a reactive
    // read would cause a re-render mid-tab-switch (when activeTab changes to the
    // destination tab), updating the back button text while the view is still
    // cross-fading out, producing a visible ghost capsule on the incoming tab.
    let backLabel: String

    // MARK: - SwiftData Query
    //
    // Scoped to the folder at init time via a predicate on persistentModelID.
    // This delegates the fetch to SwiftData's background handling, avoiding
    // blocking context.fetch() calls on the Main Actor during view evaluation.

    @Query private var decks: [DeckModel]

    // MARK: - View Model
    //
    // A fresh local instance is created for each pushed FolderView. The scope
    // matches the folder's deck subset, so the search cache is correctly isolated.
    // tearDown() is called on disappear to release all cached SwiftData references.

    @State private var viewModel = LibraryViewModel()
    @State private var isSearching: Bool = false
    @State private var searchText: String = ""

    // MARK: - Init

    init(folder: FolderModel, backLabel: String) {
        self.folder = folder
        self.backLabel = backLabel
        let folderID = folder.persistentModelID
        let filter = #Predicate<DeckModel> { $0.folder?.persistentModelID == folderID }
        _decks = Query(filter: filter, sort: \DeckModel.createdAt, order: .reverse)
    }

    // MARK: - Tab Bar Visibility

    private var tabRule: TabBarVisibilityRule {
        // Hide the tab bar during search or selection — both overlay the bottom safe area.
        // In normal browsing the tab bar remains visible even though this view is pushed,
        // mirroring the pattern used by Mail and Files for shallow navigation hierarchies.
        if isSearching || viewModel.isSelecting { return .hidden }
        return .visible
    }

    // MARK: - Body

    var body: some View {
        contentWithModifiers
            .toolbar(.hidden, for: .navigationBar)
        // Suppress swipe-back while selection is active — a tap in empty space
        // should only exit selection mode, never simultaneously dismiss the folder.
        .swipeBack(enabled: !viewModel.isSelecting) {
            dismiss()
        }
            .customTabBarVisibility(tabRule)
    }

    // MARK: - Content Modifiers

    private var contentWithModifiers: some View {
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
            title: folder.title,
            onCardTap: { cardID in
                if let card = context.safeModel(for: cardID, as: CardModel.self) {
                    viewModel.editingCardFromSearch = card
                }
            },
            onDeckNavigate: { deck in
                // Back label is the folder title — the user navigates back to this folder,
                // not to a tab. The label is frozen at push time inside DeckNavigationValue,
                // so it is immune to any subsequent router state mutations.
                router.append(DeckNavigationValue(
                    deckID: deck.persistentModelID,
                    backLabel: folder.title
                ))
            },
            onDeleteSelected: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    viewModel.deleteSelectedDecks(from: decks, context: context)
                }
            },
            onBack: { dismiss() },
            backLabel: backLabel,
            isSearching: $isSearching,
            searchText: $searchText
        )
        // ── Lifecycle & Cache Invalidation ───────────────────────────────────
        .onAppear {
            rebuildCacheIfNeeded()
        }
            .onChange(of: decks) { _, newDecks in
            rebuildCacheIfNeeded(newDecks)
        }
        // ── Search State Management ──────────────────────────────────────────
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
        // ── Memory Cleanup on Pop ────────────────────────────────────────────
        // The local viewModel is scoped to this folder push. tearDown() cancels
        // in-flight async tasks, clears cached SwiftData model references, and
        // nils the LibrarySearchActor context — preventing the iOS 17 zombie
        // context retain via NotificationCenter.
        .onDisappear {
            viewModel.tearDown()
        }
    }

    // MARK: - Cache

    private func rebuildCacheIfNeeded(_ newDecks: [DeckModel]? = nil) {
        let source = newDecks ?? decks
        viewModel.rebuildCacheIfNeeded(decks: source, container: context.container)
    }
}


// MARK: - Create Folder Sheet
struct CreateFolderSheet: View {
    @Environment(\.modelContext) private var context
    @Bindable var viewModel: HomeViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Folder Details") {
                    TextField("Folder Name", text: $viewModel.newFolderTitle)

                    ColorPicker("Label Color", selection: Binding(
                        get: { Color(hex: viewModel.newFolderColorHex) ?? .green },
                        set: { viewModel.newFolderColorHex = $0.toHex() ?? "#34C759" }
                    ))
                }
            }
                .navigationTitle("New Folder")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.showCreateFolder = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        viewModel.createFolder(context: context)
                    }
                        .disabled(viewModel.newFolderTitle.isEmpty)
                }
            }
        }
            .presentationDetents([.medium])
    }
}
