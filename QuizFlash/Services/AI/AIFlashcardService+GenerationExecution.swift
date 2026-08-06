import Foundation
import UIKit

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
        initialCoveredPrompts: [String] = [],
        onBatch: @escaping (AIFlashcardBatchChunk) async throws -> Void
    ) async throws {
        try await performPlanQueue(
            plans: plans,
            maxConcurrent: maxConcurrentTextPlanRequests,
            initialCoveredPrompts: initialCoveredPrompts,
            execute: { [self] plan, coveredPrompts in
                if plan.blueprintContext != nil {
                    return try await executeBlueprintTextPlan(
                        plan,
                        needsOCRCorrection: needsOCRCorrection,
                        options: options,
                        coveredPrompts: coveredPrompts
                    )
                }
                let messages = try buildTextMessages(
                    text: plan.text,
                    targetCards: plan.targetCards,
                    needsOCRCorrection: needsOCRCorrection,
                    options: options,
                    sourceLabel: plan.sourceLabel,
                    batchIndex: plan.batchIndex,
                    totalBatches: plan.totalBatches,
                    passIndex: plan.passIndex,
                    coveredPrompts: coveredPrompts,
                    blueprintContext: plan.blueprintContext
                )

                let cards = try await sendRequest(
                        messages: messages,
                        model: textModel,
                        options: options,
                        targetCards: plan.targetCards
                    )
                return GeneratedBatchExecutionResult(
                    cards: Array(cards.prefix(plan.targetCards)),
                    shortfallCount: 0
                )
            },
            onBatch: onBatch
        )
    }

    func executeBlueprintTextPlan(
        _ plan: TextBatchPlan,
        needsOCRCorrection: Bool,
        options: AIGenerationOptions,
        coveredPrompts: [String]
    ) async throws -> GeneratedBatchExecutionResult {
        guard let context = plan.blueprintContext else {
            return GeneratedBatchExecutionResult(cards: [], shortfallCount: plan.targetCards)
        }

        var accepted: [AIFlashcard] = []
        var remainingObjectives = context.objectives
        var completionAttempt = 0

        while !remainingObjectives.isEmpty, completionAttempt <= 2 {
            try Task.checkCancellation()
            let requestContext = AIBlueprintBatchContext(
                globalOutline: context.globalOutline,
                theme: context.theme,
                objectives: remainingObjectives
            )
            let promptSnapshot = updateCoveredPrompts(existing: coveredPrompts, with: accepted)
            let messages = try buildTextMessages(
                text: plan.text,
                targetCards: remainingObjectives.count,
                needsOCRCorrection: needsOCRCorrection,
                options: options,
                sourceLabel: plan.sourceLabel,
                batchIndex: plan.batchIndex,
                totalBatches: plan.totalBatches,
                passIndex: plan.passIndex + completionAttempt,
                coveredPrompts: promptSnapshot,
                blueprintContext: requestContext
            )
            let returned = try await sendRequest(
                messages: messages,
                model: textModel,
                options: options,
                targetCards: remainingObjectives.count
            )
            let bounded = Array(returned.prefix(remainingObjectives.count))
            if returned.count > bounded.count {
                await trace(
                    .qualityEvaluated,
                    "Discarded cards beyond the blueprint batch target.",
                    metadata: ["surplus_cards": String(returned.count - bounded.count)]
                )
            }
            accepted.append(contentsOf: bounded)
            remainingObjectives.removeFirst(min(bounded.count, remainingObjectives.count))
            completionAttempt += 1
            if bounded.isEmpty, completionAttempt > 2 { break }
        }

        return GeneratedBatchExecutionResult(
            cards: Array(accepted.prefix(plan.targetCards)),
            shortfallCount: remainingObjectives.count
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
        try await performPlanQueue(
            plans: plans,
            maxConcurrent: maxConcurrentVisionPlanRequests,
            execute: { [self] plan, coveredPrompts in
                let messages = try buildVisionMessages(
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
                    cards: try await sendRequest(
                        messages: messages,
                        model: visionModel,
                        options: options,
                        targetCards: plan.targetCards
                    ),
                    shortfallCount: 0
                )
            },
            onBatch: onBatch
        )
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
        initialCoveredPrompts: [String] = [],
        execute: @escaping @Sendable (Plan, [String]) async throws -> GeneratedBatchExecutionResult,
        onBatch: @escaping (AIFlashcardBatchChunk) async throws -> Void
    ) async throws {
        guard !plans.isEmpty else { return }
        await trace(
            .planPrepared,
            "Prepared generation plan queue.",
            metadata: [
                "plan_count": String(plans.count),
                "max_concurrent": String(effectiveMaxConcurrentRequestCount(
                    for: plans,
                    requestedMaxConcurrent: maxConcurrent
                ))
            ]
        )

        var pendingPlans = plans
        var coveredPrompts = Array(initialCoveredPrompts.prefix(64))
        var activeTaskCount = 0
        var activeSerializationKeys = Set<String>()
        let effectiveMaxConcurrent = effectiveMaxConcurrentRequestCount(
            for: plans,
            requestedMaxConcurrent: maxConcurrent
        )
        var activeConcurrency = effectiveMaxConcurrent
        var consecutiveSuccesses = 0
        var terminalFailures: [String] = []

        try await withThrowingTaskGroup(of: (Plan, Result<GeneratedBatchExecutionResult, Error>).self) { group in
            func scheduleAvailableTasks() {
                while activeTaskCount < activeConcurrency, !pendingPlans.isEmpty {
                    guard let eligibleIndex = pendingPlans.firstIndex(where: { plan in
                        guard let key = plan.serializationKey else { return true }
                        return !activeSerializationKeys.contains(key)
                    }) else { break }
                    let plan = pendingPlans.remove(at: eligibleIndex)
                    let promptSnapshot = coveredPrompts
                    let scope = traceScope(for: plan, operation: "generation_batch")
                    activeTaskCount += 1
                    if let key = plan.serializationKey {
                        activeSerializationKeys.insert(key)
                    }

                    group.addTask { [self] in
                        await trace(
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
                            await trace(
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
                if let key = plan.serializationKey {
                    activeSerializationKeys.remove(key)
                }

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
                                objectiveIDs: objectiveIDs(for: plan)
                            )
                        )
                        coveredPrompts = updateCoveredPrompts(existing: coveredPrompts, with: result.cards)
                    }
                    await trace(
                        stage: .batchCompleted,
                        message: "Completed generation batch.",
                        scope: scope,
                        metadata: [
                            "accepted_cards": String(result.cards.count),
                            "shortfall_count": String(result.shortfallCount)
                        ]
                    )

                    if consecutiveSuccesses >= max(activeConcurrency, 1), activeConcurrency < effectiveMaxConcurrent {
                        activeConcurrency += 1
                        consecutiveSuccesses = 0
                    }

                case .failure(let error):
                    consecutiveSuccesses = 0
                    activeConcurrency = max(1, activeConcurrency / 2)
                    let scope = traceScope(for: plan, operation: "generation_batch")

                    if shouldAttemptPlanSplit(after: error), let splitPlans = plan.splitForRecovery() {
                        pendingPlans.append(contentsOf: splitPlans)
                        await trace(
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

    func effectiveMaxConcurrentRequestCount<Plan: RecoverableBatchPlan>(
        for plans: [Plan],
        requestedMaxConcurrent: Int
    ) -> Int {
        guard !plans.isEmpty else { return 0 }
        let boundedMaxConcurrent = min(max(requestedMaxConcurrent, 1), plans.count)
        guard boundedMaxConcurrent > 1 else { return boundedMaxConcurrent }
        if plans.contains(where: { $0.serializationKey != nil }) {
            return boundedMaxConcurrent
        }

        var seenSourceIdentities = Set<String>()
        for plan in plans {
            let sourceIdentity = allocationID(for: plan)
                .map { "allocation:\($0.uuidString)" }
                ?? plan.sourceLabel.replacingOccurrences(
                    of: #"\s*\(focus pass \d+\)$"#,
                    with: "",
                    options: .regularExpression
                )
            if !seenSourceIdentities.insert(sourceIdentity).inserted {
                return 1
            }
        }

        return boundedMaxConcurrent
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

    func objectiveIDs(for plan: some RecoverableBatchPlan) -> [UUID] {
        (plan as? TextBatchPlan)?.blueprintContext?.objectives.map(\.id) ?? []
    }
}
