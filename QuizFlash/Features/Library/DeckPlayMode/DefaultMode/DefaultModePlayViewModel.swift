//
//  DefaultModePlayViewModel.swift
//  QuizFlash
//
//  Created by Ion Socol on 17.02.2026.
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
    
    // MARK: - Initialization
    init(deck: DeckModel) {
        self.deck = deck
        self.cards = Self.studyOrderedCards(deck.cards)
    }
    
    // MARK: - Business Logic
    
    /// Sorts cards based on spaced repetition / study priority logic
    private static func studyOrderedCards(_ deckCards: [CardModel]) -> [CardModel] {
        deckCards.sorted { a, b in
            let aSeen = a.lastSeenAt != nil
            let bSeen = b.lastSeenAt != nil
            
            if !aSeen, bSeen { return true }
            if aSeen, !bSeen { return false }
            if !aSeen, !bSeen { return a.createdAt < b.createdAt }
            
            guard let aDate = a.lastSeenAt, let bDate = b.lastSeenAt else { return false }
            if aDate != bDate { return aDate < bDate }
            
            return a.timesWrong > b.timesWrong
        }
    }
    
    func handleSwipe(_ direction: SwipeDirection) {
        guard currentIndex < cards.count else { return }
        
        let card = cards[currentIndex]
        let now = Date()
        
        // Update Stats
        if card.stats == nil {
            card.stats = CardStats(card: card)
        }
        
        if let stats = card.stats {
            stats.totalAttempts += 1
            stats.lastAttemptDate = now
            if direction == .right {
                stats.correctCount += 1
                stats.streak += 1
            } else {
                stats.wrongCount += 1
                stats.streak = 0
            }
        }
        
        if direction == .right {
            correctCount += 1
            card.lastSeenAt = now
            card.timesCorrect += 1
        } else {
            wrongCards.append(card)
            card.lastSeenAt = now
            card.timesWrong += 1
        }
        
        // Reset state for next card
        isFlipped = false
        currentIndex += 1
        
        if currentIndex >= cards.count {
            isComplete = true
        }
    }
    
    func retryWrongCards() {
        let retry = wrongCards
        wrongCards = []
        cards = Self.studyOrderedCards(retry)
        
        currentIndex = 0
        correctCount = 0
        isComplete = false
        isFlipped = false
    }
}
