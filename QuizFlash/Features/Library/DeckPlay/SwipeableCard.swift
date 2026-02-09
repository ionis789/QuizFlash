import SwiftUI

enum SwipeDirection {
    case left, right
}

/// Simple, native swipe card with smooth animations
struct SwipeableCard<Content: View>: View {
    let onSwipe: (SwipeDirection) -> Void
    let onTap: (() -> Void)?
    @ViewBuilder let content: () -> Content

    // Distance threshold for slow, intentional drags.
    private let swipeDistanceThreshold: CGFloat = 72
    // Projected end threshold keeps fast flicks feeling responsive.
    private let swipeProjectedThreshold: CGFloat = 100

    @GestureState private var dragOffset: CGFloat = 0
    @GestureState private var isInThresholdZone: Bool = false

    @State private var exitOffset: CGFloat? = nil

    init(
        onSwipe: @escaping (SwipeDirection) -> Void,
        onTap: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.onSwipe = onSwipe
        self.onTap = onTap
        self.content = content
    }

    private var currentOffset: CGFloat {
        exitOffset ?? dragOffset
    }

    private var rotation: Double {
        min(max(Double(currentOffset / 25), -8), 8)
    }

    private var swipeProgress: CGFloat {
        min(abs(currentOffset) / swipeProjectedThreshold, 1)
    }

    private var glowColor: Color {
        currentOffset >= 0 ? .green : .red
    }

    var body: some View {
        ZStack {
            content()

            // Glow border
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(glowColor.opacity(Double(swipeProgress) * 0.6), lineWidth: 3)
                .shadow(color: glowColor.opacity(Double(swipeProgress) * 0.3), radius: 8)
                .allowsHitTesting(false)

            // Gesture capture layer
            Color.clear
                .contentShape(Rectangle())
                .gesture(swipeGesture)
                .onTapGesture {
                    onTap?()
                }
        }
        .offset(x: currentOffset)
        .rotationEffect(.degrees(rotation))
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: currentOffset)
    }

    private var swipeGesture: some Gesture {
        DragGesture()
            .updating($dragOffset) { value, state, _ in
                // Track the finger with no extra animation-induced lag.
                state = value.translation.width
            }
            .updating($isInThresholdZone) { value, state, transaction in
                let enteredZone = abs(value.translation.width) >= swipeDistanceThreshold

                // One-shot haptic on transition: outside → inside.
                if enteredZone && !state {
                    transaction.animation = nil // keep haptic logic totally decoupled from animations
                    impactHaptic()
                }

                // Persist zone membership for the rest of this gesture.
                state = enteredZone
            }
            .onEnded { value in
                let translationX = value.translation.width
                let velocityX = value.predictedEndLocation.x - value.location.x
                let projected = translationX + velocityX * 0.4

                // Distance-based for slow drags; projected-based for fast flicks.
                if translationX >= swipeDistanceThreshold || projected >= swipeProjectedThreshold {
                    exit(.right)
                } else if translationX <= -swipeDistanceThreshold || projected <= -swipeProjectedThreshold {
                    exit(.left)
                }
            }
    }

    private func impactHaptic() {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }

    private func exit(_ direction: SwipeDirection) {
        let screen = UIScreen.main.bounds.width + 100

        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            exitOffset = direction == .right ? screen : -screen
        }

        // Keep this short delay; it allows the off-screen animation to start before advancing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onSwipe(direction)
        }
    }
}
