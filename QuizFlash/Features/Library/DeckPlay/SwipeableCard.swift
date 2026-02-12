//
//  SwipeableCard.swift
//  QuizFlash
//
//  Optimized swipe card.
//

import SwiftUI

enum SwipeDirection {
    case left, right
}

struct SwipeableCard<Content: View>: View {
    
    let onSwipe: (SwipeDirection) -> Void
    let onTap: (() -> Void)?
    // Changed: Now accepts a Bool (isSwiping) to pass down to content
    @ViewBuilder let content: (Bool) -> Content
    
    @State private var offset: CGFloat = 0
    @State private var isSwiping = false
    @State private var didHaptic = false
    
    private let haptic = UIImpactFeedbackGenerator(style: .light)
    private let threshold: CGFloat = 80
    
    init(
        onSwipe: @escaping (SwipeDirection) -> Void,
        onTap: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Bool) -> Content
    ) {
        self.onSwipe = onSwipe
        self.onTap = onTap
        self.content = content
    }
    
    private var rotation: Double {
        Double(offset) / 30.0
    }
    
    private var scale: CGFloat {
        1.0 - min(abs(offset) / 800.0, 0.03)
    }
    
    private var borderColor: Color {
        offset > 0 ? .green : .red
    }
    
    var body: some View {
        ZStack {
            // Pass the swipe state to the content (to disable scrolling)
            content(isSwiping)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(borderColor.opacity(min(abs(offset) / threshold, 1.0)), lineWidth: 3)
                        .opacity(abs(offset) > 10 ? 1 : 0)
                )
        }
        .scaleEffect(scale)
        .rotationEffect(.degrees(rotation), anchor: .bottom)
        .offset(x: offset)
        .gesture(dragGesture)
        .onTapGesture {
            if abs(offset) < 5 {
                onTap?()
            }
        }
    }
    
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height
                
                // Locking Logic:
                // 1. Determine direction if not locked yet
                if !isSwiping {
                    if abs(dx) > abs(dy) {
                        isSwiping = true
                    } else {
                        // Vertical movement detected, ignore this drag for swipe
                        return
                    }
                }
                
                // 2. Update position if locked to swipe
                offset = dx
                
                // Haptic feedback
                if abs(offset) >= threshold && !didHaptic {
                    haptic.impactOccurred()
                    didHaptic = true
                } else if abs(offset) < threshold * 0.5 {
                    didHaptic = false
                }
            }
            .onEnded { value in
                isSwiping = false
                didHaptic = false
                
                let dx = value.translation.width
                let vx = value.velocity.width
                
                if dx > threshold || vx > 400 {
                    exitCard(.right)
                } else if dx < -threshold || vx < -400 {
                    exitCard(.left)
                } else {
                    resetPosition()
                }
            }
    }
    
    private func resetPosition() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            offset = 0
        }
    }
    
    private func exitCard(_ direction: SwipeDirection) {
        let exitX: CGFloat = direction == .right ? 500 : -500
        
        withAnimation(.easeOut(duration: 0.2)) {
            offset = exitX
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            onSwipe(direction)
        }
    }
}
