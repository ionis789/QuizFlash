//
//  WriteModeViewModel.swift
//  QuizFlash
//
//  Runtime state and detached persistence orchestration for the write mode.
//

import Foundation
import Observation
import SwiftData

// MARK: - WriteModeViewModel

/// Owns one-prompt write flow, normalized answer matching, and retry-pass orchestration.
@Observable
@MainActor
final class WriteModeViewModel {

    // MARK: - Session State

    let deck: DeckModel

    var prompts: [WritePlayableCard] = []
    var currentIndex = 0
    var currentInput = ""
    var isEvaluated = false
    var lastCheckWasCorrect: Bool?
    var wrongCards: [WritePlayableCard] = []
    var firstPassFailedIDs: Set<PersistentIdentifier> = []
    var sessionXP = 0
    var sessionStartTime = Date()
    var loadState: PlayModeSessionLoadState = .idle
    var isComplete = false

    // MARK: - Supporting State

    var diagnostics: PlayModeValidationDiagnostics = .empty
    var errorMessage = ""
    var correctCount = 0
    var wrongCount = 0
    var isRetryPass = false
    var isShowingRetryPrompt = false
    var completionSnapshot: SessionOutcomeSnapshot?

    // MARK: - Private

    @ObservationIgnored
    private var persistenceService: PlaySessionPersistenceService?

    @ObservationIgnored
    private var reviewedCardIDs: [PersistentIdentifier] = []

    @ObservationIgnored
    private var reviewedCardIDSet: Set<PersistentIdentifier> = []

    @ObservationIgnored
    private var missedCardIDs: Set<PersistentIdentifier> = []

    @ObservationIgnored
    private var retryEvaluationCount = 0

    @ObservationIgnored
    private var currentPromptStartTime = Date()

    // MARK: - Init

    init(deck: DeckModel) {
        self.deck = deck
    }

    // MARK: - Derived State

    var currentPrompt: WritePlayableCard? {
        guard currentIndex >= 0, currentIndex < prompts.count, !isShowingRetryPrompt, !isComplete else {
            return nil
        }
        return prompts[currentIndex]
    }

    var resolvedDeckTitle: String {
        let trimmed = deck.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Deck" : trimmed
    }

    var canCheckAnswer: Bool {
        guard !isEvaluated else { return false }
        return !Self.normalizedAnswer(currentInput).isEmpty
    }

    var progressFraction: Double {
        guard !prompts.isEmpty else { return 0 }
        if isShowingRetryPrompt { return 1 }
        return min(1, Double(min(currentIndex, prompts.count)) / Double(prompts.count))
    }

    var progressLabel: String {
        guard !prompts.isEmpty else { return "0/1 reviewed" }
        if isShowingRetryPrompt { return "\(prompts.count)/\(prompts.count) reviewed" }
        return "\(min(currentIndex, prompts.count))/\(prompts.count) reviewed"
    }

    var formattedSessionDuration: String {
        PlaySessionFormatting.formatDuration(Date().timeIntervalSince(sessionStartTime))
    }

    var retryPassCount: Int {
        retryEvaluationCount
    }

    // MARK: - Lifecycle

    /// Loads and validates the deck's write payloads, then primes the first prompt.
    func startSession(container: ModelContainer) async {
        guard loadState == .idle else { return }

        sessionStartTime = Date()
        loadState = .loading
        persistenceService = PlaySessionPersistenceService(container: container)

        let repository = PlayModeCardRepository(container: container)
        let result = await repository.loadValidatedWriteCards(for: deck.persistentModelID)
        let sortedPrompts = Self.studyOrdered(result.cards)

        diagnostics = result.diagnostics
        prompts = sortedPrompts

        guard !sortedPrompts.isEmpty else {
            loadState = result.diagnostics.hasOnlyInvalidCards ? .invalid : .empty
            return
        }

        currentIndex = 0
        currentPromptStartTime = Date()
        loadState = .ready
    }

    /// Releases transient session state and cache-heavy render resources.
    func tearDown() {
        prompts = []
        wrongCards = []
        persistenceService = nil
        MathWebViewPool.shared.flush()
        ImageCache.shared.clearCache()
    }

    // MARK: - Interaction

    /// Evaluates the current typed answer against the canonical omitted text.
    func checkAnswer() {
        guard let currentPrompt, canCheckAnswer else { return }

        isEvaluated = true
        markReviewed(currentPrompt.id)

        if isRetryPass {
            retryEvaluationCount += 1
        }

        let isCorrect = Self.normalizedAnswer(currentInput) == Self.normalizedAnswer(currentPrompt.omittedText)
        lastCheckWasCorrect = isCorrect

        let timeSpent = Date().timeIntervalSince(currentPromptStartTime)

        if isCorrect {
            correctCount += 1
            let xp = PlaySessionXP.awarded(for: .good, timeSpent: timeSpent)
            sessionXP += xp

            persist(
                PlaySessionReviewWrite(
                    cardID: currentPrompt.id,
                    difficulty: .good,
                    timeSpent: timeSpent,
                    xpAwarded: xp
                )
            )
            return
        }

        wrongCount += 1
        missedCardIDs.insert(currentPrompt.id)

        guard !isRetryPass else { return }

        firstPassFailedIDs.insert(currentPrompt.id)
        wrongCards.append(currentPrompt)

        let xp = PlaySessionXP.awarded(for: .again, timeSpent: timeSpent)
        sessionXP += xp

        persist(
            PlaySessionReviewWrite(
                cardID: currentPrompt.id,
                difficulty: .again,
                timeSpent: timeSpent,
                xpAwarded: xp
            )
        )
    }

    /// Advances to the next prompt, retry prompt, or completion overlay.
    func advance() {
        if isShowingRetryPrompt {
            startRetryPass()
            return
        }

        guard isEvaluated else { return }

        currentInput = ""
        isEvaluated = false
        lastCheckWasCorrect = nil
        currentIndex += 1

        if currentIndex >= prompts.count {
            if !isRetryPass && !wrongCards.isEmpty {
                isShowingRetryPrompt = true
            } else {
                finishSession()
            }
        } else {
            currentPromptStartTime = Date()
        }
    }

    // MARK: - Private

    private func startRetryPass() {
        let retryPrompts = Self.studyOrdered(wrongCards)
        wrongCards = []
        prompts = retryPrompts
        currentIndex = 0
        currentInput = ""
        isRetryPass = true
        isShowingRetryPrompt = false
        isEvaluated = false
        lastCheckWasCorrect = nil
        currentPromptStartTime = Date()
    }

    private func finishSession() {
        isComplete = true
        isShowingRetryPrompt = false
        completionSnapshot = SessionOutcomeSnapshot(
            mode: .write,
            duration: Date().timeIntervalSince(sessionStartTime),
            correctCount: correctCount,
            wrongCount: wrongCount,
            retryCount: retryEvaluationCount,
            invalidSkippedCount: diagnostics.skippedInvalidCount,
            reviewedCardIDs: reviewedCardIDs,
            missedCardIDs: Array(missedCardIDs)
        )
    }

    private func markReviewed(_ cardID: PersistentIdentifier) {
        guard reviewedCardIDSet.insert(cardID).inserted else { return }
        reviewedCardIDs.append(cardID)
    }

    private func persist(_ review: PlaySessionReviewWrite) {
        let persistenceService = persistenceService

        Task.detached(priority: .utility) {
            await persistenceService?.persistReviews([review])
        }
    }

    private static func studyOrdered(_ prompts: [WritePlayableCard]) -> [WritePlayableCard] {
        prompts.sorted { lhs, rhs in
            if lhs.interval == 0 && rhs.interval != 0 { return true }
            if lhs.interval != 0 && rhs.interval == 0 { return false }
            if lhs.interval != rhs.interval { return lhs.interval < rhs.interval }
            return lhs.cardNumber < rhs.cardNumber
        }
    }

    private static func normalizedAnswer(_ answer: String) -> String {
        let normalizedQuotes = answer
            .replacingOccurrences(of: "“", with: "\"")
            .replacingOccurrences(of: "”", with: "\"")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "‑", with: "-")
            .replacingOccurrences(of: "\u{00A0}", with: " ")

        let collapsedWhitespace = normalizedQuotes
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let trimmedPunctuation = collapsedWhitespace.trimmingCharacters(
            in: CharacterSet(charactersIn: "\"'()[]{}.,!?;:-")
        )

        return trimmedPunctuation.lowercased()
    }
}
