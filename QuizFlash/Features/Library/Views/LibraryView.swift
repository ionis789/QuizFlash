//
//  LibraryView.swift
//  QuizFlash
//
//  Abstract:
//  Root screen for the Library tab. Displays all decks across every folder.
//
//  Architectural role:
//  LibraryView is exclusively the root of the Library NavigationStack. It has
//  no awareness of folders, no conditional init logic, and no dual-mode behaviour.
//  Folder browsing is handled by FolderView, a separate, independent destination.
//
//  This clean separation eliminates the entire class of bugs caused by the previous
//  LibraryView(folderContext:) design, where a single view managed two conceptually
//  distinct screens through runtime conditionals.
//
//  View model lifetime:
//  The long-lived LibraryViewModel is created once in MainAppView and injected via
//  the environment. This means:
//    • cachedSearchPayloads survive tab switches → no redundant cache rebuilds.
//    • Search text and scroll offset are preserved when the user leaves and returns.
//    • tearDown() is intentionally never called here — the root tab is permanent.
//

import SwiftUI
import SwiftData

/// The root view for the Library tab. Displays all available decks globally.
/// Strictly follows MVVM; all state is managed by `LibraryViewModel`.
struct LibraryView: View {

    // MARK: - Environment

    @Environment(\.modelContext) private var context
    @Environment(NavigationManager.self) private var router
    @Environment(LibraryViewModel.self) private var sharedViewModel

    // MARK: - SwiftData Query

    @Query(sort: \DeckModel.createdAt, order: .reverse) private var decks: [DeckModel]
    @Query(sort: \FolderModel.createdAt, order: .reverse) private var folders: [FolderModel]

    // MARK: - Tab Bar Visibility

    /// Determines when the main application tab bar should be hidden.
    private var tabRule: TabBarVisibilityRule {
        if sharedViewModel.isSearching || sharedViewModel.isSelecting { return .hidden }
        return .implicit
    }

    // MARK: - Body

    var body: some View {
        contentWithModifiers
            .toolbar(.hidden, for: .navigationBar)
            .customTabBarVisibility(tabRule)
    }

    // MARK: - Content Modifiers

    private var contentWithModifiers: some View {
        mainContent
            .modifier(LibraryModalsAndDialogs(
                viewModel: sharedViewModel,
                context: context,
                decks: decks,
                folders: folders
            ))
            .modifier(LibraryAlerts(viewModel: sharedViewModel))
    }

    // MARK: - Main Content

    @MainActor
    private var mainContent: some View {
        @Bindable var viewModel = sharedViewModel

        return LibraryLayout(
            decks: decks,
            folders: folders,
            viewModel: sharedViewModel,
            router: router,
            title: "Library",
            onCardTap: { cardID in
                if let card = context.safeModel(for: cardID, as: CardModel.self) {
                    sharedViewModel.editingCardFromSearch = card
                }
            },
            onDeckNavigate: { deck in
                // Back label is the active tab name, frozen at push time.
                // router.activeTab is always .library while LibraryView is visible.
                router.append(DeckNavigationValue(
                    deckID: deck.persistentModelID,
                    backLabel: router.activeTab.rawValue
                ))
            },
            onDeleteSelected: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    sharedViewModel.deleteSelectedDecks(from: decks, context: context)
                }
            },
            onBack: nil,
            isSearching: $viewModel.isSearching,
            searchText: $viewModel.searchText
        )
        // ── Lifecycle & Cache Invalidation ───────────────────────────────────
        .onAppear {
            rebuildCacheIfNeeded()
        }
        .onChange(of: decks) { _, newDecks in
            rebuildCacheIfNeeded(newDecks)
        }
        // ── Search State Management ──────────────────────────────────────────
        .onChange(of: sharedViewModel.searchText) { _, newValue in
            sharedViewModel.debounceSearchInput(newValue)
        }
        .onChange(of: sharedViewModel.isSearching) { _, active in
            if !active {
                sharedViewModel.clearSearch()
            }
        }
        // tearDown() is intentionally omitted for the root Library tab.
        // The sharedViewModel is injected from MainAppView and lives for the
        // full app session — destroying its cache on every tab switch would
        // defeat the purpose of the shared environment instance.
    }

    // MARK: - Cache

    private func rebuildCacheIfNeeded(_ newDecks: [DeckModel]? = nil) {
        let source = newDecks ?? decks
        sharedViewModel.rebuildCacheIfNeeded(decks: source, container: context.container)
    }
}
