import SwiftUI

enum SwipeDirection {
    case left, right
}

/// Swipe card that allows scrolling inside
struct SwipeableCard<Content: View>: View {
    let onSwipe: (SwipeDirection) -> Void
    let onTap: (() -> Void)?
    @ViewBuilder let content: () -> Content

    private let swipeThreshold: CGFloat = 80
    
    @State private var offset: CGFloat = 0
    @State private var hasTriggeredHaptic = false

    init(
        onSwipe: @escaping (SwipeDirection) -> Void,
        onTap: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.onSwipe = onSwipe
        self.onTap = onTap
        self.content = content
    }

    private var rotation: Double {
        min(max(Double(offset / CGFloat(30)), -6), 6)
    }

    private var glowOpacity: Double {
        min(Double(abs(offset) / CGFloat(120)), 0.5)
    }

    private var glowColor: Color {
        offset >= 0 ? .green : .red
    }

    var body: some View {
        ZStack {
            content()
                .allowsHitTesting(true) // Allow scroll inside

            // Glow effect
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(glowColor.opacity(glowOpacity), lineWidth: 3)
                .allowsHitTesting(false)
        }
        .offset(x: offset)
        .rotationEffect(.degrees(rotation))
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    // Only track horizontal drags
                    if abs(value.translation.width) > abs(value.translation.height) {
                        offset = value.translation.width
                        
                        // Haptic feedback
                        if abs(offset) >= swipeThreshold && !hasTriggeredHaptic {
                            triggerHaptic()
                            hasTriggeredHaptic = true
                        } else if abs(offset) < swipeThreshold {
                            hasTriggeredHaptic = false
                        }
                    }
                }
                .onEnded { value in
                    let horizontal = value.translation.width
                    let velocity = value.predictedEndLocation.x - value.location.x
                    
                    if horizontal > swipeThreshold || velocity > 200 {
                        exitCard(.right)
                    } else if horizontal < -swipeThreshold || velocity < -200 {
                        exitCard(.left)
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            offset = 0
                        }
                    }
                    hasTriggeredHaptic = false
                }
        )
        .onTapGesture {
            onTap?()
        }
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.7), value: offset)
    }

    private func triggerHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    private func exitCard(_ direction: SwipeDirection) {
        let exitX: CGFloat = direction == .right ? 500 : -500
        
        withAnimation(.easeOut(duration: 0.25)) {
            offset = exitX
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onSwipe(direction)
        }
    }
}

