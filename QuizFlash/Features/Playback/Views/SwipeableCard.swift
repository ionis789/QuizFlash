//
//  SwipeableCard.swift
//  QuizFlash
//

import SwiftUI

enum SwipeDirection {
    case left, right
}

struct SwipeableCard<Content: View>: View {
    let onSwipe: (SwipeDirection) -> Void
    let onTap: (() -> Void)?
    @ViewBuilder let content: () -> Content

    @State private var offset: CGSize = .zero
    @State private var didHaptic = false

    private let haptic = UIImpactFeedbackGenerator(style: .medium)
    private let swipeThreshold: CGFloat = 130

    var body: some View {
        ZStack {
            content()
                .scaleEffect(cardScale)
                .offset(x: offset.width, y: offset.height * 0.15)
                .rotationEffect(.degrees(Double(offset.width / 15)), anchor: .bottom)
            // Red/Green Glow Effect
            .shadow(color: dragShadowColor, radius: abs(offset.width) > 10 ? 25 : 15, x: 0, y: 8)
                .gesture(dragGesture)
                .onTapGesture {
                onTap?()
            }
        }
            .contentShape(Rectangle())
    }

    // Scale effect on swipe
    private var cardScale: CGFloat {
        let progress = abs(offset.width) / UIScreen.main.bounds.width
        return max(0.8, 1.0 - (progress * 0.35))
    }

    private var dragShadowColor: Color {
        if offset.width > 10 {
            return Color.green.opacity(rightGlowIntensity)
        } else if offset.width < -10 {
            return Color.red.opacity(leftGlowIntensity)
        }
        return Color.black.opacity(0.12)
    }

    private var leftGlowIntensity: Double {
        guard offset.width < 0 else { return 0 }
        let progress = abs(offset.width) / swipeThreshold
        return min(Double(progress) * 0.8, 0.8)
    }

    private var rightGlowIntensity: Double {
        guard offset.width > 0 else { return 0 }
        let progress = offset.width / swipeThreshold
        return min(Double(progress) * 0.8, 0.8)
    }

    
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onChanged { value in
            if abs(value.translation.width) > 10 && abs(value.translation.width) < 30 {
                haptic.prepare()
            }
            if abs(value.translation.height) > abs(value.translation.width) + 20 && abs(offset.width) < 10 {
                return
            }

            withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.8)) {
                offset = value.translation
            }

            if abs(offset.width) >= swipeThreshold && !didHaptic {
                haptic.impactOccurred()
                didHaptic = true
            } else if abs(offset.width) < swipeThreshold * 0.8 {
                didHaptic = false
            }
        }
            .onEnded { value in
            let dx = value.translation.width
            let velocity = value.velocity.width

            let shouldExitRight = dx > swipeThreshold || velocity > 800
            let shouldExitLeft = dx < -swipeThreshold || velocity < -800

            if shouldExitRight {
                haptic.impactOccurred(intensity: 1.0)
                exitCardAnimation(.right)
            } else if shouldExitLeft {
                haptic.impactOccurred(intensity: 1.0)
                exitCardAnimation(.left)
            } else {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                    offset = .zero
                }
            }
            didHaptic = false
        }
    }

    private func exitCardAnimation(_ direction: SwipeDirection) {
        let screenWidth = UIScreen.main.bounds.width
        let exitX = direction == .right ? screenWidth + 200 : -(screenWidth + 200)

        withAnimation(.spring(response: 0.9, dampingFraction: 0.8)) {
            offset = CGSize(width: exitX, height: offset.height)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            onSwipe(direction)
        }
    }
}
