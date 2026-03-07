//
//  GameplayCard.swift
//  QuizFlash
//
//  A thin coordinator view that composes `SwipeableCard` (gesture layer)
//  and `FlipCard` (content layer) into a single card unit.
//
//  This view is intentionally "dumb" — it owns no business logic.
//  Swipe events are forwarded directly to `FlashCardsPlayModeViewModel`
//  via the `onSwipe` closure; flip state is driven by the ViewModel's
//  `isFlipped` binding.
//

import SwiftUI

// MARK: - GameplayCard

/// A swipeable, flippable flashcard used during a play session.
///
/// `GameplayCard` coordinates two sub-components:
/// - `SwipeableCard` — UIKit-backed gesture layer with CADisplayLink at 120 fps.
/// - `FlipCard` — SwiftUI 3D flip animation showing the question or answer face.
///
/// All state changes are propagated upward: `onSwipe` triggers
/// `FlashCardsPlayModeViewModel.handleSwipe(_:)`, and `isFlipped` is a binding
/// to `FlashCardsPlayModeViewModel.isFlipped`.
struct GameplayCard: View {

    // MARK: - Properties

    /// The lightweight snapshot of the card being displayed.
    let card: PlayableCard

    /// Called by `SwipeableCard` when the user completes a horizontal swipe.
    let onSwipe: (SwipeDirection) -> Void

    /// Binding to the ViewModel's `isFlipped` property.
    ///
    /// When `true`, `FlipCard` shows the answer (back) face.
    @Binding var isFlipped: Bool

    // MARK: - Body

    var body: some View {
        SwipeableCard(onSwipe: onSwipe, onTap: handleTap) {
            FlipCard(
                card: card,
                isFlipped: $isFlipped
            )
        }
    }

    // MARK: - Actions

    /// Toggles the card between question and answer faces with a spring animation.
    private func handleTap() {
        withAnimation(.interactiveSpring(response: 0.45, dampingFraction: 0.85)) {
            isFlipped.toggle()
        }
    }
}
