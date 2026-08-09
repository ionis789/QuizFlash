//
//  DeckWorkspaceAISourcePreparation.swift
//  QuizFlash
//

import SwiftUI
import SwiftData
import PhotosUI

extension DeckWorkspaceViewModel {
    // MARK: - Workspace Seeding

    /// Re-seeds the editor so the Create tab can behave like a normal deck
    /// editor when the flow is restored from workspace routing.
    func seedEditorState(
        editingDeckID: PersistentIdentifier?,
        title: String,
        selectedFolder: FolderModel?,
        draftCards: [DraftCard],
        resetsBaseline: Bool
    ) {
        workspaceEditingDeckID = editingDeckID
        isDetachedFromInitialDeck = editingDeckID == nil
        deckTitle = title
        self.selectedFolder = selectedFolder
        self.draftCards = draftCards
        nextDraftCardNumber = max(
            editingDeckID == deckToEdit?.persistentModelID
                ? (deckToEdit?.lastAssignedCardNumber ?? 0)
                : 0,
            draftCards.map(\.cardNumber).max() ?? 0
        )

        if resetsBaseline {
            replaceInitialState(
                title: title,
                selectedFolder: selectedFolder,
                draftCards: draftCards
            )
            return
        }

        if baseDraftCardIDs.isEmpty && sessionDraftCardIDs.isEmpty && aiSessionDraftCardIDs.isEmpty {
            replaceDraftSessionBaseline(with: draftCards)
        }
    }

    /// Merges the latest persisted deck state into the in-memory draft editor
    /// without clobbering unsaved local draft-only cards or local edits.
    func mergePersistedDeckState(
        _ deck: DeckModel,
        markNewCardsAsAISession: Bool = false
    ) {
        workspaceEditingDeckID = deck.persistentModelID
        isDetachedFromInitialDeck = false

        let localCardsByOriginalID = Dictionary(
            uniqueKeysWithValues: draftCards.compactMap { draft in
                draft.originalCardID.map { ($0, draft) }
            }
        )

        let localDraftOnlyCards = draftCards.filter { $0.originalCardID == nil }
        var appendedPersistedDraftIDs: [UUID] = []

        let mergedPersistedCards = deck.cards
            .sorted {
                if $0.cardNumber == $1.cardNumber {
                    return $0.createdAt < $1.createdAt
                }
                return $0.cardNumber < $1.cardNumber
            }
            .map { persistedCard in
                if let localDraft = localCardsByOriginalID[persistedCard.persistentModelID] {
                    return localDraft
                }

                let persistedDraft = Self.persistedDraftCard(from: persistedCard)
                appendedPersistedDraftIDs.append(persistedDraft.id)
                return persistedDraft
            }

        deckTitle = deckTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? deck.title : deckTitle
        if self.selectedFolder == nil {
            self.selectedFolder = deck.folder
        }
        draftCards = mergedPersistedCards + localDraftOnlyCards
        nextDraftCardNumber = max(
            nextDraftCardNumber,
            deck.lastAssignedCardNumber,
            draftCards.map(\.cardNumber).max() ?? 0
        )

        if markNewCardsAsAISession {
            appendedPersistedDraftIDs.forEach { registerSessionDraftID($0, marksAsAI: true) }
        } else {
            baseDraftCardIDs.formUnion(appendedPersistedDraftIDs)
        }
    }

    // MARK: - PDF Selection and Auto-Analysis

    /// Called immediately after the user selects a PDF.
    ///
    /// Runs a PDFKit quality check in the background and populates `pdfAnalysis`
    /// before the generation sheet becomes visible — no perceptible delay for the user.
    func pdfWasSelected(_ url: URL) {
        PDFImportDebugStore.record(
            "pdfWasSelected",
            details: ["url": url.debugDescription]
        )
        preparedAISource = nil
        pdfAnalysis = nil
        beginAISourcePreparation(.pdf)
        scheduleAIGenerationSheetPresentation()
        aiSourcePreparationTask?.cancel()
        aiSourcePreparationTask = nil
        pendingAISourceSelection = .pdf(url)
    }

    // MARK: - AI Generation

    /// Starts the appropriate AI generation pipeline based on the currently
    /// selected input source (photos or PDF).
    func startAIGeneration() {
        guard let source = preparedAISource else { return }
        let allocations = resolvedAISourceAllocations
        guard let aiService = makeAIService() else { return }

        startAIGeneration(
            from: source,
            allocations: allocations,
            aiService: aiService,
            shouldResetProgress: true
        )
    }

    /// Streams a local mock payload through the same incremental UI path used
    /// by the real AI generator so animation work can be tested deterministically.
    func startMockAIGeneration() {
        let mockCards = Self.mockAICards(for: aiGenerationOptions.cardType)
        guard !mockCards.isEmpty else { return }

        requestedCardCount = mockCards.count
        preparedAISource = nil
        manualAISourceAllocations = []
        pdfAnalysis = nil
        aiSheetDestination = nil
        showAIPickerOptions = false

        beginAIGenerationSession(targetCardCount: mockCards.count)
        aiState = .generatingCards(progress: 0, foundCount: 0)
        resetAIGenerationRevealPipeline()
        aiCardBatchStreamIsActive = true
        aiRevealTask = Task { [weak self] in
            guard let self else { return }
            try await self.drainGeneratedCardsContinuously()
        }

        let cardsPerBatch = aiGenerationOptions.resolvedCardsPerBatch(for: mockCards.count)
        let batches = stride(from: 0, to: mockCards.count, by: cardsPerBatch).map { index in
            Array(mockCards[index ..< min(index + cardsPerBatch, mockCards.count)])
        }

        aiGenerationTask = Task { [weak self] in
            guard let self else { return }

            do {
                for batch in batches {
                    try await Task.sleep(nanoseconds: 850_000_000)
                    guard !Task.isCancelled else { return }
                    pendingAIGeneratedCards.append(contentsOf: batch)
                    await Task.yield()
                }

                aiCardBatchStreamIsActive = false
                aiDidFinishReceivingGeneratedCards = true
                try await aiRevealTask?.value
                try await Task.sleep(nanoseconds: 220_000_000)
                guard !Task.isCancelled else { return }
                await completeAIGeneration()
            } catch {
                aiCardBatchStreamIsActive = false
                guard !(error is CancellationError) else { return }
                handleAIGenerationFailure(error)
            }
        }
    }

    // MARK: - Process Photos
    //
    // Text-only — On-device Vision OCR extracts text locally; image-to-AI is
    // intentionally not used by this flow.

    func processPhotosForAI(
        _ source: AIPreparedGenerationSource,
        allocations: [AISourceRangeAllocation],
        targetCardCount: Int,
        aiService: AIFlashcardService
    ) {
        aiState = .extractingText
        let options = effectiveAIGenerationOptions()

        aiGenerationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let texts = source.textSegments.map(\.text)
                guard DocumentTextExtractor.isUsableExtractedText(texts) else {
                    aiState = .error(localizedTextExtractionFailureMessage)
                    return
                }
                try await executeTracedSourceGeneration(
                    source: source,
                    allocations: allocations,
                    targetCardCount: targetCardCount,
                    options: options,
                    aiService: aiService
                )
            } catch {
                guard !(error is CancellationError) else { return }
                handleAIGenerationFailure(error)
            }
        }
    }

    // MARK: - Process PDF
    //
    // Text-only — Prepared PDF text comes from PDFKit first, then local OCR.

    func processPDFForAI(
        _ source: AIPreparedGenerationSource,
        allocations: [AISourceRangeAllocation],
        targetCardCount: Int,
        aiService: AIFlashcardService
    ) {
        guard let url = source.pdfURL else {
            PDFImportDebugStore.record("processPDFForAI missing url")
            aiState = .error("Could not access the PDF file.")
            return
        }

        let didAccess = url.startAccessingSecurityScopedResource()
        PDFImportDebugStore.record(
            "processPDFForAI start",
            details: [
                "didAccess": String(didAccess),
                "url": url.path,
                "segments": String(source.textSegments.count)
            ]
        )

        let options = effectiveAIGenerationOptions()

        aiGenerationTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
                PDFImportDebugStore.record(
                    "processPDFForAI stopAccess",
                    details: ["didAccess": String(didAccess)]
                )
            }

            do {
                aiState = .extractingText
                let texts = source.textSegments.map(\.text)
                guard DocumentTextExtractor.isUsableExtractedText(texts) else {
                    PDFImportDebugStore.record("processPDFForAI unusable text")
                    aiState = .error(localizedTextExtractionFailureMessage)
                    return
                }
                try await executeTracedSourceGeneration(
                    source: source,
                    allocations: allocations,
                    targetCardCount: targetCardCount,
                    options: options,
                    aiService: aiService
                )
            } catch {
                guard !(error is CancellationError) else { return }
                handleAIGenerationFailure(error)
            }
        }
    }

    /// Consumes the single production source-generation pipeline.
    func executeTracedSourceGeneration(
        source: AIPreparedGenerationSource,
        allocations: [AISourceRangeAllocation],
        targetCardCount: Int,
        options: AIGenerationOptions,
        aiService: AIFlashcardService
    ) async throws {
        let pipeline = AISourceGenerationPipeline(service: aiService)
        let request = AISourceGenerationPipelineRequest(
            segments: source.textSegments,
            allocations: allocations,
            targetCardCount: targetCardCount,
            needsOCRCorrection: source.needsOCRCorrection,
            sourceKind: source.isPDF ? "pdf" : "photos_ocr",
            options: options,
            reusableBlueprint: activeAISourceBlueprint,
            remainingObjectiveIDs: remainingAIBlueprintObjectiveIDs,
            coveredPrompts: existingAISessionPromptPreviews()
        )
        try await consumeSourceGenerationEvents(from: pipeline.events(for: request))
    }

    func existingAISessionPromptPreviews() -> [String] {
        draftCards.compactMap { draft in
            guard aiSessionDraftCardIDs.contains(draft.id) else { return nil }
            let prompt = draft.content.previewCache.front
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return prompt.isEmpty ? nil : prompt
        }
    }

    // MARK: - Source Preparation

    func preparePhotoSource(from items: [PhotosPickerItem]) async {
        do {
            var images: [UIImage] = []

            for item in items {
                try Task.checkCancellation()
                if let data = try await item.loadTransferable(type: Data.self),
                   let image = await decodePreparedPhoto(from: data) {
                    images.append(image)
                }
                await Task.yield()
            }

            guard !images.isEmpty else { return }

            let source = try await AISourcePreparationService.preparePhotos(images)

            prepareSheetState(for: source, pdfAnalysis: nil)
        } catch is CancellationError {
            clearAISourcePreparation()
            return
        } catch is AISourcePreparationError {
            clearAISourcePreparation()
            aiState = .error(localizedTextExtractionFailureMessage)
        } catch {
            clearAISourcePreparation()
            aiState = .error(error.localizedDescription)
        }
    }

    func preparePDFSource(from url: URL) async {
        PDFImportDebugStore.record(
            "preparePDFSource start",
            details: ["url": url.debugDescription]
        )
        let localURL: URL
        do {
            localURL = try await AIGenerationSessionStore.shared.importPDFToDisk(from: url)
        } catch {
            clearAISourcePreparation()
            PDFImportDebugStore.record(
                "preparePDFSource import failed",
                details: ["error": error.localizedDescription]
            )
            aiState = .error("Could not access the PDF file.")
            return
        }

        do {
            let prepared = try await AISourcePreparationService.preparePDF(from: localURL)
            prepareSheetState(for: prepared.source, pdfAnalysis: prepared.analysis)
            PDFImportDebugStore.record(
                "preparePDFSource prepared",
                details: [
                    "pageCount": String(prepared.analysis.pageCount),
                    "chars": String(prepared.analysis.extractedChars),
                    "needsOCRCorrection": String(prepared.source.needsOCRCorrection)
                ]
            )
        } catch is CancellationError {
            clearAISourcePreparation()
        } catch {
            clearAISourcePreparation()
            PDFImportDebugStore.record(
                "preparePDFSource failed",
                details: ["error": error.localizedDescription]
            )
            aiState = .error(localizedTextExtractionFailureMessage)
        }
    }

    func prepareSheetState(
        for source: AIPreparedGenerationSource,
        pdfAnalysis: PDFAnalysisInfo?
    ) {
        clearAISourcePreparation()
        self.pdfAnalysis = pdfAnalysis
        preparedAISource = source
        if source.itemCount <= 1 {
            aiGenerationOptions.sourceDistributionMode = .auto
        }
        manualAISourceAllocations = defaultManualAllocations(
            itemCount: source.itemCount,
            requestedCards: requestedCardCount
        )
        presentAIGenerationSheet()
    }

    var localizedTextExtractionFailureMessage: String {
        AppLocalization.string(
            "Could not extract text from this source. Try another source.",
            locale: AppPreferences.persistedResolvedLocale
        )
    }

    func decodePreparedPhoto(from data: Data) async -> UIImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let image = autoreleasepool {
                    UIImage(data: data)?.resizedForAI(toMaxDimension: 1024)
                }
                continuation.resume(returning: image)
            }
        }
    }

    func fullQualityPreviewImage(
        for item: AIGenerationSourcePreviewItem
    ) async -> UIImage? {
        guard let source = preparedAISource else { return item.thumbnail }

        if source.isPDF {
            guard let url = source.pdfURL else { return item.thumbnail }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            return await DocumentTextExtractor.renderPDFPage(
                from: url,
                pageIndex: item.index - 1,
                dpi: 200
            ) ?? item.thumbnail
        }

        let sourceIndex = item.index - 1
        guard source.images.indices.contains(sourceIndex) else {
            return item.thumbnail
        }
        return source.images[sourceIndex]
    }

    // MARK: - Source Allocation Controls

    /// Updates the auto-generation target card count selected in the sheet.
    func setRequestedCardCount(_ count: Int) {
        let clampedCount = min(max(count, 5), maximumAICardsPerGeneration)
        guard requestedCardCount != clampedCount else { return }

        requestedCardCount = clampedCount
    }

    func setSourceDistributionMode(_ mode: AISourceDistributionMode) {
        if mode == .manual, let source = preparedAISource, source.itemCount <= 1 {
            aiGenerationOptions.sourceDistributionMode = .auto
            return
        }

        aiGenerationOptions.sourceDistributionMode = mode

        guard mode == .manual, let source = preparedAISource else { return }
        if manualAISourceAllocations.isEmpty {
            manualAISourceAllocations = defaultManualAllocations(
                itemCount: source.itemCount,
                requestedCards: requestedCardCount
            )
        }
    }

    func addManualAllocation() {
        guard let source = preparedAISource else { return }
        guard let nextStart = firstAvailableManualSourceIndex(itemCount: source.itemCount) else { return }

        manualAISourceAllocations.append(
            AISourceRangeAllocation(
                startIndex: nextStart,
                endIndex: nextStart,
                cardCount: 1
            )
        )
    }

    func removeManualAllocation(id: UUID) {
        manualAISourceAllocations.removeAll { $0.id == id }
    }

    var canAddManualAllocation: Bool {
        guard let source = preparedAISource else { return false }
        return firstAvailableManualSourceIndex(itemCount: source.itemCount) != nil
    }

    func maximumManualEndIndex(for allocation: AISourceRangeAllocation) -> Int {
        preparedAISource?.itemCount ?? allocation.endIndex
    }

    func updateManualAllocation(
        id: UUID,
        startIndex: Int? = nil,
        endIndex: Int? = nil,
        cardCount: Int? = nil
    ) {
        guard let source = preparedAISource,
              let index = manualAISourceAllocations.firstIndex(where: { $0.id == id }) else { return }

        var allocation = manualAISourceAllocations[index]

        if let startIndex {
            allocation.startIndex = min(max(startIndex, 1), source.itemCount)
        }

        if let endIndex {
            allocation.endIndex = min(max(endIndex, 1), source.itemCount)
        }

        if allocation.endIndex < allocation.startIndex {
            allocation.endIndex = allocation.startIndex
        }

        allocation.endIndex = min(allocation.endIndex, source.itemCount)

        if let cardCount {
            allocation.cardCount = min(max(cardCount, 1), maximumManualCardCount(for: allocation.id))
        }

        manualAISourceAllocations[index] = allocation
        normalizeManualAllocationChain(itemCount: source.itemCount)
    }

    func defaultManualAllocations(
        itemCount: Int,
        requestedCards: Int
    ) -> [AISourceRangeAllocation] {
        guard itemCount > 0, requestedCards > 0 else { return [] }
        return [
            AISourceRangeAllocation(
                startIndex: 1,
                endIndex: itemCount,
                cardCount: requestedCards
            ),
        ]
    }

    func maximumManualCardCount(for allocation: AISourceRangeAllocation) -> Int {
        maximumManualCardCount(for: allocation.id)
    }

    private func maximumManualCardCount(for allocationID: UUID) -> Int {
        let otherCardCount = manualAISourceAllocations
            .filter { $0.id != allocationID }
            .reduce(0) { $0 + max($1.cardCount, 0) }
        return max(maximumAICardsPerGeneration - otherCardCount, 1)
    }

    func clampManualAllocationsToCurrentLimit() {
        guard !manualAISourceAllocations.isEmpty else { return }

        var remaining = maximumAICardsPerGeneration
        manualAISourceAllocations = manualAISourceAllocations.map { allocation in
            var clamped = allocation
            let nextCount = min(max(clamped.cardCount, 1), max(remaining, 1))
            clamped.cardCount = nextCount
            remaining -= nextCount
            return clamped
        }
    }

    func normalizedManualAllocations(for itemCount: Int) -> [AISourceRangeAllocation] {
        guard itemCount > 0 else { return [] }

        return manualAISourceAllocations
            .map { allocation in
                let start = min(max(allocation.startIndex, 1), itemCount)
                let end = min(max(allocation.endIndex, start), itemCount)

                return AISourceRangeAllocation(
                    id: allocation.id,
                    startIndex: start,
                    endIndex: end,
                    cardCount: max(allocation.cardCount, 1)
                )
            }
            .sorted {
                if $0.startIndex == $1.startIndex {
                    return $0.endIndex < $1.endIndex
                }
                return $0.startIndex < $1.startIndex
            }
    }

    private func normalizeManualAllocationChain(itemCount: Int) {
        guard itemCount > 0, !manualAISourceAllocations.isEmpty else { return }

        var orderedAllocations = manualAISourceAllocations.sorted {
            if $0.startIndex == $1.startIndex {
                return $0.endIndex < $1.endIndex
            }
            return $0.startIndex < $1.startIndex
        }

        var nextStart = 1
        for index in orderedAllocations.indices {
            var allocation = orderedAllocations[index]
            let safeStart = min(max(nextStart, 1), itemCount)
            let safeEnd = min(max(allocation.endIndex, safeStart), itemCount)

            allocation.startIndex = safeStart
            allocation.endIndex = safeEnd
            orderedAllocations[index] = allocation
            nextStart = safeEnd + 1

            guard nextStart <= itemCount else {
                orderedAllocations = Array(orderedAllocations.prefix(index + 1))
                break
            }
        }

        manualAISourceAllocations = orderedAllocations
    }

    private func firstAvailableManualSourceIndex(itemCount: Int) -> Int? {
        guard itemCount > 0 else { return nil }

        var occupied = Set<Int>()
        for allocation in manualAISourceAllocations {
            let start = min(max(allocation.startIndex, 1), itemCount)
            let end = min(max(allocation.endIndex, start), itemCount)
            for index in start ... end {
                occupied.insert(index)
            }
        }

        return (1 ... itemCount).first { !occupied.contains($0) }
    }
    func hasOverlappingAllocations(_ allocations: [AISourceRangeAllocation]) -> Bool {
        guard allocations.count > 1 else { return false }

        for pairIndex in 1 ..< allocations.count {
            let previous = allocations[pairIndex - 1]
            let current = allocations[pairIndex]
            if current.startIndex <= previous.endIndex {
                return true
            }
        }

        return false
    }

    func mergeAllocationsWithSameRange(
        _ allocations: [AISourceRangeAllocation]
    ) -> [AISourceRangeAllocation] {
        guard !allocations.isEmpty else { return [] }

        var merged: [AISourceRangeAllocation] = []

        for allocation in allocations {
            if let last = merged.last,
               last.startIndex == allocation.startIndex,
               last.endIndex == allocation.endIndex {
                merged[merged.count - 1] = AISourceRangeAllocation(
                    id: last.id,
                    startIndex: last.startIndex,
                    endIndex: last.endIndex,
                    cardCount: last.cardCount + allocation.cardCount
                )
            } else {
                merged.append(allocation)
            }
        }

        return merged
    }
}
