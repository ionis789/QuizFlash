import SwiftUI

enum SwipeDirection {
    case left, right
}

/// Simple, native swipe card with smooth animations
struct SwipeableCard<Content: View>: View {
    let onSwipe: (SwipeDirection) -> Void
    let onTap: (() -> Void)?
    @ViewBuilder let content: () -> Content

    private let swipeThreshold: CGFloat = 100

    @GestureState private var dragOffset: CGFloat = 0
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
        min(abs(currentOffset) / swipeThreshold, 1)
    }

    private var glowColor: Color {
        currentOffset >= 0 ? .green : .red
    }

    var body: some View {
        ZStack {
            content()

            // Glow border
            RoundedRectangle(cornerRadius: 22, style: .continuous)
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
                state = value.translation.width
            }
            .onEnded { value in
                let velocity = value.predictedEndLocation.x - value.location.x
                let finalOffset = value.translation.width + velocity * 0.4

                if finalOffset > swipeThreshold {
                    exit(.right)
                } else if finalOffset < -swipeThreshold {
                    exit(.left)
                }
            }
    }

    private func exit(_ direction: SwipeDirection) {
        let screen = UIScreen.main.bounds.width + 100

        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            exitOffset = direction == .right ? screen : -screen
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onSwipe(direction)
        }
    }
}
