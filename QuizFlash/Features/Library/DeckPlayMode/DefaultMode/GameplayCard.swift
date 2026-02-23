//
//  GameplayCard.swift
//  QuizFlash
//

import SwiftUI

struct GameplayCard: View {
    let card: CardModel
    let onSwipe: (SwipeDirection) -> Void
    
    // Acum primește starea de la DefaultModePlay
    @Binding var isFlipped: Bool

    var body: some View {
        SwipeableCard(onSwipe: onSwipe, onTap: handleTap) {
            FlipCard(
                card: card,
                isFlipped: $isFlipped
            )
        }
    }

    private func handleTap() {
        withAnimation(.interactiveSpring(response: 0.45, dampingFraction: 0.85)) {
            isFlipped.toggle()
        }
    }
}
