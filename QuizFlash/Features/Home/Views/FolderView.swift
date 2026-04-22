// FolderView.swift
// QuizFlash
//
// Abstract:
// Dedicated screen for browsing decks inside a single folder.
//
// Architectural context:
// FolderView is a first-class navigation destination, not a mode of LibraryView.
// The previous design used LibraryView(folderContext: folder) — a single view with
// conditional logic branching on folderContext != nil throughout its body, init,
// view model selection, tab bar rules, and lifecycle callbacks. This created fragile
// coupling between two conceptually distinct screens and was the root cause of the
// back-button label bug (shared router.deckBackLabel overwritten across tabs).
//
// Separation of concerns:
// • LibraryView  — root Library tab, uses the long-lived environment LibraryViewModel.
// • FolderView   — pushed folder screen, owns a scoped local LibraryViewModel that is
//                  torn down when the view is popped, freeing cached model references.
//
// Shared infrastructure (no duplication):
// • LibraryLayout       — context-agnostic content area, receives title as a plain String.
// • LibraryTopBarView   — already parameterised with onBack / backLabel.
// • LibraryModalsAndDialogs / LibraryAlerts — applied identically here.
// • LibraryViewModel    — same class, different instance lifetime.

import SwiftUI
import SwiftData

// MARK: - Folder View

/// A navigation destination that displays all decks belonging to a single folder.
///
/// `FolderView` owns a **scoped** `LibraryViewModel` whose lifetime is tied to
/// this view instance. When the view is popped, `viewModel.tearDown()` cancels
/// in-flight async tasks and releases cached SwiftData references, preventing
/// the iOS 17 zombie-context retain via `NotificationCenter`.
///
/// The `backLabel` for the navigation back button is frozen at push time inside
/// `AppRoute.folder(_, backLabel:)` to avoid the "ghost capsule" visual artifact
/// that occurs when `router.activeTab` mutates mid-tab-switch animation.
struct FolderView: View {

    // MARK: - Environment

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(NavigationManager.self) private var router

    // MARK: - Input

    /// The folder whose decks are displayed.
    let folder: FolderModel

    /// The label shown in the back button (e.g. "Home" or "Library").
    ///
    /// Passed at push time via `AppRoute.folder(backLabel:)` and stored as a constant
    /// to prevent reactive reads of `router.activeTab` from causing unwanted re-renders.
    let backLabel: String

    // MARK: - SwiftData Query
    //
    // Scoped to the folder at init time via a predicate on persistentModelID.
    // Delegates the fetch to SwiftData's background handling, avoiding blocking
    // context.fetch() calls on the Main Actor during view evaluation.

    @Query private var decks: [DeckModel]
    @Query(sort: \FolderModel.createdAt, order: .reverse) private var folders: [FolderModel]

    // MARK: - View Model

    /// A fresh local instance created for each pushed `FolderView`.
    ///
    /// The scope matches the folder's deck subset so the search cache is correctly
    /// isolated from the root Library tab's view model.
    @State private var viewModel = LibraryViewModel()

    // MARK: - Init

    init(folder: FolderModel, backLabel: String) {
        self.folder = folder
        self.backLabel = backLabel
        let folderID = folder.persistentModelID
        let filter = #Predicate<DeckModel> { $0.folder?.persistentModelID == folderID }
        _decks = Query(filter: filter, sort: \DeckModel.createdAt, order: .reverse)
    }

    // MARK: - Tab Bar Visibility

    /// Hides the tab bar during search or selection to reclaim the bottom safe area.
    ///
    /// In normal browsing the tab bar remains visible even though this view is pushed,
    /// mirroring the pattern used by Mail and Files for shallow navigation hierarchies.
    private var tabRule: TabBarVisibilityRule {
        if viewModel.isSearching || viewModel.isSelecting { return .hidden }
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

    // MARK: - Content With Modifiers

    private var contentWithModifiers: some View {
        mainContent
            .modifier(LibraryModalsAndDialogs(viewModel: viewModel, context: context, decks: decks, folders: folders))
            .modifier(LibraryAlerts(viewModel: viewModel))
    }

    // MARK: - Main Content

    private var mainContent: some View {
        LibraryLayout(
            decks: decks,
            folders: folders,
            viewModel: viewModel,
            router: router,
            title: .verbatim(folder.title),
            titleFallback: folder.title,
            onCardTap: { cardID in
                if let card = context.safeModel(for: cardID, as: CardModel.self) {
                    viewModel.editingCardFromSearch = .edit(DraftCard.from(card))
                }
            },
            onDeckNavigate: { deckID in
                // Back label is the folder title — the user navigates back to this folder,
                // not to a tab. Frozen at push time inside DeckNavigationValue so it is
                // immune to any subsequent router state mutations.
                router.append(DeckNavigationValue(
                    deckID: deckID,
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
            isSearching: Binding(get: { viewModel.isSearching }, set: { viewModel.isSearching = $0 }),
            searchText: Binding(get: { viewModel.searchText }, set: { viewModel.searchText = $0 })
        )
        // MARK: Lifecycle & Cache Invalidation
        .onAppear {
            rebuildCacheIfNeeded()
        }
        .onChange(of: decks) { _, newDecks in
            rebuildCacheIfNeeded(newDecks)
        }
        // MARK: Search State Management
        .onChange(of: viewModel.searchText) { _, newValue in
            viewModel.debounceSearchInput(newValue)
        }
        // MARK: Memory Cleanup on Pop
        // The local viewModel is scoped to this folder push. tearDown() cancels
        // in-flight async tasks, clears cached SwiftData model references, and
        // nils the LibrarySearchActor context — preventing the iOS 17 zombie
        // context retain via NotificationCenter.
        .onDisappear {
            viewModel.tearDown()
        }
    }

    // MARK: - Cache Helpers

    /// Triggers a cache rebuild in the view model when the deck list changes.
    ///
    /// - Parameter newDecks: The updated deck array; falls back to the current `decks` query result when `nil`.
    private func rebuildCacheIfNeeded(_ newDecks: [DeckModel]? = nil) {
        let source = newDecks ?? decks
        viewModel.rebuildCacheIfNeeded(decks: source, container: context.container)
    }
}

// MARK: - Create Folder Sheet

/// A modal sheet for creating a new folder with a custom title and label colour.
///
/// Presented by `HomeView` when `HomeViewModel.showCreateFolder` is `true`.
/// Binds directly to `HomeViewModel` via `@Bindable` so changes propagate
/// back to the VM without an extra `Binding` parameter.
struct CreateFolderSheet: View {

    // MARK: - Environment

    @Environment(\.modelContext) private var context

    // MARK: - Input

    @Bindable var viewModel: HomeViewModel

    // MARK: - Body

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
        .alert("Save Error", isPresented: $viewModel.showCreateFolderError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.createFolderErrorMessage)
        }
    }
}
