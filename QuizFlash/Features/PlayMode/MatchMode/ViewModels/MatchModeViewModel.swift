//
//  MatchModeViewModel.swift
//  QuizFlash
//
//  Runtime state and persistence orchestration for the preview-based match mode.
//

import Foundation
import Observation
import SwiftData

// MARK: - MatchRoundState

/// One on-screen match board containing a shuffled prompt lane and answer lane for the same pair set.
struct MatchRoundState: Equatable, Sendable {
    let pairs: [MatchPlayablePair]
    let promptOrder: [PersistentIdentifier]
    let answerOrder: [PersistentIdentifier]
}

// MARK: - MatchModeViewModel

/// Owns round chunking, retry-mini-rounds, and detached review persistence for match mode.
@Observable
@MainActor
final class MatchModeViewModel {

    // MARK: - Session State

    let deck: DeckModel

    var allPairs: [MatchPlayablePair] = []
    var activeRound: MatchRoundState?
    var roundIndex: Int = 0
    var selectedPromptID: PersistentIdentifier?
    var selectedAnswerID: PersistentIdentifier?
    var matchedIDs: Set<PersistentIdentifier> = []
    var missedIDs: Set<PersistentIdentifier> = []
    var roundMistakes: Int = 0
    var perfectRounds: Int = 0
    var isRetryRound = false
    var sessionXP: Int = 0
    var sessionStartTime = Date()
    var loadState: PlayModeSessionLoadState = .idle
    var isComplete = false

    // MARK: - Supporting State

    var diagnostics: PlayModeValidationDiagnostics = .empty
    var errorMessage = ""
    var totalMatchedCount = 0
    var totalMismatchCount = 0
    var mismatchPromptID: PersistentIdentifier?
    var mismatchAnswerID: PersistentIdentifier?
    var mismatchAnimationToken = 0
    var completionSnapshot: SessionOutcomeSnapshot?

    // MARK: - Private

    @ObservationIgnored
    private var persistenceService: PlaySessionPersistenceService?

    @ObservationIgnored
    private var pendingPairs: [MatchPlayablePair] = []

    @ObservationIgnored
    private var failedPersistedIDsInChunk: Set<PersistentIdentifier> = []

    @ObservationIgnored
    private var reviewedCardIDs: [PersistentIdentifier] = []

    @ObservationIgnored
    private var missedCardIDs: Set<PersistentIdentifier> = []

    @ObservationIgnored
    private var currentRoundPairLookup: [PersistentIdentifier: MatchPlayablePair] = [:]

    @ObservationIgnored
    private var pairPresentedAt: [PersistentIdentifier: Date] = [:]

    @ObservationIgnored
    private var roundCapacity: Int = 6

    @ObservationIgnored
    private var retryReviewCount = 0

    @ObservationIgnored
    private var feedbackTask: Task<Void, Never>?

    // MARK: - Init

    init(deck: DeckModel) {
        self.deck = deck
    }

    deinit {
        feedbackTask?.cancel()
    }

    // MARK: - Derived State

    var formattedSessionDuration: String {
        PlaySessionFormatting.formatDuration(Date().timeIntervalSince(sessionStartTime))
    }

    var progressFraction: Double {
        guard !allPairs.isEmpty else { return 0 }
        return min(1, Double(totalMatchedCount) / Double(allPairs.count))
    }

    var progressLabel: String {
        "\(totalMatchedCount)/\(max(allPairs.count, 1)) matched"
    }

    var resolvedDeckTitle: String {
        let trimmed = deck.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Deck" : trimmed
    }

    var roundLabel: String {
        isRetryRound ? "RETRY ROUND" : "ROUND \(max(roundIndex, 1))"
    }

    // MARK: - Lifecycle

    /// Loads and validates the deck's match payloads, then materializes the first round board.
    func startSession(container: ModelContainer, roundCapacity: Int) async {
        guard loadState == .idle else { return }

        self.roundCapacity = roundCapacity
        self.sessionStartTime = Date()
        self.loadState = .loading
        self.persistenceService = PlaySessionPersistenceService(container: container)

        let repository = PlayModeCardRepository(container: container)
        let result = await repository.loadValidatedMatchPairs(for: deck.persistentModelID)
        let sortedPairs = Self.studyOrdered(result.cards)

        diagnostics = result.diagnostics
        allPairs = sortedPairs
        pendingPairs = sortedPairs

        guard !sortedPairs.isEmpty else {
            loadState = result.diagnostics.hasOnlyInvalidCards ? .invalid : .empty
            return
        }

        roundIndex = 1
        beginNextStandardRound()
        loadState = .ready
    }

    /// Releases transient card payloads and runtime caches on dismiss.
    func tearDown() {
        feedbackTask?.cancel()
        activeRound = nil
        allPairs = []
        pendingPairs = []
        currentRoundPairLookup = [:]
        pairPresentedAt = [:]
        persistenceService = nil
        MathWebViewPool.shared.flush()
        ImageCache.shared.clearCache()
    }

    // MARK: - Interaction

    /// Selects one prompt tile and evaluates if an answer tile is already active.
    func selectPrompt(_ id: PersistentIdentifier) {
        guard canSelectTile(id) else { return }
        selectedPromptID = selectedPromptID == id ? nil : id
        evaluateSelectionIfReady()
    }

    /// Selects one answer tile and evaluates if a prompt tile is already active.
    func selectAnswer(_ id: PersistentIdentifier) {
        guard canSelectTile(id) else { return }
        selectedAnswerID = selectedAnswerID == id ? nil : id
        evaluateSelectionIfReady()
    }

    // MARK: - Private

    private func canSelectTile(_ id: PersistentIdentifier) -> Bool {
        loadState == .ready &&
        !isComplete &&
        !matchedIDs.contains(id) &&
        mismatchPromptID == nil &&
        mismatchAnswerID == nil
    }

    private func evaluateSelectionIfReady() {
        guard let promptID = selectedPromptID, let answerID = selectedAnswerID else { return }

        if promptID == answerID {
            resolveCorrectMatch(for: promptID)
        } else {
            resolveWrongMatch(promptID: promptID, answerID: answerID)
        }
    }

    private func resolveCorrectMatch(for pairID: PersistentIdentifier) {
        guard let pair = currentRoundPairLookup[pairID] else { return }

        matchedIDs.insert(pairID)
        totalMatchedCount += 1
        reviewedCardIDs.append(pairID)

        let timeSpent = Date().timeIntervalSince(pairPresentedAt[pairID] ?? sessionStartTime)
        let xp = PlaySessionXP.awarded(for: .good, timeSpent: timeSpent)
        sessionXP += xp
        persist(
            PlaySessionReviewWrite(
                cardID: pair.id,
                difficulty: .good,
                timeSpent: timeSpent,
                xpAwarded: xp
            )
        )

        selectedPromptID = nil
        selectedAnswerID = nil

        if matchedIDs.count == currentRoundPairLookup.count {
            finishRoundIfNeeded()
        }
    }

    private func resolveWrongMatch(
        promptID: PersistentIdentifier,
        answerID: PersistentIdentifier
    ) {
        totalMismatchCount += 1
        roundMistakes += 1
        missedIDs.insert(promptID)
        missedIDs.insert(answerID)
        missedCardIDs.insert(promptID)
        missedCardIDs.insert(answerID)
        mismatchPromptID = promptID
        mismatchAnswerID = answerID
        mismatchAnimationToken += 1

        let newlyFailedIDs = [promptID, answerID].filter { failedPersistedIDsInChunk.insert($0).inserted }
        if !newlyFailedIDs.isEmpty {
            let reviews = newlyFailedIDs.map { id in
                let timeSpent = Date().timeIntervalSince(pairPresentedAt[id] ?? sessionStartTime)
                let xp = PlaySessionXP.awarded(for: .again, timeSpent: timeSpent)
                sessionXP += xp
                return PlaySessionReviewWrite(
                    cardID: id,
                    difficulty: .again,
                    timeSpent: timeSpent,
                    xpAwarded: xp
                )
            }
            persist(reviews)
        }

        feedbackTask?.cancel()
        feedbackTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(420))
            guard !Task.isCancelled else { return }
            selectedPromptID = nil
            selectedAnswerID = nil
            mismatchPromptID = nil
            mismatchAnswerID = nil
        }
    }

    private func finishRoundIfNeeded() {
        if !isRetryRound && roundMistakes == 0 {
            perfectRounds += 1
        }

        if !missedIDs.isEmpty && !isRetryRound {
            beginRetryRound()
            return
        }

        if pendingPairs.isEmpty {
            finishSession()
        } else {
            roundIndex += 1
            beginNextStandardRound()
        }
    }

    private func beginNextStandardRound() {
        let nextPairs = Array(pendingPairs.prefix(roundCapacity))
        pendingPairs.removeFirst(min(roundCapacity, pendingPairs.count))
        configureRound(with: nextPairs, isRetryRound: false)
    }

    private func beginRetryRound() {
        let retryPairs = activeRound?.pairs.filter { missedIDs.contains($0.id) } ?? []
        retryReviewCount += retryPairs.count
        configureRound(with: retryPairs, isRetryRound: true)
    }

    private func configureRound(with pairs: [MatchPlayablePair], isRetryRound: Bool) {
        self.isRetryRound = isRetryRound
        self.matchedIDs = []
        self.selectedPromptID = nil
        self.selectedAnswerID = nil
        self.mismatchPromptID = nil
        self.mismatchAnswerID = nil

        if !isRetryRound {
            roundMistakes = 0
            missedIDs = []
            failedPersistedIDsInChunk = []
        }

        currentRoundPairLookup = Dictionary(uniqueKeysWithValues: pairs.map { ($0.id, $0) })
        pairPresentedAt = Dictionary(uniqueKeysWithValues: pairs.map { ($0.id, Date()) })
        activeRound = MatchRoundState(
            pairs: pairs,
            promptOrder: pairs.map(\.id).shuffled(),
            answerOrder: pairs.map(\.id).shuffled()
        )
    }

    private func finishSession() {
        isComplete = true
        activeRound = nil
        completionSnapshot = SessionOutcomeSnapshot(
            mode: .match,
            duration: Date().timeIntervalSince(sessionStartTime),
            correctCount: totalMatchedCount,
            wrongCount: totalMismatchCount,
            retryCount: retryReviewCount,
            invalidSkippedCount: diagnostics.skippedInvalidCount,
            reviewedCardIDs: reviewedCardIDs,
            missedCardIDs: Array(missedCardIDs)
        )
    }

    private func persist(_ review: PlaySessionReviewWrite) {
        persist([review])
    }

    private func persist(_ reviews: [PlaySessionReviewWrite]) {
        guard !reviews.isEmpty else { return }
        let persistenceService = persistenceService

        Task.detached(priority: .utility) {
            await persistenceService?.persistReviews(reviews)
        }
    }

    private static func studyOrdered(_ pairs: [MatchPlayablePair]) -> [MatchPlayablePair] {
        pairs.sorted { lhs, rhs in
            if lhs.interval == 0 && rhs.interval != 0 { return true }
            if lhs.interval != 0 && rhs.interval == 0 { return false }
            if lhs.interval != rhs.interval { return lhs.interval < rhs.interval }
            return lhs.cardNumber < rhs.cardNumber
        }
    }
}
