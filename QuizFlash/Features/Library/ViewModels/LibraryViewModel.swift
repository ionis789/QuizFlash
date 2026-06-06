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
//

import SwiftUI
import SwiftData

// MARK: - Library View Model

enum LibrarySearchPresentation: Equatable {
    case browse
    case searchEmpty
    case searchResults
}

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
    @ObservationIgnored
    var sharedSearchActor: LibrarySearchActor?

    /// Current selected sort order for decks.
    var sortOrder: SortOrder = .newest

    /// Last hash used to compute grouped decks, preventing redundant updates.
    var lastGroupedDecksHash: Int = 0

    /// Raw UIScrollView contentOffset.y saved by ScrollPositionRestorer.
    /// Persists across NavigationStack push/pop cycles and tab switches.
    /// Intentionally NOT cleared in tearDown() — the restorer needs the last
    /// known offset to restore position when the Library tab reappears.
    @ObservationIgnored
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
    var deckToDelete: LibraryDeckActionTarget?

    /// The specific deck marked for folder moving.
    var deckToMove: LibraryDeckActionTarget?

    /// The card editor destination currently presented from the search results.
    var editingCardFromSearch: CardEditorDestination?

    /// Shows the move error alert.
    var showMoveError = false

    /// The localized move error message.
    var moveErrorMessage = ""

    // MARK: - Search State

    /// The current search text query.
    var searchText: String = ""

    /// The list of search results matching the current query.
    var searchResults: [DeckSearchResultItem] = []

    /// The query whose results are currently rendered in the list.
    ///
    /// This intentionally lags behind `searchText` so the visible list can remain
    /// stable while the next query is being computed.
    var renderedSearchQuery: String = ""

    /// Indicates if the user is currently in search mode.
    var isSearching: Bool = false

    /// Indicates if an active search query is still being computed.
    var isSearchLoading: Bool = false

    /// Indicates if the empty search result state can be shown for the current query.
    var isNoMatchReady: Bool = false

    /// Decks expanded in the search results view.
    var expandedSearchDecks: Set<PersistentIdentifier> = []

    @ObservationIgnored
    var searchTask: Task<Void, Never>?
    @ObservationIgnored
    var inputDebounceTask: Task<Void, Never>?
    @ObservationIgnored
    var noMatchPresentationTask: Task<Void, Never>?
    @ObservationIgnored
    var cacheTask: Task<Void, Never>?
    @ObservationIgnored
    var groupingTask: Task<Void, Never>?
    @ObservationIgnored
    var searchGeneration = 0

    @ObservationIgnored
    let searchEngine = SearchEngine()

    /// The payload cache holding data used for swift searching without hitting the database repeatedly.
    @ObservationIgnored
    var cachedSearchPayloads: [DeckSearchPayload] = []

    /// Grouped deck sections for LibraryListView.
    /// Stored here rather than as @State in LibraryLayout so the sorted list
    /// survives tab switches without a 50ms debounce flash on re-appear.
    var cachedGroupedDecks: [DeckSection] = []

    /// Tracks which deck IDs were used to build the current cache.
    /// Deduplication check survives across view re-renders, tab switches, etc.
    @ObservationIgnored
    var cachedDeckIDs: Set<PersistentIdentifier> = []

    /// Signature for the search payload cache currently available to the search engine.
    @ObservationIgnored
    var searchCacheSignature: Int = 0

    /// Signature for the cache build currently in flight.
    @ObservationIgnored
    var pendingSearchCacheSignature: Int?

    var searchPresentation: LibrarySearchPresentation {
        guard isSearching else { return .browse }
        return renderedSearchQuery.isEmpty ? .searchEmpty : .searchResults
    }

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

    deinit {
        cacheTask?.cancel()
        searchTask?.cancel()
        inputDebounceTask?.cancel()
        groupingTask?.cancel()
    }

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
        noMatchPresentationTask?.cancel()
        noMatchPresentationTask = nil
        groupingTask?.cancel()
        groupingTask = nil
        cachedSearchPayloads = []
        cachedDeckIDs = []
        searchResults = []
        isNoMatchReady = false
        expandedSearchDecks = []
        let searchActor = sharedSearchActor
        Task {
            await searchActor?.tearDown()
        }
    }
}

// LibrarySearchActor has been extracted to:
// Services/Search/LibrarySearchActor.swift
