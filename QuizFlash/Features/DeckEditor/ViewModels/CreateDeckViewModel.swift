//
//  CreateDeckViewModel.swift
//  QuizFlash
//
//  Manages all state and business logic for the deck creation and editing flow.
//

import SwiftUI
import SwiftData
import PhotosUI
import PDFKit

/// The destination currently presented in the AI configuration sheet.
enum AIGenerationSheetDestination: String, Identifiable {
    case prepareGeneration

    var id: String { rawValue }
}

// MARK: - AI Source Preparation

/// One previewable source item shown inside the AI generation sheet.
struct AIGenerationSourcePreviewItem: Identifiable {
    let id = UUID()
    let index: Int
    let title: String
    let characterCount: Int
    let thumbnail: UIImage?
}

/// Fully prepared source payload reused by the generation sheet and the final
/// AI pipeline so selection analysis is not recomputed unnecessarily.
struct AIPreparedGenerationSource {
    enum Kind {
        case photos
        case pdf
    }

    let kind: Kind
    let previewItems: [AIGenerationSourcePreviewItem]
    let textSegments: [AITextSourceSegment]
    let images: [UIImage]
    let pdfURL: URL?

    var isPDF: Bool { kind == .pdf }
    var itemCount: Int { previewItems.count }
    var totalCharacterCount: Int { previewItems.reduce(0) { $0 + $1.characterCount } }
    var itemLabels: [String] { previewItems.map(\.title) }
}

private struct DraftCardChangeSnapshot: Equatable {
    let originalCardID: PersistentIdentifier?
    let frontZone: ZoneModel
    let backZone: ZoneModel
    let frontType: CardContentType
    let backType: CardContentType

    init(card: DraftCard) {
        originalCardID = card.originalCardID
        frontZone = card.frontZone
        backZone = card.backZone
        frontType = card.frontType
        backType = card.backType
    }
}

private struct CreateDeckStateSnapshot: Equatable {
    let title: String
    let selectedFolderID: PersistentIdentifier?
    let draftCards: [DraftCardChangeSnapshot]
}

// MARK: - Create Deck View Model

/// The ViewModel for `CreateDeckView`, managing draft card state, AI generation,
/// and deck persistence for both new deck creation and existing deck editing.
@Observable
@MainActor
final class CreateDeckViewModel {

    // MARK: - AI State
    var aiState: AIGenerationState = .idle

    // MARK: - AI Picker UI
    var showAIPickerOptions = false
    var showAIPhotoPicker = false
    var showAIPDFPicker = false
    var aiSheetDestination: AIGenerationSheetDestination? = nil
    var showAICancelDialog = false

    var isGenerating: Bool { aiState != .idle || hasPausedAIGeneration }
    var selectedFolder: FolderModel? = nil

    // MARK: - PDF Analysis

    /// Pre-populated automatically when the user selects a PDF, before tapping Generate.
    var pdfAnalysis: PDFAnalysisInfo? = nil

    // MARK: - Generation Settings
    var requestedCardCount: Int = 15
    var extractionMode: ExtractionMode = .fast
    var aiGenerationOptions = AIGenerationOptions()
    var preparedAISource: AIPreparedGenerationSource? = nil
    var manualAISourceAllocations: [AISourceRangeAllocation] = []
    var aiGeneratedCardCount: Int = 0
    var aiTargetCardCount: Int = 0
    var aiGenerationBaseCardCount: Int = 0

    var hasPendingAISource: Bool {
        preparedAISource != nil
    }

    var hasGeneratedCardsInCurrentAISession: Bool {
        aiGeneratedCardCount > 0
    }

    private var hasIncompleteAIGenerationSession: Bool {
        if isAIGenerationPaused || isAIGenerationPausedForBackground {
            return true
        }

        guard preparedAISource != nil else { return false }
        guard aiGenerationTask == nil else { return false }
        guard aiTargetCardCount > 0 else { return false }
        guard aiGeneratedCardCount < aiTargetCardCount else { return false }

        if case .idle = aiState {
            return false
        }
        if case .error = aiState { return false }

        return true
    }

    var hasPausedAIGeneration: Bool {
        let hasRemainingTarget = aiTargetCardCount > 0 || !remainingAIAllocations.isEmpty
        return (isAIGenerationPaused || isAIGenerationPausedForBackground)
            && aiGenerationTask == nil
            && hasRemainingTarget
    }

    var pausedRemainingCardCount: Int {
        let remainingFromAllocations = targetCardCount(for: remainingAIAllocations.filter { $0.cardCount > 0 })
        let remainingFromProgress = max(aiTargetCardCount - aiGeneratedCardCount, 0)
        return max(remainingFromAllocations, remainingFromProgress)
    }

    var isPreparedSourcePDF: Bool {
        preparedAISource?.isPDF == true
    }

    var canConfirmAIGeneration: Bool {
        guard preparedAISource != nil else { return false }

        switch aiGenerationOptions.sourceDistributionMode {
        case .auto:
            return requestedCardCount > 0
        case .manual:
            return manualAllocationValidationMessage == nil && manualAllocatedCardCount > 0
        }
    }

    var manualAllocationValidationMessage: String? {
        guard let source = preparedAISource else { return "No source selected." }
        let allocations = normalizedManualAllocations(for: source.itemCount)
        guard !allocations.isEmpty else { return "Add at least one range." }

        if hasOverlappingAllocations(allocations) {
            return "Manual ranges overlap. Make each range distinct."
        }

        return nil
    }

    var manualAllocatedCardCount: Int {
        guard let source = preparedAISource else { return 0 }
        return normalizedManualAllocations(for: source.itemCount)
            .reduce(0) { $0 + $1.cardCount }
    }

    var resolvedAISourceAllocations: [AISourceRangeAllocation] {
        guard let source = preparedAISource else { return [] }

        switch aiGenerationOptions.sourceDistributionMode {
        case .auto:
            return automaticAllocations(
                for: source.previewItems.map(\.characterCount),
                totalCards: requestedCardCount
            )
        case .manual:
            return normalizedManualAllocations(for: source.itemCount)
        }
    }

    var summarizedAISourceAllocations: [AISourceRangeAllocation] {
        mergeAllocationsWithSameRange(resolvedAISourceAllocations)
    }

    // MARK: - Photos
    var selectedAIPhotos: [PhotosPickerItem] = [] {
        didSet {
            guard !selectedAIPhotos.isEmpty else { return }
            showAIPickerOptions = false
            let items = selectedAIPhotos
            selectedAIPhotos = []
            pdfAnalysis = nil
            aiSourcePreparationTask?.cancel()
            aiSourcePreparationTask = Task { [weak self] in
                await self?.preparePhotoSource(from: items)
            }
        }
    }

    // MARK: - Services

    @ObservationIgnored private let aiProviderStore: AIProviderStore
    @ObservationIgnored private let aiBackgroundCoordinator: AIGenerationBackgroundCoordinator
    @ObservationIgnored private var aiGenerationTask: Task<Void, Never>?
    @ObservationIgnored private var aiSourcePreparationTask: Task<Void, Never>?
    @ObservationIgnored private var aiRevealTask: Task<Void, Error>?
    @ObservationIgnored private var aiDeckTitleTask: Task<Void, Never>?
    @ObservationIgnored private var aiSessionPersistenceTask: Task<Void, Never>?

    @ObservationIgnored private var pendingAIDeckTitleRequestID: UUID?
    @ObservationIgnored private var pendingAIGeneratedCards: [AIFlashcard] = []
    @ObservationIgnored private var aiDidFinishReceivingGeneratedCards = false
    @ObservationIgnored private var clearsPendingAISourceOnSheetDismiss = false
    @ObservationIgnored private var aiGenerationSessionID: UUID?
    private var remainingAIAllocations: [AISourceRangeAllocation] = []
    private var aiRevealedGeneratedCardIDs: Set<UUID> = []
    private var isAIGenerationPausedForBackground = false
    private var isAIGenerationPaused = false
    private var isManualPauseInProgress = false

    // MARK: - Deck / Cards State
    var deckTitle: String = ""
    var draftCards: [DraftCard] = []
    var cardToEdit: DraftCard?
    var isCreatingNewCard = false
    var showSuccessOverlay = false
    let deckToEdit: DeckModel?
    private let initialSnapshot: CreateDeckStateSnapshot

    var hasUnsavedChanges: Bool {
        currentSnapshot != initialSnapshot
    }

    convenience init(deckToEdit: DeckModel? = nil) {
        self.init(
            deckToEdit: deckToEdit,
            aiProviderStore: AIProviderStore.shared,
            aiBackgroundCoordinator: .shared
        )
    }

    init(
        deckToEdit: DeckModel?,
        aiProviderStore: AIProviderStore,
        aiBackgroundCoordinator: AIGenerationBackgroundCoordinator
    ) {
        self.aiProviderStore = aiProviderStore
        self.aiBackgroundCoordinator = aiBackgroundCoordinator
        self.deckToEdit = deckToEdit
        let initialTitle: String
        let initialFolder: FolderModel?
        let initialDrafts: [DraftCard]

        if let deck = deckToEdit {
            deckTitle = deck.title
            selectedFolder = deck.folder
            draftCards = deck.cards.map { DraftCard.from($0) }
            initialTitle = deck.title
            initialFolder = deck.folder
            initialDrafts = deck.cards.map { DraftCard.from($0) }
        } else {
            initialTitle = ""
            initialFolder = nil
            initialDrafts = []
        }

        initialSnapshot = CreateDeckStateSnapshot(
            title: initialTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            selectedFolderID: initialFolder?.persistentModelID,
            draftCards: initialDrafts.map(DraftCardChangeSnapshot.init)
        )
        
        Task { [weak self] in
            await self?.checkForPausedSession()
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
        aiSourcePreparationTask?.cancel()

        aiSourcePreparationTask = Task { [weak self] in
            await self?.preparePDFSource(from: url)
        }
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
        let mockCards = Self.mockAIFlashcards
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
            Array(mockCards[index..<min(index + cardsPerBatch, mockCards.count)])
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
    // Fast    — On-device Vision OCR (free, fast)
    // Quality — GPT Vision, all images in a single request (accurate, understands diagrams)

    private func processPhotosForAI(
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
                switch extractionMode {
                case .fast:
                    let texts = source.textSegments.map(\.text)
                    guard DocumentTextExtractor.isUsableOCRText(texts) else {
                        try await consumeGeneratedBatchChunks(
                            from: aiService.generateFlashcardBatchStream(
                                from: source.images,
                                itemLabels: source.itemLabels,
                                targetCards: targetCardCount,
                                allocations: allocations,
                                options: options
                            )
                        )
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

                case .quality:
                    try await consumeGeneratedBatchChunks(
                        from: aiService.generateFlashcardBatchStream(
                            from: source.images,
                            itemLabels: source.itemLabels,
                            targetCards: targetCardCount,
                            allocations: allocations,
                            options: options
                        )
                    )
                }
            } catch {
                guard !(error is CancellationError) else { return }
                handleAIGenerationFailure(error)
            }
        }
    }

    // MARK: - Process PDF
    //
    // Fast    — Automatic pipeline: PDFKit → on-device Vision OCR (free)
    // Quality — Render pages as images → all in a single GPT Vision request

    private func processPDFForAI(
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
                switch extractionMode {
                case .fast:
                    aiState = .extractingText
                    let directTextIsReliable = (pdfAnalysis?.isGoodForFast ?? false)
                        && source.textSegments.contains(where: { !$0.text.isEmpty })

                    if directTextIsReliable {
                        try await consumeGeneratedBatchChunks(
                            from: aiService.generateFlashcardBatchStream(
                                fromSegments: source.textSegments,
                                targetCards: targetCardCount,
                                allocations: allocations,
                                needsOCRCorrection: false,
                                options: options
                            )
                        )
                        return
                    }

                    let images = await DocumentTextExtractor.renderPDFPages(from: url)
                    guard !images.isEmpty else { throw AIServiceError.parsingFailed }

                    let pageTexts = await DocumentTextExtractor.extractVisionTexts(from: images)
                    if DocumentTextExtractor.isUsableOCRText(pageTexts) {
                        let ocrSegments = makeTextSegments(from: pageTexts, labelPrefix: "Page")
                        try await consumeGeneratedBatchChunks(
                            from: aiService.generateFlashcardBatchStream(
                                fromSegments: ocrSegments,
                                targetCards: targetCardCount,
                                allocations: allocations,
                                needsOCRCorrection: true,
                                options: options
                            )
                        )
                        return
                    }

                    try await consumeGeneratedBatchChunks(
                        from: aiService.generateFlashcardBatchStream(
                            from: images,
                            itemLabels: source.itemLabels,
                            targetCards: targetCardCount,
                            allocations: allocations,
                            options: options
                        )
                    )

                case .quality:
                    aiState = .extractingText
                    let images = await DocumentTextExtractor.renderPDFPages(from: url, dpi: 150)
                    guard !images.isEmpty else { throw AIServiceError.parsingFailed }

                    try await consumeGeneratedBatchChunks(
                        from: aiService.generateFlashcardBatchStream(
                            from: images,
                            itemLabels: source.itemLabels,
                            targetCards: targetCardCount,
                            allocations: allocations,
                            options: options
                        )
                    )
                }
            } catch {
                guard !(error is CancellationError) else { return }
                handleAIGenerationFailure(error)
            }
        }
    }

    // MARK: - Source Preparation

    private func preparePhotoSource(from items: [PhotosPickerItem]) async {
        do {
            var images: [UIImage] = []

            for item in items {
                try Task.checkCancellation()
                if let data = try await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    images.append(image.resizedForAI(toMaxDimension: 1024))
                }
            }

            guard !images.isEmpty else { return }

            let texts = await DocumentTextExtractor.extractVisionTexts(from: images)
            let source = AIPreparedGenerationSource(
                kind: .photos,
                previewItems: makePhotoPreviewItems(images: images, texts: texts),
                textSegments: makeTextSegments(from: texts, labelPrefix: "Image"),
                images: images,
                pdfURL: nil
            )

            prepareSheetState(for: source, pdfAnalysis: nil)
        } catch is CancellationError {
            return
        } catch {
            aiState = .error(error.localizedDescription)
        }
    }

    private func preparePDFSource(from url: URL) async {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        let pageTexts = DocumentTextExtractor.extractPDFKitPages(from: url)
        let thumbnails = await DocumentTextExtractor.renderPDFPreviewThumbnails(from: url)
        let pageCount = max(pageTexts.count, await DocumentTextExtractor.pdfPageCount(url: url))
        let extractedChars = pageTexts.reduce(0) { $0 + $1.count }
        let info = PDFAnalysisInfo(
            quality: DocumentTextExtractor.pdfKitQuality(for: url),
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
            pdfURL: url
        )

        prepareSheetState(for: source, pdfAnalysis: info)
    }

    private func prepareSheetState(
        for source: AIPreparedGenerationSource,
        pdfAnalysis: PDFAnalysisInfo?
    ) {
        self.pdfAnalysis = pdfAnalysis
        preparedAISource = source
        manualAISourceAllocations = defaultManualAllocations(
            itemCount: source.itemCount,
            requestedCards: requestedCardCount
        )
        presentAIGenerationSheet()
    }

    private func makePhotoPreviewItems(
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

    private func makePDFPreviewItems(
        pageTexts: [String],
        pageCount: Int,
        thumbnails: [UIImage]
    ) -> [AIGenerationSourcePreviewItem] {
        let totalPages = max(pageCount, pageTexts.count)

        return (0..<totalPages).map { index in
            let text = pageTexts.indices.contains(index) ? pageTexts[index] : ""
            return AIGenerationSourcePreviewItem(
                index: index + 1,
                title: "Page \(index + 1)",
                characterCount: text.count,
                thumbnail: thumbnails.indices.contains(index) ? thumbnails[index] : nil
            )
        }
    }

    private func makeTextSegments(
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

    // MARK: - Source Allocation Controls

    /// Updates the auto-generation target card count selected in the sheet.
    func setRequestedCardCount(_ count: Int) {
        let clampedCount = min(max(count, 1), 100)
        guard requestedCardCount != clampedCount else { return }

        requestedCardCount = clampedCount
    }

    func setSourceDistributionMode(_ mode: AISourceDistributionMode) {
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

        let nextStart = min(
            (manualAISourceAllocations.map(\.endIndex).max() ?? 0) + 1,
            max(source.itemCount, 1)
        )

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

        if let cardCount {
            allocation.cardCount = max(cardCount, 1)
        }

        manualAISourceAllocations[index] = allocation
    }

    func allocationTitle(for allocation: AISourceRangeAllocation) -> String {
        let noun = isPreparedSourcePDF ? "Pages" : "Images"
        if allocation.startIndex == allocation.endIndex {
            return "\(noun.dropLast()) \(allocation.startIndex)"
        }
        return "\(noun) \(allocation.startIndex)-\(allocation.endIndex)"
    }

    private func defaultManualAllocations(
        itemCount: Int,
        requestedCards: Int
    ) -> [AISourceRangeAllocation] {
        guard itemCount > 0, requestedCards > 0 else { return [] }
        return [
            AISourceRangeAllocation(
                startIndex: 1,
                endIndex: itemCount,
                cardCount: requestedCards
            )
        ]
    }

    private func normalizedManualAllocations(for itemCount: Int) -> [AISourceRangeAllocation] {
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

    private func hasOverlappingAllocations(_ allocations: [AISourceRangeAllocation]) -> Bool {
        guard allocations.count > 1 else { return false }

        for pairIndex in 1..<allocations.count {
            let previous = allocations[pairIndex - 1]
            let current = allocations[pairIndex]
            if current.startIndex <= previous.endIndex {
                return true
            }
        }

        return false
    }

    private func automaticAllocations(
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

    private func preferredCoverageRangeCount(
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

    private func distributedCardCounts(
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

        for offset in 0..<leftoverCards {
            counts[orderedIndices[offset % orderedIndices.count]] += 1
        }

        return counts
    }

    private func normalizedWeights(from characterCounts: [Int]) -> [Double] {
        let positiveCounts = characterCounts.filter { $0 > 0 }
        let averagePositive = positiveCounts.isEmpty
            ? 1.0
            : Double(positiveCounts.reduce(0, +)) / Double(positiveCounts.count)
        let floorWeight = max(1.0, averagePositive * 0.18)

        return characterCounts.map { count in
            max(Double(count), floorWeight)
        }
    }

    private func weightedCoverageRanges(
        for characterCounts: [Int],
        groupCount: Int
    ) -> [ClosedRange<Int>] {
        guard !characterCounts.isEmpty, groupCount > 0 else { return [] }

        let cappedGroupCount = min(groupCount, characterCounts.count)
        let weights = normalizedWeights(from: characterCounts)

        if cappedGroupCount == characterCounts.count {
            return characterCounts.indices.map { $0...$0 }
        }

        var ranges: [ClosedRange<Int>] = []
        var startIndex = 0

        for groupIndex in 0..<(cappedGroupCount - 1) {
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

            ranges.append(startIndex...endIndex)
            startIndex = endIndex + 1
        }

        ranges.append(startIndex...(characterCounts.count - 1))
        return ranges
    }

    private func mergeAllocationsWithSameRange(
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

    // =========================================================================
    // MARK: - Progressive AI Save
    // =========================================================================

    private func beginAIGenerationSession(targetCardCount: Int) {
        beginAIGenerationSession(targetCardCount: targetCardCount, shouldResetProgress: true)
    }

    private func beginAIGenerationSession(
        targetCardCount: Int,
        shouldResetProgress: Bool
    ) {
        cancelAIGenerationTask()
        resetAIGenerationRevealPipeline()
        clearAIGenerationPauseState()
        let sessionID = UUID()
        aiGenerationSessionID = sessionID

        if shouldResetProgress {
            aiRevealedGeneratedCardIDs.removeAll()
            aiGenerationBaseCardCount = draftCards.count
            aiTargetCardCount = targetCardCount
            aiGeneratedCardCount = 0
        } else if aiTargetCardCount == 0 {
            aiTargetCardCount = aiGeneratedCardCount + targetCardCount
        }

        aiBackgroundCoordinator.beginSession(id: sessionID) { [weak self] in
            self?.pauseAIGeneration(isBackgroundTimeout: true)
        }
        Task { [aiBackgroundCoordinator] in
            _ = await aiBackgroundCoordinator.requestNotificationAuthorizationIfNeeded()
        }
    }

    private func targetCardCount(for allocations: [AISourceRangeAllocation]) -> Int {
        let allocationTotal = allocations.reduce(0) { $0 + $1.cardCount }
        return max(allocationTotal, 0)
    }

    private func consumeGeneratedCards(
        from stream: AsyncThrowingStream<[AIFlashcard], Error>
    ) async throws {
        aiState = .generatingCards(progress: 0, foundCount: 0)
        resetAIGenerationRevealPipeline()
        aiRevealTask = Task { [weak self] in
            guard let self else { return }
            try await self.drainGeneratedCardsContinuously()
        }

        do {
            for try await batch in stream {
                try Task.checkCancellation()
                guard !batch.isEmpty else { continue }
                pendingAIGeneratedCards.append(contentsOf: batch)
                await Task.yield()
            }

            aiDidFinishReceivingGeneratedCards = true
            try await aiRevealTask?.value
            try Task.checkCancellation()
            completeAIGeneration()
        } catch {
            aiDidFinishReceivingGeneratedCards = true
            aiRevealTask?.cancel()
            aiRevealTask = nil
            pendingAIGeneratedCards.removeAll()
            throw error
        }
    }

    private func consumeGeneratedBatchChunks(
        from stream: AsyncThrowingStream<AIFlashcardBatchChunk, Error>
    ) async throws {
        aiState = .generatingCards(
            progress: min(1.0, Double(aiGeneratedCardCount) / Double(max(aiTargetCardCount, 1))),
            foundCount: aiGeneratedCardCount
        )
        resetAIGenerationRevealPipeline()
        aiRevealTask = Task { [weak self] in
            guard let self else { return }
            try await self.drainGeneratedCardsContinuously()
        }

        do {
            for try await chunk in stream {
                try Task.checkCancellation()
                registerGeneratedBatchChunk(chunk)
                guard !chunk.cards.isEmpty else { continue }
                pendingAIGeneratedCards.append(contentsOf: chunk.cards)
                await Task.yield()
            }

            aiDidFinishReceivingGeneratedCards = true
            try await aiRevealTask?.value
            try Task.checkCancellation()
            completeAIGeneration()
        } catch {
            aiDidFinishReceivingGeneratedCards = true
            aiRevealTask?.cancel()
            aiRevealTask = nil
            pendingAIGeneratedCards.removeAll()
            throw error
        }
    }

    private func drainGeneratedCardsContinuously() async throws {
        let revealDelay = revealDelayNanoseconds(for: aiTargetCardCount)

        while true {
            try Task.checkCancellation()

            if let nextCard = pendingAIGeneratedCards.first {
                pendingAIGeneratedCards.removeFirst()
                appendGeneratedCard(nextCard)

                if !pendingAIGeneratedCards.isEmpty || !aiDidFinishReceivingGeneratedCards {
                    try await Task.sleep(
                        nanoseconds: adjustedRevealDelayNanoseconds(
                            base: revealDelay,
                            pendingCount: pendingAIGeneratedCards.count,
                            isAwaitingMoreCards: !aiDidFinishReceivingGeneratedCards
                        )
                    )
                }
                continue
            }

            if aiDidFinishReceivingGeneratedCards {
                break
            }

            if aiGeneratedCardCount > 0 {
                try await Task.sleep(nanoseconds: revealDelay)
            } else {
                try await Task.sleep(nanoseconds: 30_000_000)
            }
        }
    }

    private func revealDelayNanoseconds(for targetCardCount: Int) -> UInt64 {
        switch targetCardCount {
        case 0...12:
            return 220_000_000
        case 13...30:
            return 150_000_000
        case 31...60:
            return 90_000_000
        default:
            return 55_000_000
        }
    }

    private func adjustedRevealDelayNanoseconds(
        base: UInt64,
        pendingCount: Int,
        isAwaitingMoreCards: Bool
    ) -> UInt64 {
        guard isAwaitingMoreCards else { return base }

        let multiplier: Double
        switch pendingCount {
        case ...1:
            multiplier = 2.6
        case 2...3:
            multiplier = 1.9
        case 4...6:
            multiplier = 1.35
        default:
            multiplier = 1
        }

        return UInt64(Double(base) * multiplier)
    }

    private func appendGeneratedCard(
        _ generatedCard: AIFlashcard,
        markRevealAsCompleted: Bool = false
    ) {
        let draft = DraftCard(
            frontZone: AIZoneParser.parse(text: generatedCard.question),
            backZone: AIZoneParser.parse(text: generatedCard.answer),
            frontType: .text,
            backType: .text,
            createdAt: Date(),
            editedAt: Date()
        )

        let updatedCount = aiGeneratedCardCount + 1
        let progress = min(1.0, Double(updatedCount) / Double(max(aiTargetCardCount, 1)))

        draftCards.append(draft)
        if markRevealAsCompleted {
            aiRevealedGeneratedCardIDs.insert(draft.id)
        }
        aiGeneratedCardCount = updatedCount
        aiState = .generatingCards(progress: progress, foundCount: updatedCount)
    }

    private func registerGeneratedBatchChunk(_ chunk: AIFlashcardBatchChunk) {
        let decrement = max(chunk.cards.count, 0)
        guard decrement > 0 else { return }

        if let allocationID = chunk.allocationID,
           let index = remainingAIAllocations.firstIndex(where: { $0.id == allocationID }) {
            var allocation = remainingAIAllocations[index]
            allocation.cardCount = max(allocation.cardCount - decrement, 0)

            if allocation.cardCount == 0 {
                remainingAIAllocations.remove(at: index)
            } else {
                remainingAIAllocations[index] = allocation
            }
            return
        }

        guard let index = remainingAIAllocations.firstIndex(where: { $0.cardCount > 0 }) else { return }
        var allocation = remainingAIAllocations[index]
        allocation.cardCount = max(allocation.cardCount - decrement, 0)

        if allocation.cardCount == 0 {
            remainingAIAllocations.remove(at: index)
        } else {
            remainingAIAllocations[index] = allocation
        }
    }

    private func completeAIGeneration() {
        let generatedCardCount = aiGeneratedCardCount
        let deckTitle = deckTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let sessionID = aiGenerationSessionID

        if let sessionID {
            Task { [aiBackgroundCoordinator] in
                await aiBackgroundCoordinator.notifyCompletionIfNeeded(
                    sessionID: sessionID,
                    deckTitle: deckTitle,
                    generatedCardCount: generatedCardCount
                )
            }
            aiBackgroundCoordinator.endSession(id: sessionID)
        }

        aiGenerationTask = nil
        resetAIGenerationRevealPipeline()
        showAICancelDialog = false



        aiState = .idle
        pdfAnalysis = nil
        
        Task {
            try? await AIGenerationSessionStore.shared.clearSession()
        }
        preparedAISource = nil
        manualAISourceAllocations = []
        aiGenerationBaseCardCount = 0
        aiGeneratedCardCount = 0
        aiTargetCardCount = 0
        aiGenerationSessionID = nil
        remainingAIAllocations = []
        aiRevealedGeneratedCardIDs.removeAll()
        clearAIGenerationPauseState()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func handleAIGenerationFailure(_ error: Error) {
        print("AI_RESUME_DEBUG: handleAIGenerationFailure called with error: \(error.localizedDescription)")
        
        let nsError = error as NSError
        let isNetworkError = nsError.domain == NSURLErrorDomain || nsError.domain == kCFErrorDomainCFNetwork as String
        let isBackground = UIApplication.shared.applicationState != .active
        
        if isBackground && isNetworkError {
            print("AI_RESUME_DEBUG: Intercepted background network error. Forcing a background pause instead of fatal error.")
            pauseAIGeneration(isBackgroundTimeout: true)
            return
        }

        if let sessionID = aiGenerationSessionID {
            aiBackgroundCoordinator.endSession(id: sessionID)
        }
        aiGenerationTask = nil
        aiDeckTitleTask?.cancel()
        aiDeckTitleTask = nil
        pendingAIDeckTitleRequestID = nil
        resetAIGenerationRevealPipeline()
        showAICancelDialog = false



        pdfAnalysis = nil
        preparedAISource = nil
        manualAISourceAllocations = []
        aiGenerationBaseCardCount = 0
        aiGeneratedCardCount = 0
        aiTargetCardCount = 0
        aiGenerationSessionID = nil
        remainingAIAllocations = []
        aiRevealedGeneratedCardIDs.removeAll()
        clearAIGenerationPauseState()
        aiState = .error(error.localizedDescription)
    }

    private func cancelAIGenerationTask() {
        if let sessionID = aiGenerationSessionID {
            aiBackgroundCoordinator.endSession(id: sessionID)
        }
        aiGenerationTask?.cancel()
        aiGenerationTask = nil
        aiDeckTitleTask?.cancel()
        aiDeckTitleTask = nil
        pendingAIDeckTitleRequestID = nil
        aiSessionPersistenceTask?.cancel()
        aiSessionPersistenceTask = nil
        resetAIGenerationRevealPipeline()
    }

    func requestAIGenerationCancel() {
        showAICancelDialog = true
    }

    func cancelAIGeneration(keepingGeneratedCards: Bool) {
        showAICancelDialog = false



        cancelAIGenerationTask()

        if !keepingGeneratedCards {
            let preservedCount = min(aiGenerationBaseCardCount, draftCards.count)
            draftCards = Array(draftCards.prefix(preservedCount))
        }

        pdfAnalysis = nil
        preparedAISource = nil
        manualAISourceAllocations = []
        aiGenerationBaseCardCount = 0
        aiGeneratedCardCount = 0
        aiTargetCardCount = 0
        aiGenerationSessionID = nil
        remainingAIAllocations = []
        aiRevealedGeneratedCardIDs.removeAll()
        clearAIGenerationPauseState()
        aiState = .idle

        // Ensure any persisted paused session is removed so it won't be
        // resurrected after app relaunch / rebuild.
        Task {
            try? await AIGenerationSessionStore.shared.clearSession()
        }
    }

    func pauseAIGeneration(isBackgroundTimeout: Bool = false) {
        guard let sessionID = aiGenerationSessionID else { return }
        print("AI_RESUME_DEBUG: pauseAIGeneration called. isBackgroundTimeout: \(isBackgroundTimeout)")
        flushPendingGeneratedCards()
        markCurrentGeneratedCardsAsRevealed()
        aiBackgroundCoordinator.endSession(id: sessionID)
        aiGenerationSessionID = nil
        aiGenerationTask?.cancel()
        aiGenerationTask = nil
        aiDeckTitleTask?.cancel()
        aiDeckTitleTask = nil
        pendingAIDeckTitleRequestID = nil
        resetAIGenerationRevealPipeline()
        showAICancelDialog = false
        print("AI_RESUME_DEBUG: pauseAIGeneration called (isBackgroundTimeout: \(isBackgroundTimeout))")
        isAIGenerationPaused = true
        isManualPauseInProgress = isBackgroundTimeout
        
        aiState = .generatingCards(
            progress: min(1.0, Double(aiGeneratedCardCount) / Double(max(aiTargetCardCount, 1))),
            foundCount: aiGeneratedCardCount
        )
        
        if isBackgroundTimeout {
            aiSessionPersistenceTask = Task.detached(priority: .background) { [weak self] in
                guard let self else { return }
                print("AI_RESUME_DEBUG: Starting detached persistence task (background timeout)")
                await self.persistAIPausedSession()
                await MainActor.run { [weak self] in
                    print("AI_RESUME_DEBUG: Persistence complete, clearing in-progress flag")
                    self?.isManualPauseInProgress = false
                }
            }
        } else {
            // Manual pause: keep everything in-memory only, avoid heavy disk I/O
            // so the rest of the app stays responsive.
            aiSessionPersistenceTask?.cancel()
            aiSessionPersistenceTask = nil
        }
    }
    
    // MARK: - Paused Session Disk Persistence
    
    private func persistAIPausedSession() async {
        print("AI_RESUME_DEBUG: persistAIPausedSession called")
        guard hasPausedAIGeneration else {
            print("AI_RESUME_DEBUG: hasPausedAIGeneration is false, aborting save")
            return
        }
        guard let source = preparedAISource else {
            print("AI_RESUME_DEBUG: preparedAISource is nil, aborting save")
            return
        }
        
        let remainingAllocations = resumeAllocations(for: source)
        guard !remainingAllocations.isEmpty else {
            print("AI_RESUME_DEBUG: No remaining allocations, aborting save")
            return
        }
        
        print("AI_RESUME_DEBUG: Saving session with \(remainingAllocations.count) allocations")
        
        let sourceMode: AIPausedSession.SourceMode
        do {
            if source.isPDF, let url = source.pdfURL {
                let bookmark = try await AIGenerationSessionStore.shared.createBookmark(for: url)
                sourceMode = .pdf(bookmarkData: bookmark, analysis: pdfAnalysis)
            } else {
                let fileURLs = try await AIGenerationSessionStore.shared.saveImagesToDisk(source.images)
                sourceMode = .photos(fileURLs: fileURLs)
            }
        } catch {
            print("Failed to save paused AI session artifacts: \(error)")
            return
        }

        let session = AIPausedSession(
            sessionID: UUID(),
            deckTitle: deckTitle,
            folderID: selectedFolder?.persistentModelID.hashValue.description, // Can be improved
            deckID: deckToEdit?.persistentModelID.hashValue.description, // Can be improved
            targetCardCount: aiTargetCardCount,
            generatedCardCount: aiGeneratedCardCount,
            baseCardCount: aiGenerationBaseCardCount,
            options: aiGenerationOptions,
            remainingAllocations: remainingAllocations,
            sourceMode: sourceMode,
            draftCards: draftCards,
            providerProfileID: aiProviderStore.activeProfile?.id
        )
        
        try? await AIGenerationSessionStore.shared.saveSession(session)
        print("AI_RESUME_DEBUG: persistAIPausedSession successfully issued save request")
    }
    
    func checkForPausedSession() async {
        print("AI_RESUME_DEBUG: checkForPausedSession called")
        guard let session = await AIGenerationSessionStore.shared.loadSession() else {
            print("AI_RESUME_DEBUG: No paused session found on disk")
            return
        }
        
        print("AI_RESUME_DEBUG: Paused session loaded from disk, targetCardCount: \(session.targetCardCount)")
        
        // Restore essential state so the user sees the pause prompt & can resume
        self.aiTargetCardCount = session.targetCardCount
        self.aiGeneratedCardCount = session.generatedCardCount
        self.aiGenerationBaseCardCount = session.baseCardCount
        self.aiGenerationOptions = session.options
        self.remainingAIAllocations = session.remainingAllocations
        self.draftCards = session.draftCards
        self.deckTitle = session.deckTitle
        markCurrentGeneratedCardsAsRevealed()

        switch session.sourceMode {
        case .pdf(let bookmarkData, let analysis):
            do {
                let url = try await AIGenerationSessionStore.shared.resolveBookmark(data: bookmarkData)
                await preparePDFSource(from: url)
                self.pdfAnalysis = analysis
            } catch {
                print("Failed to resolve paused PDF bookmark: \(error)")
                try? await AIGenerationSessionStore.shared.clearSession()
                return
            }
        case .photos(let fileURLs):
            let images = await AIGenerationSessionStore.shared.loadImagesFromDisk(at: fileURLs)
            guard !images.isEmpty else {
                try? await AIGenerationSessionStore.shared.clearSession()
                return
            }
            
            let texts = await DocumentTextExtractor.extractVisionTexts(from: images)
            let source = AIPreparedGenerationSource(
                kind: .photos,
                previewItems: makePhotoPreviewItems(images: images, texts: texts),
                textSegments: makeTextSegments(from: texts, labelPrefix: "Image"),
                images: images,
                pdfURL: nil
            )
            prepareSheetState(for: source, pdfAnalysis: nil)
        }
        
        // Dismiss the sheet if it was presented during restoration
        self.dismissAISheet(clearPendingSourceSelection: false)
        
        self.isAIGenerationPausedForBackground = true
        self.aiState = .generatingCards(
            progress: min(1.0, Double(aiGeneratedCardCount) / Double(max(aiTargetCardCount, 1))),
            foundCount: aiGeneratedCardCount
        )
        

    }

    private func resetAIGenerationRevealPipeline() {
        aiRevealTask?.cancel()
        aiRevealTask = nil
        pendingAIGeneratedCards.removeAll()
        aiDidFinishReceivingGeneratedCards = false
    }

    /// Resets pause-only flags so a completed or cancelled session cannot leak
    /// stale paused UI into the next generation run.
    private func clearAIGenerationPauseState() {
        isAIGenerationPaused = false
        isAIGenerationPausedForBackground = false
        isManualPauseInProgress = false
    }

    /// Returns `true` once a generated card already completed its first reveal.
    func hasCompletedAIGeneratedCardReveal(id: UUID) -> Bool {
        aiRevealedGeneratedCardIDs.contains(id)
    }

    /// Marks a generated card as already materialized so it is shown statically
    /// if the generation UI is rebuilt during pause/resume.
    func markAIGeneratedCardRevealCompleted(id: UUID) {
        aiRevealedGeneratedCardIDs.insert(id)
    }

    func confirmAIGenerationFromSheet() {
        guard canConfirmAIGeneration else { return }
        clearsPendingAISourceOnSheetDismiss = false
        aiSheetDestination = nil
        startAIGeneration()
    }

    func resumePausedAIGeneration() {
        isAIGenerationPaused = false
        isAIGenerationPausedForBackground = false
        isManualPauseInProgress = false
        
        guard let source = preparedAISource else { return }
        guard let aiService = makeAIService() else { return }

        let remainingAllocations = resumeAllocations(for: source)
        let remainingTargetCardCount = targetCardCount(for: remainingAllocations)

        guard remainingTargetCardCount > 0 else {
            completeAIGeneration()
            return
        }

        startAIGeneration(
            from: source,
            allocations: remainingAllocations,
            aiService: aiService,
            shouldResetProgress: false
        )
    }

    func keepAIGenerationPaused() {



    }

    private func resumeAllocations(
        for source: AIPreparedGenerationSource
    ) -> [AISourceRangeAllocation] {
        let explicitRemaining = remainingAIAllocations.filter { $0.cardCount > 0 }
        if !explicitRemaining.isEmpty {
            return explicitRemaining
        }

        let remainingCardCount = max(aiTargetCardCount - aiGeneratedCardCount, 0)
        guard remainingCardCount > 0 else { return [] }

        switch aiGenerationOptions.sourceDistributionMode {
        case .auto:
            return automaticAllocations(
                for: source.previewItems.map(\.characterCount),
                totalCards: remainingCardCount
            )

        case .manual:
            let normalizedAllocations = normalizedManualAllocations(for: source.itemCount)
            guard !normalizedAllocations.isEmpty else { return [] }

            let redistributedCounts = distributedCardCounts(
                totalCards: remainingCardCount,
                across: normalizedAllocations.map { Double(max($0.cardCount, 1)) }
            )

            return zip(normalizedAllocations, redistributedCounts).compactMap { allocation, cardCount in
                guard cardCount > 0 else { return nil }
                return AISourceRangeAllocation(
                    id: allocation.id,
                    startIndex: allocation.startIndex,
                    endIndex: allocation.endIndex,
                    cardCount: cardCount
                )
            }
        }
    }

    func dismissAISheet(clearPendingSourceSelection: Bool) {
        clearsPendingAISourceOnSheetDismiss = clearPendingSourceSelection
        aiSheetDestination = nil
    }

    func handleAISheetDismissed() {
        defer { clearsPendingAISourceOnSheetDismiss = false }
        guard clearsPendingAISourceOnSheetDismiss else { return }
        clearPendingAISourceSelection()
    }

    private func effectiveAIGenerationOptions() -> AIGenerationOptions {
        aiGenerationOptions
    }

    private func makeAIService() -> AIFlashcardService? {
        guard let activeProfile = aiProviderStore.activeProfile else {
            aiState = .error("No AI provider is configured. Open Settings > AI Providers.")
            return nil
        }

        if let validationMessage = activeProfile.generationValidationMessage {
            aiState = .error(validationMessage)
            return nil
        }

        return AIFlashcardService(provider: activeProfile)
    }

    private func requestAIDeckTitleIfNeeded(
        from source: AIPreparedGenerationSource,
        aiService: AIFlashcardService
    ) {
        let currentTitle = deckTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard currentTitle.isEmpty else {
            aiDeckTitleTask?.cancel()
            aiDeckTitleTask = nil
            pendingAIDeckTitleRequestID = nil
            return
        }

        let sampledText = sampledTextForAIDeckTitle(from: source)
        guard !sampledText.isEmpty else { return }

        aiDeckTitleTask?.cancel()
        let requestID = UUID()
        pendingAIDeckTitleRequestID = requestID

        aiDeckTitleTask = Task { [weak self] in
            guard let self else { return }

            defer {
                if pendingAIDeckTitleRequestID == requestID {
                    aiDeckTitleTask = nil
                    pendingAIDeckTitleRequestID = nil
                }
            }

            do {
                guard let suggestedTitle = try await aiService.generateDeckTitle(fromText: sampledText)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                    !suggestedTitle.isEmpty else {
                    return
                }

                guard pendingAIDeckTitleRequestID == requestID else { return }
                guard deckTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                deckTitle = suggestedTitle
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    private func sampledTextForAIDeckTitle(from source: AIPreparedGenerationSource) -> String {
        let nonEmptySegments = source.textSegments.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !nonEmptySegments.isEmpty else { return "" }

        let sampleCount = min(max(3, Int(ceil(Double(nonEmptySegments.count) / 10.0))), 6)
        let sampledIndices = evenlySampledIndices(
            totalCount: nonEmptySegments.count,
            sampleCount: sampleCount
        )

        let sampledText = sampledIndices.map { index in
            let segment = nonEmptySegments[index]
            return "\(segment.label)\n\(segment.text)"
        }
        .joined(separator: "\n\n")

        return String(sampledText.prefix(6_000))
    }

    private func evenlySampledIndices(
        totalCount: Int,
        sampleCount: Int
    ) -> [Int] {
        guard totalCount > 0, sampleCount > 0 else { return [] }
        guard sampleCount < totalCount else { return Array(0..<totalCount) }

        let step = Double(totalCount - 1) / Double(max(sampleCount - 1, 1))
        return (0..<sampleCount).map { offset in
            Int((Double(offset) * step).rounded())
        }
    }

    private func presentAIGenerationSheet() {
        clearsPendingAISourceOnSheetDismiss = true
        aiSheetDestination = .prepareGeneration
    }

    private func clearPendingAISourceSelection() {
        aiSourcePreparationTask?.cancel()
        selectedAIPhotos = []
        preparedAISource = nil
        manualAISourceAllocations = []
        pdfAnalysis = nil
    }

    private static let mockAIFlashcards: [AIFlashcard] = [
        AIFlashcard(
            question: "Care au fost principalele cauze si conditii care au determinat aparitia **Iluminismului** in secolul al XVIII-lea?",
            answer: """
            In secolele al XVII-lea si al XVIII-lea s-a produs o adevarata revolutie in gandire, cu descoperiri in matematica (Descartes, Leibniz), astronomie (Galileo Galilei) si mecanica (Newton).

            Noua perspectiva asupra lumii, vazuta ca fiind in continua transformare, pe baza unor **legi specifice** care o guverneaza.

            Masurarea tot mai precisa a timpului si spatiului datorita instrumentelor precum barometrul lui Torricelli sau ceasornicul lui Huygens.

            Aceste progrese stiintifice au determinat, treptat, afirmarea unui nou mod de gandire, percepere si explicare a lumii.

            In aceste conditii, in secolul al XVIII-lea, s-a nascut **Iluminismul**, un curent filosofic, ideologic si literar.
            """
        ),
        AIFlashcard(
            question: "Cum se caracterizeaza **conceptia deista** si **conceptia ateista** in cadrul Iluminismului, si care au fost reprezentantii lor?",
            answer: """
            **Deistii**, precum Voltaire, interpretau realitatea pe baza conceptiei deiste: Dumnezeu a creat lumea, dar nu intervine in evolutia ei.

            Divinitatea nu mai era vazuta ca Fiinta Suprema, iar **dogmele religioase** erau respinse (de exemplu, revelatia divina sau minunile).

            Deistii criticau atitudinea clerului catolic si atotputernicia Bisericii Catolice, fiind **antidogmatici** si **anticlericali**.

            **Ateii**, precum d'Holbach si Diderot, nu credeau in existenta Divinitatii.

            Ca si deistii, ateii au fost antidogmatici si anticlericali, urmarind slabirea influentei Bisericii Catolice in societate.
            """
        ),
        AIFlashcard(
            question: "Care au fost principalele **idei social-politice** sustinute de filozofii iluministi si care au fost contributiile lor specifice?",
            answer: """
            Montesquieu a argumentat principiul **separarii puterilor** in stat.

            Voltaire a fost preocupat de buna organizare a statului.

            Jean-Jacques Rousseau a abordat problema relatiilor dintre **individ si stat**.

            Pe plan economic, Francois Quesnay a subliniat importanta agriculturii, impunandu-se curentul **fiziocrat**.

            Adam Smith, considerat parintele economiei moderne, a elaborat teorii economice fundamentale.
            """
        ),
        AIFlashcard(
            question: "Cum s-a realizat **propagarea ideilor iluministe** si care au fost mijloacele si locurile-cheie pentru raspandirea lor?",
            answer: """
            Propagarea s-a realizat prin cafenelele literare si saloanele de lectura, unde se citeau operele iluministe.

            Cluburile erau frecventate de tot mai multe persoane care dezbateau problemele societatii.

            Tiparul a contribuit prin publicatiile savante (ca `Journal des Savantes`), presa cotidiana si brosuri.

            Rolul cel mai insemnat l-a avut **dictionarul Enciclopedia**, care a format opinia publica.

            Din Franta, Iluminismul a patruns in Prusia, Austria, Rusia, Spania, Portugalia, Tarile Romane etc.
            """
        ),
        AIFlashcard(
            question: "Ce reprezenta **Iluminismul** din punct de vedere social si care au fost obiectivele sale principale in ceea ce priveste transformarea societatii?",
            answer: """
            Iluminismul reprezenta modul de gandire al **burgheziei**, clasa sociala activa, in plina afirmare.

            Denumirea de Iluminism exprima increderea filozofilor secolului al XVIII-lea in **ratiune** si in puterea de a lumina omenirea prin stiinta si cultura.

            Francmasonii urmareau rasturnarea ordinii social-politice nedrepte a **Vechiului Regim** si crearea unei societati in care indivizii sa fie egali in drepturi.

            A aparut in Franta ca o reactie impotriva inegalitatii si nedreptatilor din timpul Vechiului Regim (regimul politic absolutist anterior anului 1789).

            S-au impus o alta perspectiva asupra societatii, noi **principii si valori** in cadrul acesteia.
            """
        )
    ]

    // MARK: - Reset AI State

    /// Resets the AI pipeline state to `.idle` with an animation.
    func resetAIState() {
        cancelAIGenerationTask()
        aiSourcePreparationTask?.cancel()


        showAICancelDialog = false

        aiGenerationBaseCardCount = 0
        aiGeneratedCardCount = 0
        aiTargetCardCount = 0
        remainingAIAllocations = []
        clearAIGenerationPauseState()
        preparedAISource = nil
        manualAISourceAllocations = []
        aiRevealedGeneratedCardIDs.removeAll()
        pdfAnalysis = nil
        withAnimation { aiState = .idle }
    }

    private func startAIGeneration(
        from source: AIPreparedGenerationSource,
        allocations: [AISourceRangeAllocation],
        aiService: AIFlashcardService,
        shouldResetProgress: Bool
    ) {
        let targetCardCount = targetCardCount(for: allocations)
        guard targetCardCount > 0 else { return }

        remainingAIAllocations = allocations

        beginAIGenerationSession(
            targetCardCount: targetCardCount,
            shouldResetProgress: shouldResetProgress
        )
        requestAIDeckTitleIfNeeded(from: source, aiService: aiService)

        switch source.kind {
        case .photos:
            processPhotosForAI(
                source,
                allocations: allocations,
                targetCardCount: targetCardCount,
                aiService: aiService
            )
        case .pdf:
            processPDFForAI(
                source,
                allocations: allocations,
                targetCardCount: targetCardCount,
                aiService: aiService
            )
        }
    }

    private func flushPendingGeneratedCards() {
        guard !pendingAIGeneratedCards.isEmpty else { return }

        let queuedCards = pendingAIGeneratedCards
        pendingAIGeneratedCards.removeAll()

        for card in queuedCards {
            appendGeneratedCard(card, markRevealAsCompleted: true)
        }
    }

    /// Freezes the current streamed cards in their final visual state before a
    /// pause/resume transition rebuilds the list.
    private func markCurrentGeneratedCardsAsRevealed() {
        let cappedBaseCount = min(aiGenerationBaseCardCount, draftCards.count)
        let generatedCards = draftCards.dropFirst(cappedBaseCount)
        aiRevealedGeneratedCardIDs.formUnion(generatedCards.map(\.id))
    }

    // =========================================================================
    // MARK: - Card Actions
    // =========================================================================

    /// Appends a new draft card with the given front and back zones.
    func addCard(frontZone: ZoneModel, backZone: ZoneModel) {
        let newCard = DraftCard(
            frontZone: frontZone,
            backZone: backZone,
            frontType: .text,
            backType: .text,
            createdAt: Date(),
            editedAt: Date()
        )
        withAnimation { draftCards.append(newCard) }
    }

    /// Updates the draft card's zone content and bumps `editedAt` if content changed.
    func updateCard(_ card: DraftCard, frontZone: ZoneModel, backZone: ZoneModel) {
        guard let index = draftCards.firstIndex(where: { $0.id == card.id }) else { return }
        var updated = draftCards[index]
        let changed = updated.frontZone != frontZone || updated.backZone != backZone
        updated.frontZone = frontZone
        updated.backZone = backZone
        if changed { updated.editedAt = Date() }
        withAnimation { draftCards[index] = updated }
    }

    /// Removes the specified draft card from the list.
    func deleteCard(_ card: DraftCard) {
        withAnimation { draftCards.removeAll { $0.id == card.id } }
    }

    // MARK: - Save Deck

    /// Persists the current draft state to SwiftData.
    ///
    /// - If `deckToEdit` is set, performs an in-place update (diff-based).
    /// - Otherwise, creates a brand-new `DeckModel` and inserts all draft cards.
    ///
    /// Shows a brief success overlay before navigating away.
    func saveDeck(
        context: ModelContext,
        router: NavigationManager,
        dismissAction: @escaping () -> Void
    ) -> Bool {
        let trimmedTitle = deckTitle.trimmingCharacters(in: .whitespaces)

        if deckToEdit != nil && !hasUnsavedChanges {
            dismissAction()
            return true
        }

        if let deck = deckToEdit {
            // ── UPDATE EXISTING DECK ──────────────────────────────────────────
            let titleChanged = deck.title != trimmedTitle
            deck.title = trimmedTitle

            if deck.folder != selectedFolder {
                deck.folder?.deckCount -= 1
                selectedFolder?.deckCount += 1
                deck.folder = selectedFolder
            }

            var cardsChanged = false

            let draftOriginalIDs = Set(draftCards.compactMap { $0.originalCardID })
            let cardsToDelete = deck.cards.filter { !draftOriginalIDs.contains($0.id) }
            for card in cardsToDelete {
                context.delete(card)
                deck.cards.removeAll { $0.id == card.id }
                cardsChanged = true
            }

            for draft in draftCards {
                if let originalID = draft.originalCardID,
                    let existing = deck.cards.first(where: { $0.id == originalID }) {
                    let frontChanged = existing.frontZone != draft.frontZone
                    let backChanged = existing.backZone != draft.backZone
                    let typeChanged = existing.frontType != draft.frontType || existing.backType != draft.backType
                    if frontChanged || backChanged || typeChanged {
                        existing.frontZone = draft.frontZone
                        existing.backZone = draft.backZone
                        existing.frontType = draft.frontType
                        existing.backType = draft.backType
                        existing.editedAt = Date()
                        cardsChanged = true
                    }
                } else {
                    deck.lastAssignedCardNumber += 1
                    let newCard = CardModel(
                        frontZone: draft.frontZone,
                        backZone: draft.backZone,
                        frontType: draft.frontType,
                        backType: draft.backType,
                        cardNumber: deck.lastAssignedCardNumber
                    )
                    if let createdAt = draft.createdAt {
                        newCard.createdAt = createdAt
                    }
                    if let editedAt = draft.editedAt {
                        newCard.editedAt = editedAt
                    }
                    newCard.deck = deck
                    deck.cards.append(newCard)
                    context.insert(newCard)
                    cardsChanged = true
                }
            }
            if titleChanged || cardsChanged { deck.editedAt = Date() }
            deck.cardCount = draftCards.count

        } else {
            // ── CREATE NEW DECK ───────────────────────────────────────────────
            let newDeck = DeckModel(title: trimmedTitle, icon: "book.closed.fill", colorHex: "#FFFFFF")
            context.insert(newDeck)
            newDeck.folder = selectedFolder
            selectedFolder?.deckCount += 1

            for draft in draftCards {
                newDeck.lastAssignedCardNumber += 1
                let newCard = CardModel(
                    frontZone: draft.frontZone,
                    backZone: draft.backZone,
                    frontType: draft.frontType,
                    backType: draft.backType,
                    cardNumber: newDeck.lastAssignedCardNumber
                )
                if let createdAt = draft.createdAt {
                    newCard.createdAt = createdAt
                }
                if let editedAt = draft.editedAt {
                    newCard.editedAt = editedAt
                }
                newCard.deck = newDeck
                context.insert(newCard)
                newDeck.cards.append(newCard)
            }
            newDeck.cardCount = draftCards.count
        }

        do {
            try context.save()
        } catch {
            return false
        }

        // ── UI Triggers & Navigation ──────────────────────────────────────────
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            showSuccessOverlay = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeOut(duration: 0.25)) { self.showSuccessOverlay = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if self.deckToEdit == nil {
                    self.resetForm()
                    router.popToRoot()
                } else { dismissAction() }
            }
        }
        return true
    }

    private func resetForm() {
        deckTitle = ""
        draftCards = []
        cardToEdit = nil
        isCreatingNewCard = false
        preparedAISource = nil
        manualAISourceAllocations = []
        pdfAnalysis = nil
    }

    private var currentSnapshot: CreateDeckStateSnapshot {
        CreateDeckStateSnapshot(
            title: deckTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            selectedFolderID: selectedFolder?.persistentModelID,
            draftCards: draftCards.map(DraftCardChangeSnapshot.init)
        )
    }
}

// MARK: - UIImage Resize Helper

extension UIImage {
    /// Resizes the image to fit within `maxDimension` × `maxDimension` while preserving aspect ratio.
    ///
    /// Used before sending images to the AI service to reduce request payload size.
    func resizedForAI(toMaxDimension maxDimension: CGFloat) -> UIImage {
        let size = self.size
        guard size.width > maxDimension || size.height > maxDimension else { return self }
        let scale = min(maxDimension / size.width, maxDimension / size.height)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1.0
        return UIGraphicsImageRenderer(size: newSize, format: format)
            .image { _ in self.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}

// MARK: - DocumentTextExtractor Page Count Helper

extension DocumentTextExtractor {
    /// Counts the number of pages in the PDF at the given URL.
    ///
    /// Runs in a non-isolated async context to avoid blocking the `MainActor`.
    static func pdfPageCount(url: URL) async -> Int {
        PDFDocument(url: url)?.pageCount ?? 0
    }
}
