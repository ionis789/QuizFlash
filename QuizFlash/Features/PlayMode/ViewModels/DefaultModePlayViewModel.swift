//
//  DefaultModePlayViewModel.swift
//  QuizFlash
//

import SwiftUI
import SwiftData

@Observable
@MainActor
final class DefaultModePlayViewModel {

    // MARK: - Properties
    let deck: DeckModel
    // Context temporar pentru a scuti MainContext de a ține CardModel cu imagini uriașe
    // NOU: Nu se mai folosesc deloc ModelContext uri temporare care fac memory leak pe iOS 17!
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

// =============================================================================
// MARK: - Safe Background Actor
// =============================================================================

/// This struct contains NO CoreData tracking mechanisms. It holds pure in-memory Data.
/// By converting Heavy `CardModel`s into lightweight structs in the background, we guarantee
/// the Main Thread `ModelContext` NEVER touches `.frontZoneData`, strictly bypassing the
/// iOS 17 permanent Row Cache memory leak!
struct PlayableCard: Identifiable, Sendable {
    let id: PersistentIdentifier
    let frontZone: ZoneModel
    let backZone: ZoneModel
    let interval: Int
}

@ModelActor
final actor PlaybackActor {
    /// Loads cards safely, unpacks the heavy 2MB external blobs into pure Swift structs,
    /// and then destroys its isolated ModelContext cleanly upon return.
    func loadPlayableCards(for deckID: PersistentIdentifier) -> [PlayableCard] {
        // iOS 17 #Predicate silently crashes or returns 0 results when evaluating optional
        // nested properties (like `$0.deck?.persistentModelID`).
        // To bypass this cleanly on iOS 17, we simply fetch the parent Deck model directly
        // by ID, and access its existing `cards` relationship.
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
    
    /// Detașează scrierea datelor către o zonă care poate fi aruncată la gunoi instantaneu.
    /// Eliminând mutația din UI Thread, `MainContext`-ul nu mai reține row-ul SQLite al cardului în cache,
    /// cu tot cu eventualele date uriașe din `externalStorage`.
    func saveReview(cardID: PersistentIdentifier, timeSpent: TimeInterval, difficulty: ReviewDifficulty, xpAwarded: Int) {
        if let card = modelContext.model(for: cardID) as? CardModel {
            let review = ReviewEvent(timeSpent: timeSpent, difficulty: difficulty, xpAwarded: xpAwarded)
            card.reviewHistory.append(review)
            
            // SRS Update
            if difficulty == .again {
                card.consecutiveCorrectAnswers = 0
                card.interval = 1
                card.easeFactor = max(1.3, card.easeFactor - 0.2)
            } else {
                card.consecutiveCorrectAnswers += 1
                if card.consecutiveCorrectAnswers == 1 {
                    card.interval = 1
                } else if card.consecutiveCorrectAnswers == 2 {
                    card.interval = 6
                } else {
                    card.interval = Int(round(Double(card.interval) * card.easeFactor))
                }
            }
            card.dueDate = Calendar.current.date(byAdding: .day, value: card.interval, to: Date()) ?? Date()
            
            try? modelContext.save()
        }
    }
}
