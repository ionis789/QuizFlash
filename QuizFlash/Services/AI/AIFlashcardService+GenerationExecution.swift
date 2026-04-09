import Foundation
import UIKit
import SwiftData

extension AIFlashcardService {
    func performTextRequests(
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

    func performTextRequests(
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

    func performTextRequests(
        plans: [TextBatchPlan],
        needsOCRCorrection: Bool,
        options: AIGenerationOptions,
        onBatch: @escaping (AIFlashcardBatchChunk) async throws -> Void
    ) async throws {
        if options.cardType == .match {
            try await performPlanQueue(
                plans: plans,
                maxConcurrent: min(maxConcurrentMatchGenerationRequests, maxConcurrentTextPlanRequests),
                execute: { [self] plan, coveredPrompts in
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
                        shortfallCount: result.shortfallCount,
                        matchDiagnostics: result.diagnostics
                    )
                },
                onBatch: onBatch
            )
            return
        }

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

                return GeneratedBatchExecutionResult(
                    cards: try await sendRequest(messages: messages, model: textModel, options: options),
                    shortfallCount: 0,
                    matchDiagnostics: nil
                )
            },
            onBatch: onBatch
        )
    }

    func performVisionRequests(
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

    func performVisionRequests(
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

    func performVisionRequests(
        plans: [VisionBatchPlan],
        options: AIGenerationOptions,
        onBatch: @escaping (AIFlashcardBatchChunk) async throws -> Void
    ) async throws {
        if options.cardType == .match {
            try await performPlanQueue(
                plans: plans,
                maxConcurrent: min(maxConcurrentMatchGenerationRequests, maxConcurrentVisionPlanRequests),
                execute: { [self] plan, coveredPrompts in
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
                        shortfallCount: result.shortfallCount,
                        matchDiagnostics: result.diagnostics
                    )
                },
                onBatch: onBatch
            )
            return
        }

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

                return GeneratedBatchExecutionResult(
                    cards: try await sendRequest(messages: messages, model: visionModel, options: options),
                    shortfallCount: 0,
                    matchDiagnostics: nil
                )
            },
            onBatch: onBatch
        )
    }

    func performSequentialMatchTextRequests(
        plans: [TextBatchPlan],
        needsOCRCorrection: Bool,
        options: AIGenerationOptions,
        onBatch: @escaping (AIFlashcardBatchChunk) async throws -> Void
    ) async throws {
        guard !plans.isEmpty else { return }

        var coveredPrompts: [String] = []
        var approvedExamples: [String] = []
        var overlapHints: [String] = []
        var acceptedPairKeys: Set<String> = []
        var acceptedCards: [AIFlashcard] = []

        for plan in plans {
            try Task.checkCancellation()
            let scope = traceScope(for: plan, operation: "match_generation_batch")
            let existingPairKeys = acceptedPairKeys
            await debugTraceStore.record(
                stage: .batchStarted,
                message: "Starting sequential Match text batch.",
                scope: scope,
                metadata: ["needs_ocr_correction": String(needsOCRCorrection)]
            )

            let result = try await withTraceScope(scope) { [self] in
                try await self.sendQualityFirstMatchGenerationRequest(
                    targetCards: plan.targetCards,
                    model: self.textModel,
                    options: options,
                    existingPairKeys: existingPairKeys
                ) { requestedCards, retryHints in
                    self.buildTextMessages(
                        text: plan.text,
                        targetCards: requestedCards,
                        needsOCRCorrection: needsOCRCorrection,
                        options: options,
                        sourceLabel: plan.sourceLabel,
                        batchIndex: plan.batchIndex,
                        totalBatches: plan.totalBatches,
                        passIndex: plan.passIndex,
                        coveredPrompts: coveredPrompts + retryHints,
                        approvedMatchExamples: approvedExamples,
                        matchOverlapHints: overlapHints
                    )
                }
            }

            if !result.cards.isEmpty || result.shortfallCount > 0 {
                try await onBatch(
                    AIFlashcardBatchChunk(
                        cards: result.cards,
                        allocationID: plan.allocationID,
                        plannedCardCount: plan.targetCards,
                        shortfallCount: result.shortfallCount,
                        sourceLabel: plan.sourceLabel,
                        matchDiagnostics: result.diagnostics
                    )
                )
            }

            acceptedCards.append(contentsOf: result.cards)
            acceptedPairKeys.formUnion(
                result.cards.compactMap { card in
                    guard case .match(let content) = card.content else { return nil }
                    return matchPairKey(prompt: content.prompt, answer: content.answer)
                }
            )
            coveredPrompts = updateCoveredPrompts(existing: coveredPrompts, with: result.cards)
            approvedExamples = formattedStrongMatchApprovedExamples(from: acceptedCards)
            overlapHints = formattedMatchOverlapHints(from: acceptedCards)
            await debugTraceStore.record(
                stage: .batchCompleted,
                message: "Completed sequential Match text batch.",
                scope: scope,
                metadata: [
                    "accepted_cards": String(result.cards.count),
                    "shortfall_count": String(result.shortfallCount),
                    "low_quality_accepted": String(result.diagnostics.lowQualityAcceptedCount)
                ]
            )
        }
    }

    func performSequentialMatchVisionRequests(
        plans: [VisionBatchPlan],
        options: AIGenerationOptions,
        onBatch: @escaping (AIFlashcardBatchChunk) async throws -> Void
    ) async throws {
        guard !plans.isEmpty else { return }

        var coveredPrompts: [String] = []
        var approvedExamples: [String] = []
        var overlapHints: [String] = []
        var acceptedPairKeys: Set<String> = []
        var acceptedCards: [AIFlashcard] = []

        for plan in plans {
            try Task.checkCancellation()
            let scope = traceScope(for: plan, operation: "match_vision_batch")
            let existingPairKeys = acceptedPairKeys
            await debugTraceStore.record(
                stage: .batchStarted,
                message: "Starting sequential Match vision batch.",
                scope: scope
            )

            let result = try await withTraceScope(scope) { [self] in
                try await self.sendQualityFirstMatchGenerationRequest(
                    targetCards: plan.targetCards,
                    model: self.visionModel,
                    options: options,
                    existingPairKeys: existingPairKeys
                ) { requestedCards, retryHints in
                    self.buildVisionMessages(
                        images: plan.images,
                        targetCards: requestedCards,
                        options: options,
                        sourceLabel: plan.sourceLabel,
                        batchIndex: plan.batchIndex,
                        totalBatches: plan.totalBatches,
                        passIndex: plan.passIndex,
                        coveredPrompts: coveredPrompts + retryHints,
                        approvedMatchExamples: approvedExamples,
                        matchOverlapHints: overlapHints
                    )
                }
            }

            if !result.cards.isEmpty || result.shortfallCount > 0 {
                try await onBatch(
                    AIFlashcardBatchChunk(
                        cards: result.cards,
                        allocationID: plan.allocationID,
                        plannedCardCount: plan.targetCards,
                        shortfallCount: result.shortfallCount,
                        sourceLabel: plan.sourceLabel,
                        matchDiagnostics: result.diagnostics
                    )
                )
            }

            acceptedCards.append(contentsOf: result.cards)
            acceptedPairKeys.formUnion(
                result.cards.compactMap { card in
                    guard case .match(let content) = card.content else { return nil }
                    return matchPairKey(prompt: content.prompt, answer: content.answer)
                }
            )
            coveredPrompts = updateCoveredPrompts(existing: coveredPrompts, with: result.cards)
            approvedExamples = formattedStrongMatchApprovedExamples(from: acceptedCards)
            overlapHints = formattedMatchOverlapHints(from: acceptedCards)
            await debugTraceStore.record(
                stage: .batchCompleted,
                message: "Completed sequential Match vision batch.",
                scope: scope,
                metadata: [
                    "accepted_cards": String(result.cards.count),
                    "shortfall_count": String(result.shortfallCount),
                    "low_quality_accepted": String(result.diagnostics.lowQualityAcceptedCount)
                ]
            )
        }
    }

    func collectFlashcards(
        from stream: AsyncThrowingStream<[AIFlashcard], Error>
    ) async throws -> [AIFlashcard] {
        var allCards: [AIFlashcard] = []
        for try await chunk in stream {
            allCards.append(contentsOf: chunk)
        }
        return allCards
    }

    func performPlanQueue<Plan: RecoverableBatchPlan>(
        plans: [Plan],
        maxConcurrent: Int,
        execute: @escaping @Sendable (Plan, [String]) async throws -> GeneratedBatchExecutionResult,
        onBatch: @escaping (AIFlashcardBatchChunk) async throws -> Void
    ) async throws {
        guard !plans.isEmpty else { return }
        await trace(
            .planPrepared,
            "Prepared generation plan queue.",
            metadata: [
                "plan_count": String(plans.count),
                "max_concurrent": String(maxConcurrent)
            ]
        )

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
                    let scope = traceScope(for: plan, operation: "generation_batch")
                    activeTaskCount += 1

                    group.addTask { [self] in
                        await debugTraceStore.record(
                            stage: .batchStarted,
                            message: "Starting generation batch.",
                            scope: scope,
                            metadata: ["covered_prompt_count": String(promptSnapshot.count)]
                        )
                        do {
                            return try await withTraceScope(scope) {
                                try Task.checkCancellation()
                                let result = try await execute(plan, promptSnapshot)
                                return (plan, .success(result))
                            }
                        } catch {
                            await debugTraceStore.record(
                                stage: .batchCompleted,
                                message: "Generation batch failed.",
                                scope: scope,
                                metadata: ["error": String(describing: error)]
                            )
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
                    let scope = traceScope(for: plan, operation: "generation_batch")

                    if !result.cards.isEmpty || result.shortfallCount > 0 {
                        try await onBatch(
                            AIFlashcardBatchChunk(
                                cards: result.cards,
                                allocationID: allocationID(for: plan),
                                plannedCardCount: plan.targetCards,
                                shortfallCount: result.shortfallCount,
                                sourceLabel: plan.sourceLabel,
                                matchDiagnostics: result.matchDiagnostics
                            )
                        )
                        coveredPrompts = updateCoveredPrompts(existing: coveredPrompts, with: result.cards)
                    }
                    await debugTraceStore.record(
                        stage: .batchCompleted,
                        message: "Completed generation batch.",
                        scope: scope,
                        metadata: [
                            "accepted_cards": String(result.cards.count),
                            "shortfall_count": String(result.shortfallCount)
                        ]
                    )

                    if consecutiveSuccesses >= max(activeConcurrency, 1), activeConcurrency < maxConcurrent {
                        activeConcurrency += 1
                        consecutiveSuccesses = 0
                    }

                case .failure(let error):
                    consecutiveSuccesses = 0
                    activeConcurrency = max(1, activeConcurrency / 2)
                    let scope = traceScope(for: plan, operation: "generation_batch")

                    if shouldAttemptPlanSplit(after: error), let splitPlans = plan.splitForRecovery() {
                        pendingPlans.append(contentsOf: splitPlans)
                        await debugTraceStore.record(
                            stage: .batchRecovered,
                            message: "Split failed generation batch for recovery.",
                            scope: scope,
                            metadata: [
                                "split_plan_count": String(splitPlans.count),
                                "error": String(describing: error)
                            ]
                        )
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

    func performConversionPlanQueue(
        plans: [ConversionBatchPlan],
        targetType: AICardGenerationType,
        level: AICardGenerationLevel,
        onBatch: @escaping (AIConversionBatchChunk) async throws -> Void
    ) async throws {
        guard !plans.isEmpty else { return }
        await trace(
            .planPrepared,
            "Prepared conversion plan queue.",
            metadata: [
                "plan_count": String(plans.count),
                "target_type": targetType.rawValue
            ]
        )

        var pendingPlans = plans
        var activeTaskCount = 0
        let allowedMaxConcurrency = targetType == .match
            ? min(maxConcurrentMatchConversionRequests, maxConcurrentConversionRequests)
            : maxConcurrentConversionRequests
        var activeConcurrency = min(max(allowedMaxConcurrency, 1), plans.count)
        var consecutiveSuccesses = 0
        var terminalFailures: [String] = []

        try await withThrowingTaskGroup(of: (ConversionBatchPlan, Result<AIConversionBatchChunk, Error>).self) { group in
            func scheduleAvailableTasks() {
                while activeTaskCount < activeConcurrency, !pendingPlans.isEmpty {
                    let plan = pendingPlans.removeFirst()
                    let sourceCards = plan.sourceCards
                    let plannedCardCount = plan.targetCards
                    let sourceLabel = plan.sourceLabel
                    let scope = traceScope(for: plan, operation: "conversion_batch")
                    activeTaskCount += 1

                    group.addTask { [self] in
                        await debugTraceStore.record(
                            stage: .batchStarted,
                            message: "Starting conversion batch.",
                            scope: scope,
                            metadata: [
                                "source_card_count": String(sourceCards.count),
                                "target_type": targetType.rawValue
                            ]
                        )
                        do {
                            return try await withTraceScope(scope) { [self] in
                                try Task.checkCancellation()

                                let chunk = try await self.withExecutionTimeout(
                                    nanoseconds: self.conversionBatchExecutionTimeoutNanoseconds
                                ) {
                                    if targetType == .match {
                                        let qualityResult = try await self.sendQualityFirstMatchConversionRequest(
                                            sourceCards: sourceCards,
                                            targetCount: plannedCardCount,
                                            level: level
                                        )
                                        return AIConversionBatchChunk(
                                            outputs: qualityResult.outputs,
                                            plannedSourceIDs: sourceCards.map(\.id),
                                            plannedCardCount: plannedCardCount,
                                            shortfallCount: qualityResult.shortfallCount,
                                            sourceLabel: sourceLabel,
                                            matchDiagnostics: qualityResult.diagnostics
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
                            }
                        } catch {
                            await debugTraceStore.record(
                                stage: .batchCompleted,
                                message: "Conversion batch failed.",
                                scope: scope,
                                metadata: ["error": String(describing: error)]
                            )
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
                    await debugTraceStore.record(
                        stage: .batchCompleted,
                        message: "Completed conversion batch.",
                        scope: traceScope(for: plan, operation: "conversion_batch"),
                        metadata: [
                            "output_count": String(chunk.outputs.count),
                            "shortfall_count": String(chunk.shortfallCount)
                        ]
                    )

                    if consecutiveSuccesses >= max(activeConcurrency, 1), activeConcurrency < maxConcurrentConversionRequests {
                        activeConcurrency += 1
                        consecutiveSuccesses = 0
                    }

                case .failure(let error):
                    consecutiveSuccesses = 0
                    activeConcurrency = max(1, activeConcurrency / 2)
                    let scope = traceScope(for: plan, operation: "conversion_batch")

                    if shouldAttemptPlanSplit(after: error), let splitPlans = plan.splitForRecovery() {
                        pendingPlans.append(contentsOf: splitPlans)
                        await debugTraceStore.record(
                            stage: .batchRecovered,
                            message: "Split failed conversion batch for recovery.",
                            scope: scope,
                            metadata: [
                                "split_plan_count": String(splitPlans.count),
                                "error": String(describing: error)
                            ]
                        )
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

    func performSequentialMatchConversionPlanQueue(
        plans: [ConversionBatchPlan],
        level: AICardGenerationLevel,
        onBatch: @escaping (AIConversionBatchChunk) async throws -> Void
    ) async throws {
        guard !plans.isEmpty else { return }

        var remainingCandidates = plans.flatMap(\.sourceCards)
        var approvedExamples: [String] = []
        var overlapHints: [String] = []
        var acceptedPairKeys: Set<String> = []
        var acceptedOutputsHistory: [AICardConversionOutput] = []

        for plan in plans {
            try Task.checkCancellation()
            let scope = traceScope(for: plan, operation: "match_conversion_batch")
            await debugTraceStore.record(
                stage: .batchStarted,
                message: "Starting sequential Match conversion batch.",
                scope: scope,
                metadata: ["candidate_pool_count": String(remainingCandidates.count)]
            )

            var batchOutputs: [AICardConversionOutput] = []
            var batchPlannedSourceIDs: [PersistentIdentifier] = []
            var batchDiagnostics = MatchAIBatchDiagnostics()
            var remainingTarget = plan.targetCards

            while remainingTarget > 0, !remainingCandidates.isEmpty {
                let candidateCount = min(remainingCandidates.count, remainingTarget + 2)
                let candidateSources = Array(remainingCandidates.prefix(candidateCount))
                remainingCandidates.removeFirst(candidateCount)
                batchPlannedSourceIDs.append(contentsOf: candidateSources.map(\.id))
                let targetSnapshot = remainingTarget
                let approvedExamplesSnapshot = approvedExamples
                let overlapHintsSnapshot = overlapHints
                let acceptedPairKeysSnapshot = acceptedPairKeys

                let iterationScope = scope?.with(
                    plannedCardCount: targetSnapshot,
                    attempt: (plan.targetCards - remainingTarget) + 1
                )
                let result = try await withTraceScope(iterationScope) { [self] in
                    try await self.withExecutionTimeout(
                        nanoseconds: self.conversionBatchExecutionTimeoutNanoseconds
                    ) {
                        try await self.sendQualityFirstMatchConversionRequest(
                            sourceCards: candidateSources,
                            targetCount: targetSnapshot,
                            level: level,
                            approvedMatchExamples: approvedExamplesSnapshot,
                            matchOverlapHints: overlapHintsSnapshot,
                            existingPairKeys: acceptedPairKeysSnapshot
                        )
                    }
                }

                batchOutputs.append(contentsOf: result.outputs)
                batchDiagnostics.merge(result.diagnostics)
                acceptedPairKeys.formUnion(
                    result.outputs.compactMap { output in
                        guard case .match(let content) = output.generatedCard.content else { return nil }
                        return matchPairKey(prompt: content.prompt, answer: content.answer)
                    }
                )
                acceptedOutputsHistory.append(contentsOf: result.outputs)
                approvedExamples = formattedStrongMatchApprovedExamples(from: acceptedOutputsHistory)
                overlapHints = formattedMatchOverlapHints(from: acceptedOutputsHistory)
                remainingTarget = max(0, plan.targetCards - batchOutputs.count)
                await debugTraceStore.record(
                    stage: .qualityEvaluated,
                    message: "Evaluated sequential Match conversion candidate slice.",
                    scope: iterationScope,
                    metadata: [
                        "candidate_count": String(candidateSources.count),
                        "accepted_outputs": String(result.outputs.count),
                        "remaining_target": String(remainingTarget),
                        "low_quality_accepted": String(result.diagnostics.lowQualityAcceptedCount)
                    ]
                )
            }

            let finalShortfall = max(0, plan.targetCards - batchOutputs.count)
            if finalShortfall > 0 {
                batchDiagnostics.increment(.exhaustedCandidates, by: finalShortfall)
            }

            try await onBatch(
                AIConversionBatchChunk(
                    outputs: batchOutputs,
                    plannedSourceIDs: batchPlannedSourceIDs,
                    plannedCardCount: plan.targetCards,
                    shortfallCount: finalShortfall,
                    sourceLabel: plan.sourceLabel,
                    matchDiagnostics: batchDiagnostics
                )
            )
            await debugTraceStore.record(
                stage: .batchCompleted,
                message: "Completed sequential Match conversion batch.",
                scope: scope,
                metadata: [
                    "output_count": String(batchOutputs.count),
                    "shortfall_count": String(finalShortfall),
                    "low_quality_accepted": String(batchDiagnostics.lowQualityAcceptedCount)
                ]
            )
        }
    }

    nonisolated func traceScope<Plan: RecoverableBatchPlan>(
        for plan: Plan,
        operation: String
    ) -> AIDebugTraceScope? {
        let baseScope = AIDebugTraceContext.currentScope
        let batchIndex: Int?
        let totalBatches: Int?

        switch plan {
        case let plan as TextBatchPlan:
            batchIndex = plan.batchIndex
            totalBatches = plan.totalBatches
        case let plan as VisionBatchPlan:
            batchIndex = plan.batchIndex
            totalBatches = plan.totalBatches
        case let plan as ConversionBatchPlan:
            batchIndex = plan.batchIndex
            totalBatches = plan.totalBatches
        default:
            batchIndex = nil
            totalBatches = nil
        }

        return baseScope?.with(
            operation: operation,
            batchIndex: batchIndex,
            totalBatches: totalBatches,
            sourceLabel: plan.sourceLabel,
            plannedCardCount: plan.targetCards
        )
    }

    func updateCoveredPrompts(existing: [String], with cards: [AIFlashcard]) -> [String] {
        let additions = cards.map(promptHint(from:))
        let merged = (existing + additions).filter { !$0.isEmpty }
        return Array(merged.suffix(12))
    }

    func promptHint(from card: AIFlashcard) -> String {
        card.promptHint
    }

    func allocationID(for plan: some RecoverableBatchPlan) -> UUID? {
        if let textPlan = plan as? TextBatchPlan {
            return textPlan.allocationID
        }
        if let visionPlan = plan as? VisionBatchPlan {
            return visionPlan.allocationID
        }
        return nil
    }
}
