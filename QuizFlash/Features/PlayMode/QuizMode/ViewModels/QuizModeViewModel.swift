//
//  QuizModeViewModel.swift
//  QuizFlash
//
//  Runtime state and detached persistence orchestration for the quiz mode.
//

import Foundation
import Observation
import SwiftData

// MARK: - QuizModeViewModel

/// Owns one-question quiz flow, first-pass retry queues, and detached review writes.
@Observable
@MainActor
final class QuizModeViewModel {

    // MARK: - Session State

    let deck: DeckModel
    let settings: QuizModeSettings

    var cards: [QuizPlayableCard] = []
    var currentIndex = 0
    var isRetryPass = false
    var selectedChoiceIDs: Set<UUID> = []
    var isEvaluated = false
    var lastEvaluationWasCorrect: Bool?
    var wrongCards: [QuizPlayableCard] = []
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
    var isShowingRetryPrompt = false
    var completionSnapshot: SessionOutcomeSnapshot?
    var isExplanationRevealed = false

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
    private var currentQuestionStartTime = Date()

    // MARK: - Init

    init(deck: DeckModel, settings: QuizModeSettings) {
        self.deck = deck
        self.settings = settings
    }

    // MARK: - Derived State

    var currentCard: QuizPlayableCard? {
        guard currentIndex >= 0, currentIndex < cards.count, !isShowingRetryPrompt, !isComplete else {
            return nil
        }
        return cards[currentIndex]
    }

    var resolvedDeckTitle: String {
        let trimmed = deck.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Deck" : trimmed
    }

    var progressFraction: Double {
        guard !cards.isEmpty else { return 0 }
        if isShowingRetryPrompt { return 1 }
        let reviewed = min(currentIndex, cards.count)
        return min(1, Double(reviewed) / Double(cards.count))
    }

    var progressLabel: String {
        guard !cards.isEmpty else { return "0/1 reviewed" }
        if isShowingRetryPrompt { return "\(cards.count)/\(cards.count) reviewed" }
        return "\(min(currentIndex, cards.count))/\(cards.count) reviewed"
    }

    var formattedSessionDuration: String {
        PlaySessionFormatting.formatDuration(Date().timeIntervalSince(sessionStartTime))
    }

    var retryPassCount: Int {
        retryEvaluationCount
    }

    var shouldShowExplanation: Bool {
        guard isEvaluated, currentCard?.explanationZone != nil else { return false }
        return settings.explanationTiming == .afterCheck || isExplanationRevealed
    }

    var requiresSubmitAction: Bool {
        guard let currentCard, !isEvaluated else { return false }
        return currentCard.allowsMultipleCorrect || settings.answerValidation == .submit
    }

    var primaryActionTitle: String {
        if isShowingRetryPrompt { return "Retry Wrong Questions" }
        guard currentCard != nil else { return "Continue" }
        if isEvaluated { return currentIndex == cards.count - 1 ? "Continue" : "Next" }
        return "Submit"
    }

    var canSubmitAnswer: Bool {
        guard let currentCard else { return false }
        guard !isEvaluated else { return false }

        if currentCard.allowsMultipleCorrect {
            return !selectedChoiceIDs.isEmpty
        }

        return selectedChoiceIDs.count == 1
    }

    // MARK: - Lifecycle

    /// Loads and validates the deck's quiz payloads, then primes the first question.
    func startSession(container: ModelContainer) async {
        guard loadState == .idle else { return }

        sessionStartTime = Date()
        loadState = .loading
        persistenceService = PlaySessionPersistenceService(container: container)

        let repository = PlayModeCardRepository(container: container)
        let result = await repository.loadValidatedQuizCards(for: deck.persistentModelID)
        let sortedCards = Self.studyOrdered(result.cards)

        diagnostics = result.diagnostics
        cards = settings.shuffleChoices ? shuffledChoices(in: sortedCards) : sortedCards

        guard !cards.isEmpty else {
            loadState = result.diagnostics.hasOnlyInvalidCards ? .invalid : .empty
            return
        }

        currentIndex = 0
        currentQuestionStartTime = Date()
        loadState = .ready
    }

    /// Releases transient session state and cache-heavy render resources.
    func tearDown() {
        cards = []
        wrongCards = []
        persistenceService = nil
        MathWebViewPool.shared.flush()
        ImageCache.shared.clearCache()
    }

    // MARK: - Interaction

    /// Handles a tap on one answer choice, including immediate evaluation for single-answer cards.
    func selectChoice(_ choiceID: UUID) {
        guard let currentCard, !isEvaluated else { return }

        if currentCard.allowsMultipleCorrect {
            if selectedChoiceIDs.contains(choiceID) {
                selectedChoiceIDs.remove(choiceID)
            } else {
                selectedChoiceIDs.insert(choiceID)
            }
            return
        }

        selectedChoiceIDs = [choiceID]
        if settings.answerValidation == .instantCheck {
            evaluateSelection()
        }
    }

    /// Evaluates the current answer selection for multi-answer quiz cards.
    func submitAnswer() {
        guard canSubmitAnswer else { return }
        evaluateSelection()
    }

    /// Advances to the next question, retry prompt, or final completion overlay.
    func advance() {
        if isShowingRetryPrompt {
            startRetryPass()
            return
        }

        guard isEvaluated else { return }

        selectedChoiceIDs = []
        isEvaluated = false
        lastEvaluationWasCorrect = nil
        isExplanationRevealed = false
        currentIndex += 1

        if currentIndex >= cards.count {
            if !isRetryPass && settings.retryIncorrectQuestions && !wrongCards.isEmpty {
                isShowingRetryPrompt = true
            } else {
                finishSession()
            }
        } else {
            currentQuestionStartTime = Date()
        }
    }

    // MARK: - Private

    private func evaluateSelection() {
        guard let currentCard else { return }

        isEvaluated = true
        isExplanationRevealed = settings.explanationTiming == .afterCheck
        markReviewed(currentCard.id)

        let correctChoiceIDs = Set(currentCard.choices.filter(\.isCorrect).map(\.id))
        let isCorrect = selectedChoiceIDs == correctChoiceIDs
        lastEvaluationWasCorrect = isCorrect

        if isRetryPass {
            retryEvaluationCount += 1
        }

        let timeSpent = Date().timeIntervalSince(currentQuestionStartTime)

        if isCorrect {
            correctCount += 1
            let xp = PlaySessionXP.awarded(for: .good, timeSpent: timeSpent)
            sessionXP += xp

            persist(
                PlaySessionReviewWrite(
                    cardID: currentCard.id,
                    difficulty: .good,
                    timeSpent: timeSpent,
                    xpAwarded: xp
                )
            )
            return
        }

        wrongCount += 1
        missedCardIDs.insert(currentCard.id)

        guard !isRetryPass else { return }

        firstPassFailedIDs.insert(currentCard.id)
        wrongCards.append(currentCard)

        let xp = PlaySessionXP.awarded(for: .again, timeSpent: timeSpent)
        sessionXP += xp

        persist(
            PlaySessionReviewWrite(
                cardID: currentCard.id,
                difficulty: .again,
                timeSpent: timeSpent,
                xpAwarded: xp
            )
        )
    }

    private func startRetryPass() {
        let retryCards = Self.studyOrdered(wrongCards)
        wrongCards = []
        cards = settings.shuffleChoices ? shuffledChoices(in: retryCards) : retryCards
        currentIndex = 0
        isRetryPass = true
        isShowingRetryPrompt = false
        isEvaluated = false
        selectedChoiceIDs = []
        lastEvaluationWasCorrect = nil
        isExplanationRevealed = false
        currentQuestionStartTime = Date()
    }

    private func finishSession() {
        isComplete = true
        isShowingRetryPrompt = false
        completionSnapshot = SessionOutcomeSnapshot(
            mode: .quiz,
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

    func revealExplanation() {
        guard isEvaluated else { return }
        isExplanationRevealed = true
    }

    private static func studyOrdered(_ cards: [QuizPlayableCard]) -> [QuizPlayableCard] {
        cards.sorted { lhs, rhs in
            if lhs.interval == 0 && rhs.interval != 0 { return true }
            if lhs.interval != 0 && rhs.interval == 0 { return false }
            if lhs.interval != rhs.interval { return lhs.interval < rhs.interval }
            return lhs.cardNumber < rhs.cardNumber
        }
    }

    private func shuffledChoices(in cards: [QuizPlayableCard]) -> [QuizPlayableCard] {
        cards.map { card in
            QuizPlayableCard(
                id: card.id,
                cardNumber: card.cardNumber,
                interval: card.interval,
                questionZone: card.questionZone,
                choices: card.choices.shuffled(),
                explanationZone: card.explanationZone,
                allowsMultipleCorrect: card.allowsMultipleCorrect
            )
        }
    }
}
