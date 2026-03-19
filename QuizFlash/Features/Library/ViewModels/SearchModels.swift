//
//  SearchModels.swift
//  QuizFlash
//
//  Value types and configuration used by the Library search pipeline.
//  All types conform to `Sendable` for safe transfer across actor boundaries.
//

import Foundation
import SwiftData

// MARK: - Search Engine Configuration

/// Configuration constants for the `SearchEngine`.
enum SearchEngineConfig {

    /// Maximum number of `MatchedCardInfo` objects stored per deck result.
    ///
    /// Set high so all practical card counts are stored inline without truncation.
    /// Snippet extraction is skipped beyond this limit to guard against pathological
    /// queries (e.g. `"a"`) on very large decks.
    static let previewCardCap = 200

    /// The streaming batch size — the engine yields progressive results every N matched decks.
    ///
    /// Lower values improve perceived responsiveness; higher values reduce `MainActor` ping overhead.
    static let yieldEveryNDecks = 5
}

// MARK: - Card Match Side

/// Indicates which face(s) of a card matched the search query.
enum CardSideMatch: String, Codable, Sendable {
    case front = "PROMPT"
    case back  = "ANSWER"
    case both  = "PROMPT & ANSWER"
    case content = "CONTENT"
}

// MARK: - Search Input Payloads

/// A lightweight, `Sendable` snapshot of a deck's metadata and card text, used
/// as the input format for the `SearchEngine`. Contains no SwiftData model references.
struct DeckSearchPayload: Sendable {
    /// The deck's `PersistentIdentifier` — used to look up the live model after search completes.
    let id: PersistentIdentifier
    let title: String
    let icon: String
    let colorHex: String
    /// Pre-extracted plain-text snapshots for each card in the deck.
    let cards: [CardSearchPayload]
}

/// A lightweight, `Sendable` snapshot of a single card's text content.
struct CardSearchPayload: Sendable {
    /// The card's `PersistentIdentifier` — used to look up the live model after search completes.
    let id: PersistentIdentifier
    let frontText: String
    let backText: String
    let searchDocumentText: String
}

// MARK: - Search Result Models

/// A complete search result for a single deck, including all matched card snippets.
struct DeckSearchResultItem: Identifiable, Sendable, Equatable {
    let id: PersistentIdentifier
    let deckTitle: String
    let deckIcon: String
    let deckColorHex: String
    /// `true` if the search query matched the deck's title directly.
    let titleMatches: Bool
    /// All matched cards, up to `SearchEngineConfig.previewCardCap`.
    let matchedCards: [MatchedCardInfo]
    /// The true total match count (may exceed `matchedCards.count` for very large decks).
    let totalMatchedCardsCount: Int

    /// The number of matched cards not included in `matchedCards` due to the preview cap.
    ///
    /// Non-zero only when a deck returns more than `SearchEngineConfig.previewCardCap` matches.
    var overflowCardCount: Int {
        max(0, totalMatchedCardsCount - matchedCards.count)
    }
}

/// A single matched card within a `DeckSearchResultItem`.
struct MatchedCardInfo: Identifiable, Sendable, Equatable {
    let id: PersistentIdentifier
    /// A brief text excerpt from the matching face of the card.
    let snippet: String
    /// Which face(s) of the card matched the query.
    let matchSide: CardSideMatch
}
