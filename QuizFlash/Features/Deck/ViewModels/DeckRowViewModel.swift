//
//  DeckRowViewModel.swift
//  QuizFlash
//
//  Created by Ion Socol on 25.02.2026.
//

import SwiftUI
import SwiftData

@Observable
class DeckRowViewModel {
    // Datele brute
    let deck: DeckModel
    
    // Datele procesate pentru UI
    var totalCards: Int = 0
    var newCardsCount: Int = 0
    var learningCardsCount: Int = 0
    
    // Culori și iconițe
    var accentColor: Color {
        Color(hex: deck.colorHex) ?? ThemeManager.shared.accentColor.color
    }
    var iconName: String {
        deck.icon.isEmpty ? "book.closed.fill" : deck.icon
    }
    
    // Calcul pentru bara de progres (procentul de carduri care NU sunt noi)
    var progressPercentage: Double {
        guard totalCards > 0 else { return 0 }
        return Double(learningCardsCount) / Double(totalCards)
    }
    
    // Text descriptiv sub bara de progres
    var progressDescription: String {
        if totalCards == 0 { return "Empty deck" }
        if newCardsCount == 0 { return "All cards seen!" }
        return "\(newCardsCount) new to study"
    }
    
    init(deck: DeckModel) {
        self.deck = deck
        calculateStats()
    }
    
    private func calculateStats() {
        let cards = deck.cards
        self.totalCards = cards.count
        
        // Definiție: Un card e "Nou" dacă nu are istoric.
        self.newCardsCount = cards.filter { $0.reviewHistory.isEmpty }.count
        
        // Definiție: Restul sunt "În învățare" (văzute cel puțin o dată)
        self.learningCardsCount = totalCards - newCardsCount
    }
}
