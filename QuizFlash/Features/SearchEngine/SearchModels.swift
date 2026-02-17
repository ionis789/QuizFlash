//
//  SearchModels.swift
//  QuizFlash
//
//

import Foundation
import SwiftData

// MARK: - Search Result Models
// Strictly Sendable to safely pass data from the background ModelActor to the MainActor ViewModel.

struct DeckSearchResultItem: Identifiable, Sendable {
    let id: PersistentIdentifier // Reference to the original DeckModel
    let deckTitle: String
    let deckIcon: String
    let deckColorHex: String
    let titleMatches: Bool
    let matchedCards: [MatchedCardInfo]
}

struct MatchedCardInfo: Identifiable, Sendable {
    let id: PersistentIdentifier // Reference to the original CardModel
    let snippet: String
}
