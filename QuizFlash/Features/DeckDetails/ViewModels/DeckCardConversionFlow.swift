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
    var sourceKind: CardKind?
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
        sourceKind: CardKind?,
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
        self.sourceKind = sourceKind
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

    var availableSourceKinds: [CardKind] {
        currentScopeSources.reduce(into: []) { result, descriptor in
            guard !result.contains(descriptor.kind) else { return }
            result.append(descriptor.kind)
        }
    }

    var selectedSourceKind: CardKind? {
        guard let sourceKind else { return nil }
        return availableSourceKinds.contains(sourceKind) ? sourceKind : nil
    }

    var isSourceSelectionLocked: Bool {
        availableSourceKinds.count <= 1
    }

    var availableSourceKindCounts: [CardKind: Int] {
        var counts: [CardKind: Int] = [:]
        for descriptor in currentScopeSources {
            counts[descriptor.kind, default: 0] += 1
        }
        return counts
    }

    var filteredSources: [DeckCardConversionSourceDescriptor] {
        guard let selectedSourceKind else { return [] }
        return currentScopeSources.filter { $0.kind == selectedSourceKind }
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
        guard let selectedSourceKind else { return false }
        return sourceCount > 0
            && targetKind != selectedSourceKind
            && (destination == .sameDeck || destinationDeckTitle != nil)
    }

    func sourceCount(for kind: CardKind) -> Int {
        availableSourceKindCounts[kind] ?? 0
    }

    func isTargetKindAvailable(_ kind: CardKind) -> Bool {
        guard let selectedSourceKind else { return false }
        return kind != selectedSourceKind
    }

    mutating func updateScope(_ scope: DeckCardConversionScopeOption) {
        self.scope = scope
        normalizeSelections()
    }

    mutating func updateTargetKind(_ kind: CardKind) {
        targetKind = kind
        normalizeSelections()
    }

    mutating func selectSourceKind(_ kind: CardKind) {
        guard availableSourceKindCounts[kind] != nil else { return }
        sourceKind = kind
        normalizeSelections()
    }

    func resolvedCardIDs() -> [PersistentIdentifier] {
        filteredSources.map(\.id)
    }

    mutating func normalizeSelections() {
        let availableSourceKinds = availableSourceKinds
        if let sourceKind, availableSourceKinds.contains(sourceKind) {
            self.sourceKind = sourceKind
        } else {
            self.sourceKind = availableSourceKinds.first
        }

        guard let selectedSourceKind else { return }
        if targetKind == selectedSourceKind {
            targetKind = Self.defaultTargetKind(for: selectedSourceKind)
        }
    }

    static func makeWholeDeckRequest(
        sources: [DeckCardConversionSourceDescriptor],
        deckTitle: String,
        preferredSourceKind: CardKind? = nil,
        preferredTargetKind: CardKind? = nil,
        existingRequest: DeckCardConversionRequest? = nil,
        destination: DeckCardConversionDestinationOption? = nil
    ) -> DeckCardConversionRequest? {
        guard !sources.isEmpty else { return nil }

        let availableSourceKinds = sources.reduce(into: [CardKind]()) { result, descriptor in
            guard !result.contains(descriptor.kind) else { return }
            result.append(descriptor.kind)
        }
        let resolvedSourceKind = preferredSourceKind
            ?? existingRequest?.sourceKind
            ?? availableSourceKinds.first

        let fallbackTargetKind = defaultTargetKind(for: resolvedSourceKind ?? .flashcard)
        let resolvedTargetKind = {
            let candidate = preferredTargetKind ?? existingRequest?.targetKind ?? fallbackTargetKind
            if candidate == resolvedSourceKind {
                return fallbackTargetKind
            }
            return candidate
        }()

        let request = DeckCardConversionRequest(
            availableScopes: [.wholeDeck],
            wholeDeckSources: sources,
            recommendedSources: [],
            selectedSources: [],
            singleSources: [],
            scope: .wholeDeck,
            sourceKind: resolvedSourceKind,
            targetKind: resolvedTargetKind,
            destination: destination ?? existingRequest?.destination ?? .sameDeck,
            newDeckTitle: existingRequest?.newDeckTitle ?? "\(deckTitle) \(resolvedTargetKind.displayTitle)s"
        )
        return request.sourceCount > 0 ? request : nil
    }

    private static func defaultTargetKind(for sourceKind: CardKind) -> CardKind {
        let orderedTargets: [CardKind] = [.match, .quiz, .write, .flashcard]
        return orderedTargets.first(where: { $0 != sourceKind }) ?? .match
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
        localizedTitle(locale: AppPreferences.persistedResolvedLocale)
    }

    nonisolated func localizedTitle(locale: Locale) -> String {
        switch self {
        case .flashcard:
            return AppLocalization.string("Flashcard", locale: locale)
        case .match:
            return AppLocalization.string("Match", locale: locale)
        case .quiz:
            return AppLocalization.string("Quiz", locale: locale)
        case .write:
            return AppLocalization.string("Write", locale: locale)
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
