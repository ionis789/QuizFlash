//
//  AIGenerationLabRunner.swift
//  QuizFlash
//

#if DEBUG
import Foundation
import UIKit

/// Terminal outcome recorded for one source in a laboratory run.
nonisolated enum AIGenerationLabCaseStatus: String, Codable, Sendable {
    case succeeded
    case partial
    case failed
}

/// Timings captured around the unchanged production generation path.
nonisolated struct AIGenerationLabCaseTimings: Codable, Sendable {
    let preparationMilliseconds: Int
    let authorizationMilliseconds: Int
    let blueprintMilliseconds: Int?
    let firstCardMilliseconds: Int?
    let cardGenerationMilliseconds: Int?
    let finalizationMilliseconds: Int?
    let totalMilliseconds: Int
}

/// One generated card paired with the blueprint objective that requested it.
nonisolated struct AIGenerationLabGeneratedCard: Codable, Sendable {
    let index: Int
    let objectiveID: UUID?
    let card: AIFlashcard
}

/// Reproducible result for one independently generated corpus source.
nonisolated struct AIGenerationLabCaseResult: Identifiable, Codable, Sendable {
    let id: UUID
    let sourceID: UUID
    let sourceKind: AIGenerationLabSourceKind
    let sourceName: String
    let sourceSHA256: String
    let status: AIGenerationLabCaseStatus
    let targetCardCount: Int
    let generatedCardCount: Int
    let shortfallCount: Int
    let batchCount: Int
    let objectiveCoverageCount: Int
    let uniquePromptCount: Int
    let duplicatePromptCount: Int
    let sourceSegmentCount: Int
    let sourceCharacterCount: Int
    let suggestedTitle: String?
    let detectedLanguageCode: String?
    let promptVersion: String?
    let traceRunID: UUID?
    let timings: AIGenerationLabCaseTimings
    let errorMessage: String?
    let sourceSegments: [AITextSourceSegment]
    let blueprint: AISourceBlueprint?
    let generatedCards: [AIGenerationLabGeneratedCard]
}

/// Complete report for one ordered pass over the corpus.
nonisolated struct AIGenerationLabRunReport: Identifiable, Codable, Sendable {
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    let id: UUID
    let startedAtEpochMilliseconds: Int64
    let finishedAtEpochMilliseconds: Int64
    let targetCardCountPerSource: Int
    let options: AIGenerationOptions
    let appVersion: String
    let appBuild: String
    let deviceModel: String
    let operatingSystem: String
    let cases: [AIGenerationLabCaseResult]

    init(
        id: UUID = UUID(),
        startedAtEpochMilliseconds: Int64,
        finishedAtEpochMilliseconds: Int64,
        targetCardCountPerSource: Int,
        options: AIGenerationOptions,
        appVersion: String,
        appBuild: String,
        deviceModel: String,
        operatingSystem: String,
        cases: [AIGenerationLabCaseResult]
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.startedAtEpochMilliseconds = startedAtEpochMilliseconds
        self.finishedAtEpochMilliseconds = finishedAtEpochMilliseconds
        self.targetCardCountPerSource = targetCardCountPerSource
        self.options = options
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.deviceModel = deviceModel
        self.operatingSystem = operatingSystem
        self.cases = cases
    }
}

/// User-visible milestones emitted while a corpus case traverses the real
/// production preparation, authorization, blueprint, and card pipeline.
nonisolated enum AIGenerationLabRunStage: Equatable, Sendable {
    case preparing
    case authorizing
    case blueprint
    case generating(generated: Int, target: Int)
    case finalizing
}

/// Live progress for the currently running independent corpus case.
nonisolated struct AIGenerationLabRunProgress: Equatable, Sendable {
    let sourceName: String
    let caseIndex: Int
    let caseCount: Int
    let stage: AIGenerationLabRunStage
}

/// DEBUG-only adapter that observes the production pipeline. It contains no
/// prompt, planner, decoding, repair, or card-generation implementation.
@MainActor
final class AIGenerationLabRunner {
    private let cloudClient: CloudAIProxyClient
    private let traceStore: AIDebugTraceStore

    init(
        cloudClient: CloudAIProxyClient? = nil,
        traceStore: AIDebugTraceStore? = nil
    ) {
        self.cloudClient = cloudClient ?? .shared
        self.traceStore = traceStore ?? .shared
    }

    func runCase(
        source: AIGenerationLabSource,
        storedFileURLs: [URL],
        targetCardCount: Int,
        options: AIGenerationOptions,
        caseIndex: Int,
        caseCount: Int,
        progress: @escaping @MainActor (AIGenerationLabRunProgress) -> Void
    ) async throws -> AIGenerationLabCaseResult {
        let clock = ContinuousClock()
        let totalStart = clock.now
        var preparationMilliseconds = 0
        var authorizationMilliseconds = 0
        var blueprintMilliseconds: Int?
        var firstCardMilliseconds: Int?
        var cardGenerationMilliseconds: Int?
        var finalizationMilliseconds: Int?
        var preparedSource: AIPreparedGenerationSource?
        var cloudSession: CloudAIGenerationSession?
        var generatedCards: [AIGenerationLabGeneratedCard] = []
        var shortfallCount = 0
        var batchCount = 0
        var coveredObjectiveIDs = Set<UUID>()
        var blueprint: AISourceBlueprint?
        var pipelineStart: ContinuousClock.Instant?
        var cardGenerationStart: ContinuousClock.Instant?
        let priorTraceIDs = Set(await traceStore.listRuns().map(\.id))

        func reportProgress(_ stage: AIGenerationLabRunStage) {
            progress(
                AIGenerationLabRunProgress(
                    sourceName: source.displayName,
                    caseIndex: caseIndex,
                    caseCount: caseCount,
                    stage: stage
                )
            )
        }

        do {
            reportProgress(.preparing)
            let preparationStart = clock.now
            preparedSource = try await prepareSource(source, storedFileURLs: storedFileURLs)
            preparationMilliseconds = Self.milliseconds(from: preparationStart, to: clock.now)
            try Task.checkCancellation()

            guard let preparedSource else {
                throw AIGenerationLabRunnerError.sourcePreparationFailed
            }
            let allocations = AISourceAllocationPlanner.automaticAllocations(
                for: preparedSource.previewItems.map(\.characterCount),
                totalCards: targetCardCount
            )
            guard allocations.reduce(0, { $0 + $1.cardCount }) == targetCardCount else {
                throw AIGenerationLabRunnerError.invalidAllocationPlan
            }

            reportProgress(.authorizing)
            let authorizationStart = clock.now
            let session = try await cloudClient.startGeneration(targetCards: targetCardCount)
            cloudSession = session
            SubscriptionManager.shared.applyCloudAIQuotaState(session.quota)
            authorizationMilliseconds = Self.milliseconds(from: authorizationStart, to: clock.now)
            try Task.checkCancellation()

            let service = AIFlashcardService(
                provider: .preset(.deepSeek),
                transport: .cloudProxy(session)
            )
            let pipeline = AISourceGenerationPipeline(service: service)
            let request = AISourceGenerationPipelineRequest(
                segments: preparedSource.textSegments,
                allocations: allocations,
                targetCardCount: targetCardCount,
                needsOCRCorrection: preparedSource.needsOCRCorrection,
                sourceKind: preparedSource.isPDF ? "pdf" : "photos_ocr",
                options: options,
                reusableBlueprint: nil,
                remainingObjectiveIDs: [],
                coveredPrompts: []
            )

            reportProgress(.blueprint)
            pipelineStart = clock.now
            for try await event in pipeline.events(for: request) {
                try Task.checkCancellation()
                switch event {
                case .prepared(let context):
                    blueprint = context.blueprint
                    blueprintMilliseconds = pipelineStart.map {
                        Self.milliseconds(from: $0, to: clock.now)
                    }
                    cardGenerationStart = clock.now
                    reportProgress(.generating(generated: 0, target: targetCardCount))

                case .batch(let chunk):
                    batchCount += 1
                    shortfallCount += chunk.shortfallCount
                    let remainingCapacity = max(targetCardCount - generatedCards.count, 0)
                    let acceptedCards = Array(chunk.cards.prefix(remainingCapacity))
                    let acceptedObjectiveIDs = Array(chunk.objectiveIDs.prefix(acceptedCards.count))
                    for (offset, card) in acceptedCards.enumerated() {
                        let objectiveID = acceptedObjectiveIDs.indices.contains(offset)
                            ? acceptedObjectiveIDs[offset]
                            : nil
                        generatedCards.append(
                            AIGenerationLabGeneratedCard(
                                index: generatedCards.count + 1,
                                objectiveID: objectiveID,
                                card: card
                            )
                        )
                        if let objectiveID {
                            coveredObjectiveIDs.insert(objectiveID)
                        }
                    }
                    if firstCardMilliseconds == nil, !chunk.cards.isEmpty, let pipelineStart {
                        firstCardMilliseconds = Self.milliseconds(from: pipelineStart, to: clock.now)
                    }
                    reportProgress(
                        .generating(generated: generatedCards.count, target: targetCardCount)
                    )
                }
            }

            if let cardGenerationStart {
                cardGenerationMilliseconds = Self.milliseconds(
                    from: cardGenerationStart,
                    to: clock.now
                )
            }
            try Task.checkCancellation()

            reportProgress(.finalizing)
            let finalizationStart = clock.now
            await cloudClient.finalizeGeneration(session, validatedCards: generatedCards.count)
            finalizationMilliseconds = Self.milliseconds(from: finalizationStart, to: clock.now)
            cloudSession = nil

            let status: AIGenerationLabCaseStatus = generatedCards.count == targetCardCount && shortfallCount == 0
                ? .succeeded
                : .partial
            let errorMessage = status == .partial
                ? "The production pipeline returned fewer validated cards than requested."
                : nil
            return await makeResult(
                source: source,
                status: status,
                targetCardCount: targetCardCount,
                generatedCards: generatedCards,
                shortfallCount: max(shortfallCount, targetCardCount - generatedCards.count),
                batchCount: batchCount,
                coveredObjectiveIDs: coveredObjectiveIDs,
                preparedSource: preparedSource,
                blueprint: blueprint,
                priorTraceIDs: priorTraceIDs,
                timings: AIGenerationLabCaseTimings(
                    preparationMilliseconds: preparationMilliseconds,
                    authorizationMilliseconds: authorizationMilliseconds,
                    blueprintMilliseconds: blueprintMilliseconds,
                    firstCardMilliseconds: firstCardMilliseconds,
                    cardGenerationMilliseconds: cardGenerationMilliseconds,
                    finalizationMilliseconds: finalizationMilliseconds,
                    totalMilliseconds: Self.milliseconds(from: totalStart, to: clock.now)
                ),
                errorMessage: errorMessage
            )
        } catch is CancellationError {
            if let cloudSession {
                cloudClient.scheduleGenerationFailure(cloudSession)
            }
            throw CancellationError()
        } catch {
            if let cloudSession {
                if generatedCards.isEmpty {
                    cloudClient.scheduleGenerationFailure(cloudSession)
                } else {
                    cloudClient.scheduleGenerationFinalization(
                        cloudSession,
                        validatedCards: generatedCards.count
                    )
                }
            }
            return await makeResult(
                source: source,
                status: .failed,
                targetCardCount: targetCardCount,
                generatedCards: generatedCards,
                shortfallCount: max(shortfallCount, targetCardCount - generatedCards.count),
                batchCount: batchCount,
                coveredObjectiveIDs: coveredObjectiveIDs,
                preparedSource: preparedSource,
                blueprint: blueprint,
                priorTraceIDs: priorTraceIDs,
                timings: AIGenerationLabCaseTimings(
                    preparationMilliseconds: preparationMilliseconds,
                    authorizationMilliseconds: authorizationMilliseconds,
                    blueprintMilliseconds: blueprintMilliseconds,
                    firstCardMilliseconds: firstCardMilliseconds,
                    cardGenerationMilliseconds: cardGenerationMilliseconds,
                    finalizationMilliseconds: finalizationMilliseconds,
                    totalMilliseconds: Self.milliseconds(from: totalStart, to: clock.now)
                ),
                errorMessage: error.localizedDescription
            )
        }
    }

    private func prepareSource(
        _ source: AIGenerationLabSource,
        storedFileURLs: [URL]
    ) async throws -> AIPreparedGenerationSource {
        switch source.kind {
        case .pdf:
            guard let storedFileURL = storedFileURLs.first else {
                throw AIGenerationLabStoreError.missingStoredSource
            }
            return try await AISourcePreparationService.preparePDF(from: storedFileURL).source
        case .photos:
            let dataItems = try await Task.detached(priority: .userInitiated) {
                try storedFileURLs.map { try Data(contentsOf: $0) }
            }.value
            var images: [UIImage] = []
            for data in dataItems {
                try Task.checkCancellation()
                guard let image = await AISourcePreparationService.decodePreparedPhoto(from: data) else {
                    throw AIGenerationLabStoreError.invalidImage
                }
                images.append(image)
            }
            return try await AISourcePreparationService.preparePhotos(images)
        }
    }

    private func makeResult(
        source: AIGenerationLabSource,
        status: AIGenerationLabCaseStatus,
        targetCardCount: Int,
        generatedCards: [AIGenerationLabGeneratedCard],
        shortfallCount: Int,
        batchCount: Int,
        coveredObjectiveIDs: Set<UUID>,
        preparedSource: AIPreparedGenerationSource?,
        blueprint: AISourceBlueprint?,
        priorTraceIDs: Set<UUID>,
        timings: AIGenerationLabCaseTimings,
        errorMessage: String?
    ) async -> AIGenerationLabCaseResult {
        let promptIdentities = generatedCards.map { generatedCard in
            AIBlueprintValidator.textIdentity(generatedCard.card.promptHint)
        }
        let uniquePromptCount = Set(promptIdentities).count
        let traceRunID = await traceStore.listRuns().first { summary in
            summary.kind == .generation && !priorTraceIDs.contains(summary.id)
        }?.id

        return AIGenerationLabCaseResult(
            id: UUID(),
            sourceID: source.id,
            sourceKind: source.kind,
            sourceName: source.displayName,
            sourceSHA256: source.sha256,
            status: status,
            targetCardCount: targetCardCount,
            generatedCardCount: generatedCards.count,
            shortfallCount: shortfallCount,
            batchCount: batchCount,
            objectiveCoverageCount: coveredObjectiveIDs.count,
            uniquePromptCount: uniquePromptCount,
            duplicatePromptCount: max(generatedCards.count - uniquePromptCount, 0),
            sourceSegmentCount: preparedSource?.textSegments.count ?? 0,
            sourceCharacterCount: preparedSource?.textSegments.reduce(0) { $0 + $1.text.count } ?? 0,
            suggestedTitle: blueprint?.suggestedTitle,
            detectedLanguageCode: blueprint?.dominantLanguage?.languageCode,
            promptVersion: blueprint?.promptVersion,
            traceRunID: traceRunID,
            timings: timings,
            errorMessage: errorMessage,
            sourceSegments: preparedSource?.textSegments ?? [],
            blueprint: blueprint,
            generatedCards: generatedCards
        )
    }

    private static func milliseconds(
        from start: ContinuousClock.Instant,
        to end: ContinuousClock.Instant
    ) -> Int {
        let components = start.duration(to: end).components
        let milliseconds = components.seconds * 1_000
            + components.attoseconds / 1_000_000_000_000_000
        return max(Int(milliseconds), 0)
    }
}

/// Starts the existing Labs view model from a DEBUG launch argument so local
/// benchmarks can run without automating the app UI. The view model remains
/// the only corpus orchestrator and still invokes the unchanged production
/// generation pipeline through `AIGenerationLabRunner`.
@MainActor
final class AIGenerationLabLaunchRunner {
    static let shared = AIGenerationLabLaunchRunner()
    static let runLaunchArgument = "-RunAIGenerationLabCorpus"
    static let seedImageMirrorsLaunchArgument = "-SeedAIGenerationLabImageMirrors"

    private var runTask: Task<Void, Never>?

    private init() {}

    func startIfRequested(arguments: [String] = ProcessInfo.processInfo.arguments) {
        let shouldRun = arguments.contains(Self.runLaunchArgument)
        let shouldSeedImageMirrors = arguments.contains(Self.seedImageMirrorsLaunchArgument)
        guard shouldRun || shouldSeedImageMirrors, runTask == nil else { return }

        runTask = Task { [weak self] in
            guard let self else { return }
            defer { runTask = nil }

            let viewModel = AIGenerationLabViewModel.shared
            print("AI_LAB_CODE_RUN setup_started")
            await viewModel.load()

            if shouldSeedImageMirrors {
                await viewModel.importPDFImageMirrors()
                guard viewModel.errorMessage.isEmpty else {
                    print("AI_LAB_CODE_RUN failed reason=\(viewModel.errorMessage)")
                    return
                }
                print("AI_LAB_CODE_RUN image_mirrors_ready sources=\(viewModel.sources.count)")
            }

            guard shouldRun else {
                print("AI_LAB_CODE_RUN setup_completed")
                return
            }

            AuthManager.shared.startListening()
            guard await waitForAuthenticatedSession() else {
                print("AI_LAB_CODE_RUN failed reason=Authentication is not ready.")
                return
            }

            print("AI_LAB_CODE_RUN started")

            guard viewModel.canStartRun else {
                let reason = viewModel.errorMessage.isEmpty
                    ? "The saved corpus is empty or generation access is unavailable."
                    : viewModel.errorMessage
                print("AI_LAB_CODE_RUN failed reason=\(reason)")
                return
            }

            viewModel.startRun()
            for _ in 0..<40 where !viewModel.isRunning {
                await Task.yield()
            }

            guard viewModel.isRunning else {
                let reason = viewModel.errorMessage.isEmpty
                    ? "The corpus runner did not start."
                    : viewModel.errorMessage
                print("AI_LAB_CODE_RUN failed reason=\(reason)")
                return
            }

            while viewModel.isRunning {
                try? await Task.sleep(for: .milliseconds(250))
            }

            guard let report = viewModel.latestReport else {
                let reason = viewModel.errorMessage.isEmpty
                    ? "The corpus runner finished without a report."
                    : viewModel.errorMessage
                print("AI_LAB_CODE_RUN failed reason=\(reason)")
                return
            }

            let duration = max(
                report.finishedAtEpochMilliseconds - report.startedAtEpochMilliseconds,
                0
            )
            print(
                "AI_LAB_CODE_RUN completed report=\(report.id.uuidString) "
                    + "cases=\(report.cases.count) duration_ms=\(duration)"
            )
        }
    }

    private func waitForAuthenticatedSession() async -> Bool {
        for _ in 0..<120 {
            if AuthManager.shared.isAuthenticated {
                return true
            }
            guard !Task.isCancelled else { return false }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return false
    }
}

/// Deterministic laboratory setup failures that happen before provider output.
nonisolated enum AIGenerationLabRunnerError: LocalizedError {
    case sourcePreparationFailed
    case invalidAllocationPlan

    var errorDescription: String? {
        switch self {
        case .sourcePreparationFailed:
            return "The source could not be prepared by the production pipeline."
        case .invalidAllocationPlan:
            return "The production allocation plan did not match the requested target."
        }
    }
}
#endif
