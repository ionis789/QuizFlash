import SwiftUI

enum SwipeDirection {
    case left, right
}

/// Swipe card with proper gesture priority - swipe for horizontal, scroll for vertical
struct SwipeableCard<Content: View>: View {
    let onSwipe: (SwipeDirection) -> Void
    let onTap: (() -> Void)?
    @ViewBuilder let content: () -> Content

    private let swipeThreshold: CGFloat = 70
    private let velocityThreshold: CGFloat = 150
    
    @State private var offset: CGFloat = 0
    @State private var hasTriggeredHaptic = false
    @State private var isDragging = false
    @State private var dragDirection: DragDirection = .undetermined
    
    private enum DragDirection {
        case undetermined, horizontal, vertical
    }

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
        min(max(Double(offset / 30), -6), 6)
    }

    private var glowOpacity: Double {
        min(Double(abs(offset) / 100), 0.6)
    }

    private var glowColor: Color {
        offset >= 0 ? .green : .red
    }

    var body: some View {
        ZStack {
            content()
                // Disable scroll when swiping horizontally
                .allowsHitTesting(dragDirection != .horizontal)

            // Glow effect overlay
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(glowColor.opacity(glowOpacity), lineWidth: 3)
                .allowsHitTesting(false)
        }
        .offset(x: offset)
        .rotationEffect(.degrees(rotation))
        .gesture(swipeGesture)
        .onTapGesture {
            if !isDragging {
                onTap?()
            }
        }
        .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.75), value: offset)
    }
    
    // MARK: - Swipe Gesture
    
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onChanged { value in
                isDragging = true
                
                let horizontal = abs(value.translation.width)
                let vertical = abs(value.translation.height)
                
                // Determine direction once at start of drag
                if dragDirection == .undetermined && (horizontal > 15 || vertical > 15) {
                    if horizontal > vertical * 1.2 {
                        dragDirection = .horizontal
                    } else if vertical > horizontal * 1.2 {
                        dragDirection = .vertical
                    }
                }
                
                // Only move card if dragging horizontally
                if dragDirection == .horizontal {
                    offset = value.translation.width
                    
                    // Haptic at threshold
                    if abs(offset) >= swipeThreshold && !hasTriggeredHaptic {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        hasTriggeredHaptic = true
                    } else if abs(offset) < swipeThreshold && hasTriggeredHaptic {
                        hasTriggeredHaptic = false
                    }
                }
            }
            .onEnded { value in
                isDragging = false
                
                if dragDirection == .horizontal {
                    let horizontal = value.translation.width
                    let velocity = value.predictedEndLocation.x - value.location.x
                    
                    // Swipe completed
                    if horizontal > swipeThreshold || velocity > velocityThreshold {
                        exitCard(.right)
                    } else if horizontal < -swipeThreshold || velocity < -velocityThreshold {
                        exitCard(.left)
                    } else {
                        // Snap back
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            offset = 0
                        }
                    }
                }
                
                // Reset state
                hasTriggeredHaptic = false
                dragDirection = .undetermined
            }
    }

    private func exitCard(_ direction: SwipeDirection) {
        let exitX: CGFloat = direction == .right ? 500 : -500
        
        withAnimation(.easeOut(duration: 0.22)) {
            offset = exitX
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            onSwipe(direction)
        }
    }
}
