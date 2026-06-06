//
//  SwipeableCardUIKitBridge.swift
//  QuizFlash
//
//  UIKit bridge and coordinator for the swipeable card container.
//

import SwiftUI
import UIKit
import WebKit

// MARK: - Fixed Container

/// The fixed-size `UIView` that anchors the draggable card hierarchy.
///
/// - `clipsToBounds` is hard-wired to `false` so the card can travel outside
///   the container bounds during a swipe without being clipped.
/// - `hitTest` forwards touches to `draggableCard` even when it has moved
///   outside the container bounds.
/// - `layoutSubviews` is gated by `isDragging` so a mid-drag parent layout
///   invalidation cannot snap the card back to `bounds`.
final class _FixedContainer: UIView {
    weak var draggableCard: UIView?
    var isDragging = false

    override var clipsToBounds: Bool { get { false } set {} }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !isDragging else { return }
        draggableCard?.frame = bounds
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled else { return nil }
        if let card = draggableCard {
            let p = convert(point, to: card)
            if let hit = card.hitTest(p, with: event) { return hit }
        }
        return super.hitTest(point, with: event)
    }
}

// MARK: - UIViewRepresentable

/// The `UIViewRepresentable` bridge that creates and manages the UIKit view
/// hierarchy for `SwipeableCard`.
struct _SwipeHost<Content: View>: UIViewRepresentable {
    let onSwipe: (SwipeDirection) -> Void
    let onTap: (() -> Void)?
    let isInteractionEnabled: Bool
    let gestureTuning: SwipeGestureTuning
    let onSwipeProgress: ((SwipeProgressSnapshot) -> Void)?
    let content: () -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onSwipe: onSwipe,
            onTap: onTap,
            isInteractionEnabled: isInteractionEnabled,
            gestureTuning: gestureTuning,
            onSwipeProgress: onSwipeProgress
        )
    }

    func makeUIView(context: Context) -> _FixedContainer {
        let fixed = _FixedContainer()

        let draggable = UIView()
        draggable.backgroundColor = .clear
        draggable.clipsToBounds = false
        fixed.addSubview(draggable)
        fixed.draggableCard = draggable

        let host = UIHostingController(rootView: content())
        host.view.backgroundColor = .clear
        host.view.clipsToBounds = false
        host.view.translatesAutoresizingMaskIntoConstraints = false
        draggable.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: draggable.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: draggable.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: draggable.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: draggable.bottomAnchor),
        ])

        context.coordinator.setup(fixed: fixed, draggable: draggable, host: host)

        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        draggable.addGestureRecognizer(pan)
        context.coordinator.cardPanGesture = pan

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap)
        )
        tap.require(toFail: pan)
        draggable.addGestureRecognizer(tap)
        context.coordinator.cardTapGesture = tap

        return fixed
    }

    func updateUIView(_ uiView: _FixedContainer, context: Context) {
        context.coordinator.updateCallbacks(
            onSwipe: onSwipe,
            onTap: onTap,
            isInteractionEnabled: isInteractionEnabled,
            gestureTuning: gestureTuning,
            onSwipeProgress: onSwipeProgress
        )
        guard !context.coordinator.isDragging else { return }
        context.coordinator.host?.rootView = content()
    }
}

// MARK: - Coordinator

extension _SwipeHost {

    /// Manages gesture recognition, the `CADisplayLink` render loop, and
    /// velocity-preserving snap-back / exit animations.
    ///
    /// ## Rendering Pipeline
    /// 1. `handlePan(.changed)` writes `translationX` — the total cumulative
    ///    horizontal offset since gesture start.
    /// 2. `renderFrame` fires every display refresh, reads `translationX`,
    ///    integrates the tilt spring toward the `tanh`-derived target angle,
    ///    and commits position + rotation in one disabled-actions `CATransaction`.
    ///
    /// ## Tilt Tracking
    /// The default path keeps the slightly underdamped spring-driven tilt. Lab
    /// tuning can opt into direct tilt tracking so the visible card angle follows
    /// swipe distance linearly with no lag.
    ///
    /// ## Exit / Snap-back
    /// Both use `UIViewPropertyAnimator` with `UISpringTimingParameters`.
    /// The gesture release velocity is normalised relative to the remaining
    /// travel distance and passed as `initialVelocity`, so a fast throw exits
    /// quickly and a slow release snaps back gently.
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {

        // MARK: Callbacks & references

        var onSwipe: (SwipeDirection) -> Void
        var onTap: (() -> Void)?
        var onSwipeProgress: ((SwipeProgressSnapshot) -> Void)?
        private var isInteractionEnabled: Bool
        private var gestureTuning: SwipeGestureTuning

        weak var fixed: _FixedContainer?
        weak var draggable: UIView?
        var host: UIHostingController<Content>?
        weak var cardPanGesture: UIPanGestureRecognizer?
        weak var cardTapGesture: UITapGestureRecognizer?

        private(set) var isDragging = false

        private struct HostedScrollLock {
            weak var scrollView: UIScrollView?
            let wasScrollEnabled: Bool
            let contentOffset: CGPoint
        }

        // MARK: Spring physics state

        /// Total horizontal translation from gesture start (updated each .changed).
        private var translationX: CGFloat = 0

        /// Current tilt angle in radians, driven by the spring integrator in `renderFrame`.
        private var currentTilt: CGFloat = 0

        /// Angular velocity of the tilt spring (radians / second).
        private var tiltVelocity: CGFloat = 0

        /// Tilt spring stiffness. Higher = tighter coupling to finger direction.
        private let tiltStiffness: CGFloat = 220

        /// Tilt spring damping. Paired with stiffness 220, ratio ≈ 0.61 (underdamped).
        /// Produces a short, satisfying overshoot on fast direction reversals.
        private let tiltDamping: CGFloat = 18

        // MARK: Gesture state

        /// The card's home centre inside the container when no interaction is active.
        private var homeCenter: CGPoint = .zero

        /// The visual centre captured when the current gesture begins.
        private var gestureStartCenter: CGPoint = .zero

        private var isGestureActive = false
        private var isExiting = false
        private var displayLink: CADisplayLink?
        private var activeAnimator: UIViewPropertyAnimator?
        private var pendingSwipeCommitTask: Task<Void, Never>?
        private var pendingSwipeDirection: SwipeDirection?
        private var exitHandoffLink: CADisplayLink?
        private weak var exitObservedCard: UIView?
        private var exitObservedDirection: SwipeDirection?
        private var exitRevealMargin: CGFloat = 26
        private var entranceUnlockTask: Task<Void, Never>?
        private var gestureStartScale: CGFloat = 1
        private var hapticFired = false
        private let haptic = UIImpactFeedbackGenerator(style: .medium)
        private var latestGestureVelocityX: CGFloat = 0
        private weak var cardPanInitialWebView: WKWebView?
        private var cardPanInitialLocationInWebView: CGPoint?
        private weak var cardPanInitialEdgeHandoffScrollView: UIScrollView?

        private var hostedScrollLocks: [HostedScrollLock] = []

        // MARK: Init

        init(
            onSwipe: @escaping (SwipeDirection) -> Void,
            onTap: (() -> Void)?,
            isInteractionEnabled: Bool,
            gestureTuning: SwipeGestureTuning,
            onSwipeProgress: ((SwipeProgressSnapshot) -> Void)?
        ) {
            self.onSwipe = onSwipe
            self.onTap = onTap
            self.isInteractionEnabled = isInteractionEnabled
            self.gestureTuning = gestureTuning
            self.onSwipeProgress = onSwipeProgress
        }

        deinit {
            restoreHostedScrollViewsAfterSwipe()
            activeAnimator?.stopAnimation(true)
            pendingSwipeCommitTask?.cancel()
            entranceUnlockTask?.cancel()
            stopExitHandoffObservation()
        }

        // MARK: Setup

        /// Wires the UIKit view hierarchy and plays the entrance spring animation.
        ///
        /// The entrance animation runs directly on the UIKit layer so SwiftUI's
        /// `.identity` insertion transition never sees the scale — avoiding the
        /// `clipsToBounds = false` bleed bug where the SwiftUI transition clips
        /// the card during the scale animation.
        func setup(fixed: _FixedContainer, draggable: UIView, host: UIHostingController<Content>) {
            self.fixed = fixed
            self.draggable = draggable
            self.host = host
            entranceUnlockTask?.cancel()
            entranceUnlockTask = nil
            fixed.isUserInteractionEnabled = false
            draggable.isUserInteractionEnabled = false

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            draggable.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
            CATransaction.commit()

            UIView.animate(
                withDuration: 0.40,
                delay: 0,
                usingSpringWithDamping: 0.72,
                initialSpringVelocity: 0,
                options: [.allowUserInteraction, .beginFromCurrentState]
            ) { [weak draggable] in
                draggable?.transform = .identity
            }

            entranceUnlockTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled, let self else { return }
                self.entranceUnlockTask = nil
                self.syncInteractionEnabled()
            }
        }

        func updateCallbacks(
            onSwipe: @escaping (SwipeDirection) -> Void,
            onTap: (() -> Void)?,
            isInteractionEnabled: Bool,
            gestureTuning: SwipeGestureTuning,
            onSwipeProgress: ((SwipeProgressSnapshot) -> Void)?
        ) {
            self.onSwipe = onSwipe
            self.onTap = onTap
            self.isInteractionEnabled = isInteractionEnabled
            self.gestureTuning = gestureTuning
            self.onSwipeProgress = onSwipeProgress
            syncInteractionEnabled()
        }

        private func syncInteractionEnabled() {
            guard !isDragging, !isExiting else { return }
            let tapEnabled = isInteractionEnabled && onTap != nil
            fixed?.isUserInteractionEnabled = isInteractionEnabled
            draggable?.isUserInteractionEnabled = isInteractionEnabled
            cardPanGesture?.isEnabled = isInteractionEnabled
            cardTapGesture?.isEnabled = tapEnabled
        }

        // MARK: Tap

        @objc func handleTap() {
            publishTouchDebug(
                event: "tap ended",
                recognizer: "cardTap",
                decision: "TAP",
                reason: "card tap handler fired"
            )
            onTap?()
        }

        // MARK: Gesture recogniser delegate

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard isInteractionEnabled else {
                publishTouchDebug(
                    event: "shouldBegin",
                    recognizer: recognizerName(gestureRecognizer),
                    decision: "BLOCK",
                    reason: "interaction disabled",
                    gestureRecognizer: gestureRecognizer
                )
                return false
            }
            guard !isExiting else {
                publishTouchDebug(
                    event: "shouldBegin",
                    recognizer: recognizerName(gestureRecognizer),
                    decision: "BLOCK",
                    reason: "card exiting",
                    gestureRecognizer: gestureRecognizer
                )
                return false
            }
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let view = pan.view else {
                publishTouchDebug(
                    event: "shouldBegin",
                    recognizer: recognizerName(gestureRecognizer),
                    decision: "ALLOW",
                    reason: "non-pan recognizer",
                    gestureRecognizer: gestureRecognizer
                )
                return true
            }
            let v = pan.velocity(in: view)
            guard v != .zero else {
                publishTouchDebug(
                    event: "shouldBegin",
                    recognizer: "cardPan",
                    decision: "ALLOW",
                    reason: "zero velocity",
                    gestureRecognizer: gestureRecognizer
                )
                return true
            }
            // Reject gestures whose initial velocity is predominantly vertical.
            // This lets the card ignore scroll attempts completely — the `.began`
            // phase never fires for vertical gestures, so the card never moves.
            guard isHorizontalCardSwipeIntent(pan, in: view) else {
                publishTouchDebug(
                    event: "shouldBegin",
                    recognizer: "cardPan",
                    decision: "BLOCK",
                    reason: "not horizontal card intent",
                    gestureRecognizer: gestureRecognizer
                )
                return false
            }
            if gestureRecognizer === cardPanGesture,
               shouldMathWebViewHandlePan(pan) {
                publishTouchDebug(
                    event: "shouldBegin",
                    recognizer: "cardPan",
                    decision: "WEB",
                    reason: "math web region can scroll",
                    gestureRecognizer: gestureRecognizer
                )
                return false
            }
            if gestureRecognizer === cardPanGesture,
               shouldEdgeHandoffScrollViewHandlePan(pan) {
                publishTouchDebug(
                    event: "shouldBegin",
                    recognizer: "cardPan",
                    decision: "SCROLL",
                    reason: "edge handoff scroll view can scroll",
                    gestureRecognizer: gestureRecognizer
                )
                return false
            }
            publishTouchDebug(
                event: "shouldBegin",
                recognizer: "cardPan",
                decision: "CARD",
                reason: "card pan allowed",
                gestureRecognizer: gestureRecognizer
            )
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            guard isInteractionEnabled else { return false }
            if gestureRecognizer === cardPanGesture {
                if let touchedView = touch.view,
                   let webView = nearestHostedWebView(from: touchedView) {
                    cardPanInitialWebView = webView
                    cardPanInitialLocationInWebView = touch.location(in: webView)
                } else {
                    cardPanInitialWebView = nil
                    cardPanInitialLocationInWebView = nil
                }
                cardPanInitialEdgeHandoffScrollView = touch.view.flatMap(nearestEdgeHandoffScrollView(from:))
                publishTouchDebug(
                    event: "shouldReceive",
                    recognizer: "cardPan",
                    decision: "ALLOW",
                    reason: cardPanInitialWebView == nil ? "plain card touch" : "web touch tracked for pan handoff",
                    touch: touch,
                    gestureRecognizer: gestureRecognizer
                )
                return true
            }
            if gestureRecognizer === cardTapGesture {
                publishTouchDebug(
                    event: "shouldReceive",
                    recognizer: "cardTap",
                    decision: "ALLOW",
                    reason: touch.view.flatMap(nearestHostedWebView(from:)) == nil ? "plain card tap" : "web tap allowed",
                    touch: touch,
                    gestureRecognizer: gestureRecognizer
                )
                return true
            }
            return true
        }

        func gestureRecognizer(
            _ g: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            guard g === cardPanGesture || other === cardPanGesture else { return false }
            guard (g === cardPanGesture ? g : other) is UIPanGestureRecognizer else { return false }
            guard isHostedScrollViewGesture(g) || isHostedScrollViewGesture(other) else {
                return false
            }
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            false
        }

        // MARK: Pan handler

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let card = draggable, let container = fixed else { return }

            switch gesture.state {
            case .began:
                lockHostedScrollViewsForHorizontalSwipe()
                isDragging = true
                container.isDragging = true
                isGestureActive = true
                haptic.prepare()

                // Capture the presentation-layer state before canceling the previous
                // animator so a new drag can continue seamlessly from the exact
                // visual card pose currently on screen.
                let visualCenter = currentPresentationCenter(for: card)
                let visualTransform = currentPresentationTransform(for: card)
                let resolvedHomeCenter = CGPoint(
                    x: container.bounds.midX,
                    y: container.bounds.midY
                )

                activeAnimator?.stopAnimation(true)
                activeAnimator = nil
                pendingSwipeCommitTask?.cancel()
                pendingSwipeCommitTask = nil
                pendingSwipeDirection = nil
                stopExitHandoffObservation()

                CATransaction.begin()
                CATransaction.setDisableActions(true)
                container.isUserInteractionEnabled = true
                card.isUserInteractionEnabled = true
                card.layer.removeAllAnimations()
                card.center = visualCenter
                card.transform = visualTransform
                homeCenter = container.bounds.isEmpty ? visualCenter : resolvedHomeCenter
                gestureStartCenter = visualCenter
                CATransaction.commit()

                // Re-seed the tilt spring from the visible transform so the first
                // drag frame does not jump when the user grabs during a running
                // entrance or snap-back animation.
                translationX = 0
                currentTilt = rotationAngle(for: visualTransform)
                gestureStartScale = min(max(uniformScale(for: visualTransform), 0.9), 1.0)
                tiltVelocity = 0
                latestGestureVelocityX = 0
                onSwipeProgress?(.idle)
                startDisplayLink()

            case .changed:
                translationX = gesture.translation(in: container).x
                latestGestureVelocityX = gesture.velocity(in: container).x

                let absDx = abs(translationX)
                if absDx > 8 && absDx < 28 { haptic.prepare() }
                if absDx >= resolvedDismissDistanceThreshold && !hapticFired {
                    haptic.impactOccurred()
                    hapticFired = true
                } else if absDx < resolvedDismissDistanceThreshold * 0.7 {
                    hapticFired = false
                }

            case .ended, .cancelled, .failed:
                cardPanInitialWebView = nil
                cardPanInitialLocationInWebView = nil
                cardPanInitialEdgeHandoffScrollView = nil
                restoreHostedScrollViewsAfterSwipe()
                isGestureActive = false
                isDragging = false
                stopDisplayLink()

                let dx = gesture.translation(in: container).x
                let vx = gesture.velocity(in: container).x
                latestGestureVelocityX = vx
                let evaluation = swipeGestureEvaluator.evaluate(displacementX: dx, velocityX: vx)
                let commitDecision = evaluation.commitDecision
                emitSwipeProgressSnapshot(
                    displacementX: dx,
                    velocityX: vx,
                    phase: commitDecision == nil ? .cancelled : .committed,
                    committedDirection: commitDecision?.direction,
                    tiltAngleDegrees: rotationAngle(for: currentPresentationTransform(for: card)) * 180 / .pi
                )
                let shouldEmitCommitHaptic = !hapticFired

                if let commitDecision {
                    if shouldEmitCommitHaptic {
                        haptic.impactOccurred(intensity: 1.0)
                    }
                    commitExit(commitDecision.direction, velocityX: vx, card: card)
                } else {
                    snapBack(card: card, velocityX: vx)
                }
                hapticFired = false

            default:
                break
            }
        }

        // MARK: Display link

        private func startDisplayLink() {
            guard displayLink == nil else { return }
            let link = CADisplayLink(target: self, selector: #selector(renderFrame))
            if #available(iOS 15, *) {
                link.preferredFrameRateRange = CAFrameRateRange(
                    minimum: 60,
                    maximum: 120,
                    preferred: 120
                )
            }
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        private func stopDisplayLink() {
            displayLink?.invalidate()
            displayLink = nil
        }

        private func startExitHandoffObservation(card: UIView, direction: SwipeDirection) {
            stopExitHandoffObservation()

            let link = CADisplayLink(target: self, selector: #selector(observeExitHandoff))
            if #available(iOS 15, *) {
                link.preferredFrameRateRange = CAFrameRateRange(
                    minimum: 60,
                    maximum: 120,
                    preferred: 120
                )
            }
            link.add(to: .main, forMode: .common)

            exitObservedCard = card
            exitObservedDirection = direction
            exitHandoffLink = link
        }

        private func stopExitHandoffObservation() {
            exitHandoffLink?.invalidate()
            exitHandoffLink = nil
            exitObservedCard = nil
            exitObservedDirection = nil
            exitRevealMargin = -10
        }

        @objc private func observeExitHandoff() {
            guard
                pendingSwipeDirection != nil,
                let card = exitObservedCard,
                let container = fixed,
                let direction = exitObservedDirection
            else {
                stopExitHandoffObservation()
                return
            }

            let frame = card.layer.presentation()?.frame ?? card.frame
            let revealMargin = exitRevealMargin
            let shouldTrigger: Bool
            let displacementX = frame.midX - homeCenter.x

            emitSwipeProgressSnapshot(
                displacementX: displacementX,
                velocityX: latestGestureVelocityX,
                phase: .committed,
                committedDirection: direction,
                tiltAngleDegrees: rotationAngle(for: currentPresentationTransform(for: card)) * 180 / .pi
            )

            switch direction {
            case .right:
                shouldTrigger = frame.minX >= container.bounds.maxX - revealMargin
            case .left:
                shouldTrigger = frame.maxX <= container.bounds.minX + revealMargin
            }

            if shouldTrigger {
                triggerPendingSwipeCommit()
            }
        }

        private func triggerPendingSwipeCommit() {
            guard let direction = pendingSwipeDirection else {
                pendingSwipeCommitTask?.cancel()
                pendingSwipeCommitTask = nil
                stopExitHandoffObservation()
                return
            }

            pendingSwipeCommitTask?.cancel()
            pendingSwipeCommitTask = nil
            pendingSwipeDirection = nil
            stopExitHandoffObservation()
            onSwipe(direction)
        }

        /// Integrates the tilt spring and commits position + rotation in one
        /// disabled-actions `CATransaction` every display frame.
        ///
        /// ## Tilt target
        /// Lab tuning can switch the card to a direct linear tilt path where
        /// `min(|translationX| / threshold, 1) × 5°` maps swipe progress to the
        /// visible card angle. The default production path keeps the original
        /// eased ramp: `pow(min(|translationX| / threshold, 1), 1.85) × 5°`.
        ///
        /// ## Spring integration
        /// A simple Euler step per frame:
        /// ```
        /// force = k × (target − current) − d × velocity
        /// velocity += force × dt
        /// current  += velocity × dt
        /// ```
        /// Damping ratio ≈ 0.61 (underdamped) → slight overshoot on direction
        /// reversals, giving the card perceived mass.
        @objc private func renderFrame(_ link: CADisplayLink) {
            guard isGestureActive, let card = draggable else { return }

            let dx = translationX
            let dt = min(
                max(CGFloat(link.targetTimestamp - link.timestamp), 1.0 / 120.0),
                1.0 / 50.0
            )

            let targetTilt = tiltTargetAngle(for: dx)
            let dragScale = min(targetDragScale(for: dx), gestureStartScale)

            if usesDirectTiltTracking {
                currentTilt = targetTilt
                tiltVelocity = 0
            } else {
                // Spring-integrate current tilt toward target (Euler method).
                let force = tiltStiffness * (targetTilt - currentTilt) - tiltDamping * tiltVelocity
                tiltVelocity += force * dt
                currentTilt  += tiltVelocity * dt
            }

            // Position follows the finger with 1:1 fidelity — no lag on X axis.
            let newCenter = CGPoint(
                x: gestureStartCenter.x + dx,
                y: gestureStartCenter.y
            )
            let newTransform = cardTransform(angle: currentTilt, scale: dragScale)

            // One atomic transaction per frame — no implicit animations, no layout.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            card.transform = newTransform
            card.center    = newCenter
            CATransaction.commit()

            emitSwipeProgressSnapshot(
                displacementX: dx,
                velocityX: latestGestureVelocityX,
                phase: .dragging,
                committedDirection: nil,
                tiltAngleDegrees: currentTilt * 180 / .pi
            )

        }

        // MARK: Snap-back

        /// Returns the card to its rest position using a spring that preserves the
        /// gesture release velocity.
        ///
        /// A fast partial-drag (e.g. quick sideways swipe that doesn't cross the
        /// threshold) snaps back with visible momentum. A slow release settles
        /// gently. Both feel physical rather than mechanical.
        private func snapBack(card: UIView, velocityX: CGFloat) {
            // Read presentation-layer position — the last `renderFrame` wrote to
            // the model layer via setDisableActions(true), so presentation matches.
            // Using presentation() is safer in case any residual animation is active.
            let currentX = card.layer.presentation().map { $0.frame.midX } ?? card.center.x
            let distanceToRest = homeCenter.x - currentX

            // Normalise release velocity relative to snap distance so
            // UISpringTimingParameters receives a dimensionless initial velocity.
            // Positive = moving toward rest position.
            let normVx: CGFloat = abs(distanceToRest) > 0.5
                ? velocityX / distanceToRest
                : 0

            let springParams = UISpringTimingParameters(
                mass: 1.0,
                stiffness: 420,
                damping: 44,
                initialVelocity: CGVector(dx: normVx, dy: 0)
            )
            let animator = UIViewPropertyAnimator(duration: 0.5, timingParameters: springParams)
            animator.addAnimations { [weak self] in
                card.transform = .identity
                card.center = self?.homeCenter ?? card.center
            }
            animator.addCompletion { [weak self, weak fixed = fixed] _ in
                self?.activeAnimator = nil
                fixed?.isDragging = false
                self?.onSwipeProgress?(.idle)
            }
            activeAnimator = animator
            animator.startAnimation()
        }

        // MARK: Exit

        /// Launches the card off-screen with a spring animation that respects
        /// gesture velocity, then calls `onSwipe` so the next card enters in parallel.
        ///
        /// ## Animation strategy
        /// `onSwipe` is called as the exit animator starts. SwiftUI's `.opacity`
        /// removal and the UIKit exit animation run concurrently:
        /// - The UIKit spring moves the card off-screen in ~200–350 ms.
        /// - SwiftUI fades the `_FixedContainer` to alpha 0 in ~300 ms.
        ///
        /// The card reaches off-screen *before* its alpha reaches zero, so the
        /// fade is applied to a card that is no longer visible — no glitch.
        /// If the user throws hard (high velocity), the exit is even faster and
        /// the card is off-screen almost immediately.
        private func commitExit(_ direction: SwipeDirection, velocityX: CGFloat, card: UIView) {
            isExiting = true
            let evaluation = swipeGestureEvaluator.evaluate(
                displacementX: currentPresentationCenter(for: card).x - homeCenter.x,
                velocityX: velocityX
            )

            let width = max(resolvedExitWidth(for: card), 1)
            // Exit target: one screen width plus a small overshoot so the card
            // fully clears the display edge. The SwiftUI fade makes the exact
            // stopping point invisible, so we don't need an extreme overshoot.
            let exitX = direction == .right
                ? homeCenter.x + width + 80
                : homeCenter.x - width - 80

            let currentX = currentPresentationCenter(for: card).x
            let distanceToExit = exitX - currentX
            let currentAngle = rotationAngle(for: currentPresentationTransform(for: card))
            let currentDisplacementX = currentX - homeCenter.x
            let releaseDisplacement = abs(currentDisplacementX)
            let displacementProgress = min(releaseDisplacement / resolvedDismissDistanceThreshold, 1)
            let projectedReleaseDisplacementX = evaluation.projectedDisplacementX
            let releaseTiltAngle = tiltTargetAngle(for: projectedReleaseDisplacementX)
            let currentScale = min(max(uniformScale(for: currentPresentationTransform(for: card)), 0.9), 1.0)
            let exitScale = min(currentScale, targetDragScale(for: projectedReleaseDisplacementX))
            let directionSign: CGFloat = direction == .right ? 1 : -1

            if resolvedDismissMotionStyle == .linear {
                let exitAngleMagnitude = max(abs(currentAngle), abs(releaseTiltAngle))
                let exitAngle = directionSign * exitAngleMagnitude
                let transformLeadDuration = min(
                    resolvedDismissAnimationDuration,
                    max(0.08, resolvedDismissAnimationDuration * 0.38)
                )

                let transformAnimator = UIViewPropertyAnimator(duration: transformLeadDuration, curve: .linear)
                transformAnimator.addAnimations { [weak self] in
                    guard let self else { return }
                    card.transform = self.cardTransform(angle: exitAngle, scale: exitScale)
                }
                transformAnimator.startAnimation()

                let animator = UIViewPropertyAnimator(duration: resolvedDismissAnimationDuration, curve: .linear)
                animator.addAnimations { [weak self] in
                    guard let self else { return }
                    card.center = CGPoint(x: exitX, y: self.homeCenter.y)
                }
                animator.addCompletion { [weak self, weak fixed = fixed] _ in
                    self?.activeAnimator = nil
                    self?.isExiting = false
                    fixed?.isDragging = false
                }
                activeAnimator = animator
                animator.startAnimation()

                pendingSwipeCommitTask?.cancel()
                pendingSwipeDirection = direction
                exitRevealMargin = -10
                fixed?.isUserInteractionEnabled = false
                card.isUserInteractionEnabled = false
                startExitHandoffObservation(card: card, direction: direction)
                let handoffDelay = max(0.10, resolvedDismissAnimationDuration * 0.62)
                pendingSwipeCommitTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(handoffDelay))
                    guard !Task.isCancelled else { return }
                    self?.triggerPendingSwipeCommit()
                }
                return
            }

            // Preserve some distinction between a controlled swipe and a fast
            // flick, while still avoiding cannon-shot exits on tiny throws.
            let gestureVelocityProgress = min(abs(velocityX) / 2400, 1)
            let velocityAttenuation: CGFloat = 0.12
                + (0.48 * displacementProgress)
                + (0.08 * gestureVelocityProgress)
            let exitVelocityX = velocityX * velocityAttenuation

            // Normalise the attenuated velocity relative to remaining exit distance,
            // then soft-clamp it so quick short flicks cannot spike the launch speed.
            // Faster swipes still get a meaningfully stronger launch than slower ones.
            let rawNormVx = abs(distanceToExit) > 0.5 ? exitVelocityX / distanceToExit : 1.0
            let forwardNormVx = max(rawNormVx, 0)
            let maxLaunchVelocity: CGFloat = 0.44
                + (0.16 * displacementProgress)
                + (0.08 * gestureVelocityProgress)
            let launchResponse: CGFloat = 0.32 + (0.10 * gestureVelocityProgress)
            let normVx = min(
                max(tanh(forwardNormVx * launchResponse), 0.30),
                maxLaunchVelocity
            )

            // Spring parameters for the exit:
            // - Lower stiffness weakens the initial acceleration, stretching the
            //   swipe further and making short flicks feel less ballistic.
            // - Damping is reduced proportionally to preserve the same overall
            //   "thrown card" character instead of turning the exit mushy.
            let springParams = UISpringTimingParameters(
                mass: 0.96,
                stiffness: 132 + (24 * gestureVelocityProgress),
                damping: 18.6 + (2.0 * gestureVelocityProgress),
                initialVelocity: CGVector(dx: normVx, dy: 0)
            )

            let velocityFactor: CGFloat = min(abs(exitVelocityX) / 1800, 1)
            let exitAngleBoost: CGFloat = (1.0 + (1.35 * velocityFactor)) * (.pi / 180.0)
            let maxExitAngle: CGFloat = 5.0 * (.pi / 180.0)
            let carriedTiltMagnitude = max(abs(currentAngle), abs(releaseTiltAngle) * 0.9)
            let carriedTilt = directionSign * carriedTiltMagnitude
            let unclampedExitAngle = carriedTilt + (directionSign * exitAngleBoost)
            let exitAngle = min(max(unclampedExitAngle, -maxExitAngle), maxExitAngle)

            let animator = UIViewPropertyAnimator(duration: 0.38, timingParameters: springParams)
            animator.addAnimations { [weak self] in
                guard let self else { return }
                card.transform = self.cardTransform(angle: exitAngle, scale: exitScale)
                card.center = CGPoint(x: exitX, y: self.homeCenter.y)
            }
            animator.addCompletion { [weak self, weak fixed = fixed] _ in
                self?.activeAnimator = nil
                self?.isExiting = false
                fixed?.isDragging = false
            }
            activeAnimator = animator
            animator.startAnimation()

            // Give the exit animation a short visual lead before advancing the
            // deck. This preserves the swipe feeling while still keeping the next
            // card responsive. Faster throws get a shorter delay because the card
            // clears the screen sooner.
            pendingSwipeCommitTask?.cancel()
            pendingSwipeDirection = direction
            let normalizedVelocity: CGFloat = min(abs(exitVelocityX) / 2200, 1)
            exitRevealMargin = -(10 + (6 * normalizedVelocity))
            fixed?.isUserInteractionEnabled = false
            card.isUserInteractionEnabled = false
            startExitHandoffObservation(card: card, direction: direction)
            let handoffDelay = max(
                0.16,
                0.22 + (0.04 * (1 - displacementProgress)) - (0.04 * normalizedVelocity)
            )
            pendingSwipeCommitTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(handoffDelay))
                guard !Task.isCancelled else { return }
                self?.triggerPendingSwipeCommit()
            }
        }

        private func resolvedExitWidth(for card: UIView) -> CGFloat {
            if let windowWidth = card.window?.bounds.width, windowWidth > 0 {
                return windowWidth
            }
            if let containerWidth = fixed?.bounds.width, containerWidth > 0 {
                return containerWidth
            }
            return max(card.bounds.width, 1)
        }

        // MARK: Gesture debug

        private func publishTouchDebug(
            event: String,
            recognizer: String,
            decision: String,
            reason: String,
            touch: UITouch? = nil,
            gestureRecognizer: UIGestureRecognizer? = nil
        ) {
            let touchedView = touch?.view
            let webView = touchedView.flatMap(nearestHostedWebView(from:)) ?? cardPanInitialWebView
            let locationInWebView = webView.map { webView in
                if let touch {
                    return touch.location(in: webView)
                }
                if let gestureRecognizer {
                    return gestureRecognizer.location(in: webView)
                }
                return cardPanInitialLocationInWebView ?? .zero
            }
            let region = webView.flatMap { webView -> ScrollableMathInteractionRegion? in
                guard let locationInWebView else { return nil }
                return webView.quizflashScrollableMathInteractionRegions.first { region in
                    region.rect
                        .insetBy(dx: -UIConstants.Spacing.small, dy: -UIConstants.Spacing.small)
                        .contains(locationInWebView)
                }
            }
            let pan = gestureRecognizer as? UIPanGestureRecognizer
            let referenceView = gestureRecognizer?.view

            SwipeTouchDebugStore.latest = SwipeTouchDebugSnapshot(
                timestamp: Date(),
                event: event,
                recognizer: recognizer,
                decision: decision,
                reason: reason,
                touchedViewClass: touchedView.map { NSStringFromClass(type(of: $0)) } ?? "nil",
                locationInWebView: locationInWebView,
                translation: pan?.translation(in: referenceView) ?? .zero,
                velocity: pan?.velocity(in: referenceView) ?? .zero,
                webRegionCount: webView?.quizflashScrollableMathInteractionRegions.count ?? 0,
                webRegionCanScrollLeft: region?.canScrollLeft ?? false,
                webRegionCanScrollRight: region?.canScrollRight ?? false
            )
        }

        private func recognizerName(_ gestureRecognizer: UIGestureRecognizer) -> String {
            if gestureRecognizer === cardTapGesture { return "cardTap" }
            if gestureRecognizer === cardPanGesture { return "cardPan" }
            return String(describing: type(of: gestureRecognizer))
        }

        // MARK: WebView gesture helpers

        private func shouldEdgeHandoffScrollViewHandlePan(_ pan: UIPanGestureRecognizer) -> Bool {
            guard let scrollView = cardPanInitialEdgeHandoffScrollView else { return false }

            let translation = pan.translation(in: pan.view)
            let velocity = pan.velocity(in: pan.view)
            let direction = abs(translation.x) > 0 ? translation.x : velocity.x
            guard direction != 0 else { return false }

            return scrollView.quizflashCanScrollHorizontally(fingerDirection: direction)
        }

        private func shouldMathWebViewHandlePan(_ pan: UIPanGestureRecognizer) -> Bool {
            guard let webView = cardPanInitialWebView,
                  let location = cardPanInitialLocationInWebView else {
                return false
            }

            let region = webView.quizflashScrollableMathInteractionRegions.first { region in
                region.rect
                    .insetBy(dx: -UIConstants.Spacing.small, dy: -UIConstants.Spacing.small)
                    .contains(location)
            }
            guard let region else { return false }

            let translation = pan.translation(in: pan.view)
            let velocity = pan.velocity(in: pan.view)
            let direction = abs(translation.x) > 0 ? translation.x : velocity.x
            guard direction != 0 else { return false }

            return direction > 0 ? region.canScrollLeft : region.canScrollRight
        }

        private func nearestEdgeHandoffScrollView(from view: UIView) -> UIScrollView? {
            var currentView: UIView? = view
            while let view = currentView {
                if view === draggable { return nil }
                if let scrollView = view as? UIScrollView,
                   scrollView.quizflashAllowsCardSwipeEdgeHandoff {
                    return scrollView
                }
                currentView = view.superview
            }
            return nil
        }

        private func isHostedScrollViewGesture(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            var currentView = gestureRecognizer.view
            while let view = currentView {
                if view === draggable { return false }
                if view is UIScrollView { return true }
                currentView = view.superview
            }
            return false
        }

        private func isHorizontalCardSwipeIntent(
            _ pan: UIPanGestureRecognizer,
            in view: UIView?
        ) -> Bool {
            guard let view else { return false }
            let velocity = pan.velocity(in: view)
            let translation = pan.translation(in: view)
            let horizontalSignal = abs(velocity.x) > 1 ? abs(velocity.x) : abs(translation.x)
            let verticalSignal = max(abs(velocity.y), abs(translation.y))
            return horizontalSignal > verticalSignal * 1.5
        }

        private func lockHostedScrollViewsForHorizontalSwipe() {
            guard hostedScrollLocks.isEmpty, let draggable else { return }

            let scrollViews = hostedScrollViews(in: draggable)
            hostedScrollLocks = scrollViews.map { scrollView in
                HostedScrollLock(
                    scrollView: scrollView,
                    wasScrollEnabled: scrollView.isScrollEnabled,
                    contentOffset: scrollView.contentOffset
                )
            }

            for lock in hostedScrollLocks {
                guard let scrollView = lock.scrollView else { continue }
                scrollView.setContentOffset(lock.contentOffset, animated: false)
                scrollView.isScrollEnabled = false
            }
        }

        private func restoreHostedScrollViewsAfterSwipe() {
            guard !hostedScrollLocks.isEmpty else { return }
            for lock in hostedScrollLocks {
                guard let scrollView = lock.scrollView else { continue }
                scrollView.isScrollEnabled = lock.wasScrollEnabled
            }
            hostedScrollLocks.removeAll()
        }

        private func nearestHostedWebView(from view: UIView) -> WKWebView? {
            var currentView: UIView? = view
            while let current = currentView {
                if let webView = current as? WKWebView { return webView }
                currentView = current.superview
            }
            return nil
        }

        private func hostedScrollViews(in root: UIView) -> [UIScrollView] {
            var result: [UIScrollView] = []
            collectHostedScrollViews(in: root, result: &result)
            return result
        }

        private func collectHostedScrollViews(
            in view: UIView,
            result: inout [UIScrollView]
        ) {
            if let scrollView = view as? UIScrollView {
                result.append(scrollView)
            }
            for subview in view.subviews {
                collectHostedScrollViews(in: subview, result: &result)
            }
        }

        private func currentPresentationCenter(for card: UIView) -> CGPoint {
            guard let presentation = card.layer.presentation() else { return card.center }
            return CGPoint(x: presentation.frame.midX, y: presentation.frame.midY)
        }

        private func currentPresentationTransform(for card: UIView) -> CGAffineTransform {
            card.layer.presentation()?.affineTransform() ?? card.transform
        }

        private func rotationAngle(for transform: CGAffineTransform) -> CGFloat {
            atan2(transform.b, transform.a)
        }

        private func uniformScale(for transform: CGAffineTransform) -> CGFloat {
            sqrt((transform.a * transform.a) + (transform.b * transform.b))
        }

        private func cardTransform(angle: CGFloat, scale: CGFloat) -> CGAffineTransform {
            CGAffineTransform(rotationAngle: angle).scaledBy(x: scale, y: scale)
        }

        private func dragProgress(for displacementX: CGFloat) -> CGFloat {
            let normalizedProgress = min(abs(displacementX) / resolvedDismissDistanceThreshold, 1)
            return pow(normalizedProgress, 1.85)
        }

        private func tiltTargetAngle(for displacementX: CGFloat) -> CGFloat {
            let direction: CGFloat = displacementX >= 0 ? 1 : -1
            let progress = usesDirectTiltTracking
                ? min(abs(displacementX) / resolvedDismissDistanceThreshold, 1)
                : dragProgress(for: displacementX)
            return direction * progress * maximumTiltAngle
        }

        private func targetDragScale(for displacementX: CGFloat) -> CGFloat {
            1.0 - (0.10 * dragProgress(for: displacementX))
        }

        private func emitSwipeProgressSnapshot(
            displacementX: CGFloat,
            velocityX: CGFloat,
            phase: SwipeProgressPhase,
            committedDirection: SwipeDirection?,
            tiltAngleDegrees: CGFloat
        ) {
            onSwipeProgress?(
                makeSwipeProgressSnapshot(
                    displacementX: displacementX,
                    velocityX: velocityX,
                    phase: phase,
                    committedDirection: committedDirection,
                    tiltAngleDegrees: tiltAngleDegrees
                )
            )
        }

        private func makeSwipeProgressSnapshot(
            displacementX: CGFloat,
            velocityX: CGFloat,
            phase: SwipeProgressPhase,
            committedDirection: SwipeDirection?,
            tiltAngleDegrees: CGFloat
        ) -> SwipeProgressSnapshot {
            let evaluation = swipeGestureEvaluator.evaluate(
                displacementX: displacementX,
                velocityX: velocityX
            )

            return SwipeProgressSnapshot(
                phase: phase,
                direction: evaluation.trackingDirection,
                projectedCommitDirection: evaluation.projectedCommitDirection,
                committedDirection: committedDirection,
                displacementX: displacementX,
                distanceProgress: evaluation.distanceProgress,
                motionCurveProgress: evaluation.motionCurveProgress,
                velocityX: velocityX,
                velocityProgress: evaluation.velocityProgress,
                projectedProgress: evaluation.projectedProgress,
                commitIntentProgress: evaluation.commitIntentProgress,
                fastSwipeDetected: evaluation.fastSwipeDetected,
                tiltAngleDegrees: tiltAngleDegrees
            )
        }

        private var resolvedDismissDistanceThreshold: CGFloat {
            min(max(gestureTuning.dismissDistanceThreshold, 72), 180)
        }

        private var usesDirectTiltTracking: Bool {
            gestureTuning.usesDirectTiltTracking
        }

        private var resolvedDismissMotionStyle: SwipeDismissMotionStyle {
            gestureTuning.dismissMotionStyle
        }

        private var resolvedDismissAnimationDuration: CGFloat {
            0.34 / min(max(gestureTuning.dismissAnimationSpeed, 0.4), 2.2)
        }

        private var maximumTiltAngle: CGFloat {
            5.0 * .pi / 180.0
        }

        private var swipeGestureEvaluator: SwipeGestureEvaluator {
            SwipeGestureEvaluator(tuning: gestureTuning)
        }
    }
}
