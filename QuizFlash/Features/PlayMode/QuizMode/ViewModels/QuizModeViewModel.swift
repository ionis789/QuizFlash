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
    var incorrectChoiceIDs: Set<UUID> = []
    var missedCorrectChoiceIDs: Set<UUID> = []
    var revealedMissedCorrectChoiceIDs: Set<UUID> = []
    var wrongFeedbackChoiceIDs: Set<UUID> = []
    var wrongFeedbackTrigger = 0
    var evaluationFeedbackTrigger = 0
    var evaluationFeedbackWasCorrect: Bool?
    var isEvaluated = false
    var lastEvaluationWasCorrect: Bool?
    var currentQuestionHasWrongAttempt = false
    var wrongCards: [QuizPlayableCard] = []
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
    private var currentPassFailedIDs: Set<PersistentIdentifier> = []

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

    var hasMissedCorrectChoices: Bool {
        isEvaluated && !missedCorrectChoiceIDs.isEmpty
    }

    var canRevealMissedCorrectChoices: Bool {
        hasMissedCorrectChoices && revealedMissedCorrectChoiceIDs != missedCorrectChoiceIDs
    }

    // MARK: - Lifecycle

    /// Loads and validates the deck's quiz payloads, then primes the first question.
    func startSession(container: ModelContainer) async {
        guard loadState == .idle else { return }

        sessionStartTime = Date()
        loadState = .loading
        persistenceService = PlaySessionPersistenceService(container: container)
        currentPassFailedIDs = []

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
        currentPassFailedIDs = []
        persistenceService = nil
        MathWebViewPool.shared.flush()
        ImageCache.shared.clearCache()
    }

    // MARK: - Interaction

    /// Handles a tap on one answer choice, including immediate evaluation for single-answer cards.
    func selectChoice(_ choiceID: UUID) {
        guard let currentCard else { return }

        if isEvaluated {
            guard lastEvaluationWasCorrect == false, !currentCard.allowsMultipleCorrect else { return }
            isEvaluated = false
            lastEvaluationWasCorrect = nil
            missedCorrectChoiceIDs = []
            revealedMissedCorrectChoiceIDs = []
            wrongFeedbackChoiceIDs = []
            isExplanationRevealed = false
        }

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

    func revealMissedCorrectChoices() {
        guard hasMissedCorrectChoices else { return }
        revealedMissedCorrectChoiceIDs = missedCorrectChoiceIDs
    }

    /// Advances to the next question, retry prompt, or final completion overlay.
    func advance() {
        if isShowingRetryPrompt {
            startRetryPass()
            return
        }

        guard isEvaluated else { return }

        selectedChoiceIDs = []
        incorrectChoiceIDs = []
        missedCorrectChoiceIDs = []
        revealedMissedCorrectChoiceIDs = []
        wrongFeedbackChoiceIDs = []
        isEvaluated = false
        lastEvaluationWasCorrect = nil
        currentQuestionHasWrongAttempt = false
        isExplanationRevealed = false
        currentIndex += 1

        if currentIndex >= cards.count {
            if settings.retryIncorrectQuestions && !wrongCards.isEmpty {
                isShowingRetryPrompt = true
            } else {
                finishSession()
            }
        } else {
            currentQuestionStartTime = Date()
        }
    }

    /// Refreshes the visible quiz snapshot after editing the persisted current card.
    func refreshCurrentCard(from card: CardModel) {
        guard let refreshedCard = Self.playableCard(from: card),
              let index = cards.firstIndex(where: { $0.id == refreshedCard.id }) else {
            return
        }

        let existingChoices = cards[index].choices
        let choices = settings.shuffleChoices
            ? Self.choices(refreshedCard.choices, preservingOrderFrom: existingChoices)
            : refreshedCard.choices

        cards[index] = QuizPlayableCard(
            id: refreshedCard.id,
            cardNumber: refreshedCard.cardNumber,
            interval: refreshedCard.interval,
            questionZone: refreshedCard.questionZone,
            choices: choices,
            explanationZone: refreshedCard.explanationZone,
            allowsMultipleCorrect: refreshedCard.allowsMultipleCorrect
        )

        if index == currentIndex {
            selectedChoiceIDs = []
            incorrectChoiceIDs = []
            missedCorrectChoiceIDs = []
            revealedMissedCorrectChoiceIDs = []
            wrongFeedbackChoiceIDs = []
            isEvaluated = false
            lastEvaluationWasCorrect = nil
            currentQuestionHasWrongAttempt = false
            isExplanationRevealed = false
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
        let selectedIncorrectChoiceIDs = selectedChoiceIDs.subtracting(correctChoiceIDs)
        let selectedCorrectChoiceIDs = selectedChoiceIDs.intersection(correctChoiceIDs)
        let missedCorrectIDs = correctChoiceIDs.subtracting(selectedChoiceIDs)
        let isCorrect = selectedIncorrectChoiceIDs.isEmpty && missedCorrectIDs.isEmpty
        let isPartialCorrect = currentCard.allowsMultipleCorrect
            && !selectedCorrectChoiceIDs.isEmpty
            && selectedIncorrectChoiceIDs.isEmpty
            && !missedCorrectIDs.isEmpty

        missedCorrectChoiceIDs = missedCorrectIDs
        revealedMissedCorrectChoiceIDs = []
        lastEvaluationWasCorrect = isPartialCorrect ? nil : isCorrect
        evaluationFeedbackWasCorrect = isPartialCorrect ? nil : isCorrect
        if !isPartialCorrect {
            evaluationFeedbackTrigger &+= 1
        }

        if isRetryPass {
            retryEvaluationCount += 1
        }

        let timeSpent = Date().timeIntervalSince(currentQuestionStartTime)

        if isCorrect {
            wrongFeedbackChoiceIDs = []
            guard !currentQuestionHasWrongAttempt else { return }

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

        if isPartialCorrect {
            wrongFeedbackChoiceIDs = []
            missedCardIDs.insert(currentCard.id)
            queueCurrentCardForRetry(currentCard)
            return
        }

        let newlyIncorrectChoiceIDs = selectedIncorrectChoiceIDs.subtracting(incorrectChoiceIDs)
        incorrectChoiceIDs.formUnion(selectedIncorrectChoiceIDs)
        wrongFeedbackChoiceIDs = newlyIncorrectChoiceIDs
        if !newlyIncorrectChoiceIDs.isEmpty {
            wrongFeedbackTrigger &+= 1
        }
        missedCardIDs.insert(currentCard.id)

        guard !currentQuestionHasWrongAttempt else { return }

        currentQuestionHasWrongAttempt = true
        wrongCount += 1

        queueCurrentCardForRetry(currentCard)

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
        guard !retryCards.isEmpty else {
            finishSession()
            return
        }

        wrongCards = []
        currentPassFailedIDs = []
        cards = settings.shuffleChoices ? shuffledChoices(in: retryCards) : retryCards
        currentIndex = 0
        isRetryPass = true
        isShowingRetryPrompt = false
        isEvaluated = false
        selectedChoiceIDs = []
        incorrectChoiceIDs = []
        missedCorrectChoiceIDs = []
        revealedMissedCorrectChoiceIDs = []
        wrongFeedbackChoiceIDs = []
        lastEvaluationWasCorrect = nil
        currentQuestionHasWrongAttempt = false
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

    private func queueCurrentCardForRetry(_ card: QuizPlayableCard) {
        guard currentPassFailedIDs.insert(card.id).inserted else { return }
        wrongCards.append(card)
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

    private static func playableCard(from card: CardModel) -> QuizPlayableCard? {
        guard case .quiz(let content) = card.cardContent,
              content.questionZone.hasContent else {
            return nil
        }

        let choices = content.choices.filter { $0.contentZone.hasContent }
        let correctChoices = choices.filter(\.isCorrect)

        guard choices.count >= 2, !correctChoices.isEmpty else {
            return nil
        }

        guard content.allowsMultipleCorrect || correctChoices.count == 1 else {
            return nil
        }

        return QuizPlayableCard(
            id: card.persistentModelID,
            cardNumber: card.cardNumber,
            interval: card.interval,
            questionZone: content.questionZone,
            choices: choices,
            explanationZone: content.explanationZone?.hasContent == true ? content.explanationZone : nil,
            allowsMultipleCorrect: content.allowsMultipleCorrect
        )
    }

    private static func choices(
        _ refreshedChoices: [QuizChoiceDraft],
        preservingOrderFrom existingChoices: [QuizChoiceDraft]
    ) -> [QuizChoiceDraft] {
        let refreshedByID = Dictionary(uniqueKeysWithValues: refreshedChoices.map { ($0.id, $0) })
        let preserved = existingChoices.compactMap { refreshedByID[$0.id] }
        let preservedIDs = Set(preserved.map(\.id))
        let inserted = refreshedChoices.filter { !preservedIDs.contains($0.id) }
        return preserved + inserted
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
