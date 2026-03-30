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
import UIKit

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

    @Environment(AppPreferences.self) private var appPreferences

    // MARK: - Properties

    /// The lightweight snapshot of the card being displayed.
    let card: PlayableCard

    /// Called by `SwipeableCard` when the user completes a horizontal swipe.
    let onSwipe: (SwipeDirection) -> Void

    /// Controls whether the UIKit gesture layer should currently accept input.
    ///
    /// Preloaded upcoming cards stay mounted with interaction disabled so their
    /// rich content can finish rendering before they become visible.
    let isInteractionEnabled: Bool

    /// `true` when tapping the card should toggle between question and answer.
    let allowsTapToFlip: Bool

    /// Controls which visual treatment is used when tap reveal is enabled.
    let tapAnimationStyle: FlashcardTapAnimationStyle

    /// Controls whether static-swap text transitions animate or switch instantly.
    let staticSwapTextMotion: FlashcardStaticSwapTextMotion

    /// Controls how short content is positioned vertically inside the card.
    let contentAlignment: FlashcardContentAlignment

    /// Binding to the ViewModel's `isFlipped` property.
    ///
    /// When `true`, `FlipCard` shows the answer (back) face.
    @Binding var isFlipped: Bool
    @State private var swipeFeedback = SwipeCardFeedbackState()

    // MARK: - Body

    private var tapHandler: (() -> Void)? {
        (isInteractionEnabled && allowsTapToFlip) ? { handleTap() } : nil
    }

    var body: some View {
        SwipeableCard(
            onSwipe: onSwipe,
            onTap: tapHandler,
            isInteractionEnabled: isInteractionEnabled,
            onSwipeProgress: { direction, intensity in
                swipeFeedback.update(direction: direction, intensity: intensity)
            }
        ) {
            FlipCard(
                card: card,
                isFlipped: $isFlipped,
                swipeFeedback: swipeFeedback,
                tapAnimationStyle: tapAnimationStyle,
                staticSwapTextMotion: staticSwapTextMotion,
                contentAlignment: contentAlignment,
                onTap: tapHandler
            )
        }
    }

    // MARK: - Actions

    /// Toggles the card between question and answer faces using the selected tap animation.
    private func handleTap() {
        guard isInteractionEnabled, allowsTapToFlip else { return }
        playRevealHaptic()
        if let tapAnimation = resolvedTapAnimation {
            withAnimation(tapAnimation) {
                isFlipped.toggle()
            }
        } else {
            isFlipped.toggle()
        }
    }

    private func playRevealHaptic() {
        switch appPreferences.flashcardsSwipeHaptics {
        case .off:
            return
        case .subtle:
            let generator = UIImpactFeedbackGenerator(style: .soft)
            generator.prepare()
            generator.impactOccurred(intensity: 0.48)
        case .standard:
            let generator = UIImpactFeedbackGenerator(style: .soft)
            generator.prepare()
            generator.impactOccurred(intensity: 0.62)
        }
    }

    private var resolvedTapAnimation: Animation? {
        switch tapAnimationStyle {
        case .flip3D:
            return .interactiveSpring(response: 0.45, dampingFraction: 0.85)
        case .staticSwap:
            switch staticSwapTextMotion {
            case .animated:
                return .snappy(duration: 0.30, extraBounce: 0.02)
            case .instant:
                return nil
            }
        }
    }
}
