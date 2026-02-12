//
//  SwipeableCard.swift
//  QuizFlash
//
//  Optimized swipe card. iOS 17+
//

import SwiftUI

enum SwipeDirection {
    case left, right
}

struct SwipeableCard<Content: View>: View {
    
    let onSwipe: (SwipeDirection) -> Void
    let onTap: (() -> Void)?
    @ViewBuilder let content: () -> Content
    
    @State private var offset: CGFloat = 0
    @State private var didHaptic = false
    
    private let threshold: CGFloat = 80
    
    init(
        onSwipe: @escaping (SwipeDirection) -> Void,
        onTap: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.onSwipe = onSwipe
        self.onTap = onTap
        self.content = content
    }
    
    // Pre-calculate values to avoid recalculation during animation
    private var rotation: Double {
        Double(offset) / 30.0
    }
    
    private var scale: CGFloat {
        1.0 - Swift.min(Swift.abs(offset) / 800.0, 0.03)
    }
    
    private var glowColor: Color {
        offset > 0 ? .green : .red
    }
    
    private var glowOpacity: Double {
        Swift.min(Swift.abs(offset) / threshold, 1.0) * 0.6
    }
    
    var body: some View {
        // Card with integrated glow - moves together
        ZStack {
            // Glow background (behind card)
            if Swift.abs(offset) > 15 {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(glowColor.opacity(glowOpacity * 0.3))
                    .blur(radius: 20)
                    .scaleEffect(1.05)
            }
            
            // Card content with border glow
            content()
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(glowColor.opacity(glowOpacity), lineWidth: 3)
                        .opacity(Swift.abs(offset) > 15 ? 1 : 0)
                )
        }
        .scaleEffect(scale)
        .rotationEffect(.degrees(rotation), anchor: .bottom)
        .offset(x: offset)
        .gesture(dragGesture)
        .onTapGesture {
            onTap?()
        }
    }
    
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height
                
                // Only track horizontal movement
                guard Swift.abs(dx) > Swift.abs(dy) * 0.8 else { return }
                
                // Direct assignment - no animation during drag
                offset = dx
                
                // Haptic at threshold
                if Swift.abs(offset) >= threshold && !didHaptic {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    didHaptic = true
                } else if Swift.abs(offset) < threshold * 0.5 {
                    didHaptic = false
                }
            }
            .onEnded { value in
                didHaptic = false
                
                let dx = value.translation.width
                let vx = value.velocity.width
                
                // Fast swipe or past threshold
                if dx > threshold || vx > 400 {
                    exitCard(.right)
                } else if dx < -threshold || vx < -400 {
                    exitCard(.left)
                } else {
                    // Snap back
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        offset = 0
                    }
                }
            }
    }
    
    private func exitCard(_ direction: SwipeDirection) {
        let exitX: CGFloat = direction == .right ? 400 : -400
        
        withAnimation(.easeOut(duration: 0.18)) {
            offset = exitX
        }
        
        // Callback after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            onSwipe(direction)
        }
    }
}
