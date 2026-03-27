import Foundation
import UIKit
import SwiftData

extension AIFlashcardService {
    // MARK: - Public Entry Points
    // -------------------------------------------------------------------------

    /// Generates flashcards from a PDF file.
    ///
    /// - Parameters:
    ///   - pdfURL: The local file URL of the PDF document.
    ///   - targetCards: The desired number of flashcards to generate.
    /// - Returns: An array of `AIFlashcard` values.
    /// - Throws: `AIServiceError` if extraction, network communication, or parsing fails.
    public func generateFlashcards(from pdfURL: URL, targetCards: Int) async throws -> [AIFlashcard] {
        try await generateFlashcards(from: pdfURL, targetCards: targetCards, options: AIGenerationOptions())
    }

    public func generateFlashcards(
        from pdfURL: URL,
        targetCards: Int,
        options: AIGenerationOptions
    ) async throws -> [AIFlashcard] {
        try await collectFlashcards(
            from: generateFlashcardsStream(from: pdfURL, targetCards: targetCards, options: options)
        )
    }

    /// Generates flashcards from a collection of images.
    ///
    /// - Parameters:
    ///   - images: An array of `UIImage` values (camera captures, scanned pages, etc.).
    ///   - targetCards: The desired number of flashcards to generate.
    /// - Returns: An array of `AIFlashcard` values.
    /// - Throws: `AIServiceError` if network communication or parsing fails.
    public func generateFlashcards(from images: [UIImage], targetCards: Int) async throws -> [AIFlashcard] {
        try await generateFlashcards(from: images, targetCards: targetCards, options: AIGenerationOptions())
    }

    public func generateFlashcards(
        from images: [UIImage],
        targetCards: Int,
        options: AIGenerationOptions
    ) async throws -> [AIFlashcard] {
        try await collectFlashcards(
            from: generateFlashcardsStream(from: images, targetCards: targetCards, options: options)
        )
    }

    /// Generates flashcards from a plain-text string.
    ///
    /// - Parameters:
    ///   - text: The source text content.
    ///   - targetCards: The desired number of flashcards to generate.
    /// - Returns: An array of `AIFlashcard` values.
    /// - Throws: `AIServiceError` if network communication or parsing fails.
    public func generateFlashcards(fromText text: String, targetCards: Int) async throws -> [AIFlashcard] {
        try await generateFlashcards(fromText: text, targetCards: targetCards, options: AIGenerationOptions())
    }

    public func generateFlashcards(
        fromText text: String,
        targetCards: Int,
        options: AIGenerationOptions
    ) async throws -> [AIFlashcard] {
        try await collectFlashcards(
            from: generateFlashcardsStream(fromText: text, targetCards: targetCards, options: options)
        )
    }

    /// Generates a short deck title that matches the dominant language and
    /// subject of the supplied source text.
    public func generateDeckTitle(fromText text: String) async throws -> String? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return nil }

        return try await sendDeckTitleRequest(
            messages: buildDeckTitleMessages(fromText: trimmedText),
            model: textModel
        )
    }

    /// Converts existing persisted cards into a new target card kind while
    /// preserving one output mapping per source card.
    func convertCards(
        _ sourceCards: [AICardConversionSource],
        to targetType: AICardGenerationType,
        level: AICardGenerationLevel = .balanced
    ) async throws -> [AICardConversionOutput] {
        let stream = convertCardsStream(
            sourceCards,
            to: targetType,
            level: level
        )

        var allOutputs: [AICardConversionOutput] = []
        for try await chunk in stream {
            allOutputs.append(contentsOf: chunk.outputs)
        }
        return allOutputs
    }

    /// Streams converted card batches using the same adaptive planner used by
    /// AI generation so conversions no longer stall behind a fixed serial loop.
    func convertCardsStream(
        _ sourceCards: [AICardConversionSource],
        to targetType: AICardGenerationType,
        level: AICardGenerationLevel = .balanced
    ) -> AsyncThrowingStream<AIConversionBatchChunk, Error> {
        let trimmedCards = sourceCards.filter {
            !$0.content.searchDocumentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        let options = AIGenerationOptions(
            cardType: targetType,
            cardLevel: level
        )
        let plans = buildConversionBatchPlans(
            sourceCards: trimmedCards,
            options: options
        )

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await performConversionPlanQueue(
                        plans: plans,
                        targetType: targetType,
                        level: level
                    ) { chunk in
                        continuation.yield(chunk)
                        await Task.yield()
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    /// Streams flashcard batches from a PDF file as soon as each AI chunk finishes.
    ///
    /// - Parameters:
    ///   - pdfURL: The local file URL of the PDF document.
    ///   - targetCards: The desired number of flashcards to generate.
    /// - Returns: An `AsyncThrowingStream` yielding card batches in completion order.
    public func generateFlashcardsStream(
        from pdfURL: URL,
        targetCards: Int
    ) -> AsyncThrowingStream<[AIFlashcard], Error> {
        generateFlashcardsStream(from: pdfURL, targetCards: targetCards, options: AIGenerationOptions())
    }

    public func generateFlashcardsStream(
        from pdfURL: URL,
        targetCards: Int,
        options: AIGenerationOptions
    ) -> AsyncThrowingStream<[AIFlashcard], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let result = await DocumentTextExtractor.extract(from: pdfURL)
                    try await routeStream(
                        result: result,
                        targetCards: targetCards,
                        options: options,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    /// Streams flashcard batches from a collection of images.
    ///
    /// - Parameters:
    ///   - images: Images selected for AI generation.
    ///   - targetCards: The desired number of flashcards to generate.
    /// - Returns: An `AsyncThrowingStream` yielding card batches as they are ready.
    public func generateFlashcardsStream(
        from images: [UIImage],
        targetCards: Int
    ) -> AsyncThrowingStream<[AIFlashcard], Error> {
        generateFlashcardsStream(from: images, targetCards: targetCards, options: AIGenerationOptions())
    }

    public func generateFlashcardsStream(
        from images: [UIImage],
        targetCards: Int,
        options: AIGenerationOptions
    ) -> AsyncThrowingStream<[AIFlashcard], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let result = await DocumentTextExtractor.extract(from: images)
                    try await routeStream(
                        result: result,
                        targetCards: targetCards,
                        options: options,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    /// Streams flashcard batches from plain extracted text.
    ///
    /// - Parameters:
    ///   - text: The extracted source text.
    ///   - targetCards: The desired number of flashcards to generate.
    /// - Returns: An `AsyncThrowingStream` yielding card batches in real time.
    public func generateFlashcardsStream(
        fromText text: String,
        targetCards: Int
    ) -> AsyncThrowingStream<[AIFlashcard], Error> {
        generateFlashcardsStream(fromText: text, targetCards: targetCards, options: AIGenerationOptions())
    }

    public func generateFlashcardsStream(
        fromText text: String,
        targetCards: Int,
        options: AIGenerationOptions
    ) -> AsyncThrowingStream<[AIFlashcard], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await dispatchTextStream(
                        text,
                        targetCards: targetCards,
                        needsOCRCorrection: false,
                        options: options,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    /// Streams flashcards from pre-analyzed text segments using an explicit
    /// source-allocation plan.
    public func generateFlashcardsStream(
        fromSegments segments: [AITextSourceSegment],
        targetCards: Int,
        allocations: [AISourceRangeAllocation],
        needsOCRCorrection: Bool = false,
        options: AIGenerationOptions
    ) -> AsyncThrowingStream<[AIFlashcard], Error> {
        let batchStream = generateFlashcardBatchStream(
            fromSegments: segments,
            targetCards: targetCards,
            allocations: allocations,
            needsOCRCorrection: needsOCRCorrection,
            options: options
        )

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await chunk in batchStream {
                        continuation.yield(chunk.cards)
                        await Task.yield()
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    public func generateFlashcardBatchStream(
        fromSegments segments: [AITextSourceSegment],
        targetCards: Int,
        allocations: [AISourceRangeAllocation],
        needsOCRCorrection: Bool = false,
        options: AIGenerationOptions
    ) -> AsyncThrowingStream<AIFlashcardBatchChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await performTextRequests(
                        plans: buildTextBatchPlans(
                            segments: segments,
                            allocations: allocations,
                            options: options
                        ),
                        needsOCRCorrection: needsOCRCorrection,
                        options: options
                    ) { chunk in
                        continuation.yield(chunk)
                        await Task.yield()
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    /// Streams flashcards from explicit image ranges using an externally
    /// computed coverage plan.
    public func generateFlashcardsStream(
        from images: [UIImage],
        itemLabels: [String],
        targetCards: Int,
        allocations: [AISourceRangeAllocation],
        options: AIGenerationOptions
    ) -> AsyncThrowingStream<[AIFlashcard], Error> {
        let batchStream = generateFlashcardBatchStream(
            from: images,
            itemLabels: itemLabels,
            targetCards: targetCards,
            allocations: allocations,
            options: options
        )

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await chunk in batchStream {
                        continuation.yield(chunk.cards)
                        await Task.yield()
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    public func generateFlashcardBatchStream(
        from images: [UIImage],
        itemLabels: [String],
        targetCards: Int,
        allocations: [AISourceRangeAllocation],
        options: AIGenerationOptions
    ) -> AsyncThrowingStream<AIFlashcardBatchChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await performVisionRequests(
                        plans: buildVisionBatchPlans(
                            images: images,
                            labels: itemLabels,
                            allocations: allocations,
                            options: options
                        ),
                        options: options
                    ) { chunk in
                        continuation.yield(chunk)
                        await Task.yield()
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Routing
    // -------------------------------------------------------------------------

    private func route(
        result: ExtractionResult,
        targetCards: Int,
        options: AIGenerationOptions
    ) async throws -> [AIFlashcard] {
        switch result.method {
        case .pdfKit, .visionOCR:
            guard let text = result.text, !text.isEmpty else { throw AIServiceError.parsingFailed }
            return try await dispatchText(
                text,
                targetCards: targetCards,
                needsOCRCorrection: result.needsOCRCorrection,
                options: options
            )
        case .rawImages:
            guard let images = result.images, !images.isEmpty else { throw AIServiceError.parsingFailed }
            return try await dispatchVision(images, targetCards: targetCards, options: options)
        }
    }

    private func routeStream(
        result: ExtractionResult,
        targetCards: Int,
        options: AIGenerationOptions,
        continuation: AsyncThrowingStream<[AIFlashcard], Error>.Continuation
    ) async throws {
        switch result.method {
        case .pdfKit, .visionOCR:
            guard let text = result.text, !text.isEmpty else { throw AIServiceError.parsingFailed }
            try await dispatchTextStream(
                text,
                targetCards: targetCards,
                needsOCRCorrection: result.needsOCRCorrection,
                options: options,
                continuation: continuation
            )
        case .rawImages:
            guard let images = result.images, !images.isEmpty else { throw AIServiceError.parsingFailed }
            try await dispatchVisionStream(images, targetCards: targetCards, options: options, continuation: continuation)
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Text Dispatch (chunking)
    // -------------------------------------------------------------------------

    private func dispatchText(
        _ text: String,
        targetCards: Int,
        needsOCRCorrection: Bool,
        options: AIGenerationOptions
    ) async throws -> [AIFlashcard] {
        var allCards: [AIFlashcard] = []
        try await performTextRequests(
            text,
            targetCards: targetCards,
            needsOCRCorrection: needsOCRCorrection,
            options: options
        ) { cards in
            allCards.append(contentsOf: cards)
        }
        return allCards
    }

    private func dispatchTextStream(
        _ text: String,
        targetCards: Int,
        needsOCRCorrection: Bool,
        options: AIGenerationOptions,
        continuation: AsyncThrowingStream<[AIFlashcard], Error>.Continuation
    ) async throws {
        try await performTextRequests(
            text,
            targetCards: targetCards,
            needsOCRCorrection: needsOCRCorrection,
            options: options
        ) { cards in
            continuation.yield(cards)
            await Task.yield()
        }
    }

    private func dispatchVision(
        _ images: [UIImage],
        targetCards: Int,
        options: AIGenerationOptions
    ) async throws -> [AIFlashcard] {
        var allCards: [AIFlashcard] = []
        try await performVisionRequests(images, targetCards: targetCards, options: options) { cards in
            allCards.append(contentsOf: cards)
        }
        return allCards
    }

    private func dispatchVisionStream(
        _ images: [UIImage],
        targetCards: Int,
        options: AIGenerationOptions,
        continuation: AsyncThrowingStream<[AIFlashcard], Error>.Continuation
    ) async throws {
        try await performVisionRequests(images, targetCards: targetCards, options: options) { cards in
            continuation.yield(cards)
            await Task.yield()
        }
    }

    private func performTextRequests(
        _ text: String,
        targetCards: Int,
        needsOCRCorrection: Bool,
        options: AIGenerationOptions,
        onBatch: @escaping ([AIFlashcard]) async throws -> Void
    ) async throws {
        let plans = buildTextBatchPlans(text: text, targetCards: targetCards, options: options)
        try await performTextRequests(
            plans: plans,
            needsOCRCorrection: needsOCRCorrection,
            options: options,
            onBatch: onBatch
        )
    }

    private func performTextRequests(
        plans: [TextBatchPlan],
        needsOCRCorrection: Bool,
        options: AIGenerationOptions,
        onBatch: @escaping ([AIFlashcard]) async throws -> Void
    ) async throws {
        try await performTextRequests(
            plans: plans,
            needsOCRCorrection: needsOCRCorrection,
            options: options
        ) { chunk in
            try await onBatch(chunk.cards)
        }
    }

    private func performTextRequests(
        plans: [TextBatchPlan],
        needsOCRCorrection: Bool,
        options: AIGenerationOptions,
        onBatch: @escaping (AIFlashcardBatchChunk) async throws -> Void
    ) async throws {
        try await performPlanQueue(
            plans: plans,
            maxConcurrent: maxConcurrentTextPlanRequests,
            execute: { [self] plan, coveredPrompts in
                if options.cardType == .match {
                    let result = try await sendQualityFirstMatchGenerationRequest(
                        targetCards: plan.targetCards,
                        model: textModel,
                        options: options
                    ) { requestedCards, retryHints in
                        buildTextMessages(
                            text: plan.text,
                            targetCards: requestedCards,
                            needsOCRCorrection: needsOCRCorrection,
                            options: options,
                            sourceLabel: plan.sourceLabel,
                            batchIndex: plan.batchIndex,
                            totalBatches: plan.totalBatches,
                            passIndex: plan.passIndex,
                            coveredPrompts: coveredPrompts + retryHints
                        )
                    }
                    return GeneratedBatchExecutionResult(
                        cards: result.cards,
                        shortfallCount: result.shortfallCount
                    )
                }

                let messages = buildTextMessages(
                    text: plan.text,
                    targetCards: plan.targetCards,
                    needsOCRCorrection: needsOCRCorrection,
                    options: options,
                    sourceLabel: plan.sourceLabel,
                    batchIndex: plan.batchIndex,
                    totalBatches: plan.totalBatches,
                    passIndex: plan.passIndex,
                    coveredPrompts: coveredPrompts
                )

                return GeneratedBatchExecutionResult(
                    cards: try await sendRequest(messages: messages, model: textModel, options: options),
                    shortfallCount: 0
                )
            },
            onBatch: onBatch
        )
    }

    private func performVisionRequests(
        _ images: [UIImage],
        targetCards: Int,
        options: AIGenerationOptions,
        onBatch: @escaping ([AIFlashcard]) async throws -> Void
    ) async throws {
        let plans = buildVisionBatchPlans(images: images, targetCards: targetCards, options: options)
        try await performVisionRequests(
            plans: plans,
            options: options,
            onBatch: onBatch
        )
    }

    private func performVisionRequests(
        plans: [VisionBatchPlan],
        options: AIGenerationOptions,
        onBatch: @escaping ([AIFlashcard]) async throws -> Void
    ) async throws {
        try await performVisionRequests(
            plans: plans,
            options: options
        ) { chunk in
            try await onBatch(chunk.cards)
        }
    }

    private func performVisionRequests(
        plans: [VisionBatchPlan],
        options: AIGenerationOptions,
        onBatch: @escaping (AIFlashcardBatchChunk) async throws -> Void
    ) async throws {
        try await performPlanQueue(
            plans: plans,
            maxConcurrent: maxConcurrentVisionPlanRequests,
            execute: { [self] plan, coveredPrompts in
                if options.cardType == .match {
                    let result = try await sendQualityFirstMatchGenerationRequest(
                        targetCards: plan.targetCards,
                        model: visionModel,
                        options: options
                    ) { requestedCards, retryHints in
                        buildVisionMessages(
                            images: plan.images,
                            targetCards: requestedCards,
                            options: options,
                            sourceLabel: plan.sourceLabel,
                            batchIndex: plan.batchIndex,
                            totalBatches: plan.totalBatches,
                            passIndex: plan.passIndex,
                            coveredPrompts: coveredPrompts + retryHints
                        )
                    }
                    return GeneratedBatchExecutionResult(
                        cards: result.cards,
                        shortfallCount: result.shortfallCount
                    )
                }

                let messages = buildVisionMessages(
                    images: plan.images,
                    targetCards: plan.targetCards,
                    options: options,
                    sourceLabel: plan.sourceLabel,
                    batchIndex: plan.batchIndex,
                    totalBatches: plan.totalBatches,
                    passIndex: plan.passIndex,
                    coveredPrompts: coveredPrompts
                )

                return GeneratedBatchExecutionResult(
                    cards: try await sendRequest(messages: messages, model: visionModel, options: options),
                    shortfallCount: 0
                )
            },
            onBatch: onBatch
        )
    }

    private func collectFlashcards(
        from stream: AsyncThrowingStream<[AIFlashcard], Error>
    ) async throws -> [AIFlashcard] {
        var allCards: [AIFlashcard] = []
        for try await chunk in stream {
            allCards.append(contentsOf: chunk)
        }
        return allCards
    }

    // -------------------------------------------------------------------------
    // MARK: - Chunking Helpers
    // -------------------------------------------------------------------------

    private func buildTextBatchPlans(
        text: String,
        targetCards: Int,
        options: AIGenerationOptions
    ) -> [TextBatchPlan] {
        let batchSizes = makeCardBatchSizes(totalCards: targetCards, batchSize: options.resolvedCardsPerBatch(for: targetCards))
        guard !batchSizes.isEmpty else { return [] }

        var units = makeTextUnits(from: text)
        units = expandTextUnits(units, toReach: batchSizes.count)

        let groupedUnits = distributeElementsEvenly(units, into: batchSizes.count)

        return groupedUnits.enumerated().compactMap { index, group in
            guard !group.isEmpty else { return nil }

            let content = group
                .map(\.content)
                .joined(separator: DocumentTextExtractor.pageSeparator)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !content.isEmpty else { return nil }

            let passIndex = group.compactMap { unit -> Int? in
                if let start = unit.label.range(of: "(focus pass "),
                   let end = unit.label.range(of: ")", range: start.upperBound..<unit.label.endIndex) {
                    return Int(unit.label[start.upperBound..<end.lowerBound])
                }
                return nil
            }.max() ?? 1

            return TextBatchPlan(
                text: content,
                sourceLabel: group.map(\.label).joined(separator: ", "),
                allocationID: nil,
                targetCards: batchSizes[index],
                batchIndex: index + 1,
                totalBatches: batchSizes.count,
                passIndex: passIndex
            )
        }
    }

    private func buildVisionBatchPlans(
        images: [UIImage],
        targetCards: Int,
        options: AIGenerationOptions
    ) -> [VisionBatchPlan] {
        let batchSizes = makeCardBatchSizes(totalCards: targetCards, batchSize: options.resolvedCardsPerBatch(for: targetCards))
        guard !batchSizes.isEmpty else { return [] }

        let units = images.enumerated().map { index, image in
            TextSourceUnit(content: "", label: "Page \(index + 1)")
        }

        let selectedImages = units.compactMap { unit -> UIImage? in
            guard let pageIndex = Int(unit.label.replacingOccurrences(of: "Page ", with: "")),
                  images.indices.contains(pageIndex - 1) else { return nil }
            return images[pageIndex - 1]
        }
        guard !selectedImages.isEmpty else { return [] }

        let selectedLabels = units.map(\.label)
        let baseGroupCount = min(max(1, selectedImages.count), batchSizes.count)
        let groupedImages = distributeElementsEvenly(selectedImages, into: baseGroupCount)
        let groupedLabels = distributeElementsEvenly(selectedLabels, into: baseGroupCount)

        var plans: [VisionBatchPlan] = []

        for (index, batchSize) in batchSizes.enumerated() {
            let groupIndex = index % baseGroupCount
            let passIndex = (index / baseGroupCount) + 1
            let imagesForBatch = groupedImages[groupIndex]
            guard !imagesForBatch.isEmpty else { continue }

            let sourceLabel = groupedLabels[groupIndex].joined(separator: ", ")
            plans.append(
                VisionBatchPlan(
                    images: imagesForBatch,
                    sourceLabel: sourceLabel,
                    allocationID: nil,
                    targetCards: batchSize,
                    batchIndex: index + 1,
                    totalBatches: batchSizes.count,
                    passIndex: passIndex
                )
            )
        }

        return plans
    }

    private func buildTextBatchPlans(
        segments: [AITextSourceSegment],
        allocations: [AISourceRangeAllocation],
        options: AIGenerationOptions
    ) -> [TextBatchPlan] {
        guard !segments.isEmpty else { return [] }

        var plans: [TextBatchPlan] = []
        let deliveryBatchSize = options.resolvedCardsPerBatch(
            for: allocations.reduce(0) { $0 + $1.cardCount }
        )

        for allocation in normalizedAllocations(allocations, segmentCount: segments.count) {
            let selectedSegments = Array(segments[(allocation.startIndex - 1)..<allocation.endIndex])
            let text = selectedSegments
                .map(\.text)
                .joined(separator: DocumentTextExtractor.pageSeparator)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !text.isEmpty else { continue }

            let batchSizes = makeCardBatchSizes(
                totalCards: allocation.cardCount,
                batchSize: min(deliveryBatchSize, allocation.cardCount)
            )
            let sourceLabel = sourceLabel(for: selectedSegments.map(\.label))

            for (passIndex, batchSize) in batchSizes.enumerated() {
                plans.append(
                    TextBatchPlan(
                        text: text,
                        sourceLabel: sourceLabel,
                        allocationID: allocation.id,
                        targetCards: batchSize,
                        batchIndex: 0,
                        totalBatches: 0,
                        passIndex: passIndex + 1
                    )
                )
            }
        }

        return indexed(plans)
    }

    private func buildVisionBatchPlans(
        images: [UIImage],
        labels: [String],
        allocations: [AISourceRangeAllocation],
        options: AIGenerationOptions
    ) -> [VisionBatchPlan] {
        guard !images.isEmpty else { return [] }

        let resolvedLabels: [String]
        if labels.count == images.count {
            resolvedLabels = labels
        } else {
            resolvedLabels = images.indices.map { "Page \($0 + 1)" }
        }

        var plans: [VisionBatchPlan] = []
        let deliveryBatchSize = options.resolvedCardsPerBatch(
            for: allocations.reduce(0) { $0 + $1.cardCount }
        )

        for allocation in normalizedAllocations(allocations, segmentCount: images.count) {
            let range = (allocation.startIndex - 1)..<allocation.endIndex
            let selectedImages = Array(images[range])
            guard !selectedImages.isEmpty else { continue }

            let sourceLabel = sourceLabel(for: Array(resolvedLabels[range]))
            let batchSizes = makeCardBatchSizes(
                totalCards: allocation.cardCount,
                batchSize: min(deliveryBatchSize, allocation.cardCount)
            )

            for (passIndex, batchSize) in batchSizes.enumerated() {
                plans.append(
                    VisionBatchPlan(
                        images: selectedImages,
                        sourceLabel: sourceLabel,
                        allocationID: allocation.id,
                        targetCards: batchSize,
                        batchIndex: 0,
                        totalBatches: 0,
                        passIndex: passIndex + 1
                    )
                )
            }
        }

        return indexed(plans)
    }

    private func buildConversionBatchPlans(
        sourceCards: [AICardConversionSource],
        options: AIGenerationOptions
    ) -> [ConversionBatchPlan] {
        guard !sourceCards.isEmpty else { return [] }

        let batchSizes = makeCardBatchSizes(
            totalCards: sourceCards.count,
            batchSize: options.resolvedCardsPerBatch(for: sourceCards.count)
        )
        guard !batchSizes.isEmpty else { return [] }

        var cursor = 0
        return batchSizes.enumerated().compactMap { index, batchSize in
            guard cursor < sourceCards.count else { return nil }
            let end = min(cursor + batchSize, sourceCards.count)
            let batchSources = Array(sourceCards[cursor..<end])
            cursor = end

            return ConversionBatchPlan(
                sourceCards: batchSources,
                sourceLabel: "Cards \(index == 0 ? 1 : max(1, end - batchSources.count + 1))-\(end)",
                targetCards: batchSources.count,
                batchIndex: index + 1,
                totalBatches: batchSizes.count
            )
        }
    }

    private func makeTextUnits(from text: String) -> [TextSourceUnit] {
        let pages = text.components(separatedBy: DocumentTextExtractor.pageSeparator)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if pages.count > 1 {
            return pages.enumerated().map { index, page in
                TextSourceUnit(content: page, label: "Page \(index + 1)")
            }
        }

        let chunks = splitBySize(text)
        return chunks.enumerated().map { index, chunk in
            TextSourceUnit(content: chunk, label: "Section \(index + 1)")
        }
    }

    private func sampleTextUnitsEvenly(_ units: [TextSourceUnit], limit: Int?) -> [TextSourceUnit] {
        guard let limit, limit > 0, units.count > limit else { return units }
        let indices = evenlySampledIndices(totalCount: units.count, sampleCount: limit)
        return indices.map { units[$0] }
    }

    private func expandTextUnits(_ units: [TextSourceUnit], toReach targetCount: Int) -> [TextSourceUnit] {
        guard !units.isEmpty, targetCount > units.count else { return units }

        var expanded = units

        while expanded.count < targetCount {
            guard let longestIndex = expanded.indices.max(by: {
                expanded[$0].content.count < expanded[$1].content.count
            }) else {
                break
            }

            let current = expanded[longestIndex]
            guard let splitUnits = splitTextUnit(current), splitUnits.count > 1 else {
                break
            }

            expanded.remove(at: longestIndex)
            expanded.insert(contentsOf: splitUnits.reversed(), at: longestIndex)
        }

        if expanded.count >= targetCount {
            return expanded
        }

        let baseUnits = expanded
        var passIndex = 2
        var cursor = 0

        while expanded.count < targetCount {
            let base = baseUnits[cursor % baseUnits.count]
            expanded.append(
                TextSourceUnit(
                    content: base.content,
                    label: "\(base.label) (focus pass \(passIndex))"
                )
            )
            cursor += 1
            if cursor % baseUnits.count == 0 {
                passIndex += 1
            }
        }

        return expanded
    }

    private func splitTextUnit(_ unit: TextSourceUnit) -> [TextSourceUnit]? {
        let paragraphs = unit.content.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if paragraphs.count >= 2 {
            let splitIndex = max(1, paragraphs.count / 2)
            return [
                TextSourceUnit(content: paragraphs[..<splitIndex].joined(separator: "\n\n"), label: "\(unit.label) A"),
                TextSourceUnit(content: paragraphs[splitIndex...].joined(separator: "\n\n"), label: "\(unit.label) B")
            ]
        }

        let lines = unit.content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if lines.count >= 8 {
            let splitIndex = max(1, lines.count / 2)
            return [
                TextSourceUnit(content: lines[..<splitIndex].joined(separator: "\n"), label: "\(unit.label) A"),
                TextSourceUnit(content: lines[splitIndex...].joined(separator: "\n"), label: "\(unit.label) B")
            ]
        }

        let chunks = splitBySize(unit.content)
        guard chunks.count >= 2 else { return nil }
        return chunks.enumerated().map { index, chunk in
            TextSourceUnit(content: chunk, label: "\(unit.label) \(Character(UnicodeScalar(65 + index)!))")
        }
    }

    private func splitBySize(_ text: String) -> [String] {
        var chunks: [String] = []
        var startIndex = text.startIndex
        while startIndex < text.endIndex {
            let endOffset = min(maxCharsPerChunk, text.distance(from: startIndex, to: text.endIndex))
            var endIndex = text.index(startIndex, offsetBy: endOffset)
            if endIndex < text.endIndex {
                let lookback = text[startIndex..<endIndex]
                if let lastBreak = lookback.rangeOfCharacter(from: .newlines, options: .backwards) {
                    endIndex = lastBreak.upperBound
                }
            }
            chunks.append(String(text[startIndex..<endIndex]))
            startIndex = endIndex
        }
        return chunks
    }

    private func distributeCards(_ total: Int, across count: Int) -> [Int] {
        guard count > 0 else { return [] }
        var result = Array(repeating: total / count, count: count)
        for i in 0..<(total % count) { result[i] += 1 }
        return result
    }

    private func makeCardBatchSizes(totalCards: Int, batchSize: Int) -> [Int] {
        guard totalCards > 0 else { return [] }

        var remaining = totalCards
        var batches: [Int] = []
        let normalizedBatchSize = max(batchSize, 1)

        // Front-load a smaller preview batch so the first cards land sooner and
        // the generation screen feels responsive even for large targets.
        if totalCards > normalizedBatchSize, normalizedBatchSize >= 4 {
            let previewBatchSize = min(remaining, min(3, max(2, normalizedBatchSize / 2)))
            batches.append(previewBatchSize)
            remaining -= previewBatchSize
        }

        while remaining > 0 {
            let next = min(normalizedBatchSize, remaining)
            batches.append(next)
            remaining -= next
        }

        return batches
    }

    private func evenlySampledIndices(totalCount: Int, sampleCount: Int) -> [Int] {
        guard totalCount > 0 else { return [] }
        guard sampleCount < totalCount else { return Array(0..<totalCount) }

        let stride = Double(totalCount - 1) / Double(max(sampleCount - 1, 1))
        var indices = (0..<sampleCount).map { sampleIndex in
            Int((Double(sampleIndex) * stride).rounded())
        }

        indices = Array(Set(indices)).sorted()

        var nextIndex = 0
        while indices.count < sampleCount, nextIndex < totalCount {
            if !indices.contains(nextIndex) {
                indices.append(nextIndex)
            }
            nextIndex += 1
        }

        return indices.sorted()
    }

    private func distributeElementsEvenly<T>(_ elements: [T], into groupCount: Int) -> [[T]] {
        guard groupCount > 0 else { return [] }
        guard !elements.isEmpty else { return Array(repeating: [], count: groupCount) }

        let distribution = distributeCards(elements.count, across: groupCount)
        var cursor = 0

        return distribution.map { groupSize in
            guard groupSize > 0 else { return [] }
            let end = min(cursor + groupSize, elements.count)
            let slice = Array(elements[cursor..<end])
            cursor = end
            return slice
        }
    }

    private func performPlanQueue<Plan: RecoverableBatchPlan>(
        plans: [Plan],
        maxConcurrent: Int,
        execute: @escaping @Sendable (Plan, [String]) async throws -> GeneratedBatchExecutionResult,
        onBatch: @escaping (AIFlashcardBatchChunk) async throws -> Void
    ) async throws {
        guard !plans.isEmpty else { return }

        var pendingPlans = plans
        var coveredPrompts: [String] = []
        var activeTaskCount = 0
        var activeConcurrency = min(max(maxConcurrent, 1), plans.count)
        var consecutiveSuccesses = 0
        var terminalFailures: [String] = []

        try await withThrowingTaskGroup(of: (Plan, Result<GeneratedBatchExecutionResult, Error>).self) { group in
            func scheduleAvailableTasks() {
                while activeTaskCount < activeConcurrency, !pendingPlans.isEmpty {
                    let plan = pendingPlans.removeFirst()
                    let promptSnapshot = coveredPrompts
                    activeTaskCount += 1

                    group.addTask {
                        do {
                            try Task.checkCancellation()
                            let result = try await execute(plan, promptSnapshot)
                            return (plan, .success(result))
                        } catch {
                            return (plan, .failure(error))
                        }
                    }
                }
            }

            scheduleAvailableTasks()

            while activeTaskCount > 0 {
                try Task.checkCancellation()

                guard let (plan, result) = try await group.next() else {
                    break
                }

                activeTaskCount -= 1

                switch result {
                case .success(let result):
                    consecutiveSuccesses += 1

                    if !result.cards.isEmpty || result.shortfallCount > 0 {
                        try await onBatch(
                            AIFlashcardBatchChunk(
                                cards: result.cards,
                                allocationID: allocationID(for: plan),
                                plannedCardCount: plan.targetCards,
                                shortfallCount: result.shortfallCount,
                                sourceLabel: plan.sourceLabel
                            )
                        )
                        coveredPrompts = updateCoveredPrompts(existing: coveredPrompts, with: result.cards)
                    }

                    if consecutiveSuccesses >= max(activeConcurrency, 1), activeConcurrency < maxConcurrent {
                        activeConcurrency += 1
                        consecutiveSuccesses = 0
                    }

                case .failure(let error):
                    consecutiveSuccesses = 0
                    activeConcurrency = max(1, activeConcurrency / 2)

                    if shouldAttemptPlanSplit(after: error), let splitPlans = plan.splitForRecovery() {
                        pendingPlans.append(contentsOf: splitPlans)
                    } else {
                        terminalFailures.append(batchFailureDescription(for: plan, error: error))
                    }
                }

                scheduleAvailableTasks()
            }
        }

        if !terminalFailures.isEmpty {
            let preview = terminalFailures.prefix(3).joined(separator: "\n")
            throw AIServiceError.unknown(
                """
                AI generation completed only partially. Some request fragments still failed after retries.
                \(preview)
                """
            )
        }
    }

    private func performConversionPlanQueue(
        plans: [ConversionBatchPlan],
        targetType: AICardGenerationType,
        level: AICardGenerationLevel,
        onBatch: @escaping (AIConversionBatchChunk) async throws -> Void
    ) async throws {
        guard !plans.isEmpty else { return }

        var pendingPlans = plans
        var activeTaskCount = 0
        var activeConcurrency = min(max(maxConcurrentConversionRequests, 1), plans.count)
        var consecutiveSuccesses = 0
        var terminalFailures: [String] = []

        try await withThrowingTaskGroup(of: (ConversionBatchPlan, Result<AIConversionBatchChunk, Error>).self) { group in
            func scheduleAvailableTasks() {
                while activeTaskCount < activeConcurrency, !pendingPlans.isEmpty {
                    let plan = pendingPlans.removeFirst()
                    let sourceCards = plan.sourceCards
                    let plannedCardCount = plan.targetCards
                    let sourceLabel = plan.sourceLabel
                    activeTaskCount += 1

                    group.addTask { [self] in
                        do {
                            try Task.checkCancellation()

                            let chunk = try await withExecutionTimeout(
                                nanoseconds: conversionBatchExecutionTimeoutNanoseconds
                            ) {
                                if targetType == .match {
                                    let qualityResult = try await self.sendQualityFirstMatchConversionRequest(
                                        sourceCards: sourceCards,
                                        level: level
                                    )
                                    return AIConversionBatchChunk(
                                        outputs: qualityResult.outputs,
                                        plannedSourceIDs: sourceCards.map(\.id),
                                        plannedCardCount: plannedCardCount,
                                        shortfallCount: qualityResult.shortfallCount,
                                        sourceLabel: sourceLabel
                                    )
                                }

                                if targetType == .write {
                                    let qualityResult = try await self.sendQualityFirstWriteConversionRequest(
                                        sourceCards: sourceCards,
                                        level: level
                                    )
                                    return AIConversionBatchChunk(
                                        outputs: qualityResult.outputs,
                                        plannedSourceIDs: sourceCards.map(\.id),
                                        plannedCardCount: plannedCardCount,
                                        shortfallCount: qualityResult.shortfallCount,
                                        sourceLabel: sourceLabel
                                    )
                                }

                                let messages = self.buildConversionMessages(
                                    sourceCards: sourceCards,
                                    targetType: targetType,
                                    level: level
                                )
                                let outputs = try await self.sendConversionRequest(
                                    messages: messages,
                                    model: self.textModel,
                                    sourceCards: sourceCards,
                                    targetType: targetType
                                )
                                return AIConversionBatchChunk(
                                    outputs: outputs,
                                    plannedSourceIDs: sourceCards.map(\.id),
                                    plannedCardCount: plannedCardCount,
                                    shortfallCount: max(0, plannedCardCount - outputs.count),
                                    sourceLabel: sourceLabel
                                )
                            }

                            return (plan, .success(chunk))
                        } catch {
                            return (plan, .failure(error))
                        }
                    }
                }
            }

            scheduleAvailableTasks()

            while activeTaskCount > 0 {
                try Task.checkCancellation()

                guard let (plan, result) = try await group.next() else {
                    break
                }

                activeTaskCount -= 1

                switch result {
                case .success(let chunk):
                    consecutiveSuccesses += 1
                    try await onBatch(chunk)

                    if consecutiveSuccesses >= max(activeConcurrency, 1), activeConcurrency < maxConcurrentConversionRequests {
                        activeConcurrency += 1
                        consecutiveSuccesses = 0
                    }

                case .failure(let error):
                    consecutiveSuccesses = 0
                    activeConcurrency = max(1, activeConcurrency / 2)

                    if shouldAttemptPlanSplit(after: error), let splitPlans = plan.splitForRecovery() {
                        pendingPlans.append(contentsOf: splitPlans)
                    } else {
                        terminalFailures.append(batchFailureDescription(for: plan, error: error))
                    }
                }

                scheduleAvailableTasks()
            }
        }

        if !terminalFailures.isEmpty {
            let preview = terminalFailures.prefix(3).joined(separator: "\n")
            throw AIServiceError.unknown(
                """
                AI conversion completed only partially. Some request fragments still failed after retries.
                \(preview)
                """
            )
        }
    }

    private func normalizedAllocations(
        _ allocations: [AISourceRangeAllocation],
        segmentCount: Int
    ) -> [AISourceRangeAllocation] {
        guard segmentCount > 0 else { return [] }

        return allocations
            .sorted {
                if $0.startIndex == $1.startIndex {
                    return $0.endIndex < $1.endIndex
                }
                return $0.startIndex < $1.startIndex
            }
            .compactMap { allocation in
                let start = min(max(allocation.startIndex, 1), segmentCount)
                let end = min(max(max(allocation.endIndex, start), 1), segmentCount)
                let cardCount = max(allocation.cardCount, 1)

                return AISourceRangeAllocation(
                    id: allocation.id,
                    startIndex: start,
                    endIndex: end,
                    cardCount: cardCount
                )
            }
    }

    private func sourceLabel(for labels: [String]) -> String {
        guard let first = labels.first else { return "Selected source" }
        guard let last = labels.last, last != first else { return first }
        return "\(first) - \(last)"
    }

    private func indexed(_ plans: [TextBatchPlan]) -> [TextBatchPlan] {
        let total = plans.count
        return plans.enumerated().map { index, plan in
            TextBatchPlan(
                text: plan.text,
                sourceLabel: plan.sourceLabel,
                allocationID: plan.allocationID,
                targetCards: plan.targetCards,
                batchIndex: index + 1,
                totalBatches: total,
                passIndex: plan.passIndex
            )
        }
    }

    private func indexed(_ plans: [VisionBatchPlan]) -> [VisionBatchPlan] {
        let total = plans.count
        return plans.enumerated().map { index, plan in
            VisionBatchPlan(
                images: plan.images,
                sourceLabel: plan.sourceLabel,
                allocationID: plan.allocationID,
                targetCards: plan.targetCards,
                batchIndex: index + 1,
                totalBatches: total,
                passIndex: plan.passIndex
            )
        }
    }

    private func updateCoveredPrompts(existing: [String], with cards: [AIFlashcard]) -> [String] {
        let additions = cards.map(promptHint(from:))
        let merged = (existing + additions).filter { !$0.isEmpty }
        return Array(merged.suffix(12))
    }

    private func promptHint(from card: AIFlashcard) -> String {
        card.promptHint
    }

    private func allocationID(for plan: some RecoverableBatchPlan) -> UUID? {
        if let textPlan = plan as? TextBatchPlan {
            return textPlan.allocationID
        }
        if let visionPlan = plan as? VisionBatchPlan {
            return visionPlan.allocationID
        }
        return nil
    }

    // -------------------------------------------------------------------------
}
