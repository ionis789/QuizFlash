//
//  GameplayCard.swift
//  QuizFlash
//
//  Created by Ion Socol on 07.02.2026.
//

import SwiftUI

struct GameplayCard: View {
    let card: CardModel
    let onSwipe: (SwipeDirection) -> Void
    @State private var isFlipped = false
    
    var body: some View {
        SwipeableCard(onSwipe: onSwipe, onTap: handleTap) {
            FlipCardPreview(
                card: card,
                isPreviewMode: false,
                isFlipped: $isFlipped 
            )
        }
    }
    
    private func handleTap() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            isFlipped.toggle()
        }
    }
}
