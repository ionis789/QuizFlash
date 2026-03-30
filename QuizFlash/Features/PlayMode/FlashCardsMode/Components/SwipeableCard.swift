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
import UIKit
import WebKit
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

// MARK: - FPS Badge

/// Lightweight FPS counter rendered entirely in UIKit.
///
/// Uses no SwiftUI state so it is invisible to SwiftUI's diffing engine
/// and never triggers `updateUIView` on the parent representable.
private struct _FPSBadge: UIViewRepresentable {
    func makeUIView(context: Context) -> _FPSBadgeView { _FPSBadgeView() }
    func updateUIView(_ uiView: _FPSBadgeView, context: Context) {}
}

private final class _FPSBadgeView: UIView {
    private let label = UILabel()
    private var link: CADisplayLink?
    private var count = 0
    private var last: CFTimeInterval = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 10
        layer.masksToBounds = true
        backgroundColor = UIColor.systemGreen.withAlphaComponent(0.85)
        label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .bold)
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        link = CADisplayLink(target: self, selector: #selector(tick))
        link?.add(to: .main, forMode: .common)
    }

    required init?(coder: NSCoder) { fatalError() }
    deinit { link?.invalidate() }

    @objc private func tick(_ l: CADisplayLink) {
        if last == 0 { last = l.timestamp; return }
        count += 1
        let dt = l.timestamp - last
        if dt >= 0.5 {
            let fps = Int(Double(count) / dt)
            label.text = "\(fps) fps"
            backgroundColor = fps >= 100
                ? UIColor.systemGreen.withAlphaComponent(0.85)
                : UIColor.systemOrange.withAlphaComponent(0.85)
            count = 0
            last = l.timestamp
        }
    }
}

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
private struct _SwipeHost<Content: View>: UIViewRepresentable {
    let onSwipe: (SwipeDirection) -> Void
    let onTap: (() -> Void)?
    let isInteractionEnabled: Bool
    let onSwipeProgress: ((SwipeDirection?, CGFloat) -> Void)?
    let content: () -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onSwipe: onSwipe,
            onTap: onTap,
            isInteractionEnabled: isInteractionEnabled,
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
            onSwipeProgress: onSwipeProgress
        )
        guard !context.coordinator.isDragging else { return }
        context.coordinator.host?.rootView = content()
        DispatchQueue.main.async {
            context.coordinator.refreshHostedGestureDependencies()
        }
    }
}

// MARK: - Coordinator

extension _SwipeHost {

    /// Manages gesture recognition, the spring-physics `CADisplayLink` render loop,
    /// and velocity-preserving snap-back / exit animations.
    ///
    /// ## Rendering Pipeline
    /// 1. `handlePan(.changed)` writes `translationX` — the total cumulative
    ///    horizontal offset since gesture start.
    /// 2. `renderFrame` fires every display refresh, reads `translationX`,
    ///    integrates the tilt spring toward the `tanh`-derived target angle,
    ///    and commits position + rotation in one disabled-actions `CATransaction`.
    ///
    /// ## Tilt Spring
    /// The tilt spring (stiffness 220, damping 18, ratio ≈ 0.61) is slightly
    /// underdamped. This produces a short, pleasing overshoot when the user
    /// rapidly reverses drag direction — the card "whips" slightly, reading
    /// as physical mass rather than a UI widget.
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
        var onSwipeProgress: ((SwipeDirection?, CGFloat) -> Void)?
        private var isInteractionEnabled: Bool

        weak var fixed: _FixedContainer?
        weak var draggable: UIView?
        var host: UIHostingController<Content>?
        weak var cardPanGesture: UIPanGestureRecognizer?
        weak var cardTapGesture: UITapGestureRecognizer?

        private(set) var isDragging = false

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
        private var pendingSwipeCommit: DispatchWorkItem?
        private var pendingSwipeDirection: SwipeDirection?
        private var exitHandoffLink: CADisplayLink?
        private weak var exitObservedCard: UIView?
        private var exitObservedDirection: SwipeDirection?
        private var exitRevealMargin: CGFloat = 26
        private var entranceUnlockWorkItem: DispatchWorkItem?
        private var gestureStartScale: CGFloat = 1
        private var hapticFired = false
        private let haptic = UIImpactFeedbackGenerator(style: .medium)

        /// Displacement threshold (points) at which a release commits to an exit.
        private let threshold: CGFloat = 120

        private var requiredHostedPanGestureIDs: Set<ObjectIdentifier> = []

        // MARK: Init

        init(
            onSwipe: @escaping (SwipeDirection) -> Void,
            onTap: (() -> Void)?,
            isInteractionEnabled: Bool,
            onSwipeProgress: ((SwipeDirection?, CGFloat) -> Void)?
        ) {
            self.onSwipe = onSwipe
            self.onTap = onTap
            self.isInteractionEnabled = isInteractionEnabled
            self.onSwipeProgress = onSwipeProgress
        }

        deinit {
            activeAnimator?.stopAnimation(true)
            pendingSwipeCommit?.cancel()
            entranceUnlockWorkItem?.cancel()
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
            entranceUnlockWorkItem?.cancel()
            entranceUnlockWorkItem = nil
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

            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.entranceUnlockWorkItem = nil
                self.syncInteractionEnabled()
            }
            entranceUnlockWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
        }

        func updateCallbacks(
            onSwipe: @escaping (SwipeDirection) -> Void,
            onTap: (() -> Void)?,
            isInteractionEnabled: Bool,
            onSwipeProgress: ((SwipeDirection?, CGFloat) -> Void)?
        ) {
            self.onSwipe = onSwipe
            self.onTap = onTap
            self.isInteractionEnabled = isInteractionEnabled
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

        // MARK: Gesture dependency refresh

        func refreshHostedGestureDependencies() {
            guard let pan = cardPanGesture, let draggable else { return }
            for hostedPan in hostedWebViewPanGestures(in: draggable) {
                let id = ObjectIdentifier(hostedPan)
                guard !requiredHostedPanGestureIDs.contains(id) else { continue }
                pan.require(toFail: hostedPan)
                requiredHostedPanGestureIDs.insert(id)
            }
        }

        // MARK: Tap

        @objc func handleTap() { onTap?() }

        // MARK: Gesture recogniser delegate

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard isInteractionEnabled else { return false }
            guard !isExiting else { return false }
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let view = pan.view else { return true }
            let v = pan.velocity(in: view)
            guard v != .zero else { return true }
            // Reject gestures whose initial velocity is predominantly vertical.
            // This lets the card ignore scroll attempts completely — the `.began`
            // phase never fires for vertical gestures, so the card never moves.
            return abs(v.x) > abs(v.y) * 1.5
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            guard isInteractionEnabled else { return false }
            if gestureRecognizer === cardPanGesture {
                return !isTouchInsideScrollableHostedWebView(touch.view)
            }
            if gestureRecognizer === cardTapGesture {
                return !isTouchInsideHostedWebView(touch.view)
            }
            return true
        }

        func gestureRecognizer(
            _ g: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { false }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            guard gestureRecognizer is UIPanGestureRecognizer else { return false }
            return isHostedWebViewGesture(otherGestureRecognizer)
        }

        // MARK: Pan handler

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let card = draggable, let container = fixed else { return }

            switch gesture.state {
            case .began:
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
                pendingSwipeCommit?.cancel()
                pendingSwipeCommit = nil
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
                onSwipeProgress?(nil, 0)
                startDisplayLink()

            case .changed:
                translationX = gesture.translation(in: container).x

                let absDx = abs(translationX)
                if absDx > 8 && absDx < 28 { haptic.prepare() }
                if absDx >= threshold && !hapticFired {
                    haptic.impactOccurred()
                    hapticFired = true
                } else if absDx < threshold * 0.7 {
                    hapticFired = false
                }

            case .ended, .cancelled:
                hapticFired = false
                isGestureActive = false
                isDragging = false
                stopDisplayLink()

                let dx = gesture.translation(in: container).x
                let vx = gesture.velocity(in: container).x

                if dx > threshold || vx > 700 {
                    haptic.impactOccurred(intensity: 1.0)
                    commitExit(.right, velocityX: vx, card: card)
                } else if dx < -threshold || vx < -700 {
                    haptic.impactOccurred(intensity: 1.0)
                    commitExit(.left, velocityX: vx, card: card)
                } else {
                    snapBack(card: card, velocityX: vx)
                }

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
                pendingSwipeCommit?.cancel()
                pendingSwipeCommit = nil
                stopExitHandoffObservation()
                return
            }

            pendingSwipeCommit?.cancel()
            pendingSwipeCommit = nil
            pendingSwipeDirection = nil
            stopExitHandoffObservation()
            onSwipe(direction)
        }

        /// Integrates the tilt spring and commits position + rotation in one
        /// disabled-actions `CATransaction` every display frame.
        ///
        /// ## Tilt target
        /// `pow(min(|translationX| / threshold, 1), 1.85) × 15°` ties the tilt
        /// directly to swipe progress:
        ///
        /// | translationX | target tilt |
        /// |---|---|
        /// | ±20 px  | ±0.6° |
        /// | ±60 px  | ±4.2° |
        /// | ±90 px  | ±10.0° |
        /// | ±120 px | ±15.0° |
        /// | ±∞      | ±15.0° |
        ///
        /// The tilt now stays calm early in the drag, then ramps up more
        /// aggressively as the card approaches the exit threshold.
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

            // Compute target tilt from swipe progress so the card stays flatter
            // early in the drag and reaches full tilt near exit commitment.
            let targetTilt = tiltTargetAngle(for: dx)
            let dragScale = min(targetDragScale(for: dx), gestureStartScale)

            // Spring-integrate current tilt toward target (Euler method).
            let force = tiltStiffness * (targetTilt - currentTilt) - tiltDamping * tiltVelocity
            tiltVelocity += force * dt
            currentTilt  += tiltVelocity * dt

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

            // Report progress for border feedback.
            let intensity = min(abs(dx) / threshold, 1.0)
            if dx > 5 {
                onSwipeProgress?(.right, intensity)
            } else if dx < -5 {
                onSwipeProgress?(.left, intensity)
            } else {
                onSwipeProgress?(nil, 0)
            }
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
                self?.onSwipeProgress?(nil, 0)
            }
            animator.addCompletion { [weak self, weak fixed = fixed] _ in
                self?.activeAnimator = nil
                fixed?.isDragging = false
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

            let width = max(fixed?.bounds.width ?? UIScreen.main.bounds.width, 1)
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
            let displacementProgress = min(releaseDisplacement / threshold, 1)
            let projectedReleaseDisplacementX = currentDisplacementX + releaseVelocityLead(for: velocityX)
            let releaseTiltAngle = tiltTargetAngle(for: projectedReleaseDisplacementX)
            let currentScale = min(max(uniformScale(for: currentPresentationTransform(for: card)), 0.9), 1.0)
            let exitScale = min(currentScale, targetDragScale(for: projectedReleaseDisplacementX))

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
                mass: 1.0,
                stiffness: 108 + (18 * gestureVelocityProgress),
                damping: 16.8 + (1.4 * gestureVelocityProgress),
                initialVelocity: CGVector(dx: normVx, dy: 0)
            )

            let directionSign: CGFloat = direction == .right ? 1 : -1
            let velocityFactor: CGFloat = min(abs(exitVelocityX) / 1800, 1)
            let exitAngleBoost: CGFloat = (1.0 + (1.35 * velocityFactor)) * (.pi / 180.0)
            let maxExitAngle: CGFloat = 5.0 * (.pi / 180.0)
            let carriedTiltMagnitude = max(abs(currentAngle), abs(releaseTiltAngle) * 0.9)
            let carriedTilt = directionSign * carriedTiltMagnitude
            let unclampedExitAngle = carriedTilt + (directionSign * exitAngleBoost)
            let exitAngle = min(max(unclampedExitAngle, -maxExitAngle), maxExitAngle)

            let animator = UIViewPropertyAnimator(duration: 0.5, timingParameters: springParams)
            animator.addAnimations { [weak self] in
                guard let self else { return }
                card.transform = self.cardTransform(angle: exitAngle, scale: exitScale)
                card.center = CGPoint(x: exitX, y: self.homeCenter.y)
                self.onSwipeProgress?(nil, 0)
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
            pendingSwipeCommit?.cancel()
            pendingSwipeDirection = direction
            let normalizedVelocity: CGFloat = min(abs(exitVelocityX) / 2200, 1)
            exitRevealMargin = -(10 + (6 * normalizedVelocity))
            fixed?.isUserInteractionEnabled = false
            card.isUserInteractionEnabled = false
            startExitHandoffObservation(card: card, direction: direction)
            let handoffDelay = max(
                0.20,
                0.28 + (0.05 * (1 - displacementProgress)) - (0.03 * normalizedVelocity)
            )
            let workItem = DispatchWorkItem { [weak self] in
                self?.triggerPendingSwipeCommit()
            }
            pendingSwipeCommit = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + handoffDelay, execute: workItem)
        }

        // MARK: WebView gesture helpers

        private func isHostedWebViewGesture(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            var currentView = gestureRecognizer.view
            while let view = currentView {
                if view is WKWebView { return true }
                if NSStringFromClass(type(of: view)).contains("WK") { return true }
                currentView = view.superview
            }
            return false
        }

        private func isTouchInsideHostedWebView(_ touchedView: UIView?) -> Bool {
            var currentView = touchedView
            while let view = currentView {
                if view is WKWebView { return true }
                if NSStringFromClass(type(of: view)).contains("WK") { return true }
                currentView = view.superview
            }
            return false
        }

        private func isTouchInsideScrollableHostedWebView(_ touchedView: UIView?) -> Bool {
            var currentView = touchedView
            while let view = currentView {
                if let webView = view as? WKWebView {
                    return webView.quizflashHasHorizontalOverflow
                }
                if NSStringFromClass(type(of: view)).contains("WK"),
                   let webView = nearestHostedWebView(from: view) {
                    return webView.quizflashHasHorizontalOverflow
                }
                currentView = view.superview
            }
            return false
        }

        private func nearestHostedWebView(from view: UIView) -> WKWebView? {
            var currentView: UIView? = view
            while let current = currentView {
                if let webView = current as? WKWebView { return webView }
                currentView = current.superview
            }
            return nil
        }

        private func hostedWebViewPanGestures(in root: UIView) -> [UIPanGestureRecognizer] {
            var result: [UIPanGestureRecognizer] = []
            collectHostedWebViewPanGestures(in: root, result: &result)
            return result
        }

        private func collectHostedWebViewPanGestures(
            in view: UIView,
            result: inout [UIPanGestureRecognizer]
        ) {
            if let webView = view as? WKWebView {
                result.append(webView.scrollView.panGestureRecognizer)
            }
            for subview in view.subviews {
                collectHostedWebViewPanGestures(in: subview, result: &result)
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
            let normalizedProgress = min(abs(displacementX) / threshold, 1)
            return pow(normalizedProgress, 1.85)
        }

        private func tiltTargetAngle(for displacementX: CGFloat) -> CGFloat {
            let direction: CGFloat = displacementX >= 0 ? 1 : -1
            return direction * dragProgress(for: displacementX) * (5.0 * .pi / 180.0)
        }

        private func targetDragScale(for displacementX: CGFloat) -> CGFloat {
            1.0 - (0.10 * dragProgress(for: displacementX))
        }

        private func releaseVelocityLead(for velocityX: CGFloat) -> CGFloat {
            let unclampedLead = velocityX * 0.055
            return min(max(unclampedLead, -threshold * 0.9), threshold * 0.9)
        }
    }
}
