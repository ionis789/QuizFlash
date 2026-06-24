import Foundation
import UIKit

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

        return try await withDebugRun(
            kind: .utility,
            targetType: "deck_title",
            sourceKind: "text",
            sourceCount: 1,
            metadata: ["source_char_count": String(trimmedText.count)]
        ) { [self] in
            try await self.sendDeckTitleRequest(
                messages: try self.buildDeckTitleMessages(fromText: trimmedText),
                model: self.textModel
            )
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
                    try await withDebugRun(
                        kind: .generation,
                        targetType: options.cardType.rawValue,
                        sourceKind: "pdf",
                        targetCount: targetCards,
                        sourceCount: 1,
                        metadata: ["source_name": pdfURL.lastPathComponent]
                    ) { [self] in
                        let result = await DocumentTextExtractor.extract(from: pdfURL)
                        try await self.routeStream(
                            result: result,
                            targetCards: targetCards,
                            options: options,
                            continuation: continuation
                        )
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
                    try await withDebugRun(
                        kind: .generation,
                        targetType: options.cardType.rawValue,
                        sourceKind: "images",
                        targetCount: targetCards,
                        sourceCount: images.count,
                        metadata: ["image_count": String(images.count)]
                    ) { [self] in
                        let result = await DocumentTextExtractor.extract(from: images)
                        try await self.routeStream(
                            result: result,
                            targetCards: targetCards,
                            options: options,
                            continuation: continuation
                        )
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
                    try await withDebugRun(
                        kind: .generation,
                        targetType: options.cardType.rawValue,
                        sourceKind: "text",
                        targetCount: targetCards,
                        sourceCount: 1,
                        metadata: ["source_char_count": String(text.count)]
                    ) { [self] in
                        try await self.dispatchTextStream(
                            text,
                            targetCards: targetCards,
                            needsOCRCorrection: false,
                            options: options,
                            continuation: continuation
                        )
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
                    let combinedText = segments
                        .map(\.text)
                        .joined(separator: "\n\n")
                    let resolvedOptions = self.resolvedGenerationOptions(
                        for: combinedText,
                        needsOCRCorrection: needsOCRCorrection,
                        base: options
                    )

                    try await withDebugRun(
                        kind: .generation,
                        targetType: resolvedOptions.cardType.rawValue,
                        sourceKind: "segments",
                        targetCount: targetCards,
                        sourceCount: segments.count,
                        metadata: [
                            "segment_count": String(segments.count),
                            "allocation_count": String(allocations.count)
                        ]
                    ) { [self] in
                        await self.trace(
                            .planPrepared,
                            "Resolved text-generation language lock.",
                            metadata: [
                                "locked_source_language": resolvedOptions.sourceLanguageHint?.displayName ?? "unresolved",
                                "locked_source_language_code": resolvedOptions.sourceLanguageHint?.languageCode ?? "unresolved",
                                "card_type": resolvedOptions.cardType.rawValue,
                                "card_level": resolvedOptions.cardLevel.rawValue
                            ]
                        )

                        try await self.performTextRequests(
                            plans: self.buildTextBatchPlans(
                                segments: segments,
                                allocations: allocations,
                                options: resolvedOptions
                            ),
                            needsOCRCorrection: needsOCRCorrection,
                            options: resolvedOptions
                        ) { chunk in
                            continuation.yield(chunk)
                            await Task.yield()
                        }
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
                    let resolvedOptions = self.resolvedVisionGenerationOptions(base: options)

                    try await withDebugRun(
                        kind: .generation,
                        targetType: resolvedOptions.cardType.rawValue,
                        sourceKind: "image_ranges",
                        targetCount: targetCards,
                        sourceCount: images.count,
                        metadata: [
                            "image_count": String(images.count),
                            "allocation_count": String(allocations.count)
                        ]
                    ) { [self] in
                        await self.trace(
                            .planPrepared,
                            "Resolved vision-generation language mode.",
                            metadata: [
                                "locked_output_language": resolvedOptions.sourceLanguageHint?.displayName ?? "auto",
                                "locked_output_language_code": resolvedOptions.sourceLanguageHint?.languageCode ?? "auto",
                                "card_type": resolvedOptions.cardType.rawValue,
                                "card_level": resolvedOptions.cardLevel.rawValue
                            ]
                        )

                        try await self.performVisionRequests(
                            plans: self.buildVisionBatchPlans(
                                images: images,
                                labels: itemLabels,
                                allocations: allocations,
                                options: resolvedOptions
                            ),
                            options: resolvedOptions
                        ) { chunk in
                            continuation.yield(chunk)
                            await Task.yield()
                        }
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
        await trace(
            .planPrepared,
            "Routed extracted source into AI pipeline.",
            metadata: [
                "extraction_method": String(describing: result.method),
                "needs_ocr_correction": String(result.needsOCRCorrection),
                "target_cards": String(targetCards),
                "card_type": options.cardType.rawValue
            ]
        )
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
        let resolvedOptions = resolvedGenerationOptions(
            for: text,
            needsOCRCorrection: needsOCRCorrection,
            base: options
        )
        var allCards: [AIFlashcard] = []
        try await performTextRequests(
            text,
            targetCards: targetCards,
            needsOCRCorrection: needsOCRCorrection,
            options: resolvedOptions
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
        let resolvedOptions = resolvedGenerationOptions(
            for: text,
            needsOCRCorrection: needsOCRCorrection,
            base: options
        )

        await trace(
            .planPrepared,
            "Resolved text-generation language lock.",
            metadata: [
                "locked_source_language": resolvedOptions.sourceLanguageHint?.displayName ?? "unresolved",
                "locked_source_language_code": resolvedOptions.sourceLanguageHint?.languageCode ?? "unresolved",
                "card_type": resolvedOptions.cardType.rawValue,
                "card_level": resolvedOptions.cardLevel.rawValue
            ]
        )

        try await performTextRequests(
            text,
            targetCards: targetCards,
            needsOCRCorrection: needsOCRCorrection,
            options: resolvedOptions
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
        let resolvedOptions = resolvedVisionGenerationOptions(base: options)
        var allCards: [AIFlashcard] = []
        try await performVisionRequests(images, targetCards: targetCards, options: resolvedOptions) { cards in
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
        let resolvedOptions = resolvedVisionGenerationOptions(base: options)

        await trace(
            .planPrepared,
            "Resolved vision-generation language mode.",
            metadata: [
                "locked_output_language": resolvedOptions.sourceLanguageHint?.displayName ?? "auto",
                "locked_output_language_code": resolvedOptions.sourceLanguageHint?.languageCode ?? "auto",
                "card_type": resolvedOptions.cardType.rawValue,
                "card_level": resolvedOptions.cardLevel.rawValue
            ]
        )

        try await performVisionRequests(images, targetCards: targetCards, options: resolvedOptions) { cards in
            continuation.yield(cards)
            await Task.yield()
        }
    }

    private func resolvedGenerationOptions(
        for text: String,
        needsOCRCorrection: Bool,
        base options: AIGenerationOptions
    ) -> AIGenerationOptions {
        var resolved = options
        resolved.sourceLanguageHint = resolvedOutputLanguage(from: options)
        return resolved
    }

    private func resolvedVisionGenerationOptions(base options: AIGenerationOptions) -> AIGenerationOptions {
        var resolved = options
        resolved.sourceLanguageHint = resolvedOutputLanguage(from: options)
        return resolved
    }

    private func resolvedOutputLanguage(from options: AIGenerationOptions) -> AIGenerationLanguageHint? {
        switch options.outputLanguageMode {
        case .auto:
            return nil
        case .manual:
            return options.manualOutputLanguage
        }
    }
}
