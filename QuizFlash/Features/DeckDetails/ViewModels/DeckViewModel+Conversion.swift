//
//  DeckViewModel+Conversion.swift
//  QuizFlash
//
//  Deck conversion orchestration for the deck screen.
//

import SwiftUI
import SwiftData
import OSLog

extension DeckViewModel {
    func presentDeckConversion(
        for deck: DeckModel,
        preferredTargetKind: CardKind? = nil
    ) {
        conversionRequest = makeConversionRequest(
            for: deck,
            preferredScope: .wholeDeck,
            singleCardID: nil,
            preferredTargetKind: preferredTargetKind,
            recommendedCardIDs: []
        )
        conversionProgress = nil
        conversionSummary = nil
        conversionErrorMessage = nil
    }

    /// Opens the conversion flow starting from the current multi-card selection.
    func presentSelectionConversion(
        for deck: DeckModel,
        preferredTargetKind: CardKind? = nil
    ) {
        guard !orderedSelectedCardIDs().isEmpty else { return }
        conversionRequest = makeConversionRequest(
            for: deck,
            preferredScope: .selectedCards,
            singleCardID: nil,
            preferredTargetKind: preferredTargetKind,
            recommendedCardIDs: []
        )
        conversionProgress = nil
        conversionSummary = nil
        conversionErrorMessage = nil
    }

    /// Opens the conversion flow starting from one specific card.
    func presentSingleCardConversion(
        for cardID: PersistentIdentifier,
        in deck: DeckModel,
        preferredTargetKind: CardKind? = nil
    ) {
        conversionRequest = makeConversionRequest(
            for: deck,
            preferredScope: .singleCard,
            singleCardID: cardID,
            preferredTargetKind: preferredTargetKind,
            recommendedCardIDs: []
        )
        conversionProgress = nil
        conversionSummary = nil
        conversionErrorMessage = nil
    }

    /// Opens the conversion flow for cards specifically flagged by readiness diagnostics.
    func presentReadinessConversion(
        for targetKind: CardKind,
        in deck: DeckModel
    ) {
        let recommendedCardIDs = recommendedConversionCardIDs(for: targetKind)
        guard !recommendedCardIDs.isEmpty else { return }

        conversionRequest = makeConversionRequest(
            for: deck,
            preferredScope: .recommendedCards,
            singleCardID: nil,
            preferredTargetKind: targetKind,
            recommendedCardIDs: recommendedCardIDs
        )
        conversionProgress = nil
        conversionSummary = nil
        conversionErrorMessage = nil
    }

    /// Cancels any in-flight conversion task and clears the sheet state.
    func dismissConversionSheet() {
        cancelConversion()
        conversionRequest = nil
        conversionProgress = nil
        conversionSummary = nil
        conversionErrorMessage = nil
    }

    /// Starts the configured conversion run and keeps progress in sync for the sheet UI.
    func startConversion(
        for deck: DeckModel,
        context: ModelContext
    ) {
        guard let request = conversionRequest, request.canStart else { return }

        cancelConversion()
        conversionSummary = nil
        conversionErrorMessage = nil
        conversionProgress = DeckCardConversionProgress(
            totalCount: request.sourceCount,
            completedCount: 0,
            createdCount: 0,
            skippedCount: 0,
            failedCount: 0,
            statusMessage: "Preparing source cards"
        )

        conversionTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                try await self.runConversion(
                    request: request,
                    deck: deck,
                    context: context
                )
            } catch is CancellationError {
                self.conversionProgress = nil
            } catch {
                self.conversionProgress = nil
                self.conversionErrorMessage = error.localizedDescription
            }

            self.conversionTask = nil
        }
    }

    func cancelConversion() {
        conversionTask?.cancel()
        conversionTask = nil
    }

    private func runConversion(
        request: DeckCardConversionRequest,
        deck: DeckModel,
        context: ModelContext
    ) async throws {
        let sourceSnapshots = try await fetchConversionSources(
            request: request,
            deckID: deck.persistentModelID,
            container: context.container
        )

        guard !sourceSnapshots.isEmpty else {
            conversionProgress = nil
            conversionErrorMessage = "No compatible source cards were available for conversion."
            return
        }

        guard let activeProfile = AIProviderStore.shared.activeProfile else {
            throw NSError(
                domain: "DeckConversion",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No AI provider is configured. Open Settings > AI Providers."]
            )
        }

        if let validationMessage = activeProfile.generationValidationMessage {
            throw NSError(
                domain: "DeckConversion",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: validationMessage]
            )
        }

        let aiService = AIFlashcardService(provider: activeProfile)
        let batchID = UUID()
        let convertedAt = Date()
        let totalCount = sourceSnapshots.count
        var completedCount = 0
        var createdCount = 0
        var skippedCount = 0
        var failedCount = 0
        var destinationDeck: DeckModel? = nil

        let sourcesByID = Dictionary(uniqueKeysWithValues: sourceSnapshots.map { ($0.id, $0) })
        let skippedSources = sourceSnapshots.filter {
            $0.kind == request.targetKind ||
            $0.content.searchDocumentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let convertibleSources = sourceSnapshots.filter { source in
            !skippedSources.contains(where: { $0.id == source.id })
        }

        if !skippedSources.isEmpty {
            skippedCount += skippedSources.count
            completedCount += skippedSources.count
            updateConversionProgress(
                totalCount: totalCount,
                completedCount: completedCount,
                createdCount: createdCount,
                skippedCount: skippedCount,
                failedCount: failedCount,
                statusMessage: "Skipped \(skippedSources.count) card\(skippedSources.count == 1 ? "" : "s") already in \(request.targetKind.displayTitle)"
            )
        }

        if !convertibleSources.isEmpty {
            updateConversionProgress(
                totalCount: totalCount,
                completedCount: completedCount,
                createdCount: createdCount,
                skippedCount: skippedCount,
                failedCount: failedCount,
                statusMessage: "Planning AI conversion batches"
            )
        }

        let conversionStream = aiService.convertCardsStream(
            convertibleSources.map {
                AICardConversionSource(id: $0.id, kind: $0.kind, content: $0.content)
            },
            to: request.targetKind.aiGenerationType
        )

        do {
            for try await chunk in conversionStream {
                try Task.checkCancellation()

                let persistedCount = try persistConvertedOutputs(
                    chunk.outputs,
                    request: request,
                    sourcesByID: sourcesByID,
                    batchID: batchID,
                    convertedAt: convertedAt,
                    sourceDeck: deck,
                    destinationDeck: &destinationDeck,
                    context: context
                )

                let batchFailures = max(0, chunk.plannedCardCount - persistedCount)
                createdCount += persistedCount
                failedCount += batchFailures
                completedCount += chunk.plannedCardCount

                updateConversionProgress(
                    totalCount: totalCount,
                    completedCount: completedCount,
                    createdCount: createdCount,
                    skippedCount: skippedCount,
                    failedCount: failedCount,
                    statusMessage: conversionStatusMessage(
                        for: chunk,
                        targetKind: request.targetKind,
                        persistedCount: persistedCount
                    )
                )
            }
        } catch {
            let remainingCount = max(0, totalCount - completedCount)
            if remainingCount > 0 {
                failedCount += remainingCount
                completedCount += remainingCount
            }
            logger.error("Conversion stream finished with partial failures: \(error.localizedDescription, privacy: .public)")
        }

        conversionProgress = nil
        conversionSummary = DeckCardConversionSummary(
            sourceCount: totalCount,
            createdCount: createdCount,
            skippedCount: skippedCount,
            failedCount: failedCount,
            targetKind: request.targetKind,
            destination: request.destination,
            destinationDeckTitle: request.destination == .sameDeck
                ? deck.title
                : (destinationDeck?.title ?? request.destinationDeckTitle ?? deck.title),
            destinationDeckID: request.destination == .sameDeck
                ? deck.persistentModelID
                : destinationDeck?.persistentModelID
        )

        if request.destination == .sameDeck || createdCount > 0 {
            await loadSnapshot(deckID: deck.persistentModelID, container: context.container)
        }
    }

    private func conversionStatusMessage(
        for chunk: AIConversionBatchChunk,
        targetKind: CardKind,
        persistedCount: Int
    ) -> String {
        let rejectedCount = max(0, chunk.plannedCardCount - persistedCount)

        if rejectedCount > 0, targetKind == .match {
            return "Accepted \(persistedCount) high-quality Match card\(persistedCount == 1 ? "" : "s") from \(chunk.sourceLabel). Rejected \(rejectedCount) verbose pair\(rejectedCount == 1 ? "" : "s")."
        }

        if rejectedCount > 0 {
            return "Converted \(persistedCount) card\(persistedCount == 1 ? "" : "s") from \(chunk.sourceLabel). \(rejectedCount) could not be completed."
        }

        return "Converted \(persistedCount) \(targetKind.displayTitle.lowercased()) card\(persistedCount == 1 ? "" : "s") from \(chunk.sourceLabel)."
    }

    private func fetchConversionSources(
        request: DeckCardConversionRequest,
        deckID: PersistentIdentifier,
        container: ModelContainer
    ) async throws -> [CardConversionSourceSnapshot] {
        let actor = CardFetchActor(container: container)
        let sources = await actor.fetchConversionSources(
            deckID: deckID,
            cardIDs: request.resolvedCardIDs()
        )
        await actor.tearDown()
        return sources
    }

    func persistConvertedOutputs(
        _ outputs: [AICardConversionOutput],
        request: DeckCardConversionRequest,
        sourcesByID: [PersistentIdentifier: CardConversionSourceSnapshot],
        batchID: UUID,
        convertedAt: Date,
        sourceDeck: DeckModel,
        destinationDeck: inout DeckModel?,
        context: ModelContext
    ) throws -> Int {
        guard !outputs.isEmpty else { return 0 }

        let destinationWasCreatedInThisCall = destinationDeck == nil && request.destination == .newDeck
        let targetDeck = try resolveDestinationDeck(
            for: request,
            sourceDeck: sourceDeck,
            destinationDeck: &destinationDeck,
            context: context
        )

        let originalLastAssigned = targetDeck.lastAssignedCardNumber
        let originalCardCount = targetDeck.cardCount
        let originalEditedAt = targetDeck.editedAt
        let insertedCardsStart = targetDeck.cards.count
        var insertedCards: [CardModel] = []
        var nextCardNumber = targetDeck.lastAssignedCardNumber

        do {
            for output in outputs {
                guard let source = sourcesByID[output.sourceCardID] else {
                    throw NSError(
                        domain: "DeckConversion",
                        code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "One converted result could not be matched back to its source card."]
                    )
                }

                let content = try AIGeneratedCardContentMapper.map(output.generatedCard)
                nextCardNumber += 1

                let newCard = CardModel(
                    content: content,
                    cardNumber: nextCardNumber,
                    isPinned: false,
                    creationSource: .ai,
                    conversionMetadata: CardConversionMetadata(
                        sourceCardID: source.id,
                        sourceKind: source.kind,
                        targetKind: request.targetKind,
                        batchID: batchID,
                        convertedAt: convertedAt
                    )
                )
                newCard.deck = targetDeck
                targetDeck.cards.append(newCard)
                context.insert(newCard)
                insertedCards.append(newCard)
            }

            targetDeck.lastAssignedCardNumber = nextCardNumber
            targetDeck.cardCount = originalCardCount + insertedCards.count
            targetDeck.editedAt = Date()
            try context.save()
            return insertedCards.count
        } catch {
            for card in insertedCards {
                context.delete(card)
            }
            targetDeck.cards.removeSubrange(insertedCardsStart..<targetDeck.cards.count)
            targetDeck.lastAssignedCardNumber = originalLastAssigned
            targetDeck.cardCount = originalCardCount
            targetDeck.editedAt = originalEditedAt

            if destinationWasCreatedInThisCall {
                if let folder = targetDeck.folder {
                    folder.deckCount = max(0, folder.deckCount - 1)
                }
                context.delete(targetDeck)
                destinationDeck = nil
            }
            throw error
        }
    }

    private func resolveDestinationDeck(
        for request: DeckCardConversionRequest,
        sourceDeck: DeckModel,
        destinationDeck: inout DeckModel?,
        context: ModelContext
    ) throws -> DeckModel {
        if let destinationDeck {
            return destinationDeck
        }

        switch request.destination {
        case .sameDeck:
            return sourceDeck
        case .newDeck:
            guard let title = request.destinationDeckTitle else {
                throw NSError(
                    domain: "DeckConversion",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "Add a title for the new converted deck."]
                )
            }

            let newDeck = DeckModel(
                title: title,
                icon: sourceDeck.icon,
                colorHex: sourceDeck.colorHex
            )
            newDeck.cardGroupingMode = sourceDeck.cardGroupingMode
            context.insert(newDeck)
            if let folder = sourceDeck.folder {
                newDeck.folder = folder
                folder.deckCount += 1
            }
            destinationDeck = newDeck
            return newDeck
        }
    }

    private func updateConversionProgress(
        totalCount: Int,
        completedCount: Int,
        createdCount: Int,
        skippedCount: Int,
        failedCount: Int,
        statusMessage: String
    ) {
        conversionProgress = DeckCardConversionProgress(
            totalCount: totalCount,
            completedCount: completedCount,
            createdCount: createdCount,
            skippedCount: skippedCount,
            failedCount: failedCount,
            statusMessage: statusMessage
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
