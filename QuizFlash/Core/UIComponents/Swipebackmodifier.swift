//
//  SwipeBackModifier.swift
//

import SwiftUI
import UIKit

// MARK: - Public API

public extension View {
    /// Adds a fluid, native edge-swipe-back gesture to the view.
    ///
    /// This modifier provides a highly interactive, physics-based edge swipe gesture
    /// (often referred to as a "jelly" or "capsule" swipe). It utilizes a background
    /// `UIPanGestureRecognizer` to ensure absolute priority, silently canceling any
    /// underlying button touches without altering their visual state. It also intelligently
    /// avoids conflicts with iPadOS Slide Over multitasking gestures.
    ///
    /// - Usage:
    ///   Attach this modifier to the top-level view of your screen.
    ///
    /// ```swift
    /// ScrollView {
    ///     // Your content
    /// }
    /// .swipeBack {
    ///     dismiss()
    /// }
    /// ```
    ///
    /// - Parameter enabled: When false the gesture is fully disabled. Defaults to true.
    /// - Parameter action: The closure to execute when the swipe gesture successfully commits.
    /// - Returns: A view that responds to the edge swipe gesture.
    func swipeBack(enabled: Bool = true, action: @escaping () -> Void) -> some View {
        modifier(SwipeBackModifier(enabled: enabled, action: action))
    }
}

// MARK: - ViewModifier

/// The internal modifier that handles the state and rendering of the swipe gesture.
private struct SwipeBackModifier: ViewModifier {

    var enabled: Bool
    let action: () -> Void

    // MARK: Gesture State
    @State private var dragOffset: CGFloat = 0
    @State private var startY: CGFloat = 0
    @State private var isActive: Bool = false
    @State private var edge: Edge = .leading

    @State private var viewSize: CGSize = UIScreen.main.bounds.size

    // MARK: Configuration Constants

    /// The width of the active edge area where the gesture can be initiated.
    private let edgeActivationWidth: CGFloat = 120

    /// The horizontal distance the user must swipe to trigger the action.
    private let commitThreshold: CGFloat = 110

    /// The overall height of the jelly indicator canvas.
    private let jellyHeight: CGFloat = 200

    /// The vertical offset to ensure the indicator is visible above the user's finger.
    private let fingerVerticalOffset: CGFloat = 75

    private var progress: CGFloat { min(abs(dragOffset) / commitThreshold, 1.0) }
    private var committed: Bool { progress >= 1.0 }

    func body(content: Content) -> some View {
        content
        // Read the natural dimensions of the view hierarchy without imposing a frame.
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { viewSize = geo.size }
                    .onChange(of: geo.size) { _, s in viewSize = s }
            }
        )
        // Inject the native UIKit gesture controller into the background.
        .background(
            NativeEdgeSwipeController(
                dragOffset: $dragOffset,
                isActive: $isActive,
                startY: $startY,
                edge: $edge,
                enabled: enabled,
                commitThreshold: commitThreshold,
                edgeActivationWidth: edgeActivationWidth,
                onCommit: {
                    haptic(.success)
                    withAnimation(.spring(response: 0.18, dampingFraction: 0.9)) {
                        dragOffset = edge == .leading ? viewSize.width : -viewSize.width
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        action()
                        reset()
                    }
                },
                onCancel: {
                    haptic(.error)
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.65)) {
                        dragOffset = 0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        if dragOffset == 0 { reset() }
                    }
                }
            )
        )
        // Render the jelly indicator overlay on top of all content.
        .overlay(alignment: edge == .leading ? .topLeading : .topTrailing) {
            if isActive {
                JellyIndicator(
                    edge: edge,
                    dragOffset: dragOffset,
                    committed: committed,
                    height: jellyHeight
                )
                    .offset(y: startY - (jellyHeight / 2) - fingerVerticalOffset)
                    .animation(
                        .interactiveSpring(response: 0.15, dampingFraction: 0.8),
                    value: dragOffset
                )
                    .allowsHitTesting(false)
                    .zIndex(999)
            }
        }
    }

    private func reset() {
        isActive = false
        dragOffset = 0
        startY = 0
    }

    private func haptic(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}

// MARK: - Native iOS Gesture Integrator

/// A bridge to `UIPanGestureRecognizer` to circumvent SwiftUI gesture conflicts
/// and accurately cancel underlying component touches (e.g., buttons).
private struct NativeEdgeSwipeController: UIViewRepresentable {
    @Binding var dragOffset: CGFloat
    @Binding var isActive: Bool
    @Binding var startY: CGFloat
    @Binding var edge: Edge

    var enabled: Bool
    let commitThreshold: CGFloat
    let edgeActivationWidth: CGFloat
    let onCommit: () -> Void
    let onCancel: () -> Void

    func makeUIView(context: Context) -> ControllerView {
        let view = ControllerView()
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: ControllerView, context: Context) {
        uiView.coordinator = context.coordinator
        // Disable the pan recognizer at runtime when the gesture is suppressed.
        uiView.panRecognizer?.isEnabled = enabled
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: NativeEdgeSwipeController
        private var lastHapticBand: Int = 0

        init(parent: NativeEdgeSwipeController) {
            self.parent = parent
        }

        @objc func handlePan(_ pan: UIPanGestureRecognizer) {
            guard let view = pan.view else { return }
            let translation = pan.translation(in: view)
            let location = pan.location(in: view)

            switch pan.state {
            case .began:
                let isLeft = location.x <= parent.edgeActivationWidth
                parent.edge = isLeft ? .leading : .trailing
                parent.isActive = true
                parent.startY = location.y
                lastHapticBand = 0

            case .changed:
                if parent.isActive {
                    let raw = translation.x
                    parent.dragOffset = parent.edge == .leading ? max(raw, 0) : min(raw, 0)

                    let progress = min(abs(parent.dragOffset) / parent.commitThreshold, 1.0)
                    let band = Int(progress * 5)
                    if band > lastHapticBand {
                        lastHapticBand = band
                        let style: UIImpactFeedbackGenerator.FeedbackStyle = band >= 5 ? .heavy : band >= 3 ? .medium : .light
                        UIImpactFeedbackGenerator(style: style).impactOccurred()
                    }
                }

            case .ended, .cancelled, .failed:
                if parent.isActive {
                    let velocity = pan.velocity(in: view).x
                    let isFlick = abs(velocity) > 800
                    let commit = abs(parent.dragOffset) >= parent.commitThreshold || isFlick

                    if commit {
                        parent.onCommit()
                    } else {
                        parent.onCancel()
                    }
                }
            default: break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            // If the modifier has been disabled (e.g. during selection mode),
            // reject the gesture immediately — before any position checks.
            guard parent.enabled else { return false }

            guard let pan = gestureRecognizer as? UIPanGestureRecognizer, let view = pan.view else { return false }

            let loc = pan.location(in: view)
            let width = view.bounds.width

            let isLeft = loc.x <= parent.edgeActivationWidth
            let isRight = loc.x >= width - parent.edgeActivationWidth

            guard isLeft || isRight else { return false }

            // Protect the right edge on iPad to allow native Slide Over multitasking to function.
            let isPad = UIDevice.current.userInterfaceIdiom == .pad
            if isPad && isRight { return false }

            // Only begin if the swipe is predominantly horizontal.
            let velocity = pan.velocity(in: view)
            return abs(velocity.x) > abs(velocity.y)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // Returning false grants this pan gesture exclusive tracking rights,
            // silencing underlying scroll views or button presses.
            return false
        }
    }
}

/// A transparent UIView that automatically locates the nearest appropriate window
/// to attach the gesture recognizer, ensuring it is not constrained by SwiftUI clipping.
private class ControllerView: UIView {
    weak var coordinator: NativeEdgeSwipeController.Coordinator?
    private weak var panGesture: UIPanGestureRecognizer?

    /// Exposed so `NativeEdgeSwipeController.updateUIView` can toggle `isEnabled`.
    var panRecognizer: UIPanGestureRecognizer? { panGesture }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        setupGesture()
    }

    private func setupGesture() {
        guard panGesture == nil, let coordinator = coordinator, let window = self.window else { return }

        let pan = UIPanGestureRecognizer(target: coordinator, action: #selector(NativeEdgeSwipeController.Coordinator.handlePan(_:)))
        pan.delegate = coordinator

        // This property is crucial: it immediately cancels active touches on subviews (like SwiftUI Buttons)
        // without triggering their highlighted/pressed state.
        pan.cancelsTouchesInView = true
        window.addGestureRecognizer(pan)

        self.panGesture = pan
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        if newWindow == nil, let pan = panGesture {
            pan.view?.removeGestureRecognizer(pan)
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
        return min(abs(dragOffset) / 25.0, 1.0)
    }

    private var smoothScale: CGFloat {
        if committed { return 1.15 }
        return 0.7 + min(abs(dragOffset) / 50.0, 1.0) * 0.3
    }

    private var arrowX: CGFloat {
        let padding: CGFloat = 16 + (stretch * 0.25)
        return edge == .leading ? padding : 100 - padding
    }

    var body: some View {
        let canvasWidth: CGFloat = 100

        ZStack {
            JellyEdgeShape(stretch: stretch, edge: edge)
                .fill(.regularMaterial)
                .colorScheme(.dark)
                .shadow(color: .black.opacity(0.3), radius: 6, x: edge == .leading ? 2 : -2, y: 0)

            Image(systemName: edge == .leading ? "chevron.left" : "chevron.right")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .scaleEffect(smoothScale)
                .opacity(smoothOpacity)
                .position(x: arrowX, y: height / 2)
        }
            .frame(width: canvasWidth, height: height)
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
