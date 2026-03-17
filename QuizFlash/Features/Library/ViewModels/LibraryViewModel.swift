//
//  LibraryViewModel.swift
//  QuizFlash
//
//  Manages all UI state and business logic for the Library screen and folder views.
//
//  ## Search Cache Architecture
//  Building the search cache requires walking every card's zone tree — thousands
//  of recursive calls that would block the main thread with 70+ decks. The cache
//  is built on a background thread via `LibrarySearchActor` (Services/Search/).
//  The `MainActor` receives only the finished `[DeckSearchPayload]` array, keeping
//  tab-switch animations smooth and uninterrupted.
//
//  `LibrarySearchActor` has been extracted to `Services/Search/LibrarySearchActor.swift`.

import SwiftUI
import SwiftData

// MARK: - Library View Model

/// The ViewModel for `LibraryView` and `FolderView`.
///
/// Manages selection state, search state, import/export state, and the
/// background search payload cache. One instance lives as a long-lived
/// environment object in the root Library tab; each pushed `FolderView`
/// creates an isolated local instance that is torn down on pop.
@Observable
@MainActor
final class LibraryViewModel {

    // MARK: - View Preferences
    
    /// The shared background search actor instance.
    var sharedSearchActor: LibrarySearchActor?
    
    /// Current selected sort order for decks.
    var sortOrder: SortOrder = .newest
    
    /// Last hash used to compute grouped decks, preventing redundant updates.
    var lastGroupedDecksHash: Int = 0

    /// Raw UIScrollView contentOffset.y saved by ScrollPositionRestorer.
    /// Persists across NavigationStack push/pop cycles and tab switches.
    /// Intentionally NOT cleared in tearDown() — the restorer needs the last
    /// known offset to restore position when the Library tab reappears.
    var savedScrollOffset: CGFloat = 0

    // MARK: - Selection State
    
    /// Indicates if the user is currently selecting decks.
    var isSelecting = false
    
    /// A set holding the identifiers of the currently selected decks.
    var selectedDecks: Set<PersistentIdentifier> = []
    
    /// Indicates if the delete confirmation dialog should be shown.
    var showDeleteConfirmation = false
    
    /// Indicates if the move-to-folder confirmation dialog should be shown.
    var showMoveConfirmation = false

    // MARK: - Action States
    
    /// The specific deck marked for deletion.
    var deckToDelete: DeckModel?
    
    /// The specific deck marked for color editing.
    var deckToEditColor: DeckModel?
    
    /// The specific card currently being edited from the search results.
    var editingCardFromSearch: CardModel?
    
    /// The identifier of the deck whose action menu is currently open.
    var activeActionMenuDeckID: PersistentIdentifier?

    /// Shows the move error alert.
    var showMoveError = false

    /// The localized move error message.
    var moveErrorMessage = ""

    // MARK: - Search State
    
    /// The current search text query.
    var searchText: String = ""
    
    /// The list of search results matching the current query.
    var searchResults: [DeckSearchResultItem] = []
    
    /// Indicates if the user is currently in search mode.
    var isSearching: Bool = false
    
    /// Indicates if an active search query is still being computed.
    var isSearchLoading: Bool = false
    
    /// Decks expanded in the search results view.
    var expandedSearchDecks: Set<PersistentIdentifier> = []

    private var searchTask: Task<Void, Never>?
    private var inputDebounceTask: Task<Void, Never>?
    private var cacheTask: Task<Void, Never>? // tracks in-flight cache builds
    private var groupingTask: Task<Void, Never>?
    
    private let searchEngine = SearchEngine()

    /// The payload cache holding data used for swift searching without hitting the database repeatedly.
    var cachedSearchPayloads: [DeckSearchPayload] = []

    /// Grouped deck sections for LibraryListView.
    /// Stored here rather than as @State in LibraryLayout so the sorted list
    /// survives tab switches without a 50ms debounce flash on re-appear.
    var cachedGroupedDecks: [DeckSection] = []

    /// Tracks which deck IDs were used to build the current cache.
    /// Deduplication check survives across view re-renders, tab switches, etc.
    var cachedDeckIDs: Set<PersistentIdentifier> = []

    // MARK: - Import/Export States
    
    /// Triggers the system file importer.
    var showFileImporter = false
    
    /// Indicates if an import operation is running.
    var isImporting = false
    
    /// Shows the import error alert.
    var showImportError = false
    
    /// The localized import error message.
    var importErrorMessage = ""
    
    /// Shows the import success alert.
    var showImportSuccess = false
    
    /// Name of the recently imported deck.
    var importedDeckName = ""

    /// Indicates if an export operation is running.
    var isExporting = false
    
    /// The URLs generated for the exported decks.
    var exportedURLs: [URL] = []
    
    /// Shows the share sheet using the exported URLs.
    var showShareSheet = false
    
    /// Shows the export error alert.
    var showExportError = false
    
    /// The localized export error message.
    var exportErrorMessage = ""

    // MARK: - Lifecycle

    /// Called when a folder LibraryView is popped (folderContext != nil).
    /// Clears all cached SwiftData references and cancels in-flight async work.
    /// Also resets cachedDeckIDs so the next onAppear triggers a real rebuild
    /// (since cachedSearchPayloads will be empty, we need a fresh fetch).
    /// savedScrollOffset is intentionally kept so the scroll position can be
    /// restored if the folder is re-pushed.
    func tearDown() {
        cacheTask?.cancel()
        cacheTask = nil
        searchTask?.cancel()
        searchTask = nil
        inputDebounceTask?.cancel()
        inputDebounceTask = nil
        groupingTask?.cancel()
        groupingTask = nil
        cachedSearchPayloads = []
        cachedDeckIDs = []        // Must be cleared together with cachedSearchPayloads.
        searchResults = []        // so the next onAppear's rebuildCacheIfNeeded fires.
        expandedSearchDecks = []
        let searchActor = self.sharedSearchActor
        Task {
            await searchActor?.tearDown()
        }
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

        // Capture simple structs from the main context
        let deckInfos = decks.map { (id: $0.persistentModelID, title: $0.title, icon: $0.icon, colorHex: $0.colorHex) }

        cacheTask = Task { [weak self] in
            // Sleep on a background thread so the tab-switch animation is never
            // blocked. The previous implementation used Task { @MainActor in ... sleep }
            // which held the MainActor for 350 ms, causing visible animation stutter.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }

            // All SwiftUI/SwiftData mutations must happen on the MainActor.
            await MainActor.run {
                guard let self, !Task.isCancelled else { return }
                if self.sharedSearchActor == nil {
                    self.sharedSearchActor = LibrarySearchActor(modelContainer: container)
                }
            }

            guard !Task.isCancelled, let self else { return }
            let actor: LibrarySearchActor? = await MainActor.run { self.sharedSearchActor }
            guard let actor else { return }

            let payloads = await actor.buildPayloads(for: deckInfos)

            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.cachedSearchPayloads = payloads
            }
        }
    }

    // MARK: - Search Processing & Input

    /// Clears the input and toggles off search state safely.
    func clearSearch() {
        inputDebounceTask?.cancel()
        searchTask?.cancel()
        searchText = ""
        isSearching = false
        isSearchLoading = false
        searchResults = []
        expandedSearchDecks.removeAll()
    }
    
    /// Reevaluates input and debounces text changes before searching.
    func debounceSearchInput(_ newValue: String) {
        inputDebounceTask?.cancel()
        searchText = newValue

        if newValue.trimmingCharacters(in: .whitespaces).isEmpty {
            searchTask?.cancel()
            isSearchLoading = false
            searchResults = []
            expandedSearchDecks.removeAll()
            return
        }

        inputDebounceTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 150_000_000)
                guard !Task.isCancelled else { return }
                updateSearch(query: newValue)
            } catch {}
        }
    }

    /// Performs the search operation.
    private func updateSearch(query: String) {
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

            guard !Task.isCancelled else { return }

            let stream = searchEngine.performSearchStream(
                query: trimmedQuery, in: payloadsToSearch
            )

            for await resultsChunk in stream {
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    self.searchResults = resultsChunk
                    
                    // Auto-collapse logic when search results shrink drastically
                    if self.searchResults.count < self.expandedSearchDecks.count - 5 {
                        self.expandedSearchDecks.removeAll()
                    }
                }
            }
        }
    }

    /// Toggles the expanded status of a deck in the search results view.
    func toggleSearchDeckExpansion(for deckID: PersistentIdentifier) {
        if expandedSearchDecks.contains(deckID) {
            expandedSearchDecks.remove(deckID)
        } else {
            expandedSearchDecks.insert(deckID)
        }
    }

    // MARK: - Grouping Computation

    /// Computes and caches grouped decks on a background thread.
    func updateGroupedDecks(from snapshot: [DeckModel]) {
        groupingTask?.cancel()
        guard !snapshot.isEmpty else { return }

        let localSortOrder = sortOrder

        if cachedGroupedDecks.isEmpty {
            cachedGroupedDecks = LibraryGrouping.sections(decks: snapshot, sortOrder: localSortOrder)
            return
        }

        groupingTask = Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled else { return }
            
            let sections = await MainActor.run {
                LibraryGrouping.sections(decks: snapshot, sortOrder: localSortOrder)
            }
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                if !self.areSectionsStructurallyIdentical(old: self.cachedGroupedDecks, new: sections) {
                    self.cachedGroupedDecks = sections
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

    // MARK: - Selection

    /// Toggles the selection of a specific deck.
    func toggleSelection(for deck: DeckModel) {
        if selectedDecks.contains(deck.id) { selectedDecks.remove(deck.id) }
        else { selectedDecks.insert(deck.id) }
    }

    /// Enters multi-deck selection mode and clears any stale selection.
    func enterSelectionMode() {
        isSelecting = true
        selectedDecks.removeAll()
    }

    /// Clears selected decks and collapses the selection mode.
    func exitSelectionMode() {
        isSelecting = false
        selectedDecks.removeAll()
    }

    // MARK: - Delete

    func deleteSelectedDecks(from allDecks: [DeckModel], context: ModelContext) {
        for deck in allDecks where selectedDecks.contains(deck.id) {
            deck.folder?.deckCount -= 1
            context.delete(deck)
        }
        selectedDecks.removeAll()
        isSelecting = false
    }

    func confirmSingleDeletion(context: ModelContext) {
        if let deck = deckToDelete {
            deck.folder?.deckCount -= 1
            context.delete(deck)
        }
        deckToDelete = nil
    }

    // MARK: - Move

    func moveSelectedDecks(
        from allDecks: [DeckModel],
        to destinationFolder: FolderModel?,
        context: ModelContext
    ) {
        showMoveConfirmation = false

        let decksToMove = allDecks.filter { selectedDecks.contains($0.id) }
        guard !decksToMove.isEmpty else { return }

        let affectedFolders = uniqueFolders(
            from: decksToMove.compactMap(\.folder) + (destinationFolder.map { [$0] } ?? [])
        )
        let originalFolderCounts = Dictionary(uniqueKeysWithValues: affectedFolders.map { ($0.persistentModelID, $0.deckCount) })
        let originalDeckFolders = Dictionary(uniqueKeysWithValues: decksToMove.map { ($0.id, $0.folder) })
        let originalEditedAt = Dictionary(uniqueKeysWithValues: decksToMove.map { ($0.id, $0.editedAt) })

        var movedDecks: [DeckModel] = []

        for deck in decksToMove {
            if deck.folder?.persistentModelID == destinationFolder?.persistentModelID {
                continue
            }

            deck.folder?.deckCount -= 1
            destinationFolder?.deckCount += 1
            deck.folder = destinationFolder
            deck.editedAt = Date()
            movedDecks.append(deck)
        }

        guard !movedDecks.isEmpty else {
            exitSelectionMode()
            return
        }

        do {
            try context.save()
            exitSelectionMode()
        } catch {
            for deck in movedDecks {
                deck.folder = originalDeckFolders[deck.id] ?? nil
                if let editedAt = originalEditedAt[deck.id] {
                    deck.editedAt = editedAt
                }
            }

            for folder in affectedFolders {
                if let count = originalFolderCounts[folder.persistentModelID] {
                    folder.deckCount = count
                }
            }

            moveErrorMessage = "Couldn't move the selected decks right now."
            showMoveError = true
        }
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

    private func uniqueFolders(from folders: [FolderModel]) -> [FolderModel] {
        var seen = Set<PersistentIdentifier>()
        var unique: [FolderModel] = []

        for folder in folders {
            let id = folder.persistentModelID
            if seen.insert(id).inserted {
                unique.append(folder)
            }
        }

        return unique
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

// LibrarySearchActor has been extracted to:
// Services/Search/LibrarySearchActor.swift
