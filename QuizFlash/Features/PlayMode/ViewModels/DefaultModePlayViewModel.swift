//
//  DefaultModePlayViewModel.swift
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

// MARK: - Default Mode Play View Model

/// The ViewModel for `DefaultModePlay`, coordinating card sequencing, XP scoring,
/// SRS updates, and gamification writes for a single swipe-based play session.
@Observable
@MainActor
final class DefaultModePlayViewModel {

    // MARK: - Properties

    let deck: DeckModel
    var cards: [PlayableCard] = []
    var isSessionStarted: Bool = false

    var currentIndex: Int = 0
    var correctCount: Int = 0
    var isComplete: Bool = false
    var wrongCards: [PlayableCard] = []
    var isFlipped: Bool = false
    var sessionXP: Int = 0
    let sessionStartTime: Date = Date()
    var totalSessionSwipes: Int = 0
    var totalSessionCorrect: Int = 0

    private var currentCardStartTime: Date = Date()
    
    // Stored container to allow saving ReviewEvents safely
    private var container: ModelContainer?

    init(deck: DeckModel) {
        self.deck = deck
        self.currentCardStartTime = Date()
    }

    /// Isolated Game Session initialization through iOS 17 safe `@ModelActor`.
    func startSession(container: ModelContainer) async {
        guard !isSessionStarted else { return }
        self.container = container
        
        // Resolves PlayableCards via background actor.
        // This violently dumps the 2MB SQLite row caching instantly after decode!
        let actor = PlaybackActor(modelContainer: container)
        let loadedCards = await actor.loadPlayableCards(for: deck.persistentModelID)
        
        // Sorting logic equivalent to studyOrderedCards but for PlayableCard
        self.cards = loadedCards.sorted {
            let i1 = $0.interval
            let i2 = $1.interval
            if i1 == 0 && i2 != 0 { return true }
            if i1 != 0 && i2 == 0 { return false }
            return i1 < i2
        }
        
        self.isSessionStarted = true
    }

    /// Releases all strong references.
    func tearDown() {
        cards = []
        wrongCards = []
        MathWebViewPool.shared.flush()
        ImageCache.shared.clearCache()
    }

    // MARK: - Business Logic

    func handleSwipe(_ direction: SwipeDirection) {
        guard currentIndex < cards.count else { return }

        let playableCard = cards[currentIndex]
        let cardID       = playableCard.id
        let timeSpent    = Date().timeIntervalSince(currentCardStartTime)
        let difficulty: ReviewDifficulty = (direction == .right) ? .good : .again
        let baseXP   = (difficulty == .good) ? 10 : 2
        let speedBonus = (timeSpent < 4.0 && difficulty == .good) ? 5 : 0
        let totalXP  = baseXP + speedBonus

        // ── Step 1: update lightweight in-memory state immediately ───────────
        // These writes only touch Swift value types — zero SwiftData overhead.
        // SwiftUI sees currentIndex change and starts rendering the next card
        // before any disk I/O has occurred.
        sessionXP          += totalXP
        totalSessionSwipes += 1
        if direction == .right { totalSessionCorrect += 1; correctCount += 1 }
        else                   { wrongCards.append(playableCard) }

        isFlipped            = false
        currentIndex        += 1          // ← next card appears NOW
        currentCardStartTime = Date()

        if currentIndex >= cards.count {
            isComplete = true
            cards      = []
        }

        // ── Step 2: persist to SwiftData on a detached background Task ───────
        // All SQLite work (safeModel fetch, SRS update, gamification fetches,
        // context.save) runs after the UI has already moved to the next card.
        // Using Task.detached with the container (captured from startSession)
        // avoids creating a @ModelActor per swipe (iOS 17 retain-cycle risk).
        // We pass only value types into the closure — no ModelContext capture.
        let capturedContainer = container
        let capturedCardID    = cardID
        let capturedTimeSpent = timeSpent
        let capturedTotalXP   = totalXP
        let capturedDifficulty = difficulty

        Task.detached(priority: .utility) {
            // Create a short-lived context scoped to this task.
            // It is deallocated when the task exits — no leak risk.
            let bgContext = ModelContext(capturedContainer!)

            // SRS + review history update
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

            // Gamification — reuse the same background context
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

    private func finishSession() {
        isComplete = true
        // Release all card references now that the session is complete.
        // This allows zone caches and the CardModel instances to be
        // reclaimed before the user dismisses the playback screen.
        cards = []
    }

    func retryWrongCards() {
        let retry = wrongCards
        wrongCards = []
        
        // Sort wrong cards back into study order based on interval
        cards = retry.sorted {
            let i1 = $0.interval
            let i2 = $1.interval
            if i1 == 0 && i2 != 0 { return true }
            if i1 != 0 && i2 == 0 { return false }
            return i1 < i2
        }

        currentIndex = 0
        correctCount = 0
        isComplete = false
        isFlipped = false
        currentCardStartTime = Date()
    }
}

// MARK: - Playable Card

/// A lightweight, `Sendable` snapshot of a card's zone content for use during playback.
///
/// Converting `CardModel`s into `PlayableCard` structs on a background actor ensures
/// the main `ModelContext` never reads heavy external-storage blobs, bypassing the
/// iOS 17 permanent row-cache memory leak.
struct PlayableCard: Identifiable, Sendable {
    let id: PersistentIdentifier
    let frontZone: ZoneModel
    let backZone: ZoneModel
    let interval: Int
}

// MARK: - Playback Actor

@ModelActor
final actor PlaybackActor {

    /// Loads cards for the given deck ID, decodes zone data on the actor's background
    /// context, and returns pure `Sendable` value types.
    ///
    /// Using `@ModelActor` here is intentional — `PlaybackActor` is a short-lived
    /// object that is created once, used once, and immediately deallocated, so the
    /// iOS 17 zombie-context risk does not apply.
    func loadPlayableCards(for deckID: PersistentIdentifier) -> [PlayableCard] {
        // iOS 17 #Predicate silently crashes on optional nested properties such as
        // `$0.deck?.persistentModelID`. Fetch the parent deck directly and access
        // its cards relationship instead.
        guard let deck = modelContext.model(for: deckID) as? DeckModel else { return [] }
        let cards = deck.cards

        var results: [PlayableCard] = []
        for card in cards {
            autoreleasepool {
                let frontData = card.frontZoneData
                let backData = card.backZoneData

                let frontZone = frontData.flatMap { ZoneModel.decode(from: $0) } ?? ZoneModel(id: UUID())
                let backZone = backData.flatMap { ZoneModel.decode(from: $0) } ?? ZoneModel(id: UUID())

                results.append(PlayableCard(
                    id: card.persistentModelID,
                    frontZone: frontZone,
                    backZone: backZone,
                    interval: card.interval
                ))
            }
        }
        return results
    }
}
