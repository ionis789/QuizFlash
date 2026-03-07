//
//  SearchModels.swift
//  QuizFlash
//

import Foundation
import SwiftData

// MARK: - Engine Configuration

enum SearchEngineConfig {
    /// Maximum MatchedCardInfo objects stored per deck.
    /// Set high so all practical card counts are fully stored inline.
    /// Snippet extraction beyond this is skipped to protect against
    /// pathological queries (e.g. "a") on massive decks.
    static let previewCardCap   = 200

    /// Yield a progressive batch every N matched decks.
    static let yieldEveryNDecks = 5
}

// MARK: - Card Match Side

enum CardSideMatch: String, Codable, Sendable {
    case front = "FRONT"
    case back  = "BACK"
    case both  = "FRONT & BACK"
}

// MARK: - Pure Data Payloads

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

struct DeckSearchResultItem: Identifiable, Sendable, Equatable {
    let id: PersistentIdentifier
    let deckTitle: String
    let deckIcon: String
    let deckColorHex: String
    let titleMatches: Bool

    /// All matched cards up to previewCardCap — displayed inline when expanded.
    let matchedCards: [MatchedCardInfo]

    /// Real total, may exceed matchedCards.count only on extreme decks (200+ matches).
    let totalMatchedCardsCount: Int

    /// Non-zero only when a deck has more than previewCardCap (200) matches.
    var overflowCardCount: Int {
        max(0, totalMatchedCardsCount - matchedCards.count)
    }
}

struct MatchedCardInfo: Identifiable, Sendable, Equatable {
    let id: PersistentIdentifier
    let snippet: String
    let matchSide: CardSideMatch
}
