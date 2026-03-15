import Foundation
import UIKit // Required for UIImage – image pipeline only, no UI components used

// =============================================================================
// MARK: - AI Service Errors
// =============================================================================

public enum AIServiceError: LocalizedError {
    case invalidAPIKey
    case networkError
    case invalidResponse
    case parsingFailed
    case rateLimitExceeded
    case timeout
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .invalidAPIKey: return "Invalid API key."
        case .networkError: return "Network error."
        case .invalidResponse: return "Invalid response."
        case .parsingFailed: return "Parsing failed."
        case .rateLimitExceeded: return "Too many requests. Try again later."
        case .timeout: return "Timeout – no response from the server."
        case .unknown(let msg): return msg
        }
    }
}

// =============================================================================
// MARK: - Response DTO
// =============================================================================

/// The structured JSON contract between GPT and the app.
/// GPT returns zones as arrays — each element becomes one visual zone block.
private struct FlashcardResponseDTO: Codable {
    struct CardDTO: Codable {
        let question_zones: [String]?
        let question: String? // Fallback if question_zones are intepreted as question by AI
        let answer_zones: [String]
        let answer: [String]? // Fallback

        var resolvedQuestionZones: [String] {
            if let qz = question_zones { return qz }
            if let q = question { return [q] }
            return ["?"]
        }
    }
    let flashcards: [CardDTO]?
}

private struct DeckTitleResponseDTO: Codable {
    let deck_title: String?
}

private struct AIProviderErrorEnvelope: Decodable {
    struct APIError: Decodable {
        let message: String?
        let type: String?
        let param: String?
        let code: String?
    }

    let error: APIError?
}

// =============================================================================
// MARK: - AI Flashcard Service
// =============================================================================

public final class AIFlashcardService: @unchecked Sendable {

    // -------------------------------------------------------------------------
    // MARK: - Configuration
    // -------------------------------------------------------------------------

    private let provider: AIProviderProfile
    private let session: URLSession
    private let maxCharsPerChunk = 12_000
    private let maxConcurrentTextPlanRequests = 6
    private let maxConcurrentVisionPlanRequests = 4
    private let timeoutIntervalForRequest: TimeInterval = 360
    private let timeoutIntervalForResource: TimeInterval = 1_800
    private let maxRequestRetryCount = 4
    private let baseRetryDelayNanoseconds: UInt64 = 1_200_000_000
    private let maxRetryDelayNanoseconds: UInt64 = 12_000_000_000

    private var apiEndpoint: URL? { provider.resolvedRequestURL }
    private var textModel: String { provider.trimmedTextModel }
    private var visionModel: String { provider.trimmedVisionModel }

    private struct RetriableRequestError: Error {
        let serviceError: AIServiceError
        let retryAfter: TimeInterval?
    }

    private struct TextSourceUnit {
        let content: String
        let label: String
    }

    private protocol RecoverableBatchPlan: Sendable {
        var targetCards: Int { get }
        var sourceLabel: String { get }
        func splitForRecovery() -> [Self]?
    }

    private struct TextBatchPlan: RecoverableBatchPlan {
        let text: String
        let sourceLabel: String
        let allocationID: UUID?
        let targetCards: Int
        let batchIndex: Int
        let totalBatches: Int
        let passIndex: Int

        func splitForRecovery() -> [TextBatchPlan]? {
            guard targetCards > 1 else { return nil }
            let left = max(1, targetCards / 2)
            let right = targetCards - left
            let splitCounts = right > 0 ? [left, right] : [left]
            return splitCounts.map { count in
                TextBatchPlan(
                    text: text,
                    sourceLabel: sourceLabel,
                    allocationID: allocationID,
                    targetCards: count,
                    batchIndex: batchIndex,
                    totalBatches: totalBatches,
                    passIndex: passIndex
                )
            }
        }
    }

    private struct VisionBatchPlan: RecoverableBatchPlan, @unchecked Sendable {
        let images: [UIImage]
        let sourceLabel: String
        let allocationID: UUID?
        let targetCards: Int
        let batchIndex: Int
        let totalBatches: Int
        let passIndex: Int

        func splitForRecovery() -> [VisionBatchPlan]? {
            guard targetCards > 1 else { return nil }
            let left = max(1, targetCards / 2)
            let right = targetCards - left
            let splitCounts = right > 0 ? [left, right] : [left]
            return splitCounts.map { count in
                VisionBatchPlan(
                    images: images,
                    sourceLabel: sourceLabel,
                    allocationID: allocationID,
                    targetCards: count,
                    batchIndex: batchIndex,
                    totalBatches: totalBatches,
                    passIndex: passIndex
                )
            }
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

    init(provider: AIProviderProfile) {
        self.provider = provider
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeoutIntervalForRequest
        config.timeoutIntervalForResource = timeoutIntervalForResource
        config.waitsForConnectivity = true
        session = URLSession(configuration: config)
    }

    // -------------------------------------------------------------------------
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

                return try await sendRequest(messages: messages, model: textModel)
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

                return try await sendRequest(messages: messages, model: visionModel)
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

        while remaining > 0 {
            let next = min(batchSize, remaining)
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
        execute: @escaping @Sendable (Plan, [String]) async throws -> [AIFlashcard],
        onBatch: @escaping (AIFlashcardBatchChunk) async throws -> Void
    ) async throws {
        guard !plans.isEmpty else { return }

        var pendingPlans = plans
        var coveredPrompts: [String] = []
        var activeTaskCount = 0
        var activeConcurrency = min(max(maxConcurrent, 1), plans.count)
        var consecutiveSuccesses = 0
        var terminalFailures: [String] = []

        try await withThrowingTaskGroup(of: (Plan, Result<[AIFlashcard], Error>).self) { group in
            func scheduleAvailableTasks() {
                while activeTaskCount < activeConcurrency, !pendingPlans.isEmpty {
                    let plan = pendingPlans.removeFirst()
                    let promptSnapshot = coveredPrompts
                    activeTaskCount += 1

                    group.addTask {
                        do {
                            try Task.checkCancellation()
                            let cards = try await execute(plan, promptSnapshot)
                            return (plan, .success(cards))
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
                case .success(let cards):
                    consecutiveSuccesses += 1

                    if !cards.isEmpty {
                        try await onBatch(
                            AIFlashcardBatchChunk(
                                cards: cards,
                                allocationID: allocationID(for: plan),
                                plannedCardCount: plan.targetCards,
                                sourceLabel: plan.sourceLabel
                            )
                        )
                        coveredPrompts = updateCoveredPrompts(existing: coveredPrompts, with: cards)
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
        card.question
            .replacingOccurrences(of: AIZoneParser.zoneDelimiter, with: " / ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
    // MARK: - Message Builders
    // -------------------------------------------------------------------------

    nonisolated private func buildTextMessages(
        text: String,
        targetCards: Int,
        needsOCRCorrection: Bool,
        options: AIGenerationOptions,
        sourceLabel: String,
        batchIndex: Int,
        totalBatches: Int,
        passIndex: Int,
        coveredPrompts: [String]
    ) -> [[String: Any]] {
        [
            ["role": "system", "content": systemPrompt(targetCards: targetCards, isOCR: needsOCRCorrection, options: options)],
            ["role": "user", "content": buildTextUserMessage(
                text: text,
                targetCards: targetCards,
                sourceLabel: sourceLabel,
                batchIndex: batchIndex,
                totalBatches: totalBatches,
                passIndex: passIndex,
                coveredPrompts: coveredPrompts
            )]
        ]
    }

    nonisolated private func buildVisionMessages(
        images: [UIImage],
        targetCards: Int,
        options: AIGenerationOptions,
        sourceLabel: String,
        batchIndex: Int,
        totalBatches: Int,
        passIndex: Int,
        coveredPrompts: [String]
    ) -> [[String: Any]] {
        var userContent: [[String: Any]] = [
            ["type": "text", "text": buildVisionUserMessage(
                targetCards: targetCards,
                sourceLabel: sourceLabel,
                batchIndex: batchIndex,
                totalBatches: totalBatches,
                passIndex: passIndex,
                coveredPrompts: coveredPrompts
            )]
        ]
        for image in images {
            guard let data = image.jpegData(compressionQuality: 0.7) else { continue }
            userContent.append([
                "type": "image_url",
                "image_url": ["url": "data:image/jpeg;base64,\(data.base64EncodedString())", "detail": "auto"]
            ])
        }
        return [
            ["role": "system", "content": systemPrompt(targetCards: targetCards, isOCR: false, options: options)],
            ["role": "user", "content": userContent]
        ]
    }

    nonisolated private func buildDeckTitleMessages(fromText text: String) -> [[String: Any]] {
        [
            ["role": "system", "content": deckTitleSystemPrompt()],
            ["role": "user", "content": deckTitleUserMessage(fromText: text)]
        ]
    }

    nonisolated private func buildTextUserMessage(
        text: String,
        targetCards: Int,
        sourceLabel: String,
        batchIndex: Int,
        totalBatches: Int,
        passIndex: Int,
        coveredPrompts: [String]
    ) -> String {
        var message = """
        GENERATION CONTEXT
        - Batch \(batchIndex) of \(totalBatches)
        - Source coverage: \(sourceLabel)
        - Generate EXACTLY \(targetCards) cards from this source segment only.
        - Focus on distinct concepts from this segment. Avoid vague overview cards.
        - Avoid repeating the same wording or concept inside this batch.
        """

        if passIndex > 1 {
            message += "\n- This source has already been used before. Cover NEW concepts or a noticeably different angle."
        }

        if !coveredPrompts.isEmpty {
            message += "\n- Avoid overlapping these already-covered prompts when possible:"
            for covered in coveredPrompts.prefix(6) {
                message += "\n  • \(covered)"
            }
        }

        message += "\n\nSOURCE TEXT:\n\n\(text)"
        return message
    }

    nonisolated private func buildVisionUserMessage(
        targetCards: Int,
        sourceLabel: String,
        batchIndex: Int,
        totalBatches: Int,
        passIndex: Int,
        coveredPrompts: [String]
    ) -> String {
        var message = """
        Analyze only the attached source pages/images and generate EXACTLY \(targetCards) cards.
        Batch \(batchIndex) of \(totalBatches).
        Source coverage: \(sourceLabel).
        Focus on distinct concepts from these specific pages/images.
        """

        if passIndex > 1 {
            message += "\nThis source group has already been used in an earlier pass. Cover new concepts or a clearly different angle."
        }

        if !coveredPrompts.isEmpty {
            message += "\nAvoid overlapping these already-covered prompts when possible:"
            for covered in coveredPrompts.prefix(6) {
                message += "\n- \(covered)"
            }
        }

        return message
    }

    // =========================================================================
    // MARK: - System Prompt
    // =========================================================================
    //
    // DESIGN PRINCIPLES:
    //   • GPT returns zones as string arrays, not a single block of text
    //   • Each array element = one visual zone block in the app
    //   • Clear splitting rules: when to use 1 zone vs multiple
    //   • Explicit LaTeX escaping rules with CONCRETE before/after examples
    //   • Math always in $...$ or $$...$$, never raw
    //   • The LaTeX escaping section uses a concrete "LOOK AT THIS OUTPUT"
    //     style to prevent GPT from over-thinking the escaping.
    //
    // =========================================================================

    nonisolated private func systemPrompt(
        targetCards: Int,
        isOCR: Bool,
        options: AIGenerationOptions
    ) -> String {
        var prompt = #"""
        You are a rigorous University Professor AI specialized in generating elite, in-depth "Active Recall" flashcards.
        Your absolute priority is TECHNICAL DEPTH, ACCURACY, and HIGH READABILITY.
        
        Output STRICTLY valid JSON with EXACTLY \#(targetCards) flashcards.
        
        ═══════════════════════════════════════════════════════
        REQUIRED JSON SCHEMA (CRITICAL - DO NOT ALTER)
        ═══════════════════════════════════════════════════════
        You MUST output valid JSON matching EXACTLY this schema:
        {
          "flashcards": [
            {
              "question_zones": ["string1", "string2"],
              "answer_zones": ["string1", "string2", "string3"]
            }
          ]
        }
        STRICT RULE: NEVER use the key "question" or "answer". You MUST use EXACTLY "question_zones" and "answer_zones" as ARRAYS of strings.
        
        ═══════════════════════════════════════════════════════
        LANGUAGE RULE (CRITICAL)
        ═══════════════════════════════════════════════════════
        You MUST EXACTLY match the language of the source text. If the source text is in language X, the flashcards MUST be written in language X. Do not translate concepts to English.
        Detect the dominant language from the actual teaching material before writing.
        NEVER mix languages across cards unless the source itself explicitly mixes them.
        NEVER default to English because of model preference or technical terminology.
        If the source is X language, the flashcards MUST be fully in X language.
        
        ═══════════════════════════════════════════════════════
        ZONE SPLITTING & READABILITY
        ═══════════════════════════════════════════════════════
        You MUST break long content into multiple readable, atomic visual zones using the JSON arrays.
        Do not create "walls of text". Instead of cramming everything into one long string, split the information logically into as many zones as needed:
        
        RULE: Code MUST ALWAYS be in its own standalone string.
        RULE: Block equations ($$) MUST ALWAYS be in their own standalone string.
        
        ❌ BAD EXAMPLE (Wall of text, mixed code - DO NOT DO THIS):
        "answer_zones": [
          "The Singleton pattern restricts instantiation. Here is the code: public class Singleton { private static Singleton instance; }"
        ]
        
        ✅ GOOD EXAMPLE (Split into logical, readable zones - DO THIS EXACTLY):
        "answer_zones": [
          "The **Singleton** pattern restricts instantiation by using a private constructor.",
          "The instance is created lazily, meaning it is only instantiated when first requested.",
          "```java\npublic class Singleton {\n    private static Singleton instance;\n    private Singleton() {}\n}\n```"
        ]
        
        ═══════════════════════════════════════════════════════
        FORMATTING RULES (STRICT)
        ═══════════════════════════════════════════════════════
        - TEXT HIGHLIGHTS: Highlight all crucial concepts using double asterisks (e.g., "**Encapsulation**").
        - INLINE CODE: Use single backticks (`) for short syntax, class names, or technical terms (e.g., `new`, `String`).
        - INLINE MATH: Wrap every math symbol, variable, and inline equation in single $. Example: "$v \in V$", "$\dim(V)$".
        - BLOCK MATH: Wrap display equations in double $$. NEVER use ```math or ```latex fences for equations.
        - BLOCK CODE: Triple-backtick code blocks MUST be in their own standalone string in the array.
        
        ═══════════════════════════════════════════════════════
        LATEX ESCAPING IN JSON — READ THIS VERY CAREFULLY
        ═══════════════════════════════════════════════════════
        You are writing JSON. JSON strings use backslash (\) as an escape character.
        Therefore, to produce ONE backslash in the final text, you must write TWO backslashes in the JSON.
        
        THE RULE IS SIMPLE:
          Every LaTeX command that starts with one backslash must be written with EXACTLY two backslashes in your JSON output.
        
        COPY THESE EXAMPLES EXACTLY — do not add more backslashes:
        
          LaTeX you want   →   What you write in the JSON string
          ─────────────────────────────────────────────────────
          \lambda          →   \\lambda
          \frac{a}{b}      →   \\frac{a}{b}
          \in              →   \\in
          \mathbb{R}       →   \\mathbb{R}
          \forall          →   \\forall
          \sum_{i=1}^{n}   →   \\sum_{i=1}^{n}
          \begin{pmatrix}  →   \\begin{pmatrix}
          \end{pmatrix}    →   \\end{pmatrix}
          \text{some text} →   \\text{some text}
        
        ❌ WRONG (under-escaped — JSON will break):
          "answer_zones": ["$\lambda + \mu$"]
        
        ❌ WRONG (over-escaped — LaTeX will break):
          "answer_zones": ["$\\\\lambda + \\\\mu$"]
        
        ✅ CORRECT:
          "answer_zones": ["$\\lambda + \\mu$"]
        
        NEVER write four backslashes (\\\\) before a LaTeX command. Always exactly two (\\).
        """#

        if isOCR {
            prompt += """
        
        ═══════════════════════════════════════════════════════
        OCR CORRECTION MODE ENABLED
        ═══════════════════════════════════════════════════════
        Repair corrupted code syntax, broken LaTeX, and misrecognized symbols (e.g., 0/O, 1/l, alpha/a). Preserve strict technical correctness.
        """
        }

        prompt += cardTypePromptAddition(for: options.cardType)
        prompt += cardLevelPromptAddition(for: options.cardLevel)

        return prompt
    }

    nonisolated private func deckTitleSystemPrompt() -> String {
        #"""
        You are a precise academic assistant that creates short deck titles.

        Output STRICTLY valid JSON matching EXACTLY this schema:
        {
          "deck_title": "string"
        }

        RULES:
        - The title MUST be in the same dominant language as the source text.
        - Never translate the title to English unless the source is actually in English.
        - Keep it short: ideally 2 to 5 words.
        - Make it specific to the topic, not generic.
        - Do not add quotes, emojis, subtitles, colons, or extra commentary.
        - Return ONLY the JSON object.
        """#
    }

    nonisolated private func deckTitleUserMessage(fromText text: String) -> String {
        """
        Read the sampled source text below and infer a short deck title.

        SAMPLE SOURCE:
        \(text)
        """
    }

    nonisolated private func cardTypePromptAddition(for type: AICardGenerationType) -> String {
        switch type {
        case .flashcards:
            return """

        ═══════════════════════════════════════════════════════
        CARD TYPE PROFILE — FLASH CARDS
        ═══════════════════════════════════════════════════════
        Generate classic active-recall cards with a strong question on the front and a high-signal answer on the back.
        Prefer one core concept, mechanism, theorem, or tightly related cluster per card.
        """
        case .match:
            return """

        ═══════════════════════════════════════════════════════
        CARD TYPE PROFILE — MATCH CARDS
        ═══════════════════════════════════════════════════════
        These cards must remain easy to pair in match mode.
        The front should usually be a short term, prompt, event, notation, formula name, or compact cue.
        The back should be the direct counterpart only: concise definition, association, mapping, or result.
        Avoid essay-style answers unless the source makes that unavoidable.
        """
        case .quiz:
            return """

        ═══════════════════════════════════════════════════════
        CARD TYPE PROFILE — QUIZ CARDS
        ═══════════════════════════════════════════════════════
        Each question must behave like a multiple-choice quiz item while still using the required JSON schema.
        question_zones MUST contain:
        1. the quiz stem
        2. exactly four answer options as separate readable zones
        Exactly one option must be correct.
        answer_zones MUST begin with the exact correct option, then add a short explanation. Distractors must be plausible.
        """
        case .write:
            return """

        ═══════════════════════════════════════════════════════
        CARD TYPE PROFILE — WRITE CARDS
        ═══════════════════════════════════════════════════════
        These cards are intended for typed recall.
        question_zones should ask for an exact answer, derivation step, definition, formula, or short structured response.
        answer_zones MUST begin with the canonical expected answer.
        When useful, add one extra zone for accepted variants, precision notes, or grading cues.
        """
        }
    }

    nonisolated private func cardLevelPromptAddition(for level: AICardGenerationLevel) -> String {
        switch level {
        case .simple:
            return """

        ═══════════════════════════════════════════════════════
        CARD LEVEL PROFILE — SIMPLE
        ═══════════════════════════════════════════════════════
        Keep the wording accessible and direct.
        Focus on the clearest core facts, definitions, and cause-effect relations.
        Avoid overly layered answers unless absolutely necessary.
        """
        case .balanced:
            return """

        ═══════════════════════════════════════════════════════
        CARD LEVEL PROFILE — BALANCED
        ═══════════════════════════════════════════════════════
        Keep the current prompt style balance: clear, technically correct, and moderately detailed.
        """
        case .advanced:
            return """

        ═══════════════════════════════════════════════════════
        CARD LEVEL PROFILE — ADVANCED
        ═══════════════════════════════════════════════════════
        Prefer deeper reasoning, nuance, caveats, mechanisms, proofs, and higher-order distinctions whenever the source supports them.
        Questions should test understanding, not just memorized wording.
        """
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Network
    // -------------------------------------------------------------------------

    private func sendRequest(messages: [[String: Any]], model: String) async throws -> [AIFlashcard] {
        try await performRetriableJSONRequest(messages: messages, model: model) { [self] data in
            let content = try self.parseResponseContent(from: data)
            return try self.decodeFlashcards(from: content)
        }
    }

    private func sendDeckTitleRequest(
        messages: [[String: Any]],
        model: String
    ) async throws -> String? {
        return try await performRetriableJSONRequest(messages: messages, model: model) { [self] data in
            let content = try self.parseResponseContent(from: data)
            let decoded = try JSONDecoder().decode(DeckTitleResponseDTO.self, from: Data(content.utf8))
            return decoded.deck_title?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func performRetriableJSONRequest<T>(
        messages: [[String: Any]],
        model: String,
        parser: @escaping (Data) throws -> T
    ) async throws -> T {
        guard let url = apiEndpoint else { throw AIServiceError.networkError }
        let apiKey = try resolvedAPIKey()

        var lastServiceError: AIServiceError?

        for attempt in 0...maxRequestRetryCount {
            try Task.checkCancellation()

            do {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                applyStandardHeaders(to: &request, apiKey: apiKey)

                let body = requestBody(messages: messages, model: model)
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw AIServiceError.invalidResponse
                }
                guard (200...299).contains(http.statusCode) else {
                    throw httpError(from: http, data: data)
                }

                return try parser(data)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as RetriableRequestError {
                lastServiceError = error.serviceError
                guard attempt < maxRequestRetryCount else {
                    throw error.serviceError
                }
                try await sleepBeforeRetry(attempt: attempt, retryAfter: error.retryAfter)
            } catch let error as AIServiceError {
                lastServiceError = error
                guard attempt < maxRequestRetryCount, shouldRetry(error) else {
                    throw error
                }
                try await sleepBeforeRetry(attempt: attempt, retryAfter: nil)
            } catch let error as URLError {
                let serviceError = mapURLSessionError(error)
                lastServiceError = serviceError
                guard attempt < maxRequestRetryCount, shouldRetry(serviceError) else {
                    throw serviceError
                }
                try await sleepBeforeRetry(attempt: attempt, retryAfter: nil)
            } catch {
                lastServiceError = .networkError
                guard attempt < maxRequestRetryCount else {
                    throw AIServiceError.networkError
                }
                try await sleepBeforeRetry(attempt: attempt, retryAfter: nil)
            }
        }

        throw lastServiceError ?? .networkError
    }

    private func resolvedAPIKey() throws -> String {
        let trimmedAPIKey = provider.trimmedAPIKey
        guard !trimmedAPIKey.isEmpty else { throw AIServiceError.invalidAPIKey }
        return trimmedAPIKey
    }

    private func applyStandardHeaders(to request: inout URLRequest, apiKey: String) {
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let referer = provider.httpRefererURL?.absoluteString, !referer.isEmpty {
            request.setValue(referer, forHTTPHeaderField: "HTTP-Referer")
        }

        let title = provider.trimmedXTitle
        if !title.isEmpty {
            request.setValue(title, forHTTPHeaderField: "X-Title")
        }
    }

    private func requestBody(messages: [[String: Any]], model: String) -> [String: Any] {
        switch provider.requestStyle {
        case .openAICompatible:
            var body: [String: Any] = [
                "model": model,
                "messages": messages,
                "response_format": ["type": "json_object"]
            ]

            if supportsTemperatureParameter(for: model) {
                body["temperature"] = 0.2
            }

            if let extraBody = provider.extraBodyObject {
                body.merge(extraBody) { _, new in new }
            }

            return body
        }
    }

    private func shouldRetry(_ error: AIServiceError) -> Bool {
        switch error {
        case .networkError, .invalidResponse, .parsingFailed, .rateLimitExceeded, .timeout:
            return true
        case .invalidAPIKey:
            return false
        case .unknown(let message):
            if message.contains("HTTP 408") || message.contains("HTTP 409") || message.contains("HTTP 425") ||
                message.contains("HTTP 429") || message.contains("HTTP 500") || message.contains("HTTP 502") ||
                message.contains("HTTP 503") || message.contains("HTTP 504") {
                return true
            }
            return false
        }
    }

    private func shouldAttemptPlanSplit(after error: Error) -> Bool {
        if let retriable = error as? RetriableRequestError {
            return shouldRetry(retriable.serviceError)
        }

        if let serviceError = error as? AIServiceError {
            return shouldRetry(serviceError)
        }

        if error is URLError {
            return true
        }

        return false
    }

    private func mapURLSessionError(_ error: URLError) -> AIServiceError {
        switch error.code {
        case .timedOut:
            return .timeout
        case .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .dnsLookupFailed, .notConnectedToInternet, .internationalRoamingOff, .callIsActive, .dataNotAllowed:
            return .networkError
        default:
            return .networkError
        }
    }

    private func httpError(from response: HTTPURLResponse, data: Data) -> Error {
        let message = apiErrorMessage(from: data, statusCode: response.statusCode)
        let retryAfter = retryAfterInterval(from: response)

        switch response.statusCode {
        case 401, 403:
            return AIServiceError.invalidAPIKey
        case 408:
            return RetriableRequestError(serviceError: .timeout, retryAfter: retryAfter)
        case 429:
            return RetriableRequestError(serviceError: .rateLimitExceeded, retryAfter: retryAfter)
        case 500, 502, 503, 504:
            return RetriableRequestError(serviceError: .unknown(message), retryAfter: retryAfter)
        default:
            return AIServiceError.unknown(message)
        }
    }

    private func retryAfterInterval(from response: HTTPURLResponse) -> TimeInterval? {
        guard let rawValue = response.value(forHTTPHeaderField: "Retry-After") else {
            return nil
        }

        if let seconds = TimeInterval(rawValue), seconds > 0 {
            return seconds
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"

        guard let date = formatter.date(from: rawValue) else {
            return nil
        }

        return max(date.timeIntervalSinceNow, 0)
    }

    private func sleepBeforeRetry(attempt: Int, retryAfter: TimeInterval?) async throws {
        let delayNanoseconds: UInt64

        if let retryAfter, retryAfter > 0 {
            delayNanoseconds = UInt64(retryAfter * 1_000_000_000)
        } else {
            let exponentialMultiplier = pow(2.0, Double(attempt))
            let exponentialDelay = UInt64(Double(baseRetryDelayNanoseconds) * exponentialMultiplier)
            let jitter = UInt64.random(in: 0...400_000_000)
            delayNanoseconds = min(exponentialDelay + jitter, maxRetryDelayNanoseconds)
        }

        try await Task.sleep(nanoseconds: delayNanoseconds)
    }

    private func batchFailureDescription<Plan: RecoverableBatchPlan>(for plan: Plan, error: Error) -> String {
        let baseDescription: String

        if let serviceError = error as? AIServiceError {
            baseDescription = serviceError.localizedDescription
        } else if let retriable = error as? RetriableRequestError {
            baseDescription = retriable.serviceError.localizedDescription
        } else if let urlError = error as? URLError {
            baseDescription = mapURLSessionError(urlError).localizedDescription
        } else {
            baseDescription = error.localizedDescription
        }

        return "• \(plan.sourceLabel) — \(plan.targetCards) cards: \(baseDescription)"
    }

    // -------------------------------------------------------------------------
    // MARK: - Response Parsing
    // -------------------------------------------------------------------------

    private func parseResponseContent(from data: Data) throws -> String {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any]
        else {
            throw AIServiceError.parsingFailed
        }

        if let content = message["content"] as? String {
            return content
        }

        if let contentParts = message["content"] as? [[String: Any]] {
            let text = contentParts.compactMap { part -> String? in
                if let text = part["text"] as? String { return text }
                return nil
            }
            .joined(separator: "\n")

            if !text.isEmpty {
                return text
            }
        }

        throw AIServiceError.parsingFailed
    }

    private func supportsTemperatureParameter(for model: String) -> Bool {
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !normalized.hasPrefix("gpt-5")
    }

    private func apiErrorMessage(from data: Data, statusCode: Int) -> String {
        if
            let decoded = try? JSONDecoder().decode(AIProviderErrorEnvelope.self, from: data),
            let message = decoded.error?.message?.trimmingCharacters(in: .whitespacesAndNewlines),
            !message.isEmpty
        {
            return "\(provider.trimmedName) HTTP \(statusCode): \(message)"
        }

        if
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = object["error"] as? [String: Any],
            let message = error["message"] as? String,
            !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return "\(provider.trimmedName) HTTP \(statusCode): \(message)"
        }

        if
            let raw = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty
        {
            return "\(provider.trimmedName) HTTP \(statusCode): \(raw)"
        }

        return "\(provider.trimmedName) HTTP \(statusCode)"
    }

    private func decodeFlashcards(from jsonString: String) throws -> [AIFlashcard] {
        // Strip markdown code fences if present (shouldn't happen with json_object mode, but defensive)
        print("═══════════════════════════════════")
        print("📦 RAW GPT JSON:")
        print(jsonString)
        print("═══════════════════════════════════")
        var clean = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)

        if clean.hasPrefix("```json") {
            clean = String(clean.dropFirst(7))
        } else if clean.hasPrefix("```") {
            clean = String(clean.dropFirst(3))
        }
        if clean.hasSuffix("```") {
            clean = String(clean.dropLast(3))
        }

        clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)

        clean = fixLatexEscaping(in: clean)
        guard let data = clean.data(using: .utf8) else {
            throw AIServiceError.parsingFailed
        }

        do {
            let dto = try JSONDecoder().decode(FlashcardResponseDTO.self, from: data)
            guard let cards = dto.flashcards, !cards.isEmpty else {
                throw AIServiceError.parsingFailed
            }

            return cards.map { card in
                // Use resolvedQuestionZones instead of question_zones for robust fallback handling
                let questionZones = card.resolvedQuestionZones
                    .map { AIZoneParser.sanitizeLatex($0) }
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

                let answerZones = card.answer_zones
                    .map { AIZoneParser.sanitizeLatex($0) }
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

                let question = questionZones.joined(separator: AIZoneParser.zoneDelimiter)
                let answer = answerZones.joined(separator: AIZoneParser.zoneDelimiter)

                return AIFlashcard(
                    id: UUID(),
                    question: question.isEmpty ? card.resolvedQuestionZones.joined(separator: " ") : question,
                    answer: answer.isEmpty ? card.answer_zones.joined(separator: " "): answer
                )
            }
        } catch {
            print("❌ JSON DECODE ERROR: \(error)")
            print("📦 RAW JSON FROM GPT:\n\(clean)")
            throw AIServiceError.parsingFailed
        }
    }
    // -------------------------------------------------------------------------
    // MARK: - LaTeX JSON Escape Fixer  (runs on RAW JSON string, before JSONDecoder)
    // -------------------------------------------------------------------------

    /// GPT sometimes writes LaTeX commands with a SINGLE backslash inside JSON
    /// (e.g. `\lambda`), which is an invalid JSON escape sequence.  JSONDecoder
    /// would either throw or silently drop the backslash, producing `lambda`.
    ///
    /// This function runs on the raw JSON TEXT (before decoding) and ensures
    /// every LaTeX command has exactly two backslashes (\\command), so that
    /// after JSONDecoder the Swift String contains the correct single \command.
    ///
    /// Strategy:
    ///   • Regex: find a single backslash (not preceded by another backslash)
    ///     followed by a known LaTeX command name.
    ///   • Replace with \\command.
    ///
    /// Over-escaping (\\\\command → \\command) is handled POST-decode in
    /// AIZoneParser.fixOverescapedLatex(), which is simpler and safer there.
    private func fixLatexEscaping(in jsonString: String) -> String {
        // Comprehensive list — all common LaTeX math commands.
        // Grouped for readability; order does not matter for the regex.
        let commands = [
            // Greek lowercase
            "alpha", "beta", "gamma", "delta", "epsilon", "varepsilon",
            "zeta", "eta", "theta", "vartheta", "iota", "kappa", "lambda",
            "mu", "nu", "xi", "pi", "varpi", "rho", "varrho", "sigma",
            "varsigma", "tau", "upsilon", "phi", "varphi", "chi", "psi", "omega",
            // Greek uppercase
            "Gamma", "Delta", "Theta", "Lambda", "Xi", "Pi", "Sigma",
            "Upsilon", "Phi", "Psi", "Omega",
            // Arrows
            "to", "rightarrow", "Rightarrow", "leftarrow", "Leftarrow",
            "leftrightarrow", "Leftrightarrow", "mapsto", "hookrightarrow",
            "nrightarrow", "nRightarrow", "uparrow", "downarrow",
            "nearrow", "searrow", "swarrow", "nwarrow",
            // Set / logic
            "in", "notin", "ni", "subset", "subseteq", "supset", "supseteq",
            "cup", "cap", "bigcup", "bigcap", "setminus", "emptyset",
            "forall", "exists", "nexists", "neg", "lnot", "wedge", "vee",
            "land", "lor", "Rightarrow", "Leftrightarrow", "equiv",
            // Relations / comparison
            "leq", "geq", "neq", "approx", "sim", "simeq", "cong",
            "ll", "gg", "prec", "succ", "perp", "parallel", "mid", "nmid",
            // Operators
            "cdot", "times", "div", "oplus", "otimes", "circ", "bullet",
            "pm", "mp", "star", "ast", "dagger", "ddagger",
            // Big operators
            "sum", "prod", "coprod", "int", "oint", "iint", "iiint",
            "bigoplus", "bigotimes", "bigsqcup", "biguplus", "bigvee", "bigwedge",
            // Fractions / roots
            "frac", "dfrac", "tfrac", "cfrac", "sqrt", "over",
            // Delimiters
            "left", "right", "langle", "rangle", "lfloor", "rfloor",
            "lceil", "rceil", "lbrace", "rbrace", "vert", "Vert",
            // Dots
            "ldots", "cdots", "vdots", "ddots", "dots",
            // Functions (math mode)
            "sin", "cos", "tan", "cot", "sec", "csc",
            "arcsin", "arccos", "arctan",
            "sinh", "cosh", "tanh",
            "log", "ln", "exp", "lim", "limsup", "liminf",
            "sup", "inf", "max", "min", "gcd", "lcm", "det",
            "ker", "dim", "deg", "hom", "arg", "Pr", "mod",
            // Accents / decorators
            "hat", "bar", "tilde", "vec", "dot", "ddot", "widetilde",
            "widehat", "overline", "underline", "overbrace", "underbrace",
            "overset", "underset",
            // Environments / structure
            "begin", "end", "text", "mathrm", "mathbf", "mathbb", "mathcal",
            "mathit", "mathsf", "mathtt", "boldsymbol", "operatorname",
            "textbf", "textit", "texttt",
            // Spacing
            "quad", "qquad",
            // Misc math
            "infty", "partial", "nabla", "triangle", "angle", "measuredangle",
            "prime", "backslash", "textbackslash",
            "not", "iff", "implies", "therefore", "because",
            "rank", "span", "trace", "tr", "sgn", "sign",
            "colon", "coloneq", "eqcolon",
            "flat", "natural", "sharp",
            "Re", "Im", "top", "bot", "ell",
            // Matrix environments
            "pmatrix", "bmatrix", "vmatrix", "Vmatrix", "matrix",
            "cases", "aligned", "align", "gather", "equation",
            "array", "substack",
            // Display layout
            "displaystyle", "textstyle", "scriptstyle", "scriptscriptstyle",
            "limits", "nolimits",
            "label", "tag", "nonumber",
        ].joined(separator: "|")

        // Match a SINGLE backslash (not preceded by another backslash)
        // followed immediately by one of the command names, at a word boundary.
        let pattern = #"(?<!\\)\\(?!\\)(\#(commands))\b"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return jsonString
        }

        let range = NSRange(jsonString.startIndex..., in: jsonString)
        // Replace \command → \\command (valid JSON escape)
        return regex.stringByReplacingMatches(
            in: jsonString,
            options: [],
            range: range,
            withTemplate: #"\\\\$1"#
        )
    }
}
