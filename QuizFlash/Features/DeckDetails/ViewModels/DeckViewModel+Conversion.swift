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
        makeWholeDeckConversionRequest(for: deck, preferredTargetKind: preferredTargetKind)
    }

    /// All deck-detail entry points converge into the same deck-scoped conversion draft.
    func presentSelectionConversion(
        for deck: DeckModel,
        preferredTargetKind: CardKind? = nil
    ) -> DeckCardConversionRequest? {
        let selectedSources = allCardInfos
            .filter { selectedCards.contains($0.id) }
            .map(conversionSourceDescriptor(from:))
        return makeScopedConversionRequest(
            for: deck,
            scope: .selectedCards,
            scopedSources: selectedSources,
            preferredTargetKind: preferredTargetKind
        )
    }

    /// Single-card entry points freeze the currently opened card as the only source.
    func presentSingleCardConversion(
        for cardID: PersistentIdentifier,
        in deck: DeckModel,
        preferredTargetKind: CardKind? = nil
    ) -> DeckCardConversionRequest? {
        let singleSources = allCardInfos
            .filter { $0.id == cardID }
            .map(conversionSourceDescriptor(from:))
        return makeScopedConversionRequest(
            for: deck,
            scope: .singleCard,
            scopedSources: singleSources,
            preferredTargetKind: preferredTargetKind
        )
    }

    /// Readiness entry points reuse the same deck-level editor but keep the preferred target kind.
    func presentReadinessConversion(
        for targetKind: CardKind,
        in deck: DeckModel
    ) -> DeckCardConversionRequest? {
        makeWholeDeckConversionRequest(for: deck, preferredTargetKind: targetKind)
    }

    private func makeWholeDeckConversionRequest(
        for deck: DeckModel,
        preferredTargetKind: CardKind?
    ) -> DeckCardConversionRequest? {
        let wholeDeckSources = allCardInfos.map(conversionSourceDescriptor(from:))
        return DeckCardConversionRequest.makeWholeDeckRequest(
            sources: wholeDeckSources,
            deckTitle: deck.title,
            preferredTargetKind: preferredTargetKind
        )
    }

    private func makeScopedConversionRequest(
        for deck: DeckModel,
        scope: DeckCardConversionScopeOption,
        scopedSources: [DeckCardConversionSourceDescriptor],
        preferredTargetKind: CardKind?
    ) -> DeckCardConversionRequest? {
        guard !scopedSources.isEmpty else { return nil }

        let wholeDeckSources = allCardInfos.map(conversionSourceDescriptor(from:))
        let preferredSourceKind = scopedSources.first?.kind
        let resolvedTargetKind = preferredTargetKind
            ?? defaultTargetKind(for: preferredSourceKind ?? .flashcard)

        return DeckCardConversionRequest(
            availableScopes: [scope],
            wholeDeckSources: wholeDeckSources,
            recommendedSources: scope == .recommendedCards ? scopedSources : [],
            selectedSources: scope == .selectedCards ? scopedSources : [],
            singleSources: scope == .singleCard ? scopedSources : [],
            scope: scope,
            sourceKind: preferredSourceKind,
            targetKind: resolvedTargetKind,
            destination: .sameDeck,
            newDeckTitle: "\(deck.title) \(resolvedTargetKind.displayTitle)s"
        )
    }

    private func conversionSourceDescriptor(from info: GridCardInfo) -> DeckCardConversionSourceDescriptor {
        DeckCardConversionSourceDescriptor(id: info.id, kind: info.kind)
    }

    private func defaultTargetKind(for sourceKind: CardKind) -> CardKind {
        let orderedTargets: [CardKind] = [.match, .quiz, .write, .flashcard]
        return orderedTargets.first(where: { $0 != sourceKind }) ?? .match
    }
}
