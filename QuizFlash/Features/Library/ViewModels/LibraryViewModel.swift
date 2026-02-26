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
    var sortOrder: SortOrder = .newest

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
    private var cacheTask: Task<Void, Never>?          // tracks in-flight cache builds
    private let searchEngine = SearchEngine()

    var cachedSearchPayloads: [DeckSearchPayload] = []

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

    // MARK: - Search Cache (Async)

    /// Builds the search payload cache on a background thread.
    /// Safe to call as often as needed — any in-flight build is cancelled
    /// first, so rapid calls (e.g. deck add/delete) don't stack up.
    func buildSearchCache(decks: [DeckModel]) {
        // Cancel any previous in-flight build.
        cacheTask?.cancel()

        // Snapshot the data we need from the MainActor before leaving.
        // DeckSearchPayload and CardSearchPayload are Sendable value types,
        // so they're safe to construct and send across the actor boundary.
        struct DeckSnapshot: Sendable {
            let id: PersistentIdentifier
            let title: String
            let icon: String
            let colorHex: String
            let cards: [CardSnapshot]
        }
        struct CardSnapshot: Sendable {
            let id: PersistentIdentifier
            let frontText: String
            let backText: String
        }

        // Extract all text on the MainActor (where SwiftData objects live),
        // then hand off only Sendable value types to the background task.
        let snapshots: [DeckSnapshot] = decks.map { deck in
            DeckSnapshot(
                id: deck.id,
                title: deck.title,
                icon: deck.icon,
                colorHex: deck.colorHex,
                cards: deck.cards.map { card in
                    CardSnapshot(
                        id: card.id,
                        frontText: extractAllText(from: card.frontZone),
                        backText: extractAllText(from: card.backZone)
                    )
                }
            )
        }

        // The snapshot construction above is O(decks × cards) in string ops
        // and is still on the MainActor. For 76 decks it's fast (~1-2ms).
        // The heavy lifting is in the search engine itself, which is already
        // off-thread. However, if extractAllText proves expensive, you can
        // move even that into the detached task by making ZoneModel Sendable.

        cacheTask = Task { [weak self] in
            guard let self else { return }

            // Build DeckSearchPayload objects on background thread.
            let payloads = await Task.detached(priority: .utility) {
                snapshots.map { snap in
                    DeckSearchPayload(
                        id: snap.id,
                        title: snap.title,
                        icon: snap.icon,
                        colorHex: snap.colorHex,
                        cards: snap.cards.map { c in
                            CardSearchPayload(id: c.id, frontText: c.frontText, backText: c.backText)
                        }
                    )
                }
            }.value

            guard !Task.isCancelled else { return }

            // Publish result back on MainActor.
            await MainActor.run {
                self.cachedSearchPayloads = payloads
            }
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

    // MARK: - Zone Text Extraction

    private func extractAllText(from zone: ZoneModel) -> String {
        let isLeaf = zone.children == nil || zone.children?.isEmpty == true
        if isLeaf {
            return zone.contentType == .text ? zone.text : ""
        }
        guard let children = zone.children else { return "" }
        return children
            .map { extractAllText(from: $0) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
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
