//
//  LibraryViewModel+Selection.swift
//  QuizFlash
//
//  Selection state transitions for the Library view model.
//

import SwiftData

// MARK: - Selection

extension LibraryViewModel {

    /// Toggles the selection of a specific deck.
    func toggleSelection(for deckID: PersistentIdentifier) {
        if selectedDecks.contains(deckID) {
            selectedDecks.remove(deckID)
        } else {
            selectedDecks.insert(deckID)
        }
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
}
