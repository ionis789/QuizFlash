//
//  LibraryViewModel.swift
//  QuizFlash
//
//  PERFORMANCE FIX — buildSearchCache
//  ─────────────────────────────────────────────────────────────────────────────
//  The original buildSearchCache() mapped 76 decks synchronously on the
//  MainActor. Each deck iterates all its cards, and each card calls
//  extractAllText() which recursively walks the zone tree. With 76 decks ×
//  ~20 cards × zone traversal = thousands of recursive calls per invocation,
//  all blocking the main thread. This was the direct cause of lag on tab
//  switches (onAppear fires buildSearchCache every time).
//
//  FIX: The entire payload-building loop runs on a background thread via
//  Task.detached. The MainActor receives only the finished [DeckSearchPayload]
//  array. The main thread is free to animate the tab transition uninterrupted.

import SwiftUI
import SwiftData

@Observable
@MainActor
final class LibraryViewModel {

    // MARK: - View Preferences
    var sharedSearchActor: LibrarySearchActor?
    var sortOrder: SortOrder = .newest
    var lastGroupedDecksHash: Int = 0

    /// Raw UIScrollView contentOffset.y saved by ScrollPositionRestorer.
    /// Persists across NavigationStack push/pop cycles and tab switches.
    /// Intentionally NOT cleared in tearDown() — the restorer needs the last
    /// known offset to restore position when the Library tab reappears.
    var savedScrollOffset: CGFloat = 0

    // MARK: - Selection State
    var isSelecting = false
    var selectedDecks: Set<PersistentIdentifier> = []
    var showDeleteConfirmation = false

    // MARK: - Action States
    var deckToDelete: DeckModel?
    var deckToEditColor: DeckModel?
    var editingCardFromSearch: CardModel?

    // MARK: - Search State
    var searchText: String = ""
    var searchResults: [DeckSearchResultItem] = []
    var isSearching: Bool = false
    var isSearchLoading: Bool = false

    private var searchTask: Task<Void, Never>?
    private var cacheTask: Task<Void, Never>? // tracks in-flight cache builds
    private let searchEngine = SearchEngine()

    var cachedSearchPayloads: [DeckSearchPayload] = []

    // Grouped deck sections for LibraryListView.
    // Stored here rather than as @State in LibraryLayout so the sorted list
    // survives tab switches without a 50ms debounce flash on re-appear.
    // For the root tab, sharedViewModel persists indefinitely. For folder views,
    // localViewModel is recreated on path restoration — handled by synchronous
    // first-load computation in LibraryLayout.updateGroupedDecks().
    var cachedGroupedDecks: [DeckSection] = []

    // Tracks which deck IDs were used to build the current cache.
    // Stored here (not in the View) so the deduplication check survives
    // across view re-renders, tab switches, and new LibraryView instances
    // that share this viewModel via environment injection.
    var cachedDeckIDs: Set<PersistentIdentifier> = []

    // MARK: - Import/Export States
    var showFileImporter = false
    var isImporting = false
    var showImportError = false
    var importErrorMessage = ""
    var showImportSuccess = false
    var importedDeckName = ""

    var isExporting = false
    var exportedURLs: [URL] = []
    var showShareSheet = false
    var showExportError = false
    var exportErrorMessage = ""

    // MARK: - Lifecycle

    /// Releases all cached SwiftData model references and cancels in-flight
    /// async work. Called when the Library tab is suspended during a tab switch.
    /// The cache will be lazily rebuilt on the next `onAppear` via
    /// `rebuildCacheIfNeeded`.
    func tearDown() {
        cacheTask?.cancel()
        cacheTask = nil
        searchTask?.cancel()
        searchTask = nil
        cachedSearchPayloads = []
        cachedGroupedDecks = []
        searchResults = []
        // NOTE: We intentionally keep `cachedDeckIDs` and `savedScrollOffset` populated.
        // cachedDeckIDs preserves the dedup check so re-appearing the Library tab
        // doesn't re-fault every card's text through SwiftData's row cache.
        // savedScrollOffset preserves the UIScrollView contentOffset.y so
        // ScrollPositionRestorer can restore the exact pixel position on the
        // next navigation return — without it the list would always reset to top.
    }

    // MARK: - Search Cache (Async)

    /// Rebuilds the search payload cache only if the deck dataset has materially
    /// changed since the last build.
    ///
    /// This is the primary entry point for cache management. Views should call
    /// this method rather than `buildSearchCache(decks:)` directly, so that
    /// repeated `onAppear` calls (caused by tab switches or navigation) are
    /// free when the underlying data has not changed.
    ///
    /// By storing `cachedDeckIDs` on the ViewModel rather than as `@State` on
    /// the View, the deduplication check survives across all view instances that
    /// share this ViewModel (e.g. the root Library tab reusing the environment
    /// injected instance across tab switches).
    func rebuildCacheIfNeeded(decks: [DeckModel], container: ModelContainer) {
        let newIDs = Set(decks.map { $0.id })
        guard newIDs != cachedDeckIDs else { return }
        cachedDeckIDs = newIDs
        buildSearchCache(decks: decks, container: container)
    }

    /// Builds the search payload cache on a background thread.
    /// Safe to call as often as needed — any in-flight build is cancelled
    /// first, so rapid calls (e.g. deck add/delete) don't stack up.
    func buildSearchCache(decks: [DeckModel], container: ModelContainer) {
        // Cancel any previous in-flight build.
        cacheTask?.cancel()

        // Snapshot ONLY lightweight deck metadata from the MainActor.
        // We intentionally do NOT access deck.cards here — that would
        // fault ALL CardModel objects into the main context permanently
        // (iOS 17 has no ModelContext.reset()).
        struct DeckInfo: Sendable {
            let id: PersistentIdentifier
            let title: String
            let icon: String
            let colorHex: String
        }
        cacheTask?.cancel()

        // Capture simple structs from the main context
        let deckInfos = decks.map { (id: $0.persistentModelID, title: $0.title, icon: $0.icon, colorHex: $0.colorHex) }

        cacheTask = Task { @MainActor [weak self] in
            guard let self else { return }

            if self.sharedSearchActor == nil {
                self.sharedSearchActor = LibrarySearchActor(modelContainer: container)
            }
            let payloads = await self.sharedSearchActor!.buildPayloads(for: deckInfos)

            guard !Task.isCancelled else { return }
            self.cachedSearchPayloads = payloads
        }
    }

    // MARK: - Search (Streamed)

    func updateSearch(query: String) {
        searchTask?.cancel()
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)

        if trimmedQuery.isEmpty {
            isSearching = false
            isSearchLoading = false
            searchResults = []
            return
        }

        isSearching = true
        isSearchLoading = true
        searchResults = []

        let payloadsToSearch = self.cachedSearchPayloads

        searchTask = Task {
            defer {
                if !Task.isCancelled {
                    Task { @MainActor in self.isSearchLoading = false }
                }
            }

            // Debounce is handled by LibraryLayout's inputDebounceTask.
            // No additional sleep needed here.
            guard !Task.isCancelled else { return }

            let stream = searchEngine.performSearchStream(
                query: trimmedQuery, in: payloadsToSearch
            )

            for await resultsChunk in stream {
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    self.searchResults = resultsChunk
                }
            }
        }
    }

    // MARK: - Selection

    func toggleSelection(for deck: DeckModel) {
        if selectedDecks.contains(deck.id) { selectedDecks.remove(deck.id) }
        else { selectedDecks.insert(deck.id) }
    }

    func exitSelectionMode() {
        isSelecting = false
        selectedDecks.removeAll()
    }

    // MARK: - Delete

    func deleteSelectedDecks(from allDecks: [DeckModel], context: ModelContext) {
        for deck in allDecks where selectedDecks.contains(deck.id) { context.delete(deck) }
        selectedDecks.removeAll()
        isSelecting = false
    }

    func confirmSingleDeletion(context: ModelContext) {
        if let deck = deckToDelete { context.delete(deck) }
        deckToDelete = nil
    }

    // MARK: - Import

    func handleFileImport(_ result: Result<[URL], Error>, context: ModelContext) {
        switch result {
        case .success(let urls):
            let qflashURLs = urls.filter { $0.pathExtension.lowercased() == "qflash" }
            guard !qflashURLs.isEmpty else {
                importErrorMessage = "Please select .qflash files"
                showImportError = true
                return
            }
            isImporting = true
            Task {
                var importedCount = 0
                var lastImportedName = ""
                var errors: [String] = []

                for url in qflashURLs {
                    do {
                        let deck = try await DeckSharingManager.shared.importDeck(from: url, into: context)
                        importedCount += 1
                        lastImportedName = deck.title
                    } catch {
                        errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
                    }
                }

                self.isImporting = false
                if importedCount > 0 {
                    self.importedDeckName = importedCount == 1 ? lastImportedName : "\(importedCount) decks"
                    self.showImportSuccess = true
                }
                if !errors.isEmpty {
                    self.importErrorMessage = errors.joined(separator: "\n")
                    self.showImportError = true
                }
            }
        case .failure(let error):
            importErrorMessage = error.localizedDescription
            showImportError = true
        }
    }

    // MARK: - Export

    func exportSelectedDecks(from allDecks: [DeckModel]) {
        let selected = allDecks.filter { selectedDecks.contains($0.id) }
        guard !selected.isEmpty else { return }

        isExporting = true
        Task {
            var exportedFiles: [URL] = []
            var errors: [String] = []

            for deck in selected {
                do {
                    let url = try await DeckSharingManager.shared.exportDeck(deck)
                    exportedFiles.append(url)
                } catch {
                    errors.append("\(deck.title): \(error.localizedDescription)")
                }
            }

            self.isExporting = false
            if !exportedFiles.isEmpty {
                self.exportedURLs = exportedFiles
                self.showShareSheet = true
            }
            if !errors.isEmpty {
                self.exportErrorMessage = errors.joined(separator: "\n")
                self.showExportError = true
            }
        }
    }
}

// =============================================================================
// MARK: - Safe Background Actor
// =============================================================================

@ModelActor
final actor LibrarySearchActor {
    func buildPayloads(for deckInfos: [(id: PersistentIdentifier, title: String, icon: String, colorHex: String)]) -> [DeckSearchPayload] {
        var results: [DeckSearchPayload] = []

        for info in deckInfos {
            autoreleasepool {
                // Fetch cards for this specific deck using the isolated actor context.
                let id = info.id
                var desc = FetchDescriptor<CardModel>(predicate: #Predicate { $0.deck?.persistentModelID == id })
                guard let cards = try? modelContext.fetch(desc) else { return }

                let searchCards = cards.map { CardSearchPayload(id: $0.id, frontText: $0.frontText, backText: $0.backText) }

                results.append(DeckSearchPayload(
                    id: info.id,
                    title: info.title,
                    icon: info.icon,
                    colorHex: info.colorHex,
                    cards: searchCards
                ))
            }
        }

        return results
    }
}
