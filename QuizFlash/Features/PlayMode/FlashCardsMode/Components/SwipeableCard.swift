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

// MARK: - SwipeDirection

/// The horizontal direction in which the user swiped a card.
enum SwipeDirection { case left, right }

// MARK: - SwipeProgressPhase

/// Gesture lifecycle phase associated with a swipe-progress snapshot.
enum SwipeProgressPhase {
    case idle
    case dragging
    case cancelled
    case committed
}

enum SwipeDismissMotionStyle {
    case spring
    case linear
}

// MARK: - SwipeGestureTuning

/// Runtime tuning values for the swipe-recognition engine.
///
/// `flickSensitivity` modulates the velocity-only commit lane while still
/// sharing the same dismiss distance target used by the direct drag lane.
/// `dismissDistanceThreshold` controls how far the card must travel before a
/// pure distance-based dismiss commits.
struct SwipeGestureTuning {
    var flickSensitivity: CGFloat = 1
    var dismissDistanceThreshold: CGFloat = 120
    var usesDirectTiltTracking: Bool = false
    var dismissMotionStyle: SwipeDismissMotionStyle = .spring
    var dismissAnimationSpeed: CGFloat = 1

    static let `default` = SwipeGestureTuning()
}

// MARK: - SwipeProgressSnapshot

/// Lightweight swipe-progress payload emitted by the UIKit swipe host.
///
/// - `distanceProgress` is the linear distance-to-threshold value in `0...1`.
/// - `motionCurveProgress` matches the internal drag curve used by the card motion.
/// - `velocityProgress` normalises horizontal flick speed against the commit threshold.
/// - `projectedProgress` estimates threshold reach only when the release velocity
///   is strong enough to qualify as a genuine flick candidate.
/// - `commitIntentProgress` combines the direct-distance lane with the validated
///   flick lane without letting projection override a slow drag.
/// - `tiltAngleDegrees` mirrors the visible card tilt at the time the snapshot was emitted.
struct SwipeProgressSnapshot {
    let phase: SwipeProgressPhase
    let direction: SwipeDirection?
    let projectedCommitDirection: SwipeDirection?
    let committedDirection: SwipeDirection?
    let displacementX: CGFloat
    let distanceProgress: CGFloat
    let motionCurveProgress: CGFloat
    let velocityX: CGFloat
    let velocityProgress: CGFloat
    let projectedProgress: CGFloat
    let commitIntentProgress: CGFloat
    let fastSwipeDetected: Bool
    let tiltAngleDegrees: CGFloat

    static let idle = SwipeProgressSnapshot(
        phase: .idle,
        direction: nil,
        projectedCommitDirection: nil,
        committedDirection: nil,
        displacementX: 0,
        distanceProgress: 0,
        motionCurveProgress: 0,
        velocityX: 0,
        velocityProgress: 0,
        projectedProgress: 0,
        commitIntentProgress: 0,
        fastSwipeDetected: false,
        tiltAngleDegrees: 0
    )
}

// MARK: - SwipeGestureEvaluation

enum SwipeCommitReason {
    case distance
    case flick
}

struct SwipeCommitDecision {
    let direction: SwipeDirection
    let reason: SwipeCommitReason
}

struct SwipeGestureEvaluation {
    let trackingDirection: SwipeDirection?
    let projectedCommitDirection: SwipeDirection?
    let commitDecision: SwipeCommitDecision?
    let projectedDisplacementX: CGFloat
    let distanceProgress: CGFloat
    let motionCurveProgress: CGFloat
    let velocityProgress: CGFloat
    let projectedProgress: CGFloat
    let commitIntentProgress: CGFloat
    let flickCommitCandidate: Bool

    var fastSwipeDetected: Bool {
        if let commitDecision {
            return commitDecision.reason == .flick
        }
        return flickCommitCandidate
    }
}

struct SwipeGestureEvaluator {
    let tuning: SwipeGestureTuning

    private let baseFlickCommitVelocityThreshold: CGFloat = 700
    private let directionTrackingSlop: CGFloat = 5

    func evaluate(displacementX: CGFloat, velocityX: CGFloat) -> SwipeGestureEvaluation {
        let trackingDirection = resolvedDirection(forSignedValue: displacementX, slop: directionTrackingSlop)
        let absoluteDisplacement = abs(displacementX)
        let distanceProgress = min(absoluteDisplacement / resolvedDismissDistanceThreshold, 1)
        let motionCurveProgress = pow(distanceProgress, 1.85)
        let alignedVelocityX = resolvedAlignedVelocityX(displacementX: displacementX, velocityX: velocityX)
        let velocityProgress = min(abs(alignedVelocityX) / resolvedFlickCommitVelocityThreshold, 1)
        let projectedDisplacementX = displacementX + projectionLeadDistance(for: alignedVelocityX)
        let projectedProgress = min(abs(projectedDisplacementX) / resolvedDismissDistanceThreshold, 1)
        let flickTravelProgress = min(absoluteDisplacement / resolvedMinimumFlickTravel, 1)
        let projectedCommitDirection = resolvedProjectedCommitDirection(
            projectedDisplacementX: projectedDisplacementX,
            alignedVelocityX: alignedVelocityX,
            flickTravelProgress: flickTravelProgress
        )
        let flickCommitCandidate = projectedCommitDirection != nil
        let commitDecision = resolvedCommitDecision(
            displacementX: displacementX,
            projectedCommitDirection: projectedCommitDirection
        )
        let flickCommitProgress = projectedProgress * velocityProgress * flickTravelProgress
        let commitIntentProgress = min(max(distanceProgress, flickCommitProgress), 1)

        return SwipeGestureEvaluation(
            trackingDirection: trackingDirection,
            projectedCommitDirection: projectedCommitDirection,
            commitDecision: commitDecision,
            projectedDisplacementX: projectedDisplacementX,
            distanceProgress: distanceProgress,
            motionCurveProgress: motionCurveProgress,
            velocityProgress: velocityProgress,
            projectedProgress: projectedProgress,
            commitIntentProgress: commitIntentProgress,
            flickCommitCandidate: flickCommitCandidate
        )
    }

    private func resolvedCommitDecision(
        displacementX: CGFloat,
        projectedCommitDirection: SwipeDirection?
    ) -> SwipeCommitDecision? {
        if displacementX >= resolvedDismissDistanceThreshold {
            return SwipeCommitDecision(direction: .right, reason: .distance)
        }
        if displacementX <= -resolvedDismissDistanceThreshold {
            return SwipeCommitDecision(direction: .left, reason: .distance)
        }
        if let projectedCommitDirection {
            return SwipeCommitDecision(direction: projectedCommitDirection, reason: .flick)
        }
        return nil
    }

    private func resolvedProjectedCommitDirection(
        projectedDisplacementX: CGFloat,
        alignedVelocityX: CGFloat,
        flickTravelProgress: CGFloat
    ) -> SwipeDirection? {
        guard abs(alignedVelocityX) >= resolvedFlickCommitVelocityThreshold else { return nil }
        guard flickTravelProgress >= 1 else { return nil }

        if projectedDisplacementX >= resolvedDismissDistanceThreshold {
            return .right
        }
        if projectedDisplacementX <= -resolvedDismissDistanceThreshold {
            return .left
        }
        return nil
    }

    private func resolvedAlignedVelocityX(displacementX: CGFloat, velocityX: CGFloat) -> CGFloat {
        guard let velocityDirection = resolvedDirection(forSignedValue: velocityX, slop: directionTrackingSlop) else {
            return 0
        }

        if let trackingDirection = resolvedDirection(forSignedValue: displacementX, slop: directionTrackingSlop),
           trackingDirection != velocityDirection {
            return 0
        }

        return velocityX
    }

    private func projectionLeadDistance(for alignedVelocityX: CGFloat) -> CGFloat {
        let absoluteVelocity = abs(alignedVelocityX)
        guard absoluteVelocity >= resolvedFlickCommitVelocityThreshold else { return 0 }

        let overdriveProgress = min(
            (absoluteVelocity - resolvedFlickCommitVelocityThreshold)
                / (resolvedFlickCommitVelocityThreshold * 1.10),
            1
        )
        let leadProgress = 0.36 + (0.64 * pow(max(overdriveProgress, 0), 0.82))
        let direction: CGFloat = alignedVelocityX >= 0 ? 1 : -1
        return direction * resolvedProjectionLeadCap * leadProgress
    }

    private func resolvedDirection(forSignedValue value: CGFloat, slop: CGFloat) -> SwipeDirection? {
        if value > slop {
            return .right
        }
        if value < -slop {
            return .left
        }
        return nil
    }

    private var resolvedFlickSensitivity: CGFloat {
        min(max(tuning.flickSensitivity, 0.55), 1.9)
    }

    private var normalizedFlickSensitivity: CGFloat {
        min(max((resolvedFlickSensitivity - 0.55) / (1.9 - 0.55), 0), 1)
    }

    private var resolvedFlickCommitVelocityThreshold: CGFloat {
        max(baseFlickCommitVelocityThreshold / sqrt(resolvedFlickSensitivity), 420)
    }

    private var resolvedMinimumFlickTravel: CGFloat {
        let travelRatio = 0.18 - (0.08 * normalizedFlickSensitivity)
        return max(resolvedDismissDistanceThreshold * travelRatio, 12)
    }

    private var resolvedProjectionLeadCap: CGFloat {
        resolvedDismissDistanceThreshold * (1.02 + (0.20 * normalizedFlickSensitivity))
    }

    private var resolvedDismissDistanceThreshold: CGFloat {
        min(max(tuning.dismissDistanceThreshold, 72), 180)
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
///   - onSwipeProgress: Emits live drag progress for developer tooling or
///     alternative swipe feedback systems.
///   - content: The SwiftUI content displayed inside the swipeable container.
struct SwipeableCard<Content: View>: View {
    let onSwipe: (SwipeDirection) -> Void
    let onTap: (() -> Void)?
    let isInteractionEnabled: Bool
    let gestureTuning: SwipeGestureTuning
    let onSwipeProgress: ((SwipeProgressSnapshot) -> Void)?
    @ViewBuilder let content: () -> Content

    var body: some View {
        _SwipeHost(
            onSwipe: onSwipe,
            onTap: onTap,
            isInteractionEnabled: isInteractionEnabled,
            gestureTuning: gestureTuning,
            onSwipeProgress: onSwipeProgress,
            content: content
        )
    }
}
