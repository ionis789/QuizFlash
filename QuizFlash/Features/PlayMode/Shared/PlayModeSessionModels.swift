//
//  PlayModeSessionModels.swift
//  QuizFlash
//
//  Shared runtime models for gameplay sessions.
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - Validated Play Load Result

/// A validated payload bundle returned by the background play-mode repository.
struct ValidatedPlayModeLoadResult<Payload: Sendable>: Sendable {
    let cards: [Payload]
    let diagnostics: PlayModeValidationDiagnostics
}

// MARK: - Validation Diagnostics

/// Explicit runtime validation buckets for mode-specific invalid cards.
enum PlayModeValidationReason: String, CaseIterable, Hashable, Sendable {
    case missingQuestion
    case insufficientChoices
    case missingCorrectChoice
    case multipleCorrectChoicesDisallowed
}

/// Deck-level diagnostics emitted alongside validated runtime payloads.
struct PlayModeValidationDiagnostics: Equatable, Sendable {
    let compatibleCount: Int
    let playableCount: Int
    let invalidReasonCounts: [PlayModeValidationReason: Int]

    /// Number of compatible cards rejected by runtime validation.
    var skippedInvalidCount: Int {
        max(compatibleCount - playableCount, 0)
    }

    /// `true` when the deck had compatible cards but every one of them was invalid at runtime.
    var hasOnlyInvalidCards: Bool {
        compatibleCount > 0 && playableCount == 0
    }

    /// Stable, non-zero reason buckets sorted by severity label for UI rendering.
    var nonZeroReasonCounts: [(reason: PlayModeValidationReason, count: Int)] {
        PlayModeValidationReason.allCases.compactMap { reason in
            guard let count = invalidReasonCounts[reason], count > 0 else { return nil }
            return (reason, count)
        }
    }

    /// Empty diagnostics placeholder used before the first repository load completes.
    nonisolated static let empty = PlayModeValidationDiagnostics(
        compatibleCount: 0,
        playableCount: 0,
        invalidReasonCounts: [:]
    )
}

// MARK: - Session Lifecycle

/// Shared loading phases for the interactive play-mode runtimes.
enum PlayModeSessionLoadState: Equatable {
    case idle
    case loading
    case ready
    case empty
    case invalid
    case failed
}

/// In-memory completion summary used by gameplay overlays and future analytics hooks.
struct SessionOutcomeSnapshot: Equatable, Sendable {
    let mode: DeckPlayModeDestination
    let duration: TimeInterval
    let correctCount: Int
    let wrongCount: Int
    let retryCount: Int
    let invalidSkippedCount: Int
    let reviewedCardIDs: [PersistentIdentifier]
    let missedCardIDs: [PersistentIdentifier]
}

// MARK: - Completion UI

/// One completion metric tile shown inside play-mode overlays.
struct PlayModeCompletionStat: Identifiable {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var id: String { title }
}

// MARK: - XP

/// Shared XP rules aligned with the existing flashcards session semantics.
enum PlaySessionXP {
    static func awarded(for difficulty: ReviewDifficulty, timeSpent: TimeInterval) -> Int {
        let baseXP = difficulty == .good ? 10 : 2
        let speedBonus = difficulty == .good && timeSpent < 4.0 ? 5 : 0
        return baseXP + speedBonus
    }
}

/// Shared formatting helpers used across play-mode session overlays and headers.
enum PlaySessionFormatting {
    static func formatDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return minutes > 0 ? "\(minutes)m \(seconds)s" : "\(seconds)s"
    }
}
