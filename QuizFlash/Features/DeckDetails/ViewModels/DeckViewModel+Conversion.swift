//
//  DeckViewModel+Conversion.swift
//  QuizFlash
//
//  Deck conversion request building for the deck screen.
//

import SwiftUI
import SwiftData

extension DeckViewModel {
    func presentDeckConversion(
        for deck: DeckModel,
        preferredTargetKind: CardKind? = nil
    ) -> DeckCardConversionRequest? {
        makeConversionRequest(
            for: deck,
            preferredScope: .wholeDeck,
            singleCardID: nil,
            preferredTargetKind: preferredTargetKind,
            recommendedCardIDs: []
        )
    }

    /// Opens the conversion flow starting from the current multi-card selection.
    func presentSelectionConversion(
        for deck: DeckModel,
        preferredTargetKind: CardKind? = nil
    ) -> DeckCardConversionRequest? {
        guard !orderedSelectedCardIDs().isEmpty else { return nil }
        return makeConversionRequest(
            for: deck,
            preferredScope: .selectedCards,
            singleCardID: nil,
            preferredTargetKind: preferredTargetKind,
            recommendedCardIDs: []
        )
    }

    /// Opens the conversion flow starting from one specific card.
    func presentSingleCardConversion(
        for cardID: PersistentIdentifier,
        in deck: DeckModel,
        preferredTargetKind: CardKind? = nil
    ) -> DeckCardConversionRequest? {
        makeConversionRequest(
            for: deck,
            preferredScope: .singleCard,
            singleCardID: cardID,
            preferredTargetKind: preferredTargetKind,
            recommendedCardIDs: []
        )
    }

    /// Opens the conversion flow for cards specifically flagged by readiness diagnostics.
    func presentReadinessConversion(
        for targetKind: CardKind,
        in deck: DeckModel
    ) -> DeckCardConversionRequest? {
        let recommendedCardIDs = recommendedConversionCardIDs(for: targetKind)
        guard !recommendedCardIDs.isEmpty else { return nil }

        return makeConversionRequest(
            for: deck,
            preferredScope: .recommendedCards,
            singleCardID: nil,
            preferredTargetKind: targetKind,
            recommendedCardIDs: recommendedCardIDs
        )
    }

    private func makeConversionRequest(
        for deck: DeckModel,
        preferredScope: DeckCardConversionScopeOption,
        singleCardID: PersistentIdentifier?,
        preferredTargetKind: CardKind?,
        recommendedCardIDs: [PersistentIdentifier]
    ) -> DeckCardConversionRequest? {
        let selectedIDs = orderedSelectedCardIDs()
        let selectedIDSet = Set(selectedIDs)
        let recommendedIDSet = Set(recommendedCardIDs)
        let visibleCards = visibleCardsInDisplayOrder()

        let wholeDeckSources = allCardInfos.map {
            DeckCardConversionSourceDescriptor(id: $0.id, kind: $0.kind)
        }
        let selectedSources = visibleCards
            .filter { selectedIDSet.contains($0.id) }
            .map { DeckCardConversionSourceDescriptor(id: $0.id, kind: $0.kind) }
        let recommendedSources = visibleCards
            .filter { recommendedIDSet.contains($0.id) }
            .map { DeckCardConversionSourceDescriptor(id: $0.id, kind: $0.kind) }
        let singleSources = singleCardID.flatMap { id in
            allCardInfos
                .first(where: { $0.id == id })
                .map { [DeckCardConversionSourceDescriptor(id: $0.id, kind: $0.kind)] }
        } ?? []

        var availableScopes: [DeckCardConversionScopeOption] = [.wholeDeck]
        if !recommendedCardIDs.isEmpty {
            availableScopes.insert(.recommendedCards, at: 0)
        }
        if !selectedIDs.isEmpty {
            availableScopes.append(.selectedCards)
        }
        if singleCardID != nil {
            availableScopes.insert(.singleCard, at: 0)
        }

        guard availableScopes.contains(preferredScope) else { return nil }

        let currentSources: [DeckCardConversionSourceDescriptor]
        switch preferredScope {
        case .wholeDeck:
            currentSources = wholeDeckSources
        case .recommendedCards:
            currentSources = recommendedSources
        case .selectedCards:
            currentSources = selectedSources
        case .singleCard:
            currentSources = singleSources
        }

        let sourceKinds = currentSources.map(\.kind)
        guard !sourceKinds.isEmpty else { return nil }

        let targetKind = preferredTargetKind ?? defaultConversionTargetKind(for: sourceKinds)
        let sourceKindFilters = Set(
            currentSources
                .map(\.kind)
                .filter { $0 != targetKind }
        )
        let newDeckTitle = "\(deck.title) \(targetKind.displayTitle)s"

        return DeckCardConversionRequest(
            availableScopes: availableScopes,
            wholeDeckSources: wholeDeckSources,
            recommendedSources: recommendedSources,
            selectedSources: selectedSources,
            singleSources: singleSources,
            scope: preferredScope,
            sourceKindFilters: sourceKindFilters,
            targetKind: targetKind,
            destination: .sameDeck,
            newDeckTitle: newDeckTitle
        )
    }

    private func defaultConversionTargetKind(for sourceKinds: [CardKind]) -> CardKind {
        let sourceKindSet = Set(sourceKinds)
        let orderedTargets: [CardKind] = [.match, .quiz, .write, .flashcard]
        return orderedTargets.first(where: { !sourceKindSet.contains($0) }) ?? .match
    }

    private func orderedSelectedCardIDs() -> [PersistentIdentifier] {
        visibleCardsInDisplayOrder()
            .filter { selectedCards.contains($0.id) }
            .map(\.id)
    }

    private func recommendedConversionCardIDs(for targetKind: CardKind) -> [PersistentIdentifier] {
        visibleCardsInDisplayOrder()
            .filter { card in
                CardReadinessDiagnostics.diagnostics(for: card)
                    .contains { $0.recommendedConversionTargetKind == targetKind }
            }
            .map(\.id)
    }

    private func visibleCardsInDisplayOrder() -> [GridCardInfo] {
        cachedGroupedCards.flatMap(\.cards)
    }
}
