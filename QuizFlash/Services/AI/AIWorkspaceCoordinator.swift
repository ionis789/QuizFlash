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
    let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "QuizFlash",
        category: "AIWorkspaceCoordinator"
    )

    @ObservationIgnored let jobSessionStore: AIJobSessionStore
    @ObservationIgnored var conversionTask: Task<Void, Never>?
    @ObservationIgnored var hasRestoredPersistedJob = false

    var generationStatus: AIWorkspaceGenerationStatus?
    var conversionSeed: AIWorkspaceConversionSeed?
    var conversionSheetToken: AIWorkspaceConversionSheetToken?
    var conversionProgress: DeckCardConversionProgress?
    var conversionSummary: DeckCardConversionSummary?
    var conversionErrorMessage: String?
    var workspaceDeckContext: AIWorkspaceDeckContext?
    var conversionReturnContext: AIWorkspaceReturnContext?
    var showConversionCancelDialog = false

    var activeConversionTargetKind: CardKind?
    var shouldShowConversionOutcome = false
    var pausedConversionSession: AIPausedConversionSession?

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
}
