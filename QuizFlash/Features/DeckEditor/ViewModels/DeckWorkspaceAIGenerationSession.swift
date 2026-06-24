//
//  DeckWorkspaceAIGenerationSession.swift
//  QuizFlash
//

import SwiftUI
import SwiftData
import PhotosUI
import PDFKit

extension DeckWorkspaceViewModel {
    // MARK: - Progressive AI Save
    // =========================================================================

    func beginAIGenerationSession(targetCardCount: Int) {
        beginAIGenerationSession(targetCardCount: targetCardCount, shouldResetProgress: true)
    }

    func beginAIGenerationSession(
        targetCardCount: Int,
        shouldResetProgress: Bool
    ) {
        cancelAIGenerationTask()
        resetAIGenerationRevealPipeline()
        clearAIGenerationPauseState()
        let sessionID = UUID()
        aiGenerationSessionID = sessionID

        if shouldResetProgress {
            aiSessionDraftCardIDs.removeAll()
            aiGenerationBaseCardCount = draftCards.count
            aiTargetCardCount = targetCardCount
            aiGeneratedCardCount = 0
            aiAccumulatedGenerationDuration = 0
        } else if aiTargetCardCount == 0 {
            aiTargetCardCount = aiGeneratedCardCount + targetCardCount
        }

        aiGenerationStartedAt = Date()

        aiBackgroundCoordinator.beginSession(id: sessionID) { [weak self] in
            self?.pauseAIGeneration(isBackgroundTimeout: true)
        }
        Task { [aiBackgroundCoordinator] in
            _ = await aiBackgroundCoordinator.requestNotificationAuthorizationIfNeeded()
        }
    }

    func targetCardCount(for allocations: [AISourceRangeAllocation]) -> Int {
        let allocationTotal = allocations.reduce(0) { $0 + $1.cardCount }
        return max(allocationTotal, 0)
    }

    func consumeGeneratedCards(
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

    func consumeGeneratedBatchChunks(
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
                aiGeneratedShortfallCount += chunk.shortfallCount
                guard !chunk.cards.isEmpty else { continue }
                pendingAIGeneratedCards.append(contentsOf: chunk.cards)
                await Task.yield()
            }

            aiDidFinishReceivingGeneratedCards = true
            try await aiRevealTask?.value
            try Task.checkCancellation()
            if aiGeneratedShortfallCount > 0 {
                throw AIServiceError.unknown(
                    "Generated \(aiGeneratedCardCount) card\(aiGeneratedCardCount == 1 ? "" : "s"). \(aiGeneratedShortfallCount) requested card\(aiGeneratedShortfallCount == 1 ? "" : "s") could not be completed from the available candidates."
                )
            }
            completeAIGeneration()
        } catch {
            aiDidFinishReceivingGeneratedCards = true
            aiRevealTask?.cancel()
            aiRevealTask = nil
            pendingAIGeneratedCards.removeAll()
            throw error
        }
    }

    func drainGeneratedCardsContinuously() async throws {
        let revealDelay = revealDelayNanoseconds(for: aiTargetCardCount)

        while true {
            try Task.checkCancellation()

            if let nextCard = pendingAIGeneratedCards.first {
                pendingAIGeneratedCards.removeFirst()
                try appendGeneratedCard(nextCard)

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

    func revealDelayNanoseconds(for targetCardCount: Int) -> UInt64 {
        switch targetCardCount {
        case 0...12:
            return 340_000_000
        case 13...30:
            return 250_000_000
        case 31...60:
            return 180_000_000
        default:
            return 130_000_000
        }
    }

    func adjustedRevealDelayNanoseconds(
        base: UInt64,
        pendingCount: Int,
        isAwaitingMoreCards: Bool
    ) -> UInt64 {
        let _ = pendingCount
        let _ = isAwaitingMoreCards
        return base
    }

    func appendGeneratedCard(_ generatedCard: AIFlashcard) throws {
        let draftContent = try makeDraftContent(from: generatedCard)
        let draft = DraftCard(
            cardNumber: allocateNextDraftCardNumber(),
            content: draftContent,
            isPinned: false,
            creationSource: .ai,
            createdAt: Date(),
            editedAt: Date()
        )

        let updatedCount = aiGeneratedCardCount + 1
        let progress = min(1.0, Double(updatedCount) / Double(max(aiTargetCardCount, 1)))

        withAnimation(.easeOut(duration: UIConstants.Animation.standard)) {
            draftCards.append(draft)
            registerSessionDraftID(draft.id, marksAsAI: true)
            aiGeneratedCardCount = updatedCount
            aiState = .generatingCards(progress: progress, foundCount: updatedCount)
        }
    }

    func makeDraftContent(from generatedCard: AIFlashcard) throws -> DraftCardContent {
        try AIGeneratedCardContentMapper.map(generatedCard)
    }

    func registerGeneratedBatchChunk(_ chunk: AIFlashcardBatchChunk) {
        let decrement = max(chunk.cards.count + chunk.shortfallCount, 0)
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

    func completeAIGeneration() {
        let generatedCardCount = aiGeneratedCardCount
        let deckTitle = deckTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let sessionID = aiGenerationSessionID
        let cloudSession = cloudAIGenerationSession

        if let cloudSession {
            Task {
                _ = try? await CloudAIProxyClient.shared.finishGeneration(
                    cloudSession,
                    validatedCards: generatedCardCount
                )
            }
        }

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
        finalizeAIGenerationClock()

        aiState = .idle
        pdfAnalysis = nil
        integrateAllDraftCardsIntoBaseline()
        
        Task {
            try? await AIGenerationSessionStore.shared.clearSession()
        }
        preparedAISource = nil
        manualAISourceAllocations = []
        aiGenerationBaseCardCount = 0
        aiGeneratedCardCount = 0
        aiTargetCardCount = 0
        aiGenerationSessionID = nil
        cloudAIGenerationSession = nil
        remainingAIAllocations = []
        aiGeneratedShortfallCount = 0
        aiGenerationStartedAt = nil
        aiAccumulatedGenerationDuration = 0
        clearAIGenerationPauseState()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func handleAIGenerationFailure(_ error: Error) {
        let nsError = error as NSError
        let isNetworkError = nsError.domain == NSURLErrorDomain || nsError.domain == kCFErrorDomainCFNetwork as String
        let isBackground = UIApplication.shared.applicationState != .active
        
        if isBackground && isNetworkError {
            pauseAIGeneration(isBackgroundTimeout: true)
            return
        }

        let cloudSession = cloudAIGenerationSession
        let generatedCardCount = aiGeneratedCardCount
        if let cloudSession {
            Task {
                if generatedCardCount > 0 {
                    _ = try? await CloudAIProxyClient.shared.finishGeneration(
                        cloudSession,
                        validatedCards: generatedCardCount
                    )
                } else {
                    await CloudAIProxyClient.shared.failGeneration(cloudSession)
                }
            }
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
        finalizeAIGenerationClock()

        pdfAnalysis = nil
        preparedAISource = nil
        manualAISourceAllocations = []
        aiGenerationBaseCardCount = 0
        aiGeneratedCardCount = 0
        aiTargetCardCount = 0
        aiGenerationSessionID = nil
        cloudAIGenerationSession = nil
        remainingAIAllocations = []
        aiGeneratedShortfallCount = 0
        aiGenerationStartedAt = nil
        aiAccumulatedGenerationDuration = 0
        clearAIGenerationPauseState()
        aiState = .error(error.localizedDescription)
    }

    func cancelAIGenerationTask() {
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
        finalizeAIGenerationClock()

        let cloudSession = cloudAIGenerationSession
        let generatedCardCount = aiGeneratedCardCount
        if let cloudSession {
            Task {
                if keepingGeneratedCards && generatedCardCount > 0 {
                    _ = try? await CloudAIProxyClient.shared.finishGeneration(
                        cloudSession,
                        validatedCards: generatedCardCount
                    )
                } else {
                    await CloudAIProxyClient.shared.failGeneration(cloudSession)
                }
            }
        }

        cancelAIGenerationTask()

        if !keepingGeneratedCards {
            let preservedCount = min(aiGenerationBaseCardCount, draftCards.count)
            draftCards = Array(draftCards.prefix(preservedCount))
            let preservedIDs = Set(draftCards.map(\.id))
            sessionDraftCardIDs.formIntersection(preservedIDs)
        } else {
            integrateAllDraftCardsIntoBaseline()
        }

        pdfAnalysis = nil
        preparedAISource = nil
        manualAISourceAllocations = []
        aiGenerationBaseCardCount = 0
        aiGeneratedCardCount = 0
        aiTargetCardCount = 0
        aiGenerationSessionID = nil
        cloudAIGenerationSession = nil
        remainingAIAllocations = []
        aiGeneratedShortfallCount = 0
        aiGenerationStartedAt = nil
        aiAccumulatedGenerationDuration = 0
        aiSessionDraftCardIDs.removeAll()
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
        flushPendingGeneratedCards()
        aiBackgroundCoordinator.endSession(id: sessionID)
        aiGenerationSessionID = nil
        aiGenerationTask?.cancel()
        aiGenerationTask = nil
        aiDeckTitleTask?.cancel()
        aiDeckTitleTask = nil
        pendingAIDeckTitleRequestID = nil
        resetAIGenerationRevealPipeline()
        showAICancelDialog = false
        finalizeAIGenerationClock()
        isAIGenerationPaused = true
        isManualPauseInProgress = isBackgroundTimeout
        
        aiState = .generatingCards(
            progress: min(1.0, Double(aiGeneratedCardCount) / Double(max(aiTargetCardCount, 1))),
            foundCount: aiGeneratedCardCount
        )
        
        if isBackgroundTimeout {
            aiSessionPersistenceTask = Task.detached(priority: .background) { [weak self] in
                guard let self else { return }
                await self.persistAIPausedSession()
                await MainActor.run { [weak self] in
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
    
    func persistAIPausedSession() async {
        guard hasPausedAIGeneration else {
            return
        }
        guard let source = preparedAISource else {
            return
        }
        
        let remainingAllocations = resumeAllocations(for: source)
        guard !remainingAllocations.isEmpty else {
            return
        }

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
    }
    
    func checkForPausedSession() async {
        guard let session = await AIGenerationSessionStore.shared.loadSession() else {
            return
        }

        // Restore essential state so the user sees the pause prompt & can resume
        self.aiTargetCardCount = session.targetCardCount
        self.aiGeneratedCardCount = session.generatedCardCount
        self.aiGenerationBaseCardCount = session.baseCardCount
        self.aiGenerationStartedAt = nil
        self.aiAccumulatedGenerationDuration = 0
        self.aiGenerationOptions = session.options
        self.remainingAIAllocations = session.remainingAllocations
        self.draftCards = session.draftCards
        self.deckTitle = session.deckTitle
        let baseDraftIDs = Set(session.draftCards.prefix(session.baseCardCount).map(\.id))
        let sessionDraftIDs = Set(session.draftCards.dropFirst(session.baseCardCount).map(\.id))
        self.baseDraftCardIDs = baseDraftIDs
        self.sessionDraftCardIDs = sessionDraftIDs
        self.aiSessionDraftCardIDs = sessionDraftIDs

        switch session.sourceMode {
        case .pdf(let bookmarkData, let analysis):
            do {
                let url = try await AIGenerationSessionStore.shared.resolveBookmark(data: bookmarkData)
                await preparePDFSource(from: url)
                self.pdfAnalysis = analysis
            } catch {
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
            guard DocumentTextExtractor.isUsableExtractedText(texts) else {
                try? await AIGenerationSessionStore.shared.clearSession()
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
        }
        
        // Dismiss the sheet if it was presented during restoration
        self.dismissAISheet(clearPendingSourceSelection: false)
        
        self.isAIGenerationPausedForBackground = true
        self.aiState = .generatingCards(
            progress: min(1.0, Double(aiGeneratedCardCount) / Double(max(aiTargetCardCount, 1))),
            foundCount: aiGeneratedCardCount
        )
        

    }

    func resetAIGenerationRevealPipeline() {
        aiRevealTask?.cancel()
        aiRevealTask = nil
        pendingAIGeneratedCards.removeAll()
        aiDidFinishReceivingGeneratedCards = false
        aiGeneratedShortfallCount = 0
    }

    /// Resets pause-only flags so a completed or cancelled session cannot leak
    /// stale paused UI into the next generation run.
    func clearAIGenerationPauseState() {
        isAIGenerationPaused = false
        isAIGenerationPausedForBackground = false
        isManualPauseInProgress = false
    }

    func confirmAIGenerationFromSheet() {
        guard canConfirmAIGeneration else { return }
        clearsPendingAISourceOnSheetDismiss = false
        aiSheetDestination = nil
        startAIGeneration()
    }

    @discardableResult
    func stageAIGenerationDisplayForSheetDismiss() -> Bool {
        guard canConfirmAIGeneration else { return false }

        let targetCardCount = targetCardCount(for: resolvedAISourceAllocations)
        guard targetCardCount > 0 else { return false }

        cancelAIGenerationTask()
        resetAIGenerationRevealPipeline()
        clearAIGenerationPauseState()

        clearsPendingAISourceOnSheetDismiss = false
        aiSessionDraftCardIDs.removeAll()
        aiGenerationBaseCardCount = draftCards.count
        aiTargetCardCount = targetCardCount
        aiGeneratedCardCount = 0
        aiAccumulatedGenerationDuration = 0
        aiGenerationStartedAt = nil

        withAnimation(.easeInOut(duration: UIConstants.Animation.standard)) {
            aiState = .generatingCards(progress: 0, foundCount: 0)
        }

        return true
    }

    func resumePausedAIGeneration() {
        isAIGenerationPaused = false
        isAIGenerationPausedForBackground = false
        isManualPauseInProgress = false
        aiGenerationStartedAt = Date()
        
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

    func finalizeAIGenerationClock(referenceDate: Date = Date()) {
        guard let startedAt = aiGenerationStartedAt else { return }
        aiAccumulatedGenerationDuration += max(0, referenceDate.timeIntervalSince(startedAt))
        aiGenerationStartedAt = nil
    }

    func resumeAllocations(
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

    func effectiveAIGenerationOptions() -> AIGenerationOptions {
        aiGenerationOptions
    }

    func makeAIService() -> AIFlashcardService? {
#if DEBUG
        guard let activeProfile = aiProviderStore.activeProfile else {
            aiState = .error("No AI provider is configured. Open Settings > AI Providers.")
            return nil
        }

        if let validationMessage = activeProfile.generationValidationMessage {
            aiState = .error(validationMessage)
            return nil
        }

        guard let promptBundle = debugAIPromptBundle ?? AIPromptBundleCache.loadStoredBundleSynchronously() else {
            aiState = .error("AI prompt configuration is unavailable.")
            return nil
        }

        return AIFlashcardService(
            provider: activeProfile,
            transport: .directProvider,
            promptBundle: promptBundle
        )
#else
        guard let cloudAIGenerationSession else {
            aiState = .error("AI generation session is unavailable.")
            return nil
        }
        return AIFlashcardService(
            provider: .preset(.deepSeek),
            transport: .cloudProxy(cloudAIGenerationSession)
        )
#endif
    }

    func requestAIDeckTitleIfNeeded(
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

    func sampledTextForAIDeckTitle(from source: AIPreparedGenerationSource) -> String {
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

    func evenlySampledIndices(
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

    func presentAIGenerationSheet() {
        clearsPendingAISourceOnSheetDismiss = true
        aiSheetDestination = .prepareGeneration
    }

    func startPendingAISourcePreparationIfNeeded() {
        guard aiSourcePreparationTask == nil,
              preparedAISource == nil,
              let pendingSource = pendingAISourceSelection else { return }

        pendingAISourceSelection = nil
        aiSourcePreparationTask = Task { [weak self] in
            guard let self else { return }
            defer { self.aiSourcePreparationTask = nil }

            await Task.yield()
            try? await Task.sleep(for: .milliseconds(180))

            switch pendingSource {
            case .photos(let items):
                await self.preparePhotoSource(from: items)
            case .pdf(let url):
                await self.preparePDFSource(from: url)
            }
        }
    }

    func scheduleAIGenerationSheetPresentation() {
        Task { @MainActor [weak self] in
            guard let self else { return }

            for _ in 0..<90 {
                guard isPreparingAISource else { return }
                if !showAIPhotoPicker && !showAIPDFPicker {
                    break
                }
                try? await Task.sleep(for: .milliseconds(16))
            }

            guard isPreparingAISource, aiSheetDestination == nil else { return }
            presentAIGenerationSheet()
        }
    }

    func beginAISourcePreparation(_ state: AISourcePreparationState) {
        withAnimation(.easeInOut(duration: UIConstants.Animation.instant)) {
            aiSourcePreparationState = state
        }
    }

    func clearAISourcePreparation() {
        withAnimation(.easeInOut(duration: UIConstants.Animation.instant)) {
            aiSourcePreparationState = nil
        }
    }

    func clearPendingAISourceSelection() {
        aiSourcePreparationTask?.cancel()
        aiSourcePreparationTask = nil
        pendingAISourceSelection = nil
        selectedAIPhotos = []
        clearAISourcePreparation()
        preparedAISource = nil
        manualAISourceAllocations = []
        pdfAnalysis = nil
    }

    static func mockAICards(for type: AICardGenerationType) -> [AIFlashcard] {
        switch type {
        case .flashcards:
            return [
                AIFlashcard(
                    question: "Care au fost principalele cauze si conditii care au determinat aparitia **Iluminismului** in secolul al XVIII-lea?",
                    answer: """
                    In secolele al XVII-lea si al XVIII-lea s-a produs o adevarata revolutie in gandire, cu descoperiri in matematica (Descartes, Leibniz), astronomie (Galileo Galilei) si mecanica (Newton).

                    Noua perspectiva asupra lumii, vazuta ca fiind in continua transformare, pe baza unor **legi specifice** care o guverneaza.

                    Masurarea tot mai precisa a timpului si spatiului datorita instrumentelor precum barometrul lui Torricelli sau ceasornicul lui Huygens.

                    In aceste conditii, in secolul al XVIII-lea, s-a nascut **Iluminismul**, un curent filosofic, ideologic si literar.
                    """
                ),
                AIFlashcard(
                    question: "Cum s-a realizat **propagarea ideilor iluministe** si care au fost mijloacele si locurile-cheie pentru raspandirea lor?",
                    answer: """
                    Propagarea s-a realizat prin cafenelele literare si saloanele de lectura, unde se citeau operele iluministe.

                    Tiparul a contribuit prin publicatiile savante, presa cotidiana si brosuri.

                    Rolul cel mai insemnat l-a avut **Enciclopedia**, care a format opinia publica.
                    """
                ),
                AIFlashcard(
                    question: "Ce reprezenta **Iluminismul** din punct de vedere social?",
                    answer: """
                    Iluminismul reprezenta modul de gandire al **burgheziei**, clasa sociala activa, in plina afirmare.

                    Curentul exprima increderea in **ratiune**, stiinta si cultura ca forte de transformare sociala.
                    """
                )
            ]
        case .quiz:
            return [
                AIFlashcard(
                    questionZones: [
                        "Ce a sustinut **Montesquieu** in plan politic in contextul Iluminismului?"
                    ],
                    choices: [
                        "Principiul **separarii puterilor** in stat",
                        "Suprematia exclusiva a monarhiei absolute",
                        "Eliminarea completa a dreptului de proprietate",
                        "Subordonarea economiei fata de cler"
                    ],
                    correctIndexes: [0],
                    explanationZones: [
                        "Montesquieu este asociat in mod clasic cu principiul **separarii puterilor**."
                    ]
                ),
                AIFlashcard(
                    questionZones: [
                        "Care dintre urmatoarele trasaturi caracterizeaza curentul **Iluminist**?"
                    ],
                    choices: [
                        "Incredere in **ratiune**",
                        "Accent pe **stiinta** si educatie",
                        "Respinge orice schimbare sociala",
                        "Critica nedreptatile Vechiului Regim"
                    ],
                    correctIndexes: [0, 1, 3],
                    explanationZones: [
                        "Iluminismul valorizeaza ratiunea, stiinta si reforma sociala, nu conservarea oarba a vechilor structuri."
                    ]
                )
            ]
        }
    }

    // MARK: - Reset AI State

    /// Resets the AI pipeline state to `.idle` with an animation.
    func resetAIState() {
        cancelAIGenerationTask()
        aiSourcePreparationTask?.cancel()
        clearAISourcePreparation()

        showAICancelDialog = false

        aiGenerationBaseCardCount = 0
        aiGeneratedCardCount = 0
        aiTargetCardCount = 0
        remainingAIAllocations = []
        aiGeneratedShortfallCount = 0
        clearAIGenerationPauseState()
        preparedAISource = nil
        manualAISourceAllocations = []
        aiSessionDraftCardIDs.removeAll()
        pdfAnalysis = nil
        withAnimation { aiState = .idle }
    }

    func startAIGeneration(
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

    func flushPendingGeneratedCards() {
        guard !pendingAIGeneratedCards.isEmpty else { return }

        let queuedCards = pendingAIGeneratedCards
        pendingAIGeneratedCards.removeAll()

        for card in queuedCards {
            do {
                try appendGeneratedCard(card)
            } catch {
                aiState = .error(error.localizedDescription)
                break
            }
        }
    }
}
