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

    /// Controls which visual treatment is used when tap reveal is enabled.
    let tapAnimationStyle: FlashcardTapAnimationStyle

    /// Controls whether static-swap text transitions animate or switch instantly.
    let staticSwapTextMotion: FlashcardStaticSwapTextMotion

    /// Controls how short content is positioned vertically inside the card.
    let contentAlignment: FlashcardContentAlignment

    /// Controls the text scale used by the flashcard face renderer.
    let textSize: FlashcardTextSize

    /// Optional live swipe-progress callback used by play-mode developer tooling.
    let onSwipeProgress: ((SwipeProgressSnapshot) -> Void)?

    /// Runtime tuning for velocity/projection-based swipe commits.
    let swipeGestureTuning: SwipeGestureTuning

    /// Developer-only layout diagnostics emitted by the visible flashcard face.
    let onLayoutDebugSnapshot: ((ZoneContentLayoutDebugSnapshot) -> Void)?

    /// Binding to the ViewModel's `isFlipped` property.
    ///
    /// When `true`, `FlipCard` shows the answer (back) face.
    @Binding var isFlipped: Bool

    // MARK: - Init

    init(
        card: PlayableCard,
        onSwipe: @escaping (SwipeDirection) -> Void,
        isInteractionEnabled: Bool,
        tapAnimationStyle: FlashcardTapAnimationStyle,
        staticSwapTextMotion: FlashcardStaticSwapTextMotion,
        contentAlignment: FlashcardContentAlignment,
        textSize: FlashcardTextSize,
        onSwipeProgress: ((SwipeProgressSnapshot) -> Void)?,
        swipeGestureTuning: SwipeGestureTuning,
        onLayoutDebugSnapshot: ((ZoneContentLayoutDebugSnapshot) -> Void)? = nil,
        isFlipped: Binding<Bool>
    ) {
        self.card = card
        self.onSwipe = onSwipe
        self.isInteractionEnabled = isInteractionEnabled
        self.tapAnimationStyle = tapAnimationStyle
        self.staticSwapTextMotion = staticSwapTextMotion
        self.contentAlignment = contentAlignment
        self.textSize = textSize
        self.onSwipeProgress = onSwipeProgress
        self.swipeGestureTuning = swipeGestureTuning
        self.onLayoutDebugSnapshot = onLayoutDebugSnapshot
        self._isFlipped = isFlipped
    }

    // MARK: - Body

    private var tapHandler: (() -> Void)? {
        isInteractionEnabled ? { handleTap() } : nil
    }

    var body: some View {
        SwipeableCard(
            onSwipe: onSwipe,
            onTap: tapHandler,
            isInteractionEnabled: isInteractionEnabled,
            gestureTuning: swipeGestureTuning,
            onSwipeProgress: onSwipeProgress
        ) {
            FlipCard(
                card: card,
                isFlipped: $isFlipped,
                tapAnimationStyle: tapAnimationStyle,
                staticSwapTextMotion: staticSwapTextMotion,
                contentAlignment: contentAlignment,
                textSize: textSize,
                onTap: tapHandler,
                onLayoutDebugSnapshot: onLayoutDebugSnapshot
            )
        }
    }

    // MARK: - Actions

    /// Toggles the card between question and answer faces using the selected tap animation.
    private func handleTap() {
        guard isInteractionEnabled else { return }
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
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.prepare()
        generator.impactOccurred(intensity: 0.62)
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
