//
//  SwipeableCard.swift
//  QuizFlash
//
//  UIKit-backed swipeable card container with spring physics,
//  targeting 60–120 fps on ProMotion displays.
//
//  ## Physics Model
//
//  **During drag:**
//  - Position follows the finger 1:1 (direct manipulation, zero lag on X).
//  - Tilt angle is governed by a per-frame spring integrator running inside
//    `CADisplayLink`. The spring chases a progress-shaped target angle derived
//    from the current translation, and the card scales down slightly toward the
//    swipe threshold. This gives the card perceived mass:
//    rapid direction reversals produce a short overshoot before the tilt
//    settles, and slow drags ramp up tilt gently instead of jumping.
//
//  **After release:**
//  - Snap-back and exit both use `UIViewPropertyAnimator` with
//    `UISpringTimingParameters`, preserving gesture release velocity so the
//    card behaves as if the user physically threw it.
//  - `onSwipe` is dispatched at the moment the exit animation starts.
//    The SwiftUI `.opacity` removal and the UIKit exit animation run in
//    parallel — the card fades *as it flies off*, which looks intentional.
//    The card reaches off-screen before the opacity reaches zero, so there
//    is no visible disappearance mid-flight.
//
//  ## Architecture
//  - `UIPanGestureRecognizer` writes `translationX` (cumulative X offset).
//  - `CADisplayLink` reads `translationX`, spring-integrates the tilt angle,
//    and commits one `CATransaction` per frame — no layout work between frames.
//  - No `shouldRasterize` — rasterisation freezes the GPU texture at capture
//    scale and produces visible distortion during the rotation transform.
//  - Drag scale is tied to the same swipe progress as the tilt, shrinking
//    gently toward `0.9` as the card approaches the exit threshold.
//  - `gestureRecognizerShouldBegin` rejects gestures whose initial velocity is
//    primarily vertical, preventing the card from moving during scroll attempts.
//
//  ## Issues Fixed vs Previous Implementation
//
//  **FIX 1 — Mechanical, mass-less tilt:**
//    `min(abs(dx)/14, 18°)` produced a linear ramp with a hard cap. It felt
//    like a UI element, not a physical card.
//    Fix: `tanh(dx/90)×15°` gives smooth natural saturation with no hard cap.
//    A spring integrator with stiffness 220 / damping 18 chases this target,
//    giving the card perceived inertia and a pleasing overshoot on reversals.
//
//  **FIX 2 — shouldRasterize artifacts:**
//    `shouldRasterize = true` during drag captured the layer tree as a GPU
//    texture at a fixed scale. When the rotation transform was applied, the
//    pre-baked texture stretched/distorted noticeably.
//    Fix: removed entirely. Core Animation composites the live layer tree each
//    frame without rasterisation overhead at 120 fps.
//
//  **FIX 3 — Animation conflict between UIKit exit and SwiftUI removal:**
//    `onSwipe` was dispatched 150 ms into a 300–580 ms UIKit center animation.
//    SwiftUI's `.opacity` removal started at 150 ms, fading the card while it
//    was still on-screen. Both animations competed, producing a glitchy jump.
//    Fix: `onSwipe` is dispatched when the exit animator starts. The UIKit exit
//    and SwiftUI fade run together from t=0. The exit animation is tuned to
//    complete in 200–350 ms so the card reaches off-screen before the ~300 ms
//    SwiftUI fade completes — the fade is invisible because it applies to an
//    off-screen card.
//
//  **FIX 4 — Snap-back ignoring gesture velocity:**
//    `initialSpringVelocity` was hardcoded to `0.4` regardless of how fast the
//    user was moving when they released.
//    Fix: release velocity is normalised relative to the snap distance and
//    passed to `UISpringTimingParameters` so a fast partial-drag snaps back
//    with momentum and a slow one settles gently.
//
//  **FIX 5 — Scale transform during drag:**
//    `scale = max(0.88, 1 - |dx|/width × 0.26)` applied simultaneously with
//    rotation. Scale + rotation together felt unnatural.
//    Fix: replaced with a threshold-linked scale curve. The card now shrinks
//    progressively toward `0.9` only as it nears exit commitment.
//

import SwiftUI
import Observation

// MARK: - SwipeDirection

/// The horizontal direction in which the user swiped a card.
enum SwipeDirection { case left, right }

// MARK: - SwipeCardFeedbackState

/// Observable state used to drive the card's swipe-direction border feedback.
///
/// Updated each `CADisplayLink` frame during drag. The `@Observable` macro
/// ensures `FlipCard` reacts to changes without any manual `objectWillChange`.
@Observable
@MainActor
final class SwipeCardFeedbackState {
    private(set) var direction: SwipeDirection?
    private(set) var intensity: CGFloat = 0

    func update(direction: SwipeDirection?, intensity: CGFloat) {
        let clamped = min(max(intensity, 0), 1)
        guard self.direction != direction || abs(self.intensity - clamped) >= 0.01 else { return }
        self.direction = direction
        self.intensity = clamped
    }
}

// MARK: - SwipeableCard

/// A SwiftUI wrapper around a UIKit-backed pan-gesture layer with spring physics.
///
/// Hosts arbitrary SwiftUI content inside a draggable `UIView` driven by a
/// `CADisplayLink` tilt-spring at up to 120 fps. Snap-back and exit animations
/// use `UIViewPropertyAnimator` with `UISpringTimingParameters` to preserve
/// gesture release velocity.
///
/// - Parameters:
///   - onSwipe: Called when the user completes a decisive horizontal swipe.
///   - onTap: Called on a single tap (typically flips the card).
///   - onSwipeProgress: Called each display frame during drag with the current
///     direction and a normalised intensity in `0…1` for border feedback.
///   - content: The SwiftUI content displayed inside the swipeable container.
struct SwipeableCard<Content: View>: View {
    let onSwipe: (SwipeDirection) -> Void
    let onTap: (() -> Void)?
    let isInteractionEnabled: Bool
    let onSwipeProgress: ((SwipeDirection?, CGFloat) -> Void)?
    @ViewBuilder let content: () -> Content

    var body: some View {
        _SwipeHost(
            onSwipe: onSwipe,
            onTap: onTap,
            isInteractionEnabled: isInteractionEnabled,
            onSwipeProgress: onSwipeProgress,
            content: content
        )
    }
}
