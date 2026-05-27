//
//  SwipeBackModifier.swift
//  QuizFlash
//

import SwiftUI
import UIKit

// MARK: - Public API

public enum SwipeBackAttachment {
    case window
    case localHost
}

public extension View {
    /// Adds a fluid, native edge-swipe-back gesture to the view.
    ///
    /// This modifier provides a highly interactive, physics-based edge swipe gesture
    /// (often referred to as a "jelly" or "capsule" swipe). It utilizes a background
    /// `UIPanGestureRecognizer` to ensure absolute priority, silently canceling any
    /// underlying button touches without altering their visual state.
    ///
    /// - Parameters:
    ///   - enabled: Determines if the gesture is active. Defaults to `true`.
    ///   - attachment: Selects whether the recognizer attaches to the app window
    ///     or to the highest local host view. Sheet-hosted surfaces should prefer
    ///     `.localHost` so the gesture stays scoped to that presentation.
    ///   - action: The closure to execute when the swipe gesture successfully commits.
    /// - Returns: A view modified to support the edge swipe gesture.
    func swipeBack(
        enabled: Bool = true,
        attachment: SwipeBackAttachment = .window,
        action: @escaping () -> Void
    ) -> some View {
        modifier(SwipeBackModifier(enabled: enabled, attachment: attachment, action: action))
    }
}

// MARK: - ViewModifier

/// The internal modifier that handles the state, geometry, and rendering of the swipe gesture.
private struct SwipeBackModifier: ViewModifier {

    // MARK: - Properties
    @State private var keyboardMonitor = KeyboardMonitor.shared
    let enabled: Bool
    let attachment: SwipeBackAttachment
    let action: () -> Void

    // MARK: - State
    
    @State private var dragOffset: CGFloat = 0
    @State private var startY: CGFloat = 0
    @State private var isActive: Bool = false
    @State private var edge: Edge = .leading
    @State private var viewSize: CGSize = .zero // Replaced deprecated UIScreen.main
    @State private var isFinishingGesture = false
    @State private var didTriggerThresholdHaptic = false

    // MARK: - Constants

    private let commitThreshold: CGFloat = 110
    private let jellyHeight: CGFloat = 200
    private let fingerVerticalOffset: CGFloat = 75
    private let leadingActivationFraction: CGFloat = 0.7
    private let trailingActivationFraction: CGFloat = 0.3

    // MARK: - Computed Properties
    
    private var progress: CGFloat { min(abs(dragOffset) / commitThreshold, 1.0) }
    private var committed: Bool { progress >= 1.0 }
    private var effectiveEnabled: Bool { enabled && !keyboardMonitor.isVisible }

    // MARK: - Body
    
    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { viewSize = geo.size }
                        .onChange(of: geo.size) { _, newSize in viewSize = newSize }
                }
            )
            .background(
                NativeSwipeBackController(
                    dragOffset: $dragOffset,
                    isActive: $isActive,
                    startY: $startY,
                    edge: $edge,
                    enabled: effectiveEnabled,
                    attachment: attachment,
                    commitThreshold: commitThreshold,
                    leadingActivationFraction: leadingActivationFraction,
                    trailingActivationFraction: trailingActivationFraction,
                    onThresholdReached: handleThresholdReached,
                    onCommit: handleCommit,
                    onCancel: handleCancel
                )
            )
            .overlay(alignment: edge == .leading ? .topLeading : .topTrailing) {
                if isActive {
                    JellyIndicator(
                        edge: edge,
                        dragOffset: dragOffset,
                        committed: committed,
                        height: jellyHeight
                    )
                    .offset(y: startY - (jellyHeight / 2) - fingerVerticalOffset)
                    .animation(.interactiveSpring(response: 0.15, dampingFraction: 0.8), value: dragOffset)
                    .allowsHitTesting(false)
                    .zIndex(999)
                }
            }
    }

    // MARK: - Handlers
    
    private func handleCommit() {
        guard !isFinishingGesture else { return }
        isFinishingGesture = true
        if !didTriggerThresholdHaptic {
            haptic()
        }
        withAnimation(.spring(response: 0.18, dampingFraction: 0.9)) {
            dragOffset = edge == .leading ? viewSize.width : -viewSize.width
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            action()
            resetState()
        }
    }
    
    private func handleCancel() {
        guard !isFinishingGesture else { return }
        isFinishingGesture = true
        withAnimation(.spring(response: 0.22, dampingFraction: 0.65)) {
            dragOffset = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if dragOffset == 0 { resetState() }
        }
    }

    private func handleThresholdReached() {
        guard !didTriggerThresholdHaptic else { return }
        didTriggerThresholdHaptic = true
        haptic()
    }

    private func resetState() {
        isActive = false
        dragOffset = 0
        startY = 0
        isFinishingGesture = false
        didTriggerThresholdHaptic = false
    }

    private func haptic() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred(intensity: 0.82)
    }
}

// MARK: - Native iOS Gesture Integrator

/// A bridge to `UIPanGestureRecognizer` to circumvent SwiftUI gesture conflicts.
private struct NativeSwipeBackController: UIViewRepresentable {
    
    @Binding var dragOffset: CGFloat
    @Binding var isActive: Bool
    @Binding var startY: CGFloat
    @Binding var edge: Edge

    let enabled: Bool
    let attachment: SwipeBackAttachment
    let commitThreshold: CGFloat
    let leadingActivationFraction: CGFloat
    let trailingActivationFraction: CGFloat
    let onThresholdReached: () -> Void
    let onCommit: () -> Void
    let onCancel: () -> Void

    func makeUIView(context: Context) -> ControllerView {
        let view = ControllerView()
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: ControllerView, context: Context) {
        context.coordinator.parent = self
        uiView.coordinator = context.coordinator
        uiView.attachment = attachment
        uiView.refreshGestureAttachmentIfNeeded()
        uiView.panRecognizer?.isEnabled = enabled
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: NativeSwipeBackController
        private var pendingEdge: Edge?

        private let leadingHorizontalDominanceRatio: CGFloat = 1.15
        private let trailingHorizontalDominanceRatio: CGFloat = 0.75

        init(parent: NativeSwipeBackController) {
            self.parent = parent
        }

        @objc func handlePan(_ pan: UIPanGestureRecognizer) {
            guard let view = pan.view else { return }
            let translation = pan.translation(in: view)
            let location = pan.location(in: view)

            switch pan.state {
            case .began:
                guard let pendingEdge else { return }
                parent.edge = pendingEdge
                parent.isActive = true
                parent.startY = location.y

            case .changed:
                if parent.isActive {
                    let raw = translation.x
                    parent.dragOffset = parent.edge == .leading ? max(raw, 0) : min(raw, 0)
                    if abs(parent.dragOffset) >= parent.commitThreshold {
                        parent.onThresholdReached()
                    }
                }

            case .ended, .cancelled, .failed:
                if parent.isActive {
                    let velocity = pan.velocity(in: view).x
                    let isFlick = abs(velocity) > 800 && velocitySupportsCommit(velocity)
                    let commit = abs(parent.dragOffset) >= parent.commitThreshold || isFlick

                    if commit {
                        parent.onCommit()
                    } else {
                        parent.onCancel()
                    }
                }
                pendingEdge = nil
            default: break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard parent.enabled,
                  let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let view = pan.view else { return false }

            let location = pan.location(in: view)
            let viewWidth = max(view.bounds.width, 1)
            let leadingZoneMaxX = viewWidth * parent.leadingActivationFraction
            let trailingZoneMinX = viewWidth * (1 - parent.trailingActivationFraction)
            let velocity = pan.velocity(in: view)

            if location.x <= leadingZoneMaxX {
                guard gestureShowsHorizontalIntent(
                    velocity,
                    minimumRatio: leadingHorizontalDominanceRatio
                ) else {
                    pendingEdge = nil
                    return false
                }
                if velocity != .zero, velocity.x < 0 {
                    pendingEdge = nil
                    return false
                }
                pendingEdge = .leading
                return true
            }

            if location.x >= trailingZoneMinX {
                if UIDevice.current.userInterfaceIdiom == .pad {
                    pendingEdge = nil
                    return false
                }
                guard gestureShowsHorizontalIntent(
                    velocity,
                    minimumRatio: trailingHorizontalDominanceRatio
                ) else {
                    pendingEdge = nil
                    return false
                }
                pendingEdge = .trailing
                return true
            }

            pendingEdge = nil
            return false
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return false
        }

        private func velocitySupportsCommit(_ velocity: CGFloat) -> Bool {
            switch parent.edge {
            case .leading:
                velocity > 0
            case .trailing:
                velocity < 0
            default:
                false
            }
        }

        private func gestureShowsHorizontalIntent(_ velocity: CGPoint, minimumRatio: CGFloat) -> Bool {
            guard velocity != .zero else { return true }
            return abs(velocity.x) > abs(velocity.y) * minimumRatio
        }
    }
}

/// A transparent UIView that attaches a gesture recognizer to its hosting window.
private final class ControllerView: UIView {
    weak var coordinator: NativeSwipeBackController.Coordinator?
    var attachment: SwipeBackAttachment = .window
    private var panGesture: UIPanGestureRecognizer?
    private weak var gestureHostView: UIView?

    var panRecognizer: UIPanGestureRecognizer? { panGesture }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        refreshGestureAttachmentIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        refreshGestureAttachmentIfNeeded()
    }

    func refreshGestureAttachmentIfNeeded() {
        guard let coordinator else { return }
        guard let target = gestureTargetView() else {
            detachGesture()
            return
        }

        if panGesture == nil {
            let pan = UIPanGestureRecognizer(
                target: coordinator,
                action: #selector(NativeSwipeBackController.Coordinator.handlePan(_:))
            )
            pan.delegate = coordinator
            pan.cancelsTouchesInView = true
            pan.maximumNumberOfTouches = 1
            panGesture = pan
        }

        guard let panGesture else { return }
        if gestureHostView !== target {
            detachGesture()
            target.addGestureRecognizer(panGesture)
            gestureHostView = target
        }
    }

    private func gestureTargetView() -> UIView? {
        switch attachment {
        case .window:
            return window
        case .localHost:
            return highestLocalHostView()
        }
    }

    private func highestLocalHostView() -> UIView? {
        var candidate: UIView? = superview
        var highest: UIView?
        while let view = candidate, !(view is UIWindow) {
            highest = view
            candidate = view.superview
        }
        return highest
    }

    private func detachGesture() {
        if let panGesture {
            panGesture.view?.removeGestureRecognizer(panGesture)
        }
        gestureHostView = nil
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        if newWindow == nil {
            detachGesture()
            panGesture = nil
        }
        super.willMove(toWindow: newWindow)
    }
}

// MARK: - Jelly Indicator Views

private struct JellyIndicator: View {
    let edge: Edge
    let dragOffset: CGFloat
    let committed: Bool
    let height: CGFloat

    private var stretch: CGFloat {
        let maxStretch: CGFloat = 55
        let raw = abs(dragOffset)
        return min(raw, 130) * (maxStretch / 130)
    }

    private var smoothOpacity: CGFloat {
        min(abs(dragOffset) / 25.0, 1.0)
    }

    private var smoothScale: CGFloat {
        committed ? 1.15 : 0.7 + min(abs(dragOffset) / 50.0, 1.0) * 0.3
    }

    private var arrowX: CGFloat {
        let padding: CGFloat = 16 + (stretch * 0.25)
        return edge == .leading ? padding : 100 - padding
    }

    var body: some View {
        ZStack {
            JellyEdgeShape(stretch: stretch, edge: edge)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.3), radius: 6, x: edge == .leading ? 2 : -2, y: 0)

            Image(systemName: edge == .leading ? "chevron.left" : "chevron.right")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .scaleEffect(smoothScale)
                .opacity(smoothOpacity)
                .position(x: arrowX, y: height / 2)
        }
        .frame(width: 100, height: height)
    }
}

// MARK: - Custom Bezier Shape

/// A custom shape representing a fluid, organic capsule emerging from the screen edge.
private struct JellyEdgeShape: Shape {
    var stretch: CGFloat
    var edge: Edge

    var animatableData: CGFloat {
        get { stretch }
        set { stretch = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard stretch > 0 else { return path }

        let h = rect.height
        let w = stretch
        let centerY = h / 2

        let tipSpread: CGFloat = h * 0.15
        let baseSpread: CGFloat = h * 0.3

        if edge == .leading {
            path.move(to: CGPoint(x: 0, y: 0))

            path.addCurve(
                to: CGPoint(x: w, y: centerY),
                control1: CGPoint(x: 0, y: baseSpread),
                control2: CGPoint(x: w, y: centerY - tipSpread)
            )

            path.addCurve(
                to: CGPoint(x: 0, y: h),
                control1: CGPoint(x: w, y: centerY + tipSpread),
                control2: CGPoint(x: 0, y: h - baseSpread)
            )
            path.closeSubpath()

        } else {
            let startX = rect.width
            path.move(to: CGPoint(x: startX, y: 0))

            path.addCurve(
                to: CGPoint(x: startX - w, y: centerY),
                control1: CGPoint(x: startX, y: baseSpread),
                control2: CGPoint(x: startX - w, y: centerY - tipSpread)
            )

            path.addCurve(
                to: CGPoint(x: startX, y: h),
                control1: CGPoint(x: startX - w, y: centerY + tipSpread),
                control2: CGPoint(x: startX, y: h - baseSpread)
            )
            path.closeSubpath()
        }
        return path
    }
}
