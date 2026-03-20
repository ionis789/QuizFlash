//
//  DeckCardConversionFlow.swift
//  QuizFlash
//
//  Shared deck-detail conversion state used by `DeckViewModel` and its sheet UI.
//

import Foundation
import SwiftData

// MARK: - Conversion Scope

/// The source scope the user wants to convert from the current deck.
enum DeckCardConversionScopeOption: String, CaseIterable, Identifiable, Sendable {
    case wholeDeck
    case recommendedCards
    case selectedCards
    case singleCard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wholeDeck:
            return "Whole Deck"
        case .recommendedCards:
            return "Recommended Cards"
        case .selectedCards:
            return "Selection"
        case .singleCard:
            return "Single Card"
        }
    }

    var subtitle: String {
        switch self {
        case .wholeDeck:
            return "Convert every card currently in this deck."
        case .recommendedCards:
            return "Convert only the cards flagged by readiness diagnostics."
        case .selectedCards:
            return "Convert only the cards currently selected."
        case .singleCard:
            return "Convert just the card you opened from the grid."
        }
    }
}

// MARK: - Conversion Destination

/// The destination strategy for a conversion run.
enum DeckCardConversionDestinationOption: String, CaseIterable, Identifiable, Sendable {
    case sameDeck
    case newDeck

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sameDeck:
            return "Same Deck"
        case .newDeck:
            return "New Deck"
        }
    }

    var subtitle: String {
        switch self {
        case .sameDeck:
            return "Keep originals and append converted copies."
        case .newDeck:
            return "Create a sibling deck with the converted cards only."
        }
    }
}

// MARK: - Conversion Draft

/// Mutable configuration state for the deck conversion sheet.
struct DeckCardConversionRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    let availableScopes: [DeckCardConversionScopeOption]
    let wholeDeckCardCount: Int
    let recommendedCardIDs: [PersistentIdentifier]
    let selectedCardIDs: [PersistentIdentifier]
    let singleCardID: PersistentIdentifier?
    let sourceKinds: [CardKind]
    var scope: DeckCardConversionScopeOption
    var targetKind: CardKind
    var destination: DeckCardConversionDestinationOption
    var newDeckTitle: String

    init(
        availableScopes: [DeckCardConversionScopeOption],
        wholeDeckCardCount: Int,
        recommendedCardIDs: [PersistentIdentifier],
        selectedCardIDs: [PersistentIdentifier],
        singleCardID: PersistentIdentifier?,
        sourceKinds: [CardKind],
        scope: DeckCardConversionScopeOption,
        targetKind: CardKind,
        destination: DeckCardConversionDestinationOption,
        newDeckTitle: String
    ) {
        self.id = UUID()
        self.availableScopes = availableScopes
        self.wholeDeckCardCount = wholeDeckCardCount
        self.recommendedCardIDs = recommendedCardIDs
        self.selectedCardIDs = selectedCardIDs
        self.singleCardID = singleCardID
        self.sourceKinds = sourceKinds
        self.scope = scope
        self.targetKind = targetKind
        self.destination = destination
        self.newDeckTitle = newDeckTitle
    }

    var selectedCardCount: Int {
        selectedCardIDs.count
    }

    var recommendedCardCount: Int {
        recommendedCardIDs.count
    }

    var sourceCount: Int {
        switch scope {
        case .wholeDeck:
            return wholeDeckCardCount
        case .recommendedCards:
            return recommendedCardIDs.count
        case .selectedCards:
            return selectedCardIDs.count
        case .singleCard:
            return singleCardID == nil ? 0 : 1
        }
    }

    var destinationDeckTitle: String? {
        guard destination == .newDeck else { return nil }
        let trimmed = newDeckTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var canStart: Bool {
        sourceCount > 0 && (destination == .sameDeck || destinationDeckTitle != nil)
    }

    func resolvedCardIDs() -> [PersistentIdentifier]? {
        switch scope {
        case .wholeDeck:
            return nil
        case .recommendedCards:
            return recommendedCardIDs
        case .selectedCards:
            return selectedCardIDs
        case .singleCard:
            return singleCardID.map { [$0] } ?? []
        }
    }
}

// MARK: - Conversion Progress

/// Live status shown while the AI conversion pipeline is running.
struct DeckCardConversionProgress: Equatable, Sendable {
    let totalCount: Int
    let completedCount: Int
    let createdCount: Int
    let skippedCount: Int
    let failedCount: Int
    let statusMessage: String

    var fractionCompleted: Double {
        guard totalCount > 0 else { return 0 }
        return min(1, Double(completedCount) / Double(totalCount))
    }
}

// MARK: - Conversion Summary

/// Final persisted summary for one conversion run.
struct DeckCardConversionSummary: Equatable, Sendable {
    let sourceCount: Int
    let createdCount: Int
    let skippedCount: Int
    let failedCount: Int
    let targetKind: CardKind
    let destination: DeckCardConversionDestinationOption
    let destinationDeckTitle: String
    let destinationDeckID: PersistentIdentifier?
}

// MARK: - Card Kind Presentation

extension CardKind {
    /// Human-readable label used in conversion UI.
    nonisolated var displayTitle: String {
        switch self {
        case .flashcard:
            return "Flashcard"
        case .match:
            return "Match"
        case .quiz:
            return "Quiz"
        case .write:
            return "Write"
        }
    }

    /// SF Symbol used by compact conversion pickers.
    nonisolated var conversionSystemImage: String {
        switch self {
        case .flashcard:
            return "rectangle.stack.fill"
        case .match:
            return "square.grid.2x2.fill"
        case .quiz:
            return "questionmark.square.dashed"
        case .write:
            return "pencil.line"
        }
    }

    /// Matching AI output profile used by the conversion service.
    nonisolated var aiGenerationType: AICardGenerationType {
        switch self {
        case .flashcard:
            return .flashcards
        case .match:
            return .match
        case .quiz:
            return .quiz
        case .write:
            return .write
        }
    }
}
