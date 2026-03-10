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

    /// Lightweight, `Sendable` snapshots of the deck's cards loaded for playback.
    var cards: [PlayableCard] = []

    /// Whether `startSession(container:)` has been called at least once.
    var isSessionStarted: Bool = false

    // MARK: - Progress Tracking

    /// Index of the card currently shown to the user.
    var currentIndex: Int = 0

    /// Number of cards the user swiped right (marked correct) in this session.
    var correctCount: Int = 0

    /// `true` when the user has reviewed every card in the session.
    var isComplete: Bool = false

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

    /// Progress segments for the header progress bar — `true` = completed.
    ///
    /// Exposed so the View can render a simple `ForEach` without arithmetic.
    var progressSegments: [(id: Int, completed: Bool)] {
        cards.indices.map { (id: $0, completed: $0 < currentIndex) }
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

    init(deck: DeckModel) {
        self.deck = deck
        self.currentCardStartTime = Date()
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

        // Load cards via a background actor to keep the main ModelContext clean.
        // The actor decodes all zone data and returns pure Sendable value types,
        // which means the main context's row cache is never populated with card blobs.
        let actor = PlaybackActor(modelContainer: container)
        let loadedCards = await actor.loadPlayableCards(for: deck.persistentModelID)

        // Study-order sort: new cards (interval == 0) first, then by shortest interval.
        self.cards = loadedCards.sorted {
            let i1 = $0.interval
            let i2 = $1.interval
            if i1 == 0 && i2 != 0 { return true }
            if i1 != 0 && i2 == 0 { return false }
            return i1 < i2
        }

        self.isSessionStarted = true
    }

    /// Releases all strong card references and flushes caches.
    ///
    /// Must be called from `.onDisappear` to prevent memory bloat between sessions.
    func tearDown() {
        cards = []
        wrongCards = []
        MathWebViewPool.shared.flush()
        ImageCache.shared.clearCache()
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
        let baseXP        = difficulty == .good ? 10 : 2
        let speedBonus    = (timeSpent < 4.0 && difficulty == .good) ? 5 : 0
        let totalXP       = baseXP + speedBonus

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

        if currentIndex >= cards.count {
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
        let capturedContainer  = container
        let capturedCardID     = cardID
        let capturedTimeSpent  = timeSpent
        let capturedTotalXP    = totalXP
        let capturedDifficulty = difficulty

        Task.detached(priority: .utility) {
            // A short-lived context scoped to this task.
            // It is deallocated when the task exits — no leak risk.
            let bgContext = ModelContext(capturedContainer!)

            // ── SRS update ───────────────────────────────────────────────────
            if let realCard = bgContext.safeModel(for: capturedCardID, as: CardModel.self) {
                let review = ReviewEvent(
                    timeSpent: capturedTimeSpent,
                    difficulty: capturedDifficulty,
                    xpAwarded: capturedTotalXP
                )
                realCard.reviewHistory.append(review)

                if capturedDifficulty == .again {
                    realCard.consecutiveCorrectAnswers = 0
                    realCard.interval   = 1
                    realCard.easeFactor = max(1.3, realCard.easeFactor - 0.2)
                } else {
                    realCard.consecutiveCorrectAnswers += 1
                    switch realCard.consecutiveCorrectAnswers {
                    case 1:  realCard.interval = 1
                    case 2:  realCard.interval = 6
                    default: realCard.interval = Int(round(Double(realCard.interval) * realCard.easeFactor))
                    }
                }
                realCard.dueDate = Calendar.current.date(
                    byAdding: .day, value: realCard.interval, to: Date()
                ) ?? Date()
            }

            // ── Gamification counters ────────────────────────────────────────
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let todayString = formatter.string(from: Date())

            let dailyDesc = FetchDescriptor<DailyActivityLog>(
                predicate: #Predicate { $0.dateString == todayString }
            )
            let todayLog: DailyActivityLog
            if let existing = (try? bgContext.fetch(dailyDesc))?.first {
                todayLog = existing
            } else {
                todayLog = DailyActivityLog(date: Date())
                bgContext.insert(todayLog)
            }
            todayLog.cardsReviewed += 1
            todayLog.xpEarnedToday += capturedTotalXP

            let profileDesc = FetchDescriptor<UserProfile>()
            let profile: UserProfile
            if let existing = (try? bgContext.fetch(profileDesc))?.first {
                profile = existing
            } else {
                profile = UserProfile()
                bgContext.insert(profile)
            }
            profile.totalXP      += capturedTotalXP
            profile.lastActiveDate = Date()

            try? bgContext.save()
        }
    }

    /// Queues all previously incorrect cards for a retry round.
    ///
    /// Resets session counters so the retry is treated as a fresh sub-session
    /// rather than accumulating on top of the original run.
    func retryWrongCards() {
        let retry = wrongCards
        wrongCards = []

        // Maintain study order for the retry batch.
        cards = retry.sorted {
            let i1 = $0.interval
            let i2 = $1.interval
            if i1 == 0 && i2 != 0 { return true }
            if i1 != 0 && i2 == 0 { return false }
            return i1 < i2
        }

        currentIndex = 0
        correctCount = 0
        isComplete   = false
        isFlipped    = false
        currentCardStartTime = Date()
    }
}

// MARK: - PlayableCard

/// A lightweight, `Sendable` snapshot of a card's zone content used during playback.
///
/// Converting `CardModel` instances into `PlayableCard` structs on a background actor
/// ensures the main `ModelContext` never reads external-storage blobs, bypassing the
/// iOS 17 permanent row-cache memory leak.
struct PlayableCard: Identifiable, Sendable {
    /// The persistent identifier used to re-fetch the original `CardModel` for SRS writes.
    let id: PersistentIdentifier
    /// Decoded content for the front (question) face.
    let frontZone: ZoneModel
    /// Decoded content for the back (answer) face.
    let backZone: ZoneModel
    /// Current SRS interval in days. `0` means the card is new.
    let interval: Int
}

// MARK: - PlaybackActor

/// A short-lived `@ModelActor` whose sole purpose is to load `PlayableCard` snapshots
/// for a single play session.
///
/// Because `PlaybackActor` is created once, used once, and immediately deallocated,
/// the iOS 17 zombie-context risk associated with long-lived `@ModelActor` instances
/// does not apply here.
@ModelActor
final actor PlaybackActor {

    /// Loads cards for the given deck ID, decodes zone data on the actor's background
    /// context, and returns pure `Sendable` value types.
    ///
    /// - Parameter deckID: The `PersistentIdentifier` of the deck to load cards from.
    /// - Returns: An array of `PlayableCard` snapshots, or an empty array on failure.
    func loadPlayableCards(for deckID: PersistentIdentifier) -> [PlayableCard] {
        // iOS 17 `#Predicate` silently crashes on optional nested properties such as
        // `$0.deck?.persistentModelID`. Fetch the parent deck directly and access
        // its `cards` relationship instead.
        guard let deck = modelContext.model(for: deckID) as? DeckModel else { return [] }
        let cards = deck.cards

        var results: [PlayableCard] = []
        for card in cards {
            autoreleasepool {
                let frontData = card.frontZoneData
                let backData  = card.backZoneData

                let frontZone = frontData.flatMap { ZoneModel.decode(from: $0) } ?? ZoneModel(id: UUID())
                let backZone  = backData.flatMap  { ZoneModel.decode(from: $0) } ?? ZoneModel(id: UUID())

                results.append(PlayableCard(
                    id: card.persistentModelID,
                    frontZone: frontZone,
                    backZone:  backZone,
                    interval:  card.interval
                ))
            }
        }
        return results
    }
}
