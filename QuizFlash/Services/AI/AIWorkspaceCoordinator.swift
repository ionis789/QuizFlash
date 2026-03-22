//
//  AIWorkspaceCoordinator.swift
//  QuizFlash
//
//  Global AI workspace owner coordinating deck generation status and deck conversion runs.
//

import SwiftUI
import SwiftData
import OSLog

// MARK: - Workspace Types

enum AIWorkspaceJobKind: String, Equatable, Sendable {
    case generation
    case conversion
}

enum AIWorkspaceJobPhase: Equatable, Sendable {
    case preparing
    case running
    case paused
    case completed
    case failed
}

struct AIWorkspaceConversionSeed: Equatable, Sendable {
    let sourceDeckID: PersistentIdentifier
    let sourceDeckTitle: String
    var request: DeckCardConversionRequest
}

struct AIWorkspaceDeckContext: Equatable, Sendable {
    let sourceDeckID: PersistentIdentifier
    let sourceDeckTitle: String
    let destination: DeckCardConversionDestinationOption
    let destinationDeckTitle: String?
    let liveDeckID: PersistentIdentifier?
    let destinationBaseCardIDs: [PersistentIdentifier]

    var displayTitle: String {
        switch destination {
        case .sameDeck:
            return sourceDeckTitle
        case .newDeck:
            let trimmedTitle = destinationDeckTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmedTitle.isEmpty ? sourceDeckTitle : trimmedTitle
        }
    }
}

struct AIWorkspaceReturnContext: Equatable, Sendable {
    let ownerTab: AppTabBar
    let backLabel: String
}

struct AIWorkspaceFloatingStatus: Equatable {
    let kind: AIWorkspaceJobKind
    let phase: AIWorkspaceJobPhase
    let title: String
    let subtitle: String
    let progressLabel: String?
    let progressFraction: Double?
    let systemImage: String
}

struct AIWorkspaceGenerationStatus: Equatable {
    let phase: AIWorkspaceJobPhase
    let title: String
    let foundCount: Int
    let targetCount: Int
    let progress: Double
    let message: String
    let errorMessage: String?
}

struct AIWorkspaceConversionSheetToken: Identifiable, Equatable {
    let id = UUID()
}

// MARK: - Coordinator

@Observable
@MainActor
final class AIWorkspaceCoordinator {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "QuizFlash",
        category: "AIWorkspaceCoordinator"
    )

    @ObservationIgnored private let jobSessionStore: AIJobSessionStore
    @ObservationIgnored private var conversionTask: Task<Void, Never>?
    @ObservationIgnored private var hasRestoredPersistedJob = false

    var generationStatus: AIWorkspaceGenerationStatus?
    var conversionSeed: AIWorkspaceConversionSeed?
    var conversionSheetToken: AIWorkspaceConversionSheetToken?
    var conversionProgress: DeckCardConversionProgress?
    var conversionSummary: DeckCardConversionSummary?
    var conversionErrorMessage: String?
    var workspaceDeckContext: AIWorkspaceDeckContext?
    var conversionReturnContext: AIWorkspaceReturnContext?
    var showConversionCancelDialog = false

    private var activeConversionTargetKind: CardKind?
    private var shouldShowConversionOutcome = false
    private var pausedConversionSession: AIPausedConversionSession?

    init(jobSessionStore: AIJobSessionStore = .shared) {
        self.jobSessionStore = jobSessionStore
    }

    var hasBlockingJob: Bool {
        if let generationStatus {
            switch generationStatus.phase {
            case .preparing, .running, .paused:
                return true
            case .completed, .failed:
                break
            }
        }
        return conversionProgress != nil || pausedConversionSession != nil
    }

    var canResumeConversion: Bool {
        pausedConversionSession != nil && conversionTask == nil
    }

    var canPauseConversion: Bool {
        conversionTask != nil && conversionProgress != nil
    }

    var canCancelConversion: Bool {
        conversionProgress != nil || pausedConversionSession != nil
    }

    var convertedCardCountInVisibleSession: Int {
        conversionProgress?.createdCount ?? pausedConversionSession?.createdCount ?? conversionSummary?.createdCount ?? 0
    }

    var hasVisibleConversionWorkspaceState: Bool {
        conversionProgress != nil
            || pausedConversionSession != nil
            || (shouldShowConversionOutcome && (conversionSummary != nil || conversionErrorMessage != nil))
    }

    var floatingStatus: AIWorkspaceFloatingStatus? {
        if let progress = conversionProgress, let targetKind = activeConversionTargetKind {
            return AIWorkspaceFloatingStatus(
                kind: .conversion,
                phase: canResumeConversion ? .paused : .running,
                title: canResumeConversion ? "AI Conversion Paused" : "AI Conversion",
                subtitle: progress.statusMessage,
                progressLabel: "\(progress.createdCount)/\(progress.totalCount)",
                progressFraction: progress.fractionCompleted,
                systemImage: canResumeConversion ? "pause.circle.fill" : targetKind.conversionSystemImage
            )
        }

        if shouldShowConversionOutcome, let summary = conversionSummary {
            let title = summary.createdCount == 1
                ? "1 \(summary.targetKind.displayTitle) card created"
                : "\(summary.createdCount) \(summary.targetKind.displayTitle) cards created"
            return AIWorkspaceFloatingStatus(
                kind: .conversion,
                phase: .completed,
                title: title,
                subtitle: summary.destinationDeckTitle,
                progressLabel: nil,
                progressFraction: nil,
                systemImage: "checkmark.circle.fill"
            )
        }

        if shouldShowConversionOutcome, let conversionErrorMessage {
            return AIWorkspaceFloatingStatus(
                kind: .conversion,
                phase: .failed,
                title: "Conversion stopped",
                subtitle: conversionErrorMessage,
                progressLabel: nil,
                progressFraction: nil,
                systemImage: "exclamationmark.triangle.fill"
            )
        }

        guard let generationStatus else { return nil }

        let systemImage: String
        switch generationStatus.phase {
        case .preparing:
            systemImage = "doc.text.viewfinder"
        case .running:
            systemImage = "wand.and.stars"
        case .paused:
            systemImage = "pause.circle.fill"
        case .completed:
            systemImage = "checkmark.circle.fill"
        case .failed:
            systemImage = "exclamationmark.triangle.fill"
        }

        return AIWorkspaceFloatingStatus(
            kind: .generation,
            phase: generationStatus.phase,
            title: generationStatus.title,
            subtitle: generationStatus.message,
            progressLabel: generationStatus.targetCount > 0
                ? "\(generationStatus.foundCount)/\(generationStatus.targetCount)"
                : nil,
            progressFraction: generationStatus.phase == .running || generationStatus.phase == .paused
                ? generationStatus.progress
                : nil,
            systemImage: systemImage
        )
    }

    func shouldShowFloatingStatus(isWorkspaceVisible: Bool) -> Bool {
        !isWorkspaceVisible && floatingStatus != nil
    }

    @discardableResult
    func seedConversion(
        request: DeckCardConversionRequest,
        sourceDeck: DeckModel,
        ownerTab: AppTabBar? = nil,
        backLabel: String? = nil,
        showsConfiguration: Bool = true,
        activatesWorkspaceContext: Bool = true
    ) -> Bool {
        guard !hasBlockingJob else {
            conversionSheetToken = nil
            return false
        }

        conversionTask?.cancel()
        conversionTask = nil
        conversionProgress = nil
        conversionSummary = nil
        conversionErrorMessage = nil
        shouldShowConversionOutcome = false
        activeConversionTargetKind = request.targetKind
        conversionSeed = AIWorkspaceConversionSeed(
            sourceDeckID: sourceDeck.persistentModelID,
            sourceDeckTitle: sourceDeck.title,
            request: request
        )
        conversionReturnContext = {
            guard let ownerTab, let backLabel else { return nil }
            return AIWorkspaceReturnContext(ownerTab: ownerTab, backLabel: backLabel)
        }()
        if activatesWorkspaceContext {
            workspaceDeckContext = makeWorkspaceDeckContext(
                sourceDeckID: sourceDeck.persistentModelID,
                sourceDeckTitle: sourceDeck.title,
                request: request,
                liveDeckID: request.destination == .sameDeck ? sourceDeck.persistentModelID : nil,
                destinationBaseCardIDs: request.destination == .sameDeck
                    ? sourceDeck.cards.map(\.persistentModelID)
                    : []
            )
        } else {
            workspaceDeckContext = nil
        }
        conversionSheetToken = showsConfiguration ? AIWorkspaceConversionSheetToken() : nil
        return true
    }

    func updateConversionDraft(_ update: (inout DeckCardConversionRequest) -> Void) {
        guard var seed = conversionSeed else { return }
        update(&seed.request)
        seed.request.normalizeSelections()
        activeConversionTargetKind = seed.request.targetKind
        conversionSeed = seed
        guard workspaceDeckContext != nil else { return }
        let liveDeckID: PersistentIdentifier?
        if seed.request.destination == .sameDeck {
            liveDeckID = seed.sourceDeckID
        } else if workspaceDeckContext?.destination == .newDeck {
            liveDeckID = workspaceDeckContext?.liveDeckID
        } else {
            liveDeckID = nil
        }
        workspaceDeckContext = makeWorkspaceDeckContext(
            sourceDeckID: seed.sourceDeckID,
            sourceDeckTitle: seed.sourceDeckTitle,
            request: seed.request,
            liveDeckID: liveDeckID,
            destinationBaseCardIDs: workspaceDeckContext?.destinationBaseCardIDs ?? []
        )
    }

    func dismissConversionConfiguration() {
        conversionSheetToken = nil
        conversionSeed = nil
        activeConversionTargetKind = nil
        if conversionProgress == nil, conversionSummary == nil, conversionErrorMessage == nil {
            workspaceDeckContext = nil
            conversionReturnContext = nil
        }
    }

    func dismissConversionOutcome() {
        if pausedConversionSession != nil {
            pausedConversionSession = nil
            conversionProgress = nil
            conversionErrorMessage = nil
            shouldShowConversionOutcome = false
            activeConversionTargetKind = nil
            workspaceDeckContext = nil
            conversionReturnContext = nil
            Task {
                try? await jobSessionStore.clearSession()
            }
            return
        }

        conversionSummary = nil
        conversionErrorMessage = nil
        shouldShowConversionOutcome = false
        activeConversionTargetKind = nil
        workspaceDeckContext = nil
        conversionReturnContext = nil
    }

    func restorePersistedJobIfNeeded(context: ModelContext) async {
        guard !hasRestoredPersistedJob else { return }
        hasRestoredPersistedJob = true
        _ = context.container

        guard let session = await jobSessionStore.loadSession() else { return }

        switch session {
        case .generation(let generationSession):
            restoreGenerationStatus(from: generationSession)
        case .conversion(let conversionSession):
            restoreConversionSession(conversionSession)
        }
    }

    func startConversion(context: ModelContext) {
        guard let seed = conversionSeed, seed.request.canStart else { return }

        conversionTask?.cancel()
        conversionSheetToken = nil
        conversionSummary = nil
        conversionErrorMessage = nil
        shouldShowConversionOutcome = false
        activeConversionTargetKind = seed.request.targetKind
        pausedConversionSession = nil

        let request = seed.request
        let sourceDeckID = seed.sourceDeckID

        conversionSeed = nil
        if let sourceDeck = context.safeModel(for: sourceDeckID, as: DeckModel.self) {
            workspaceDeckContext = makeWorkspaceDeckContext(
                sourceDeckID: sourceDeckID,
                sourceDeckTitle: seed.sourceDeckTitle,
                request: request,
                liveDeckID: request.destination == .sameDeck ? sourceDeckID : nil,
                destinationBaseCardIDs: request.destination == .sameDeck
                    ? sourceDeck.cards.map(\.persistentModelID)
                    : []
            )
        }

        conversionTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                let session = try await self.makeFreshConversionSession(
                    request: request,
                    sourceDeckID: sourceDeckID,
                    context: context
                )
                try await self.persistPausedConversionSession(session)
                try await self.continueConversion(
                    from: session,
                    context: context
                )
            } catch is CancellationError {
                self.conversionProgress = self.pausedConversionSession?.progress
            } catch {
                self.conversionErrorMessage = error.localizedDescription
                self.shouldShowConversionOutcome = true
            }

            self.conversionTask = nil
        }
    }

    func resumeConversion(context: ModelContext) {
        guard let session = pausedConversionSession, conversionTask == nil else { return }

        conversionSummary = nil
        conversionErrorMessage = nil
        shouldShowConversionOutcome = false
        activeConversionTargetKind = session.request.targetKind
        conversionProgress = session.progress

        conversionTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                try await self.continueConversion(
                    from: session,
                    context: context
                )
            } catch is CancellationError {
                self.conversionProgress = self.pausedConversionSession?.progress
            } catch {
                self.conversionErrorMessage = error.localizedDescription
                self.shouldShowConversionOutcome = true
            }

            self.conversionTask = nil
        }
    }

    func pauseConversion() {
        guard canPauseConversion else { return }
        conversionTask?.cancel()
        conversionTask = nil
    }

    func requestConversionCancel() {
        guard canCancelConversion else { return }
        showConversionCancelDialog = true
    }

    func dismissConversionCancelRequest() {
        showConversionCancelDialog = false
    }

    func cancelConversion(
        context: ModelContext,
        keepingCreatedCards: Bool
    ) {
        showConversionCancelDialog = false
        let sessionToCancel = pausedConversionSession
        conversionTask?.cancel()
        conversionTask = nil
        if !keepingCreatedCards, let sessionToCancel {
            try? discardConvertedOutputs(from: sessionToCancel, context: context)
        }
        pausedConversionSession = nil
        conversionProgress = nil
        conversionSummary = nil
        conversionErrorMessage = nil
        shouldShowConversionOutcome = false
        conversionSeed = nil
        conversionSheetToken = nil
        workspaceDeckContext = nil
        conversionReturnContext = nil
        activeConversionTargetKind = nil

        Task {
            try? await jobSessionStore.clearSession()
        }
    }

    func openWorkspace(router: NavigationManager) {
        router.createPath = NavigationPath()
        router.activeTab = .create
    }

    func syncGenerationState(
        aiState: AIGenerationState,
        hasPausedGeneration: Bool,
        generatedCardCount: Int,
        targetCardCount: Int,
        deckTitle: String
    ) {
        if let conversionProgress {
            _ = conversionProgress
            return
        }

        if hasPausedGeneration {
            generationStatus = AIWorkspaceGenerationStatus(
                phase: .paused,
                title: "AI generation paused",
                foundCount: generatedCardCount,
                targetCount: max(targetCardCount, 1),
                progress: min(1.0, Double(generatedCardCount) / Double(max(targetCardCount, 1))),
                message: deckTitle.isEmpty ? "Resume in Create" : deckTitle,
                errorMessage: nil
            )
            return
        }

        switch aiState {
        case .idle:
            generationStatus = nil
        case .analyzingDocument:
            generationStatus = AIWorkspaceGenerationStatus(
                phase: .preparing,
                title: "Preparing AI source",
                foundCount: generatedCardCount,
                targetCount: max(targetCardCount, 1),
                progress: 0,
                message: deckTitle.isEmpty ? "Analyzing document" : deckTitle,
                errorMessage: nil
            )
        case .extractingText:
            generationStatus = AIWorkspaceGenerationStatus(
                phase: .preparing,
                title: "Preparing AI source",
                foundCount: generatedCardCount,
                targetCount: max(targetCardCount, 1),
                progress: 0,
                message: deckTitle.isEmpty ? "Reading source" : deckTitle,
                errorMessage: nil
            )
        case .generatingCards(let progress, let foundCount):
            generationStatus = AIWorkspaceGenerationStatus(
                phase: .running,
                title: "Generating cards",
                foundCount: foundCount,
                targetCount: max(targetCardCount, 1),
                progress: progress,
                message: deckTitle.isEmpty ? "Create" : deckTitle,
                errorMessage: nil
            )
        case .error(let message):
            generationStatus = AIWorkspaceGenerationStatus(
                phase: .failed,
                title: "Generation stopped",
                foundCount: generatedCardCount,
                targetCount: max(targetCardCount, 1),
                progress: 0,
                message: message,
                errorMessage: message
            )
        }
    }

    // MARK: - Conversion Runtime

    private func restoreGenerationStatus(from session: AIPausedSession) {
        generationStatus = AIWorkspaceGenerationStatus(
            phase: .paused,
            title: "AI generation paused",
            foundCount: session.generatedCardCount,
            targetCount: max(session.targetCardCount, 1),
            progress: min(1.0, Double(session.generatedCardCount) / Double(max(session.targetCardCount, 1))),
            message: session.deckTitle.isEmpty ? "Resume in Create" : session.deckTitle,
            errorMessage: nil
        )
    }

    private func restoreConversionSession(_ session: AIPausedConversionSession) {
        pausedConversionSession = session
        activeConversionTargetKind = session.request.targetKind
        conversionProgress = session.progress
        conversionSummary = nil
        conversionErrorMessage = nil
        shouldShowConversionOutcome = false
        workspaceDeckContext = makeWorkspaceDeckContext(
            sourceDeckID: session.sourceDeckID,
            sourceDeckTitle: session.sourceDeckTitle,
            request: session.request,
            liveDeckID: session.request.destination == .sameDeck ? session.sourceDeckID : session.destinationDeckID,
            destinationBaseCardIDs: session.destinationBaseCardIDs
        )
    }

    private func makeFreshConversionSession(
        request: DeckCardConversionRequest,
        sourceDeckID: PersistentIdentifier,
        context: ModelContext
    ) async throws -> AIPausedConversionSession {
        guard let sourceDeck = context.safeModel(for: sourceDeckID, as: DeckModel.self) else {
            throw NSError(
                domain: "AIWorkspaceConversion",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The source deck could not be loaded."]
            )
        }

        let sourceSnapshots = try await fetchFrozenConversionSources(
            request: request,
            deckID: sourceDeckID,
            container: context.container
        )

        guard !sourceSnapshots.isEmpty else {
            throw NSError(
                domain: "AIWorkspaceConversion",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "No eligible source cards were available."]
            )
        }

        guard let providerProfile = resolvedProviderProfile(for: nil) else {
            throw NSError(
                domain: "AIWorkspaceConversion",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "No AI provider is configured. Open Settings > AI Providers."]
            )
        }

        if let validationMessage = providerProfile.generationValidationMessage {
            throw NSError(
                domain: "AIWorkspaceConversion",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: validationMessage]
            )
        }

        let session = AIPausedConversionSession(
            sourceDeckID: sourceDeckID,
            sourceDeckTitle: sourceDeck.title,
            request: request,
            destinationBaseCardIDs: request.destination == .sameDeck
                ? sourceDeck.cards.map(\.persistentModelID)
                : [],
            remainingSources: sourceSnapshots,
            totalCount: sourceSnapshots.count,
            completedCount: 0,
            createdCount: 0,
            skippedCount: 0,
            failedCount: 0,
            statusMessage: "Preparing source cards",
            destinationDeckID: nil,
            providerProfileID: providerProfile.id,
            batchID: UUID(),
            convertedAt: Date()
        )
        pausedConversionSession = session
        conversionProgress = session.progress
        workspaceDeckContext = makeWorkspaceDeckContext(
            sourceDeckID: sourceDeckID,
            sourceDeckTitle: sourceDeck.title,
            request: request,
            liveDeckID: request.destination == .sameDeck ? sourceDeckID : nil,
            destinationBaseCardIDs: session.destinationBaseCardIDs
        )
        return session
    }

    private func continueConversion(
        from session: AIPausedConversionSession,
        context: ModelContext
    ) async throws {
        guard let sourceDeck = context.safeModel(for: session.sourceDeckID, as: DeckModel.self) else {
            throw NSError(
                domain: "AIWorkspaceConversion",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The source deck could not be loaded."]
            )
        }

        guard let providerProfile = resolvedProviderProfile(for: session.providerProfileID) else {
            throw NSError(
                domain: "AIWorkspaceConversion",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "No AI provider is configured. Open Settings > AI Providers."]
            )
        }

        if let validationMessage = providerProfile.generationValidationMessage {
            throw NSError(
                domain: "AIWorkspaceConversion",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: validationMessage]
            )
        }

        var runtimeSession = session
        activeConversionTargetKind = runtimeSession.request.targetKind
        conversionProgress = runtimeSession.progress
        pausedConversionSession = runtimeSession

        let aiService = AIFlashcardService(provider: providerProfile)
        var destinationDeck = runtimeSession.destinationDeckID.flatMap { id in
            context.safeModel(for: id, as: DeckModel.self)
        }

        let sourcesByID = Dictionary(uniqueKeysWithValues: runtimeSession.remainingSources.map { ($0.id, $0) })
        let groupedSources = CardKind.allCases.compactMap { kind -> (CardKind, [CardConversionSourceSnapshot])? in
            let group = runtimeSession.remainingSources.filter { $0.kind == kind }
            return group.isEmpty ? nil : (kind, group)
        }

        for (sourceKind, groupSources) in groupedSources {
            try Task.checkCancellation()

            let skippedSources = groupSources.filter {
                $0.kind == runtimeSession.request.targetKind ||
                $0.content.searchDocumentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            let convertibleSources = groupSources.filter { source in
                !skippedSources.contains(where: { $0.id == source.id })
            }

            if !skippedSources.isEmpty {
                let skippedSourceIDs = Set(skippedSources.map(\.id))
                runtimeSession = runtimeSession.updating(
                    removedSourceIDs: skippedSourceIDs,
                    completedDelta: skippedSources.count,
                    createdDelta: 0,
                    skippedDelta: skippedSources.count,
                    failedDelta: 0,
                    statusMessage: "Skipped \(skippedSources.count) \(sourceKind.displayTitle.lowercased()) card\(skippedSources.count == 1 ? "" : "s")"
                )
                try await persistPausedConversionSession(runtimeSession)
                updateConversionProgress(
                    totalCount: runtimeSession.totalCount,
                    completedCount: runtimeSession.completedCount,
                    createdCount: runtimeSession.createdCount,
                    skippedCount: runtimeSession.skippedCount,
                    failedCount: runtimeSession.failedCount,
                    statusMessage: runtimeSession.statusMessage
                )
            }

            guard !convertibleSources.isEmpty else { continue }

            updateConversionProgress(
                totalCount: runtimeSession.totalCount,
                completedCount: runtimeSession.completedCount,
                createdCount: runtimeSession.createdCount,
                skippedCount: runtimeSession.skippedCount,
                failedCount: runtimeSession.failedCount,
                statusMessage: "Converting \(sourceKind.displayTitle) to \(runtimeSession.request.targetKind.displayTitle)"
            )

            let conversionStream = aiService.convertCardsStream(
                convertibleSources.map {
                    AICardConversionSource(id: $0.id, kind: $0.kind, content: $0.content)
                },
                to: runtimeSession.request.targetKind.aiGenerationType
            )

            do {
                for try await chunk in conversionStream {
                    try Task.checkCancellation()

                    let persistedCount = try persistConvertedOutputs(
                        chunk.outputs,
                        request: runtimeSession.request,
                        sourcesByID: sourcesByID,
                        batchID: runtimeSession.batchID,
                        convertedAt: runtimeSession.convertedAt,
                        sourceDeck: sourceDeck,
                        destinationDeck: &destinationDeck,
                        context: context
                    )

                    let batchFailures = max(0, chunk.plannedCardCount - persistedCount)
                    runtimeSession = runtimeSession.updating(
                        removedSourceIDs: Set(chunk.plannedSourceIDs),
                        completedDelta: chunk.plannedCardCount,
                        createdDelta: persistedCount,
                        skippedDelta: 0,
                        failedDelta: batchFailures,
                        statusMessage: conversionStatusMessage(
                            for: chunk,
                            sourceKind: sourceKind,
                            targetKind: runtimeSession.request.targetKind,
                            persistedCount: persistedCount
                        ),
                        destinationDeckID: destinationDeck?.persistentModelID
                    )
                    try await persistPausedConversionSession(runtimeSession)

                    updateConversionProgress(
                        totalCount: runtimeSession.totalCount,
                        completedCount: runtimeSession.completedCount,
                        createdCount: runtimeSession.createdCount,
                        skippedCount: runtimeSession.skippedCount,
                        failedCount: runtimeSession.failedCount,
                        statusMessage: runtimeSession.statusMessage
                    )
                }
            } catch {
                logger.error("Conversion stream stopped early: \(error.localizedDescription, privacy: .public)")
                throw error
            }
        }

        pausedConversionSession = nil
        try? await jobSessionStore.clearSession()
        conversionProgress = nil
        conversionSummary = DeckCardConversionSummary(
            sourceCount: runtimeSession.totalCount,
            createdCount: runtimeSession.createdCount,
            skippedCount: runtimeSession.skippedCount,
            failedCount: runtimeSession.failedCount,
            targetKind: runtimeSession.request.targetKind,
            destination: runtimeSession.request.destination,
            destinationDeckTitle: runtimeSession.request.destination == .sameDeck
                ? sourceDeck.title
                : (destinationDeck?.title ?? runtimeSession.request.destinationDeckTitle ?? sourceDeck.title),
            destinationDeckID: runtimeSession.request.destination == .sameDeck
                ? sourceDeck.persistentModelID
                : destinationDeck?.persistentModelID
        )
        conversionErrorMessage = nil
        shouldShowConversionOutcome = true
        workspaceDeckContext = makeWorkspaceDeckContext(
            sourceDeckID: runtimeSession.sourceDeckID,
            sourceDeckTitle: runtimeSession.sourceDeckTitle,
            request: runtimeSession.request,
            liveDeckID: runtimeSession.request.destination == .sameDeck
                ? runtimeSession.sourceDeckID
                : destinationDeck?.persistentModelID,
            destinationBaseCardIDs: runtimeSession.destinationBaseCardIDs
        )
    }

    private func resolvedProviderProfile(for preferredProfileID: UUID?) -> AIProviderProfile? {
        let store = AIProviderStore.shared
        if let preferredProfileID,
           let preferredProfile = store.profiles.first(where: { $0.id == preferredProfileID }) {
            return preferredProfile
        }
        return store.activeProfile
    }

    private func persistPausedConversionSession(_ session: AIPausedConversionSession) async throws {
        pausedConversionSession = session
        conversionProgress = session.progress
        workspaceDeckContext = makeWorkspaceDeckContext(
            sourceDeckID: session.sourceDeckID,
            sourceDeckTitle: session.sourceDeckTitle,
            request: session.request,
            liveDeckID: session.request.destination == .sameDeck ? session.sourceDeckID : session.destinationDeckID,
            destinationBaseCardIDs: session.destinationBaseCardIDs
        )
        try await jobSessionStore.saveSession(.conversion(session))
    }

    private func makeWorkspaceDeckContext(
        sourceDeckID: PersistentIdentifier,
        sourceDeckTitle: String,
        request: DeckCardConversionRequest,
        liveDeckID: PersistentIdentifier?,
        destinationBaseCardIDs: [PersistentIdentifier]
    ) -> AIWorkspaceDeckContext {
        AIWorkspaceDeckContext(
            sourceDeckID: sourceDeckID,
            sourceDeckTitle: sourceDeckTitle,
            destination: request.destination,
            destinationDeckTitle: request.destinationDeckTitle,
            liveDeckID: liveDeckID,
            destinationBaseCardIDs: destinationBaseCardIDs
        )
    }

    private func fetchFrozenConversionSources(
        request: DeckCardConversionRequest,
        deckID: PersistentIdentifier,
        container: ModelContainer
    ) async throws -> [CardConversionSourceSnapshot] {
        let actor = CardFetchActor(container: container)
        let requestedIDs = request.resolvedCardIDs()
        let fetchedSources = await actor.fetchConversionSources(
            deckID: deckID,
            cardIDs: requestedIDs
        )
        await actor.tearDown()

        let snapshotsByID = Dictionary(uniqueKeysWithValues: fetchedSources.map { ($0.id, $0) })
        return request.filteredSources.compactMap { snapshotsByID[$0.id] }
    }

    private func conversionStatusMessage(
        for chunk: AIConversionBatchChunk,
        sourceKind: CardKind,
        targetKind: CardKind,
        persistedCount: Int
    ) -> String {
        let rejectedCount = max(0, chunk.plannedCardCount - persistedCount)

        if rejectedCount > 0, targetKind == .match {
            return "Accepted \(persistedCount) Match card\(persistedCount == 1 ? "" : "s") from \(sourceKind.displayTitle). Rejected \(rejectedCount) verbose pair\(rejectedCount == 1 ? "" : "s")."
        }

        if rejectedCount > 0 {
            return "Converted \(persistedCount) \(targetKind.displayTitle.lowercased()) card\(persistedCount == 1 ? "" : "s") from \(sourceKind.displayTitle). \(rejectedCount) failed."
        }

        return "Converted \(persistedCount) \(targetKind.displayTitle.lowercased()) card\(persistedCount == 1 ? "" : "s") from \(sourceKind.displayTitle)."
    }

    private func persistConvertedOutputs(
        _ outputs: [AICardConversionOutput],
        request: DeckCardConversionRequest,
        sourcesByID: [PersistentIdentifier: CardConversionSourceSnapshot],
        batchID: UUID,
        convertedAt: Date,
        sourceDeck: DeckModel,
        destinationDeck: inout DeckModel?,
        context: ModelContext
    ) throws -> Int {
        guard !outputs.isEmpty else { return 0 }

        let destinationWasCreatedInThisCall = destinationDeck == nil && request.destination == .newDeck
        let targetDeck = try resolveDestinationDeck(
            for: request,
            sourceDeck: sourceDeck,
            destinationDeck: &destinationDeck,
            context: context
        )

        let originalLastAssigned = targetDeck.lastAssignedCardNumber
        let originalCardCount = targetDeck.cardCount
        let originalEditedAt = targetDeck.editedAt
        let insertedCardsStart = targetDeck.cards.count
        var insertedCards: [CardModel] = []
        var nextCardNumber = targetDeck.lastAssignedCardNumber
        var representedSourceIDs = Set(
            targetDeck.cards.compactMap { card -> PersistentIdentifier? in
                guard let metadata = card.conversionMetadata,
                      metadata.batchID == batchID,
                      metadata.targetKind == request.targetKind else {
                    return nil
                }
                return metadata.sourceCardID
            }
        )

        do {
            for output in outputs {
                if representedSourceIDs.contains(output.sourceCardID) {
                    continue
                }

                guard let source = sourcesByID[output.sourceCardID] else {
                    logger.error("Skipping converted output because the source card snapshot was missing.")
                    continue
                }

                let content: DraftCardContent
                do {
                    content = try AIGeneratedCardContentMapper.map(output.generatedCard)
                } catch {
                    logger.error("Skipping converted output because mapping failed: \(error.localizedDescription, privacy: .public)")
                    continue
                }
                nextCardNumber += 1

                let newCard = CardModel(
                    content: content,
                    cardNumber: nextCardNumber,
                    isPinned: false,
                    creationSource: .ai,
                    conversionMetadata: CardConversionMetadata(
                        sourceCardID: source.id,
                        sourceKind: source.kind,
                        targetKind: request.targetKind,
                        batchID: batchID,
                        convertedAt: convertedAt
                    )
                )
                newCard.deck = targetDeck
                targetDeck.cards.append(newCard)
                context.insert(newCard)
                insertedCards.append(newCard)
                representedSourceIDs.insert(output.sourceCardID)
            }

            targetDeck.lastAssignedCardNumber = nextCardNumber
            targetDeck.cardCount = originalCardCount + insertedCards.count
            targetDeck.editedAt = Date()
            try context.save()
            return representedSourceIDs.intersection(Set(outputs.map(\.sourceCardID))).count
        } catch {
            for card in insertedCards {
                context.delete(card)
            }
            targetDeck.cards.removeSubrange(insertedCardsStart..<targetDeck.cards.count)
            targetDeck.lastAssignedCardNumber = originalLastAssigned
            targetDeck.cardCount = originalCardCount
            targetDeck.editedAt = originalEditedAt

            if destinationWasCreatedInThisCall {
                if let folder = targetDeck.folder {
                    folder.deckCount = max(0, folder.deckCount - 1)
                }
                context.delete(targetDeck)
                destinationDeck = nil
            }
            throw error
        }
    }

    private func resolveDestinationDeck(
        for request: DeckCardConversionRequest,
        sourceDeck: DeckModel,
        destinationDeck: inout DeckModel?,
        context: ModelContext
    ) throws -> DeckModel {
        if let destinationDeck {
            return destinationDeck
        }

        switch request.destination {
        case .sameDeck:
            return sourceDeck
        case .newDeck:
            guard let title = request.destinationDeckTitle else {
                throw NSError(
                    domain: "AIWorkspaceConversion",
                    code: 5,
                    userInfo: [NSLocalizedDescriptionKey: "Add a title for the new converted deck."]
                )
            }

            let newDeck = DeckModel(
                title: title,
                icon: sourceDeck.icon,
                colorHex: sourceDeck.colorHex
            )
            newDeck.cardGroupingMode = sourceDeck.cardGroupingMode
            context.insert(newDeck)
            if let folder = sourceDeck.folder {
                newDeck.folder = folder
                folder.deckCount += 1
            }
            destinationDeck = newDeck
            return newDeck
        }
    }

    private func discardConvertedOutputs(
        from session: AIPausedConversionSession,
        context: ModelContext
    ) throws {
        let targetDeckID: PersistentIdentifier?
        switch session.request.destination {
        case .sameDeck:
            targetDeckID = session.sourceDeckID
        case .newDeck:
            targetDeckID = session.destinationDeckID
        }

        guard let targetDeckID,
              let targetDeck = context.safeModel(for: targetDeckID, as: DeckModel.self) else {
            return
        }

        let batchCardIDs = Set(
            targetDeck.cards.compactMap { card -> PersistentIdentifier? in
                guard let metadata = card.conversionMetadata,
                      metadata.batchID == session.batchID,
                      metadata.targetKind == session.request.targetKind else {
                    return nil
                }
                return card.persistentModelID
            }
        )

        guard !batchCardIDs.isEmpty else { return }

        for card in targetDeck.cards where batchCardIDs.contains(card.persistentModelID) {
            context.delete(card)
        }
        targetDeck.cards.removeAll { batchCardIDs.contains($0.persistentModelID) }
        targetDeck.cardCount = targetDeck.cards.count
        targetDeck.lastAssignedCardNumber = targetDeck.cards.map(\.cardNumber).max() ?? 0
        targetDeck.editedAt = Date()

        if session.request.destination == .newDeck && targetDeck.cards.isEmpty {
            if let folder = targetDeck.folder {
                folder.deckCount = max(0, folder.deckCount - 1)
            }
            context.delete(targetDeck)
        }

        try context.save()
    }

    private func updateConversionProgress(
        totalCount: Int,
        completedCount: Int,
        createdCount: Int,
        skippedCount: Int,
        failedCount: Int,
        statusMessage: String
    ) {
        conversionProgress = DeckCardConversionProgress(
            totalCount: totalCount,
            completedCount: completedCount,
            createdCount: createdCount,
            skippedCount: skippedCount,
            failedCount: failedCount,
            statusMessage: statusMessage
        )
    }
}
