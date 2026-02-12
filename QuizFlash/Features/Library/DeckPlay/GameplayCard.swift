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
        // Now receives 'isSwiping' boolean from the closure
        SwipeableCard(onSwipe: onSwipe, onTap: handleTap) { isSwiping in
            FlipCardPreview(
                card: card,
                isPreviewMode: false,
                isFlipped: $isFlipped,
                scrollDisabled: isSwiping // Passes the lock state to the inner view
            )
        }
    }
    
    private func handleTap() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            isFlipped.toggle()
        }
    }
}
