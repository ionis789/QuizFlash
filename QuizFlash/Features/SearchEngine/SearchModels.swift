//
//  SearchModels.swift
//  QuizFlash
//

import Foundation
import SwiftData

// MARK: - Card Match Side
enum CardSideMatch: String, Codable, Sendable {
    case front = "FRONT"
    case back = "BACK"
    case both = "FRONT & BACK"
}

// MARK: - Pure Data Payloads
// Strictly Sendable structures to safely pass live, in-memory data
// from the MainActor to the Background Search Engine without triggering SwiftData thread violations.

struct DeckSearchPayload: Sendable {
    let id: PersistentIdentifier
    let title: String
    let icon: String
    let colorHex: String
    let cards: [CardSearchPayload]
}

struct CardSearchPayload: Sendable {
    let id: PersistentIdentifier
    let frontText: String
    let backText: String
}

// MARK: - Search Result Models
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
    let matchSide: CardSideMatch
}
