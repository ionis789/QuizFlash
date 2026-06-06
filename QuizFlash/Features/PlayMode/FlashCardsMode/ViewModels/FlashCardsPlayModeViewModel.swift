//
//  FlashCardsPlayModeViewModel.swift
//  QuizFlash
//
//  Manages the runtime state for a default (swipe-to-rate) flashcard session.
//
//  ## iOS 17 Memory-Safe Persistence
//  All SwiftData writes are pushed to a background `Task.detached` so that the
//  main `ModelContext` never retains card data in the row cache during playback.
//

import SwiftUI
import SwiftData
import Observation

// MARK: - FlashCards Play Mode ViewModel

/// The ViewModel for `FlashCardsPlayModeView`, coordinating card sequencing,
/// XP scoring, SRS updates, and gamification writes for a single swipe-based
/// play session.
///
/// All properties are observable via the `@Observable` macro (iOS 17+).
/// The class is `@MainActor`-bound so every property mutation is
/// automatically safe to consume from SwiftUI without extra synchronisation.
@Observable
@MainActor
final class FlashCardsPlayModeViewModel {

    // MARK: - Session State

    /// The deck that this session is playing through.
    let deck: DeckModel

    /// The deck-scoped flashcard settings captured when the session starts.
    let settings: FlashcardModeSettings

    /// Lightweight, `Sendable` snapshots of the deck's cards loaded for playback.
    var cards: [PlayableCard] = []

    /// Increments whenever the same logical cards are replayed as a new visual run.
    ///
    /// SwiftUI can otherwise reuse a UIKit swipe host whose card already exited
    /// off-screen, because retry rounds reuse the same persistent card IDs.
    var playRunGeneration: Int = 0

    /// Whether `startSession(container:)` has been called at least once.
    var isSessionStarted: Bool = false

    /// Whether every playable flashcard payload for this session has been decoded.
    var hasLoadedAllCards: Bool = false

    // MARK: - Progress Tracking

    /// Index of the card currently shown to the user.
    var currentIndex: Int = 0

    /// Number of cards the user swiped right (marked correct) in this session.
    var correctCount: Int = 0

    /// `true` when the user has reviewed every card in the session.
    var isComplete: Bool = false

    /// Total number of cards in the current run, preserved even if `cards`
    /// gets cleared to release memory after completion.
    var totalCardCount: Int = 0

    /// Cards the user swiped left (marked incorrect) — eligible for retry.
    var wrongCards: [PlayableCard] = []

    /// `true` when the current card is showing its back (answer) face.
    var isFlipped: Bool = false

    // MARK: - Gamification

    /// Total XP earned during this session (base + speed bonus per card).
    var sessionXP: Int = 0

    /// Timestamp captured when the session started, used to compute total duration.
    let sessionStartTime: Date = Date()

    /// Total number of swipe events recorded (correct + incorrect).
    var totalSessionSwipes: Int = 0

    /// Total number of correct swipes recorded.
    var totalSessionCorrect: Int = 0

    // MARK: - Private

    /// Timestamp of when the current card was first presented to the user.
    private var currentCardStartTime: Date = Date()

    /// Stored container reference captured during `startSession(container:)`.
    /// Passed into detached tasks instead of capturing a `ModelContext` reference.
    private var container: ModelContainer?

    /// Shared detached persistence service reused by all interactive play modes.
    private var persistenceService: PlaySessionPersistenceService?

    /// Background continuation that fills the rest of the deck after first paint.
    @ObservationIgnored private var remainingCardLoadTask: Task<Void, Never>?

    // MARK: - Computed Properties

    /// Session accuracy expressed as an integer percentage (0–100).
    ///
    /// Returns `0` before any swipe has been recorded to avoid division by zero.
    var sessionAccuracy: Int {
        guard totalSessionSwipes > 0 else { return 0 }
        return Int((Double(totalSessionCorrect) / Double(totalSessionSwipes)) * 100)
    }

    /// Human-readable representation of time elapsed since `sessionStartTime`.
    ///
    /// Examples: `"42s"`, `"1m 7s"`.
    var formattedSessionDuration: String {
        Self.formatInterval(Date().timeIntervalSince(sessionStartTime))
    }

    /// Number of cards already reviewed in the active run.
    var reviewedCardCount: Int {
        min(currentIndex, totalCardCount)
    }

    /// Fractional progress for the header progress bar.
    var progressFraction: Double {
        guard totalCardCount > 0 else { return 0 }
        return min(1, Double(reviewedCardCount) / Double(totalCardCount))
    }

    // MARK: - Static Helpers

    /// Formats a `TimeInterval` into a concise string such as `"1m 7s"` or `"42s"`.
    static func formatInterval(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let minutes = total / 60
        let seconds = total % 60
        return minutes > 0 ? "\(minutes)m \(seconds)s" : "\(seconds)s"
    }

    // MARK: - Init

    init(deck: DeckModel, settings: FlashcardModeSettings) {
        self.deck = deck
        self.settings = settings
        self.currentCardStartTime = Date()
        self.totalCardCount = deck.cardCount
    }

    // MARK: - Session Lifecycle

    /// Starts the session by loading `PlayableCard` snapshots on a background actor.
    ///
    /// Calling this when `isSessionStarted == true` is a no-op, making it safe
    /// to call from `.task {}` which may fire more than once in some edge cases.
    ///
    /// - Parameter container: The `ModelContainer` from the SwiftUI environment.
    func startSession(container: ModelContainer) async {
        guard !isSessionStarted else { return }
        self.container = container
        self.persistenceService = PlaySessionPersistenceService(container: container)
        MathWebViewPool.shared.prewarm(count: 2, initialDelayMilliseconds: 0)

        let repository = PlayModeCardRepository(container: container)
        let deckID = deck.persistentModelID
        let order = settings.order
        let initialBatch = await repository.loadPlayableCardBatch(
            for: deckID,
            order: order,
            limit: 6
        )

        self.cards = initialBatch.cards
        self.totalCardCount = initialBatch.totalCount
        self.hasLoadedAllCards = initialBatch.loadedAll
        self.isFlipped = false
        self.isSessionStarted = true

        guard !initialBatch.loadedAll else { return }

        let loadedIDs = Set(initialBatch.cards.map(\.id))
        remainingCardLoadTask?.cancel()
        remainingCardLoadTask = Task { @MainActor [weak self] in
            let remainingRepository = PlayModeCardRepository(container: container)
            let remainingBatch = await remainingRepository.loadPlayableCardBatch(
                for: deckID,
                order: order,
                excludingIDs: loadedIDs
            )
            guard !Task.isCancelled, let self else { return }

            let currentIDs = Set(self.cards.map(\.id))
            let newCards = remainingBatch.cards.filter { !currentIDs.contains($0.id) }
            self.cards.append(contentsOf: newCards)
            self.totalCardCount = remainingBatch.totalCount
            self.hasLoadedAllCards = true
        }
    }

    /// Releases all strong card references owned by the active session.
    ///
    /// Must be called from `.onDisappear` to prevent memory bloat between sessions.
    /// Shared render caches stay alive because they are bounded and already flush
    /// themselves on memory pressure. Clearing them here forces WebKit and image
    /// decoding cold starts every time Flashcards is opened.
    func tearDown() {
        remainingCardLoadTask?.cancel()
        remainingCardLoadTask = nil
        cards = []
        wrongCards = []
        totalCardCount = 0
        hasLoadedAllCards = false
        persistenceService = nil
    }

    // MARK: - Gameplay

    /// Handles a swipe event from `SwipeableCard`.
    ///
    /// The function performs two distinct phases:
    /// 1. **Immediate** — updates lightweight in-memory state so the next card
    ///    appears on screen before any disk I/O has been started.
    /// 2. **Deferred** — persists the SRS update and gamification counters to
    ///    SwiftData on a utility-priority background task.
    ///
    /// - Parameter direction: `.right` for a correct answer, `.left` for incorrect.
    func handleSwipe(_ direction: SwipeDirection) {
        guard currentIndex < cards.count else { return }

        let playableCard  = cards[currentIndex]
        let cardID        = playableCard.id
        let timeSpent     = Date().timeIntervalSince(currentCardStartTime)
        let difficulty: ReviewDifficulty = direction == .right ? .good : .again
        let totalXP       = PlaySessionXP.awarded(for: difficulty, timeSpent: timeSpent)

        // ── Phase 1: update lightweight in-memory state immediately ──────────
        // These writes only touch Swift value types — zero SwiftData overhead.
        // SwiftUI sees `currentIndex` change and renders the next card
        // before any disk I/O has occurred.
        sessionXP          += totalXP
        totalSessionSwipes += 1
        if direction == .right {
            totalSessionCorrect += 1
            correctCount        += 1
        } else {
            wrongCards.append(playableCard)
        }

        isFlipped            = false
        currentIndex        += 1        // The next card appears here.
        currentCardStartTime = Date()

        if currentIndex >= cards.count, hasLoadedAllCards {
            cards = []                  // Release references before completion overlay.
            isComplete = true
        }

        // ── Phase 2: persist to SwiftData on a background task ───────────────
        // All SQLite work (model fetch, SRS update, gamification counters,
        // context.save) runs after the UI has already moved to the next card.
        // Using `Task.detached` with the container (captured from startSession)
        // avoids creating a @ModelActor per swipe, which carries an iOS 17
        // retain-cycle risk for short-lived actors.
        // Only value types are passed into the closure — no ModelContext capture.
        let reviewWrite = PlaySessionReviewWrite(
            cardID: cardID,
            difficulty: difficulty,
            timeSpent: timeSpent,
            xpAwarded: totalXP
        )
        let persistenceService = persistenceService

        Task.detached(priority: .utility) {
            await persistenceService?.persistReviews([reviewWrite])
        }
    }

    /// Queues all previously incorrect cards for a retry round.
    ///
    /// Resets session counters so the retry is treated as a fresh sub-session
    /// rather than accumulating on top of the original run.
    func retryWrongCards() {
        let retry = wrongCards
        guard !retry.isEmpty else {
            isComplete = true
            return
        }

        wrongCards = []

        // Maintain study order for the retry batch.
        playRunGeneration += 1
        cards = orderedCards(retry)
        totalCardCount = cards.count

        currentIndex = 0
        correctCount = 0
        totalSessionSwipes = 0
        totalSessionCorrect = 0
        isComplete   = false
        isFlipped    = false
        hasLoadedAllCards = true
        currentCardStartTime = Date()
    }

    /// Reloads a single lightweight snapshot after inline card editing so the
    /// current play session can stay on the same index with fresh content.
    func refreshCardSnapshot(for cardID: PersistentIdentifier) async {
        guard let container else { return }

        let repository = PlayModeCardRepository(container: container)
        guard let refreshedCard = await repository.loadPlayableCard(for: cardID) else { return }

        if let currentCardIndex = cards.firstIndex(where: { $0.id == cardID }) {
            cards[currentCardIndex] = refreshedCard
        }

        if let wrongCardIndex = wrongCards.firstIndex(where: { $0.id == cardID }) {
            wrongCards[wrongCardIndex] = refreshedCard
        }
    }

    // MARK: - Helpers

    private func orderedCards(_ cards: [PlayableCard]) -> [PlayableCard] {
        switch settings.order {
        case .studyPriority:
            return cards.sorted {
                let i1 = $0.interval
                let i2 = $1.interval
                if i1 == 0 && i2 != 0 { return true }
                if i1 != 0 && i2 == 0 { return false }
                if i1 != i2 { return i1 < i2 }
                return $0.cardNumber < $1.cardNumber
            }
        case .newestFirst:
            return cards.sorted { lhs, rhs in
                if lhs.cardNumber != rhs.cardNumber {
                    return lhs.cardNumber > rhs.cardNumber
                }
                return lhs.interval < rhs.interval
            }
        case .oldestFirst:
            return cards.sorted { lhs, rhs in
                if lhs.cardNumber != rhs.cardNumber {
                    return lhs.cardNumber < rhs.cardNumber
                }
                return lhs.interval < rhs.interval
            }
        case .shuffled:
            return cards.shuffled()
        }
    }
}
