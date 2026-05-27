//
//  AnimatedProgressRing.swift
//  QuizFlash
//
//  Shared circular progress rings used across dashboard and deck surfaces.
//

import SwiftUI

// MARK: - Animated Progress Ring

/// A shared animated circular progress ring with customizable center content.
///
/// The ring animates its arc on first appearance and when `progress` changes so
/// dashboard and deck surfaces reuse the same motion language.
struct AnimatedProgressRing<CenterContent: View>: View {

    // MARK: - Inputs

    /// The progress fraction in `[0, 1]`.
    let progress: Double
    /// The inactive track color.
    let trackColor: Color
    /// The active arc color.
    let progressColor: Color
    /// The ring diameter in points.
    var size: CGFloat = 72
    /// The stroke width of both the track and the active arc.
    var strokeWidth: CGFloat = 9
    /// Content rendered in the middle of the ring.
    @ViewBuilder var centerContent: (_ animatedProgress: Double) -> CenterContent

    // MARK: - Private State

    @State private var animatedProgress: Double
    @State private var isGlowing = false
    @State private var glowResetTask: Task<Void, Never>?

    init(
        progress: Double,
        trackColor: Color,
        progressColor: Color,
        size: CGFloat = 72,
        strokeWidth: CGFloat = 9,
        @ViewBuilder centerContent: @escaping (_ animatedProgress: Double) -> CenterContent
    ) {
        self.progress = progress
        self.trackColor = trackColor
        self.progressColor = progressColor
        self.size = size
        self.strokeWidth = strokeWidth
        self.centerContent = centerContent
        _animatedProgress = State(initialValue: Self.clamp(progress))
    }

    static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    trackColor,
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )

            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    progressColor,
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(
                    color: isGlowing ? progressColor.opacity(0.8) : .clear,
                    radius: isGlowing ? 10 : 0
                )

            centerContent(animatedProgress)
        }
        .frame(width: size, height: size)
        .onChange(of: progress) { oldValue, newValue in
            glowResetTask?.cancel()
            let plan = AnimatedProgressRingTransitionPlan.make(previousProgress: oldValue, newProgress: newValue)
            guard abs(plan.targetProgress - Self.clamp(oldValue)) > 0.001 else { return }

            switch plan.style {
            case .settle:
                withAnimation(.circularProgressSpring) {
                    animatedProgress = plan.targetProgress
                }

                if plan.shouldGlow {
                    withAnimation(.easeIn(duration: 0.18)) {
                        isGlowing = true
                    }
                    glowResetTask = Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.0))
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeInOut(duration: 0.4)) {
                            isGlowing = false
                        }
                    }
                } else {
                    isGlowing = false
                }

            case .zeroSettle:
                withAnimation(.easeInOut(duration: 0.22)) {
                    animatedProgress = 0
                }
                withAnimation(.easeOut(duration: 0.12)) {
                    isGlowing = false
                }
            }
        }
        .onDisappear {
            glowResetTask?.cancel()
        }
    }
}

// MARK: - Animated Progress Ring Transition Plan

struct AnimatedProgressRingTransitionPlan: Equatable {
    enum Style: Equatable {
        case settle
        case zeroSettle
    }

    let targetProgress: Double
    let style: Style
    let shouldGlow: Bool

    static func make(previousProgress: Double, newProgress: Double) -> Self {
        let previous = AnimatedProgressRing<EmptyView>.clamp(previousProgress)
        let target = AnimatedProgressRing<EmptyView>.clamp(newProgress)

        if target == 0 {
            return Self(targetProgress: 0, style: .zeroSettle, shouldGlow: false)
        }

        return Self(
            targetProgress: target,
            style: .settle,
            shouldGlow: target >= previous
        )
    }
}

// MARK: - Mastery Progress Ring

/// A deck-style mastery ring reused across the app for compact progress surfaces.
struct MasteryProgressRing: View {

    // MARK: - Inputs

    /// The mastery fraction in `[0, 1]`.
    let mastery: Double
    /// The surface tint used for the inactive track.
    let deckColor: Color
    /// The ring diameter in points.
    var size: CGFloat = 72
    /// The ring stroke width.
    var strokeWidth: CGFloat = 9

    // MARK: - Body

    var body: some View {
        AnimatedProgressRing(
            progress: mastery,
            trackColor: deckColor.opacity(0.2),
            progressColor: masteryColor(mastery),
            size: size,
            strokeWidth: strokeWidth
        ) { animatedProgress in
            Text("\(Int(animatedProgress * 100))%")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(.primary)
                .contentTransition(.numericText(value: animatedProgress * 100))
        }
    }
}

// MARK: - masteryColor

/// Returns a semantic colour that represents a given mastery fraction.
///
/// - Parameter mastery: A value in `[0, 1]` where `1.0` is fully mastered.
/// - Returns: `.red` for < 25 %, `.orange` for 25–50 %, `.yellow` for 50–75 %,
///   `.teal` for 75–90 %, and `.green` for ≥ 90 %.
func masteryColor(_ mastery: Double) -> Color {
    switch mastery {
    case ..<0.25:       return .red
    case 0.25..<0.50:   return .orange
    case 0.50..<0.75:   return .yellow
    case 0.75..<0.90:   return .teal
    default:            return .green
    }
}
