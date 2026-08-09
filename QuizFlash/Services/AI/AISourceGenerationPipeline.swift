//
//  AISourceGenerationPipeline.swift
//  QuizFlash
//

import Foundation

/// Complete immutable input for one production source-generation run.
nonisolated struct AISourceGenerationPipelineRequest: Sendable {
    let segments: [AITextSourceSegment]
    let allocations: [AISourceRangeAllocation]
    let targetCardCount: Int
    let needsOCRCorrection: Bool
    let sourceKind: String
    let options: AIGenerationOptions
    let reusableBlueprint: AISourceBlueprint?
    let remainingObjectiveIDs: Set<UUID>
    let coveredPrompts: [String]
}

/// Blueprint and resolved language state produced before card batches begin.
nonisolated struct AISourceGenerationPipelineContext: Sendable {
    let blueprint: AISourceBlueprint
    let resolvedOptions: AIGenerationOptions
    let remainingObjectiveIDs: Set<UUID>
}

/// Ordered milestones emitted by the production source-generation pipeline.
nonisolated enum AISourceGenerationPipelineEvent: Sendable {
    case prepared(AISourceGenerationPipelineContext)
    case batch(AIFlashcardBatchChunk)
}

/// The single production owner for blueprint planning and objective-backed
/// card generation. UI surfaces consume its event stream; they do not rebuild
/// any part of the generation route themselves.
final class AISourceGenerationPipeline: @unchecked Sendable {
    private let service: AIFlashcardService

    init(service: AIFlashcardService) {
        self.service = service
    }

    func events(
        for request: AISourceGenerationPipelineRequest
    ) -> AsyncThrowingStream<AISourceGenerationPipelineEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [service] in
                do {
                    try await service.withDebugRun(
                        kind: .generation,
                        targetType: request.options.cardType.rawValue,
                        sourceKind: request.sourceKind,
                        targetCount: request.targetCardCount,
                        sourceCount: request.segments.count,
                        metadata: [
                            "allocation_count": String(request.allocations.count),
                            "distribution_mode": request.options.sourceDistributionMode.rawValue,
                            "has_user_instructions": String(request.options.normalizedUserInstructions != nil),
                            "user_instruction_length": String(request.options.normalizedUserInstructions?.count ?? 0),
                            "needs_ocr_correction": String(request.needsOCRCorrection),
                            "segment_count": String(request.segments.count)
                        ]
                    ) {
                        let context = try await Self.resolveContext(
                            request: request,
                            service: service
                        )
                        continuation.yield(.prepared(context))

                        let stream = service.generateFlashcardBatchStream(
                            fromSegments: request.segments,
                            targetCards: request.targetCardCount,
                            allocations: request.allocations,
                            needsOCRCorrection: request.needsOCRCorrection,
                            options: context.resolvedOptions,
                            blueprint: context.blueprint,
                            remainingObjectiveIDs: context.remainingObjectiveIDs,
                            initialCoveredPrompts: request.coveredPrompts
                        )
                        for try await chunk in stream {
                            try Task.checkCancellation()
                            continuation.yield(.batch(chunk))
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

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private static func resolveContext(
        request: AISourceGenerationPipelineRequest,
        service: AIFlashcardService
    ) async throws -> AISourceGenerationPipelineContext {
        let manualConstraints = request.options.sourceDistributionMode == .manual
            ? request.allocations
            : []
        let fingerprintSegments: [AITextSourceSegment]
        if manualConstraints.isEmpty {
            fingerprintSegments = request.segments
        } else {
            let selectedIndexes = Set(
                manualConstraints.flatMap { Array($0.startIndex ... $0.endIndex) }
            )
            fingerprintSegments = request.segments.filter {
                selectedIndexes.contains($0.index)
            }
        }
        let fingerprint = AIBlueprintValidator.sourceFingerprint(for: fingerprintSegments)

        let blueprint: AISourceBlueprint
        let remainingObjectiveIDs: Set<UUID>
        if let reusableBlueprint = request.reusableBlueprint,
           reusableBlueprint.sourceFingerprint == fingerprint,
           request.remainingObjectiveIDs.count == request.targetCardCount {
            blueprint = reusableBlueprint
            remainingObjectiveIDs = request.remainingObjectiveIDs
        } else {
            blueprint = try await service.buildSourceBlueprint(
                segments: request.segments,
                targetCards: request.targetCardCount,
                options: request.options,
                manualAllocations: manualConstraints
            )
            remainingObjectiveIDs = Set(blueprint.objectives.map(\.id))
        }

        var resolvedOptions = request.options
        switch request.options.outputLanguageMode {
        case .auto:
            resolvedOptions.sourceLanguageHint = blueprint.dominantLanguage
        case .manual:
            resolvedOptions.sourceLanguageHint = request.options.manualOutputLanguage
        }

        return AISourceGenerationPipelineContext(
            blueprint: blueprint,
            resolvedOptions: resolvedOptions,
            remainingObjectiveIDs: remainingObjectiveIDs
        )
    }
}
