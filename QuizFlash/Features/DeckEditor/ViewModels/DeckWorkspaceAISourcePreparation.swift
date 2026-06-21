//
//  DeckWorkspaceAISourcePreparation.swift
//  QuizFlash
//

import SwiftUI
import SwiftData
import PhotosUI
import PDFKit

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

                aiDidFinishReceivingGeneratedCards = true
                try await aiRevealTask?.value
                try await Task.sleep(nanoseconds: 220_000_000)
                guard !Task.isCancelled else { return }
                completeAIGeneration()
            } catch {
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

                try await consumeGeneratedBatchChunks(
                    from: aiService.generateFlashcardBatchStream(
                        fromSegments: source.textSegments,
                        targetCards: targetCardCount,
                        allocations: allocations,
                        needsOCRCorrection: true,
                        options: options
                    )
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
            aiState = .error("Could not access the PDF file.")
            return
        }

        guard url.startAccessingSecurityScopedResource() else {
            aiState = .error("Could not access the PDF file.")
            return
        }

        let options = effectiveAIGenerationOptions()

        aiGenerationTask = Task { [weak self] in
            guard let self else { return }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                aiState = .extractingText
                let texts = source.textSegments.map(\.text)
                guard DocumentTextExtractor.isUsableExtractedText(texts) else {
                    aiState = .error(localizedTextExtractionFailureMessage)
                    return
                }

                try await consumeGeneratedBatchChunks(
                    from: aiService.generateFlashcardBatchStream(
                        fromSegments: source.textSegments,
                        targetCards: targetCardCount,
                        allocations: allocations,
                        needsOCRCorrection: source.needsOCRCorrection,
                        options: options
                    )
                )
            } catch {
                guard !(error is CancellationError) else { return }
                handleAIGenerationFailure(error)
            }
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

            let texts = await DocumentTextExtractor.extractVisionTexts(from: images)
            await Task.yield()

            guard DocumentTextExtractor.isUsableExtractedText(texts) else {
                clearAISourcePreparation()
                aiState = .error(localizedTextExtractionFailureMessage)
                return
            }

            let source = AIPreparedGenerationSource(
                kind: .photos,
                previewItems: makePhotoPreviewItems(images: images, texts: texts),
                textSegments: makeTextSegments(from: texts, labelPrefix: "Image"),
                images: images,
                pdfURL: nil,
                needsOCRCorrection: true
            )

            prepareSheetState(for: source, pdfAnalysis: nil)
        } catch is CancellationError {
            clearAISourcePreparation()
            return
        } catch {
            clearAISourcePreparation()
            aiState = .error(error.localizedDescription)
        }
    }

    func preparePDFSource(from url: URL) async {
        guard url.startAccessingSecurityScopedResource() else {
            clearAISourcePreparation()
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        var pageTexts = await extractPDFKitPageTexts(from: url)
        var needsOCRCorrection = false
        await Task.yield()

        if !DocumentTextExtractor.isUsableExtractedText(pageTexts) {
            pageTexts = await DocumentTextExtractor.extractVisionTextsFromPDFPages(from: url)
            needsOCRCorrection = true
            await Task.yield()
        }

        guard DocumentTextExtractor.isUsableExtractedText(pageTexts) else {
            clearAISourcePreparation()
            aiState = .error(localizedTextExtractionFailureMessage)
            return
        }

        let thumbnails = await DocumentTextExtractor.renderPDFPreviewThumbnails(from: url)
        await Task.yield()
        let pageCount = max(pageTexts.count, await extractPDFPageCount(from: url))
        let extractedChars = pageTexts.reduce(0) { $0 + $1.count }
        let info = PDFAnalysisInfo(
            quality: await extractPDFQuality(from: url),
            pageCount: pageCount,
            extractedChars: extractedChars
        )

        let source = AIPreparedGenerationSource(
            kind: .pdf,
            previewItems: makePDFPreviewItems(
                pageTexts: pageTexts,
                pageCount: pageCount,
                thumbnails: thumbnails
            ),
            textSegments: makeTextSegments(from: pageTexts, labelPrefix: "Page"),
            images: [],
            pdfURL: url,
            needsOCRCorrection: needsOCRCorrection
        )

        prepareSheetState(for: source, pdfAnalysis: info)
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

    func extractPDFKitPageTexts(from url: URL) async -> [String] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: DocumentTextExtractor.extractPDFKitPages(from: url))
            }
        }
    }

    func extractPDFPageCount(from url: URL) async -> Int {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: DocumentTextExtractor.pdfPageCount(url: url))
            }
        }
    }

    func extractPDFQuality(from url: URL) async -> Double {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: DocumentTextExtractor.pdfKitQuality(for: url))
            }
        }
    }

    func makePhotoPreviewItems(
        images: [UIImage],
        texts: [String]
    ) -> [AIGenerationSourcePreviewItem] {
        images.enumerated().map { index, image in
            let text = texts.indices.contains(index) ? texts[index] : ""
            return AIGenerationSourcePreviewItem(
                index: index + 1,
                title: "Image \(index + 1)",
                characterCount: text.count,
                thumbnail: image.resizedForAI(toMaxDimension: 240)
            )
        }
    }

    func makePDFPreviewItems(
        pageTexts: [String],
        pageCount: Int,
        thumbnails: [UIImage]
    ) -> [AIGenerationSourcePreviewItem] {
        let totalPages = max(pageCount, pageTexts.count)

        return (0 ..< totalPages).map { index in
            let text = pageTexts.indices.contains(index) ? pageTexts[index] : ""
            return AIGenerationSourcePreviewItem(
                index: index + 1,
                title: "Page \(index + 1)",
                characterCount: text.count,
                thumbnail: thumbnails.indices.contains(index) ? thumbnails[index] : nil
            )
        }
    }

    func makeTextSegments(
        from texts: [String],
        labelPrefix: String
    ) -> [AITextSourceSegment] {
        texts.enumerated().map { index, text in
            AITextSourceSegment(
                index: index + 1,
                label: "\(labelPrefix) \(index + 1)",
                text: text
            )
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
        let clampedCount = min(max(count, 5), Self.maximumAICardsPerGeneration)
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
        return max(Self.maximumAICardsPerGeneration - otherCardCount, 1)
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

    func automaticAllocations(
        for characterCounts: [Int],
        totalCards: Int
    ) -> [AISourceRangeAllocation] {
        guard !characterCounts.isEmpty, totalCards > 0 else { return [] }

        let coverageRangeCount = preferredCoverageRangeCount(
            itemCount: characterCounts.count,
            totalCards: totalCards
        )

        let baseRanges = weightedCoverageRanges(
            for: characterCounts,
            groupCount: coverageRangeCount
        )
        guard !baseRanges.isEmpty else { return [] }

        let weights = normalizedWeights(from: characterCounts)
        let rangeWeights = baseRanges.map { range in
            weights[range].reduce(0, +)
        }
        let distributedCardCounts = distributedCardCounts(
            totalCards: totalCards,
            across: rangeWeights
        )

        return zip(baseRanges, distributedCardCounts).compactMap { range, cardCount in
            guard cardCount > 0 else { return nil }
            return AISourceRangeAllocation(
                startIndex: range.lowerBound + 1,
                endIndex: range.upperBound + 1,
                cardCount: cardCount
            )
        }
    }

    func preferredCoverageRangeCount(
        itemCount: Int,
        totalCards: Int
    ) -> Int {
        guard itemCount > 0, totalCards > 0 else { return 0 }

        if itemCount <= 8 {
            return min(itemCount, totalCards)
        }

        let sourceDriven = Int(ceil(Double(itemCount) / 6.0))
        let cardDriven = Int(ceil(Double(totalCards) / 8.0))
        let preferredCount = max(3, max(sourceDriven, cardDriven))

        return min(itemCount, min(totalCards, min(preferredCount, 14)))
    }

    func distributedCardCounts(
        totalCards: Int,
        across weights: [Double]
    ) -> [Int] {
        guard !weights.isEmpty, totalCards > 0 else { return [] }

        var counts = Array(repeating: 1, count: weights.count)
        let remainingCards = totalCards - counts.count
        guard remainingCards > 0 else {
            return counts
        }

        let safeTotalWeight = max(weights.reduce(0, +), .leastNonzeroMagnitude)
        let rawExtras = weights.map { weight in
            (weight / safeTotalWeight) * Double(remainingCards)
        }

        var assignedExtras = 0
        var remainders: [(index: Int, value: Double)] = []

        for (index, rawExtra) in rawExtras.enumerated() {
            let wholeCards = Int(rawExtra.rounded(.down))
            counts[index] += wholeCards
            assignedExtras += wholeCards
            remainders.append((index: index, value: rawExtra - Double(wholeCards)))
        }

        let leftoverCards = remainingCards - assignedExtras
        guard leftoverCards > 0 else {
            return counts
        }

        let orderedIndices = remainders
            .sorted {
                if $0.value == $1.value {
                    return weights[$0.index] > weights[$1.index]
                }
                return $0.value > $1.value
            }
            .map(\.index)

        for offset in 0 ..< leftoverCards {
            counts[orderedIndices[offset % orderedIndices.count]] += 1
        }

        return counts
    }

    func normalizedWeights(from characterCounts: [Int]) -> [Double] {
        let positiveCounts = characterCounts.filter { $0 > 0 }
        let averagePositive = positiveCounts.isEmpty
            ? 1.0
            : Double(positiveCounts.reduce(0, +)) / Double(positiveCounts.count)
        let floorWeight = max(1.0, averagePositive * 0.18)

        return characterCounts.map { count in
            max(Double(count), floorWeight)
        }
    }

    func weightedCoverageRanges(
        for characterCounts: [Int],
        groupCount: Int
    ) -> [ClosedRange<Int>] {
        guard !characterCounts.isEmpty, groupCount > 0 else { return [] }

        let cappedGroupCount = min(groupCount, characterCounts.count)
        let weights = normalizedWeights(from: characterCounts)

        if cappedGroupCount == characterCounts.count {
            return characterCounts.indices.map { $0 ... $0 }
        }

        var ranges: [ClosedRange<Int>] = []
        var startIndex = 0

        for groupIndex in 0 ..< (cappedGroupCount - 1) {
            let groupsRemaining = cappedGroupCount - groupIndex
            let remainingWeight = weights[startIndex...].reduce(0, +)
            let targetWeight = remainingWeight / Double(groupsRemaining)
            let latestEndIndex = characterCounts.count - groupsRemaining

            var endIndex = startIndex
            var accumulatedWeight = 0.0

            while endIndex < latestEndIndex {
                accumulatedWeight += weights[endIndex]
                if accumulatedWeight >= targetWeight {
                    break
                }
                endIndex += 1
            }

            ranges.append(startIndex ... endIndex)
            startIndex = endIndex + 1
        }

        ranges.append(startIndex ... (characterCounts.count - 1))
        return ranges
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
