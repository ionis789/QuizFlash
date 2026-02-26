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
    var cards: [CardModel] = []

    var currentIndex: Int = 0
    var correctCount: Int = 0
    var isComplete: Bool = false
    var wrongCards: [CardModel] = []
    var isFlipped: Bool = false
    var sessionXP: Int = 0
    let sessionStartTime: Date = Date()
    var totalSessionSwipes: Int = 0
    var totalSessionCorrect: Int = 0

    private var currentCardStartTime: Date = Date()

    init(deck: DeckModel) {
        self.deck = deck
        self.cards = Self.studyOrderedCards(deck.cards)

        for card in self.cards {
            _ = card.frontZone
            _ = card.backZone
        }

        self.currentCardStartTime = Date()
    }

    // MARK: - Business Logic

    private static func studyOrderedCards(_ deckCards: [CardModel]) -> [CardModel] {
        return deckCards.sorted { a, b in
            if a.dueDate != b.dueDate {
                return a.dueDate < b.dueDate
            }
            return a.createdAt < b.createdAt
        }
    }

    // 🟢 Cerem contextul direct în funcția care face salvarea
    func handleSwipe(_ direction: SwipeDirection, context: ModelContext) {
        guard currentIndex < cards.count else { return }

        let card = cards[currentIndex]
        let now = Date()

        let timeSpent = now.timeIntervalSince(currentCardStartTime)
        let difficulty: ReviewDifficulty = (direction == .right) ? .good : .again

        let baseXP = (difficulty == .good) ? 10 : 2
        let speedBonus = (timeSpent < 4.0 && difficulty == .good) ? 5 : 0
        let totalXP = baseXP + speedBonus

        // 🟢 NOU: Acumulăm datele pentru rezumatul sesiunii
        self.sessionXP += totalXP
        self.totalSessionSwipes += 1
        if direction == .right { self.totalSessionCorrect += 1 }

        let review = ReviewEvent(timeSpent: timeSpent, difficulty: difficulty, xpAwarded: totalXP)
        card.reviewHistory.append(review)

        updateSRS(for: card, difficulty: difficulty)
        updateGamification(xpAwarded: totalXP, context: context) // 🟢 Pasăm contextul mai departe

        if direction == .right {
            correctCount += 1
        } else {
            wrongCards.append(card)
        }

        // 🟢 Salvăm folosind contextul primit
        try? context.save()

        isFlipped = false
        currentIndex += 1
        currentCardStartTime = Date()

        if currentIndex >= cards.count {
            isComplete = true
        }
    }

    private func updateSRS(for card: CardModel, difficulty: ReviewDifficulty) {
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
    }

    // 🟢 Folosim contextul primit ca parametru
    private func updateGamification(xpAwarded: Int, context: ModelContext) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayString = formatter.string(from: Date())

        let dailyDescriptor = FetchDescriptor<DailyActivityLog>(predicate: #Predicate { $0.dateString == todayString })
        let dailyLogs = (try? context.fetch(dailyDescriptor)) ?? []

        let todayLog: DailyActivityLog
        if let existingLog = dailyLogs.first {
            todayLog = existingLog
        } else {
            todayLog = DailyActivityLog(date: Date())
            context.insert(todayLog)
        }

        todayLog.cardsReviewed += 1
        todayLog.xpEarnedToday += xpAwarded

        let profileDescriptor = FetchDescriptor<UserProfile>()
        let profiles = (try? context.fetch(profileDescriptor)) ?? []

        let profile: UserProfile
        if let existingProfile = profiles.first {
            profile = existingProfile
        } else {
            profile = UserProfile()
            context.insert(profile)
        }

        profile.totalXP += xpAwarded
        profile.lastActiveDate = Date()
    }

    func retryWrongCards() {
        let retry = wrongCards
        wrongCards = []
        cards = Self.studyOrderedCards(retry)

        currentIndex = 0
        correctCount = 0
        isComplete = false
        isFlipped = false
        currentCardStartTime = Date()
    }
}
