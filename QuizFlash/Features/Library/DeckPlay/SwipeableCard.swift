//
//  SwipeableCard.swift
//  QuizFlash
//
//  Smooth swipe card with spring animations and no lag.
//

import SwiftUI

private let resetSpring = Animation.spring(response: 0.42, dampingFraction: 0.78)
private let exitSpring = Animation.spring(response: 0.38, dampingFraction: 0.84)
private let exitDuration: TimeInterval = 0.38

enum SwipeDirection {
    case left, right
}

struct SwipeableCard<Content: View>: View {
    let onSwipe: (SwipeDirection) -> Void
    let onTap: (() -> Void)?
    @ViewBuilder let content: (Bool) -> Content

    @State private var offset: CGFloat = 0
    @State private var isSwiping = false
    @State private var didHaptic = false

    private let haptic = UIImpactFeedbackGenerator(style: .light)
    private let swipeThreshold: CGFloat = 100
    private let exitDistance: CGFloat = 600

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
        Double(offset) / 22
    }

    private var scale: CGFloat {
        1.0 - min(abs(offset) / 1200, 0.04)
    }

    private var swipeProgress: CGFloat {
        min(abs(offset) / swipeThreshold, 1.0)
    }

    var body: some View {
        ZStack {
            content(isSwiping)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(
                            (offset > 0 ? Color.green : Color.red).opacity(swipeProgress * 0.85),
                            lineWidth: 2.5
                        )
                        .opacity(swipeProgress > 0.08 ? 1 : 0)
                )
        }
        .scaleEffect(scale)
        .rotationEffect(.degrees(rotation), anchor: .center)
        .offset(x: offset)
        .gesture(dragGesture)
        .onTapGesture {
            if abs(offset) < 8 {
                onTap?()
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height

                if !isSwiping {
                    if abs(dx) > abs(dy) * 1.2 {
                        isSwiping = true
                    } else {
                        return
                    }
                }

                offset = dx

                if abs(offset) >= swipeThreshold && !didHaptic {
                    haptic.impactOccurred()
                    didHaptic = true
                } else if abs(offset) < swipeThreshold * 0.6 {
                    didHaptic = false
                }
            }
            .onEnded { value in
                let dx = value.translation.width
                let predicted = value.predictedEndTranslation.width
                let flickThreshold: CGFloat = 180

                let shouldExitRight = dx > swipeThreshold || predicted > flickThreshold
                let shouldExitLeft = dx < -swipeThreshold || predicted < -flickThreshold

                if shouldExitRight {
                    exitCard(.right)
                } else if shouldExitLeft {
                    exitCard(.left)
                } else {
                    resetPosition()
                }

                isSwiping = false
                didHaptic = false
            }
    }

    private func resetPosition() {
        withAnimation(resetSpring) {
            offset = 0
        }
    }

    private func exitCard(_ direction: SwipeDirection) {
        let exitX = direction == .right ? exitDistance : -exitDistance

        withAnimation(exitSpring) {
            offset = exitX
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + exitDuration) {
            onSwipe(direction)
        }
    }
}

