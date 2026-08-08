//
//  AIWorkspaceCoordinator.swift
//  QuizFlash
//
//  Global AI workspace owner coordinating deck generation status.
//

import SwiftUI
import SwiftData
import OSLog

// MARK: - Workspace Types

enum AIWorkspaceJobKind: String, Equatable, Sendable {
    case generation
}

enum AIWorkspaceJobPhase: Equatable, Sendable {
    case preparing
    case running
    case paused
    case completed
    case failed
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

// MARK: - Coordinator

@Observable
@MainActor
final class AIWorkspaceCoordinator {
    let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "QuizFlash",
        category: "AIWorkspaceCoordinator"
    )

    @ObservationIgnored let jobSessionStore: AIJobSessionStore
    @ObservationIgnored var hasRestoredPersistedJob = false
    @ObservationIgnored private var generationOwnerID: UUID?

    var generationStatus: AIWorkspaceGenerationStatus?

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
        return false
    }

    var floatingStatus: AIWorkspaceFloatingStatus? {
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

    func openWorkspace(router: NavigationManager) {
        guard generationStatus != nil else { return }
        router.showCreateRoot()
    }

    func restorePersistedJobIfNeeded(context: ModelContext) async {
        guard !hasRestoredPersistedJob else { return }
        hasRestoredPersistedJob = true

        guard let session = await jobSessionStore.loadSession() else { return }
        switch session {
        case .generation(let pausedSession):
            generationStatus = AIWorkspaceGenerationStatus(
                phase: .paused,
                title: "AI generation paused",
                foundCount: pausedSession.generatedCardCount,
                targetCount: max(pausedSession.targetCardCount, 1),
                progress: min(
                    1.0,
                    Double(pausedSession.generatedCardCount) / Double(max(pausedSession.targetCardCount, 1))
                ),
                message: pausedSession.deckTitle,
                errorMessage: nil
            )
        }
    }

    func syncGenerationState(
        ownerID: UUID,
        aiState: AIGenerationState,
        hasPausedGeneration: Bool,
        generatedCardCount: Int,
        targetCardCount: Int,
        deckTitle: String
    ) {
        if hasPausedGeneration {
            generationOwnerID = ownerID
            generationStatus = AIWorkspaceGenerationStatus(
                phase: .paused,
                title: "AI generation paused",
                foundCount: generatedCardCount,
                targetCount: max(targetCardCount, 1),
                progress: min(1.0, Double(generatedCardCount) / Double(max(targetCardCount, 1))),
                message: deckTitle,
                errorMessage: nil
            )
            return
        }

        switch aiState {
        case .idle:
            guard generationOwnerID == ownerID else { return }
            generationOwnerID = nil
            generationStatus = nil
        case .analyzingDocument:
            generationOwnerID = ownerID
            generationStatus = AIWorkspaceGenerationStatus(
                phase: .preparing,
                title: "Preparing AI source",
                foundCount: generatedCardCount,
                targetCount: max(targetCardCount, 1),
                progress: 0,
                message: deckTitle,
                errorMessage: nil
            )
        case .extractingText:
            generationOwnerID = ownerID
            generationStatus = AIWorkspaceGenerationStatus(
                phase: .preparing,
                title: "Preparing AI source",
                foundCount: generatedCardCount,
                targetCount: max(targetCardCount, 1),
                progress: 0,
                message: deckTitle,
                errorMessage: nil
            )
        case .generatingCards(let progress, let foundCount):
            generationOwnerID = ownerID
            generationStatus = AIWorkspaceGenerationStatus(
                phase: .running,
                title: "Generating cards",
                foundCount: foundCount,
                targetCount: max(targetCardCount, 1),
                progress: progress,
                message: deckTitle,
                errorMessage: nil
            )
        case .error(let message):
            generationOwnerID = ownerID
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
