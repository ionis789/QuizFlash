//
//  DeckCardConversionFlow.swift
//  QuizFlash
//
//  Shared deck-detail conversion state used by `DeckViewModel` and its sheet UI.
//

import Foundation
import SwiftData

// MARK: - Conversion Source Descriptor

/// Frozen lightweight source descriptor captured when the conversion draft is created.
///
/// The descriptor intentionally stores both the source ID and its card kind so mixed-deck
/// conversion runs can filter by type without re-reading the live deck after new cards land.
nonisolated struct DeckCardConversionSourceDescriptor: Identifiable, Equatable, Hashable, Codable, Sendable {
    let id: PersistentIdentifier
    let kind: CardKind
}

// MARK: - Conversion Scope

/// The source scope the user wants to convert from the current deck.
nonisolated enum DeckCardConversionScopeOption: String, CaseIterable, Identifiable, Codable, Sendable {
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
nonisolated enum DeckCardConversionDestinationOption: String, CaseIterable, Identifiable, Codable, Sendable {
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
nonisolated struct DeckCardConversionRequest: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let availableScopes: [DeckCardConversionScopeOption]
    let wholeDeckSources: [DeckCardConversionSourceDescriptor]
    let recommendedSources: [DeckCardConversionSourceDescriptor]
    let selectedSources: [DeckCardConversionSourceDescriptor]
    let singleSources: [DeckCardConversionSourceDescriptor]
    var scope: DeckCardConversionScopeOption
    var sourceKindFilters: Set<CardKind>
    var targetKind: CardKind
    var destination: DeckCardConversionDestinationOption
    var newDeckTitle: String

    init(
        availableScopes: [DeckCardConversionScopeOption],
        wholeDeckSources: [DeckCardConversionSourceDescriptor],
        recommendedSources: [DeckCardConversionSourceDescriptor],
        selectedSources: [DeckCardConversionSourceDescriptor],
        singleSources: [DeckCardConversionSourceDescriptor],
        scope: DeckCardConversionScopeOption,
        sourceKindFilters: Set<CardKind>,
        targetKind: CardKind,
        destination: DeckCardConversionDestinationOption,
        newDeckTitle: String
    ) {
        self.id = UUID()
        self.availableScopes = availableScopes
        self.wholeDeckSources = wholeDeckSources
        self.recommendedSources = recommendedSources
        self.selectedSources = selectedSources
        self.singleSources = singleSources
        self.scope = scope
        self.sourceKindFilters = sourceKindFilters
        self.targetKind = targetKind
        self.destination = destination
        self.newDeckTitle = newDeckTitle
        normalizeSelections()
    }

    var selectedCardCount: Int {
        selectedSources.count
    }

    var recommendedCardCount: Int {
        recommendedSources.count
    }

    var currentScopeSources: [DeckCardConversionSourceDescriptor] {
        switch scope {
        case .wholeDeck:
            return wholeDeckSources
        case .recommendedCards:
            return recommendedSources
        case .selectedCards:
            return selectedSources
        case .singleCard:
            return singleSources
        }
    }

    var eligibleSourceKinds: [CardKind] {
        CardKind.allCases.filter { kind in
            kind != targetKind && currentScopeSources.contains(where: { $0.kind == kind })
        }
    }

    var availableSourceKindCounts: [CardKind: Int] {
        var counts: [CardKind: Int] = [:]
        for descriptor in currentScopeSources where descriptor.kind != targetKind {
            counts[descriptor.kind, default: 0] += 1
        }
        return counts
    }

    var filteredSources: [DeckCardConversionSourceDescriptor] {
        let filters = normalizedSourceKindFilters
        guard !filters.isEmpty else { return [] }
        return currentScopeSources.filter { filters.contains($0.kind) }
    }

    var normalizedSourceKindFilters: Set<CardKind> {
        let eligibleKinds = Set(eligibleSourceKinds)
        let filteredKinds = sourceKindFilters.intersection(eligibleKinds)
        return filteredKinds.isEmpty ? eligibleKinds : filteredKinds
    }

    var sourceCount: Int {
        filteredSources.count
    }

    var destinationDeckTitle: String? {
        guard destination == .newDeck else { return nil }
        let trimmed = newDeckTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var canStart: Bool {
        sourceCount > 0 && (destination == .sameDeck || destinationDeckTitle != nil)
    }

    func sourceCount(for kind: CardKind) -> Int {
        availableSourceKindCounts[kind] ?? 0
    }

    mutating func updateScope(_ scope: DeckCardConversionScopeOption) {
        self.scope = scope
        normalizeSelections()
    }

    mutating func updateTargetKind(_ kind: CardKind) {
        targetKind = kind
        normalizeSelections()
    }

    mutating func toggleSourceKind(_ kind: CardKind) {
        guard availableSourceKindCounts[kind] != nil else { return }

        if sourceKindFilters.contains(kind) {
            sourceKindFilters.remove(kind)
        } else {
            sourceKindFilters.insert(kind)
        }

        if normalizedSourceKindFilters.isEmpty {
            sourceKindFilters = Set(eligibleSourceKinds)
        }
    }

    func resolvedCardIDs() -> [PersistentIdentifier] {
        filteredSources.map(\.id)
    }

    mutating func normalizeSelections() {
        let eligibleKinds = Set(eligibleSourceKinds)
        sourceKindFilters = sourceKindFilters.intersection(eligibleKinds)
        if sourceKindFilters.isEmpty {
            sourceKindFilters = eligibleKinds
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
