//
//  LibraryViewModel.swift
//  QuizFlash
//

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
    private let searchEngine = SearchEngine()

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

    // MARK: - Search
    func updateSearch(query: String, decks: [DeckModel]) {
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

        let payloads = decks.map { deck in
            DeckSearchPayload(
                id: deck.id,
                title: deck.title,
                icon: deck.icon,
                colorHex: deck.colorHex,
                cards: deck.cards.map { card in
                    CardSearchPayload(
                        id: card.id,
                        frontText: extractAllText(from: card.frontZone),
                        backText: extractAllText(from: card.backZone)
                    )
                }
            )
        }

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }

            let results = await searchEngine.performSearch(query: trimmedQuery, in: payloads)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.searchResults = results
                    self.isSearchLoading = false
                }
            }
        }
    }

    private func extractAllText(from zone: ZoneModel) -> String {
        let isLeafNode = (zone.children == nil || zone.children?.isEmpty == true)
        if isLeafNode {
            return zone.contentType == .text ? zone.text : ""
        }
        guard let children = zone.children else { return "" }
        return children.map { extractAllText(from: $0) }.filter { !$0.isEmpty }.joined(separator: " ")
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
