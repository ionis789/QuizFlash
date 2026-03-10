//
//  SwipeableCard.swift
//  QuizFlash
//
//  UIKit-backed swipeable card container targeting 60–120 fps on ProMotion displays.
//
//  ## Architecture
//  - Gesture writes `pendingDX` (a plain `CGFloat` — zero overhead).
//  - A `CADisplayLink` commits exactly one `CATransaction` per display frame,
//    keeping the main thread clear of layout work between frames.
//  - `shouldRasterize` flattens the SwiftUI sub-layer tree to a single GPU
//    texture during drag, then is disabled after the gesture ends so the
//    3D flip animation in `FlipCard` renders correctly.
//  - An `_FPSBadge` overlay (pure `UIView`/`CADisplayLink`) shows live FPS
//    without touching any SwiftUI state and therefore never triggers re-renders.
//
//  ## Known Issues Resolved
//
//  **ISSUE 1 — Teleport at gesture start:**
//    `card.layer.removeAllAnimations()` snaps the MODEL layer to its final
//    value. If done outside a disabled-actions `CATransaction`, Core Animation
//    wraps the subsequent `card.center = visualCenter` in an implicit 0.25s
//    animation → visible jump on screen.
//    Fix: entire `.began` setup is one atomic `CATransaction` with
//    `setDisableActions(true)`.
//
//  **ISSUE 2 — Vertical swipe causes card glitches:**
//    Axis lock was checked in `.changed` AFTER the gesture was already recognised.
//    Fix: override `gestureRecognizerShouldBegin`. If the initial velocity is
//    primarily vertical, return `false` — the gesture is rejected before
//    `.began` fires. The card never moves for vertical swipes.
//
//  **ISSUE 3 — Y-axis card movement:**
//    `dy * 0.10` was applied to `card.center.y`, causing visible vertical drift
//    on diagonal swipes.
//    Fix: card moves on X axis ONLY. Y is always `restCenter.y`.
//
//  **ISSUE 4 — `layoutSubviews` resetting card mid-drag:**
//    If any parent layout invalidation fired during drag, `layoutSubviews` would
//    reset `card.frame = bounds` even with the `isDragging` guard, because the
//    guard was set after the presentation-layer read. Race condition.
//    Fix: `isDragging` is set on the container as the FIRST operation in `.began`,
//    inside the same `CATransaction` that performs all the setup.
//

import SwiftUI
import UIKit

// MARK: - SwipeDirection

/// The horizontal direction in which the user swiped a card.
enum SwipeDirection { case left, right }

// MARK: - SwipeableCard

/// A SwiftUI wrapper around a UIKit-backed pan gesture layer.
///
/// Hosts arbitrary SwiftUI content inside a draggable `UIView` driven by
/// `CADisplayLink` at up to 120 fps. A `CADisplayLink` commits exactly one
/// `CATransaction` per display refresh, ensuring smooth drag without blocking
/// the main thread between frames.
///
/// - Parameters:
///   - onSwipe: Closure invoked when the user completes a decisive horizontal swipe.
///   - onTap: Optional closure invoked on a single tap (used to flip the card).
///   - content: The SwiftUI content to display inside the swipeable container.
struct SwipeableCard<Content: View>: View {
    let onSwipe: (SwipeDirection) -> Void
    let onTap:   (() -> Void)?
    @ViewBuilder let content: () -> Content

    var body: some View {
        _SwipeHost(onSwipe: onSwipe, onTap: onTap, content: content)
    }
}

// MARK: - FPS Badge

/// A lightweight FPS counter overlay rendered by a pure `UIView` + `CADisplayLink`.
///
/// Uses no SwiftUI state (`@Published`, `@StateObject`, etc.) so it is
/// completely invisible to SwiftUI's diffing engine and never triggers
/// `updateUIView` on the parent representable.
private struct _FPSBadge: UIViewRepresentable {
    func makeUIView(context: Context) -> _FPSBadgeView { _FPSBadgeView() }
    func updateUIView(_ uiView: _FPSBadgeView, context: Context) {}
}

private final class _FPSBadgeView: UIView {
    private let label = UILabel()
    private var link:  CADisplayLink?
    private var count: Int = 0
    private var last:  CFTimeInterval = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius  = 10
        layer.masksToBounds = true
        backgroundColor     = UIColor.systemGreen.withAlphaComponent(0.85)
        label.font          = .monospacedDigitSystemFont(ofSize: 13, weight: .bold)
        label.textColor     = .white
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
            label.text  = "\(fps) fps"
            backgroundColor = fps >= 100
                ? UIColor.systemGreen.withAlphaComponent(0.85)
                : UIColor.systemOrange.withAlphaComponent(0.85)
            count = 0; last = l.timestamp
        }
    }
}

// MARK: - UIViewRepresentable

/// The `UIViewRepresentable` bridge that creates and manages the UIKit view hierarchy
/// for `SwipeableCard`.
///
/// Delegates all gesture handling to `Coordinator` and guards against
/// SwiftUI re-renders invalidating the `shouldRasterize` texture cache
/// during an active drag.
private struct _SwipeHost<Content: View>: UIViewRepresentable {
    let onSwipe: (SwipeDirection) -> Void
    let onTap:   (() -> Void)?
    let content: () -> Content

    func makeCoordinator() -> Coordinator { Coordinator(onSwipe: onSwipe, onTap: onTap) }

    func makeUIView(context: Context) -> _FixedContainer {
        let fixed = _FixedContainer()

        // glowView: empty UIView whose only job is to cast a colored shadow.
        // shadowPath is set explicitly in layoutSubviews — CA uses the path
        // directly, no alpha-channel analysis on empty content needed.
        let glow = UIView()
        glow.backgroundColor     = .clear
        glow.clipsToBounds       = false
        glow.layer.masksToBounds = false
        glow.layer.shadowOffset  = CGSize(width: 0, height: 4)
        glow.layer.shadowRadius  = 14
        glow.layer.shadowOpacity = 0
        glow.layer.shadowColor   = UIColor.black.cgColor
        fixed.addSubview(glow)
        fixed.glowView = glow

        let draggable = UIView()
        draggable.backgroundColor = .clear
        draggable.clipsToBounds   = false
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

        context.coordinator.setup(fixed: fixed, draggable: draggable, glow: glow, host: host)

        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        pan.maximumNumberOfTouches = 1
        pan.delegate               = context.coordinator
        draggable.addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap)
        )
        tap.require(toFail: pan)
        draggable.addGestureRecognizer(tap)

        return fixed
    }

    // Never push a SwiftUI content update to the host during an active drag.
    // Any rootView reassignment invalidates the `shouldRasterize` texture cache,
    // causing a visible pop the next time the card is rasterised mid-flight.
    func updateUIView(_ uiView: _FixedContainer, context: Context) {
        guard !context.coordinator.isDragging else { return }
        context.coordinator.host?.rootView = content()
    }
}

// MARK: - Fixed Container

/// The fixed-size `UIView` that anchors the card hierarchy.
///
/// Owns two sub-views: `draggableCard` (the visible card content) and
/// `glowView` (an empty view behind the card that casts a directional
/// coloured shadow indicating swipe direction without any rasterisation cost).
///
/// Overrides `hitTest` to forward touches to `draggableCard` even when it has
/// moved outside the container bounds during a drag.
final class _FixedContainer: UIView {
    weak var draggableCard: UIView?
    weak var glowView:      UIView?
    var isDragging: Bool = false

    override var clipsToBounds: Bool { get { false } set {} }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Never reset card position during drag — would fight the pan gesture.
        guard !isDragging else { return }

        if let card = draggableCard {
            card.frame = bounds
        }
        if let glow = glowView {
            glow.frame = bounds
            // Explicit shadowPath so CA has a defined shape on an empty view.
            glow.layer.shadowPath = UIBezierPath(
                roundedRect: bounds,
                cornerRadius: 24
            ).cgPath
        }
    }

    // Forward touches to draggableCard even when it has moved outside bounds.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01 else { return nil }
        if let card = draggableCard {
            let p = convert(point, to: card)
            if let hit = card.hitTest(p, with: event) { return hit }
        }
        return super.hitTest(point, with: event)
    }
}

// MARK: - Coordinator

extension _SwipeHost {

    /// Manages the pan and tap gesture recognisers, the `CADisplayLink` render loop,
    /// and the card exit/snap-back animations for a single `_SwipeHost` instance.
    ///
    /// ## Rendering Pipeline
    /// 1. `handlePan(_:)` writes `pendingDX` (a plain `CGFloat` — no lock needed
    ///    because all writes happen on the main thread).
    /// 2. `renderFrame(_:)` fires once per display refresh and commits the transform,
    ///    center, and glow shadow in one `CATransaction` with actions disabled,
    ///    keeping the main thread clear between frames.
    ///
    /// ## Gesture Filtering
    /// `gestureRecognizerShouldBegin` rejects gestures whose initial velocity is
    /// primarily vertical (|vy| > |vx| / 1.5), preventing the card from moving
    /// or glitching on accidental vertical touches.
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {

        let onSwipe: (SwipeDirection) -> Void
        let onTap:   (() -> Void)?

        weak var fixed:     _FixedContainer?
        weak var draggable: UIView?
        weak var glowView:  UIView?
        var  host:          UIHostingController<Content>?

        private(set) var isDragging: Bool = false

        // Gesture writes here. DisplayLink reads once per frame.
        private var pendingDX: CGFloat = 0
        private var isGestureActive: Bool = false
        private var displayLink: CADisplayLink?

        private var restCenter:  CGPoint = .zero
        private var hapticFired: Bool    = false
        private let haptic       = UIImpactFeedbackGenerator(style: .medium)
        private let threshold:   CGFloat = 120

        init(onSwipe: @escaping (SwipeDirection) -> Void, onTap: (() -> Void)?) {
            self.onSwipe = onSwipe
            self.onTap   = onTap
        }

        func setup(
            fixed: _FixedContainer,
            draggable: UIView,
            glow: UIView,
            host: UIHostingController<Content>
        ) {
            self.fixed     = fixed
            self.draggable = draggable
            self.glowView  = glow
            self.host      = host
        }

        @objc func handleTap() { onTap?() }

        // MARK: - gestureRecognizerShouldBegin
        //
        // Axis-lock filter: reject the gesture before it starts when the initial
        // finger direction is primarily vertical. This prevents `.began` from
        // ever firing for vertical swipes — the card never moves or glitches.
        // Performing the check here (before `.began`) is the only correct approach;
        // filtering in `.changed` is always too late.

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let view = pan.view else { return true }
            let v = pan.velocity(in: view)
            // Require horizontal velocity to be at least 1.5× the vertical.
            // This threshold catches accidental diagonal starts without making
            // intentional horizontal swipes harder to trigger.
            guard v != .zero else { return true }
            return abs(v.x) > abs(v.y) * 1.5
        }

        func gestureRecognizer(
            _ g: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { false }

        // MARK: - Pan

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let card = draggable, let container = fixed else { return }

            switch gesture.state {

            case .began:
                // Set isDragging FIRST, then perform all setup inside ONE
                // CATransaction with actions disabled. This guarantees:
                //   a) layoutSubviews cannot reset card.frame (isDragging = true)
                //   b) the center assignment from the presentation layer is
                //      non-animated (no implicit CA transaction wrapping it)
                isDragging           = true
                container.isDragging = true
                isGestureActive      = true
                haptic.prepare()

                CATransaction.begin()
                CATransaction.setDisableActions(true)

                // Read VISUAL position (presentation layer) in case a
                // snap-back animation is still in flight.
                let visual = card.layer.presentation()
                    .map { CGPoint(x: $0.frame.midX, y: $0.frame.midY) }
                    ?? card.center

                // Cancel all in-flight animations, then immediately write
                // the visual position back — all inside the same disabled
                // transaction so there is zero implicit animation.
                card.layer.removeAllAnimations()
                glowView?.layer.removeAllAnimations()
                card.center  = visual
                restCenter   = visual

                // Mirror glowView to card position
                if let glow = glowView {
                    glow.layer.removeAllAnimations()
                    glow.center = visual
                }

                // Flatten SwiftUI layer tree → single GPU texture for drag
                card.layer.rasterizationScale = UIScreen.main.scale
                card.layer.shouldRasterize    = true

                CATransaction.commit()

                pendingDX = 0
                startDisplayLink()

            case .changed:
                // Gesture was already approved as horizontal by shouldBegin.
                // Just write dx — no further axis checking needed.
                let dx = gesture.translation(in: container).x
                pendingDX = dx

                if abs(dx) > 8 && abs(dx) < 28 { haptic.prepare() }

                if abs(dx) >= threshold && !hapticFired {
                    haptic.impactOccurred(); hapticFired = true
                } else if abs(dx) < threshold * 0.7 {
                    hapticFired = false
                }

            case .ended, .cancelled:
                hapticFired     = false
                isGestureActive = false
                isDragging      = false
                stopDisplayLink()

                // Re-enable live rendering so card flip works after drag
                card.layer.shouldRasterize = false

                let dx = gesture.translation(in: container).x
                let vx = gesture.velocity(in: container).x

                if dx > threshold || vx > 700 {
                    haptic.impactOccurred(intensity: 1.0)
                    commitExit(.right, velocityX: vx, card: card)
                } else if dx < -threshold || vx < -700 {
                    haptic.impactOccurred(intensity: 1.0)
                    commitExit(.left, velocityX: vx, card: card)
                } else {
                    snapBack(card: card)
                }

            default:
                break
            }
        }

        // MARK: - Display Link

        private func startDisplayLink() {
            guard displayLink == nil else { return }
            let link = CADisplayLink(target: self, selector: #selector(renderFrame))
            if #available(iOS 15, *) {
                link.preferredFrameRateRange = CAFrameRateRange(
                    minimum: 60, maximum: 120, preferred: 120
                )
            }
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        private func stopDisplayLink() {
            displayLink?.invalidate()
            displayLink = nil
        }

        // MARK: - Render Frame

        // Fires exactly once per display refresh via the CADisplayLink.
        // The card moves on the X axis only — card.center.y is always restCenter.y.
        // One CATransaction with disabled actions keeps the commit atomic and overhead-free.

        @objc private func renderFrame(_ link: CADisplayLink) {
            guard isGestureActive,
                  let card = draggable,
                  let glow = glowView else { return }

            let dx    = pendingDX
            let W     = UIScreen.main.bounds.width
            let scale = max(0.88, 1.0 - abs(dx) / W * 0.26)
            let angle = (dx / 20.0) * (.pi / 180.0)

            let newTransform = CGAffineTransform(scaleX: scale, y: scale)
                .concatenating(CGAffineTransform(rotationAngle: angle))

            // X axis only — Y never changes during drag
            let newCenter = CGPoint(x: restCenter.x + dx, y: restCenter.y)

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            card.transform = newTransform
            card.center    = newCenter
            glow.transform = newTransform
            glow.center    = newCenter
            CATransaction.commit()

            // Glow on empty glowView — shadowPath already set, only
            // opacity and color change (no rasterization cost)
            let intensity = Float(min(abs(dx) / threshold, 1.0))
            if dx > 5 {
                glow.layer.shadowColor   = UIColor.systemGreen.cgColor
                glow.layer.shadowOpacity = intensity * 0.90
            } else if dx < -5 {
                glow.layer.shadowColor   = UIColor.systemRed.cgColor
                glow.layer.shadowOpacity = intensity * 0.90
            } else {
                glow.layer.shadowOpacity = 0
            }
        }

        // MARK: - Snap Back

        private func snapBack(card: UIView) {
            fixed?.isDragging = false
            UIView.animate(
                withDuration: 0.46, delay: 0,
                usingSpringWithDamping: 0.68,
                initialSpringVelocity: 0.4,
                options: [.allowUserInteraction, .beginFromCurrentState]
            ) {
                card.transform           = .identity
                card.center              = self.restCenter
                self.glowView?.transform = .identity
                self.glowView?.center    = self.restCenter
                self.glowView?.layer.shadowOpacity = 0
            }
        }

        // MARK: - Exit

        private func commitExit(_ direction: SwipeDirection, velocityX: CGFloat, card: UIView) {
            fixed?.isDragging = false
            let W     = UIScreen.main.bounds.width
            let exitX = direction == .right
                ? restCenter.x + W + 200
                : restCenter.x - W - 200
            let springV = min(abs(velocityX) / W, 1.2)

            UIView.animate(
                withDuration: 0.42, delay: 0,
                usingSpringWithDamping: 0.88,
                initialSpringVelocity: springV,
                options: [.beginFromCurrentState]
            ) {
                card.center                        = CGPoint(x: exitX, y: self.restCenter.y)
                self.glowView?.center              = CGPoint(x: exitX, y: self.restCenter.y)
                self.glowView?.layer.shadowOpacity = 0
            }

            // Fire onSwipe at 0.15 s — the card is already past the screen
            // edge at this point so the next card can begin appearing
            // immediately, without waiting for the full exit spring to settle.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.onSwipe(direction)
            }
        }
    }
}
