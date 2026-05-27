//
//  LibraryViewModel+Search.swift
//  QuizFlash
//
//  Search input and result presentation for the Library view model.
//

import Foundation
import SwiftData

// MARK: - Search

extension LibraryViewModel {

    /// Clears the input and toggles off search state safely.
    func clearSearch() {
        searchGeneration += 1
        inputDebounceTask?.cancel()
        searchTask?.cancel()
        searchText = ""
        renderedSearchQuery = ""
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
            searchGeneration += 1
            searchTask?.cancel()
            isSearchLoading = false
            renderedSearchQuery = ""
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

    /// Toggles the expanded status of a deck in the search results view.
    func toggleSearchDeckExpansion(for deckID: PersistentIdentifier) {
        if expandedSearchDecks.contains(deckID) {
            expandedSearchDecks.remove(deckID)
        } else {
            expandedSearchDecks.insert(deckID)
        }
    }
}

// MARK: - Search Processing

private extension LibraryViewModel {

    /// Performs the search operation.
    func updateSearch(query: String) {
        searchTask?.cancel()
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)

        if trimmedQuery.isEmpty {
            renderedSearchQuery = ""
            isSearchLoading = false
            searchResults = []
            return
        }

        searchGeneration += 1
        let generation = searchGeneration
        isSearchLoading = true

        let payloadsToSearch = cachedSearchPayloads

        searchTask = Task {
            guard !Task.isCancelled else { return }

            let stream = searchEngine.performSearchStream(
                query: trimmedQuery,
                in: payloadsToSearch
            )

            var latestResults: [DeckSearchResultItem] = []
            for await resultsChunk in stream {
                guard !Task.isCancelled else { break }
                latestResults = resultsChunk
            }

            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard generation == self.searchGeneration else { return }
                self.searchResults = latestResults
                self.renderedSearchQuery = trimmedQuery
                self.isSearchLoading = false
                self.expandedSearchDecks.removeAll()
            }
        }
    }
}
