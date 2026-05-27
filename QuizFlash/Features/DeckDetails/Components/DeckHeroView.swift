//
//  DeckHeroView.swift
//  QuizFlash
//
//  Collapsed pill shown in the navigation bar area once the user scrolls
//  past the deck's title. Contains the animated mastery-ring border.
//

import SwiftUI

// MARK: - HeroAnimation Constants

/// Scroll-behaviour constants shared between `DeckHeroView` and `DeckView`.
enum HeroAnimation {
    /// Scroll distance (points) after which the collapsed pill becomes visible.
    static let scrollThreshold: CGFloat = 500
    /// Initial scale of the pill when it first appears (animates up to 1.0).
    static let pillInitialScale: CGFloat = 0.82
}

// MARK: - DeckHeroView

/// A fixed-position overlay that renders the collapsed deck-title pill.
///
/// Visibility is driven entirely by `DeckScrollState.pillVisible`, which is set
/// by a geometry anchor in `DeckView`'s scroll content. This view is fully dumb:
/// it reads the shared scroll state from the environment and renders accordingly.
struct DeckHeroView: View {

    // MARK: - Inputs

    /// The deck whose title and mastery percentage are displayed.
    let deck: DeckModel
    /// Aggregate stats used to compute the mastery ring colour and fill.
    let stats: DeckStats
    /// Maximum width available for the centered collapsed pill after leading and
    /// trailing chrome reserve their footprint.
    var maxWidth: CGFloat? = nil

    @Environment(DeckScrollState.self) private var scrollState
    @State private var measuredTextWidth: CGFloat = 0

    /// Convenience accessor; avoids multiple `scrollState.pillVisible` reads.
    private var pillVisible: Bool { scrollState.pillVisible }
    private var resolvedTitle: String {
        let trimmed = deck.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Deck" : trimmed
    }
    private var resolvedWidth: CGFloat {
        let intrinsicWidth = measuredTextWidth + (UIConstants.Spacing.standard * 2)
        let unclampedWidth = min(220, max(UIConstants.Size.capsuleHeight, intrinsicWidth))
        if let maxWidth {
            return min(unclampedWidth, max(UIConstants.Size.capsuleHeight, maxWidth))
        }
        return unclampedWidth
    }

    var body: some View {
        collapsedPill
    }

    private var collapsedPill: some View {
        ZStack {
            Text(resolvedTitle)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .hidden()
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { newWidth in
                    if abs(measuredTextWidth - newWidth) > 0.5 {
                        measuredTextWidth = newWidth
                    }
                }

            Text(resolvedTitle)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.92)
                .frame(width: max(0, resolvedWidth - (UIConstants.Spacing.standard * 2)))
        }
        .padding(.horizontal, UIConstants.Spacing.standard)
        .padding(.vertical, 8)
        .frame(width: resolvedWidth)
        .frame(height: UIConstants.Size.capsuleHeight)
        .background {
            AnimatedPillBackground(mastery: stats.deckMastery)
        }
        .opacity(pillVisible ? 1 : 0)
        .scaleEffect(pillVisible ? 1 : HeroAnimation.pillInitialScale, anchor: .top)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: pillVisible)
    }
}

// MARK: - AnimatedPillBackground

/// Renders the `ultraThinMaterial` capsule background with an animated mastery border.
///
/// - Layer 1 (surface): A plain `ultraThinMaterial` capsule.
/// - Layer 2 (active progress): A colour-tinted fill trimmed to `mastery`, starting from the
///   9 o'clock position (achieved via a 180° Y-axis flip of the default 3 o'clock origin).
private struct AnimatedPillBackground: View {

    private static let progressLineWidth: CGFloat = 4

    // MARK: - Inputs

    /// The deck's mastery fraction in [0, 1].
    let mastery: Double

    // MARK: - Private State

    @State private var animatedMastery: Double = 0
    @State private var isGlowing: Bool = false
    @State private var glowResetTask: Task<Void, Never>?

    private var ringColor: Color { masteryColor(mastery) }

    // MARK: - Body

    var body: some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay {
                // Active progress border — coloured portion reflecting the mastery level.
                // SwiftUI trims from 3 o'clock by default; flipping the Y axis shifts the
                // start point to 9 o'clock for a left-to-right fill appearance.
                Capsule()
                    .fill(ringColor.opacity(isGlowing ? 1.0 : 0.85))
                    .blur(radius: isGlowing ? 12 : 8)
                    .mask {
                        Capsule()
                            .inset(by: Self.progressLineWidth / 2)
                            .trim(from: 0, to: animatedMastery)
                            .stroke(
                                style: StrokeStyle(lineWidth: Self.progressLineWidth, lineCap: .round)
                            )
                    }
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                    .clipShape(Capsule())
            }
            .onAppear {
                withAnimation(.spring(response: 0.8, dampingFraction: 0.8).delay(0.15)) {
                    animatedMastery = mastery
                }
            }
            .onChange(of: mastery) { old, new in
                guard abs(new - old) > 0.001 else { return }
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { animatedMastery = new }
                // Pulse a brief glow to draw attention to the change.
                withAnimation(.easeIn(duration: 0.2)) { isGlowing = true }
                glowResetTask?.cancel()
                glowResetTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.2))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeInOut(duration: 0.8)) { isGlowing = false }
                }
            }
            .onDisappear {
                glowResetTask?.cancel()
            }
    }
}

// MARK: - Support Views

/// A circular icon badge showing the deck's SF Symbol on a translucent coloured background.
struct DeckIconBadge: View {
    /// The SF Symbol name. Falls back to `"sparkles.rectangle.stack.fill"` when empty.
    let icon: String
    /// The badge background tint.
    let color: Color
    /// Diameter of the badge in points.
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.20)).frame(width: size, height: size)
            Circle().stroke(color.opacity(0.30), lineWidth: 0.5).frame(width: size, height: size)
            Image(systemName: icon.isEmpty ? "sparkles.rectangle.stack.fill" : icon)
                .font(.system(size: size * 0.38, weight: .bold)).foregroundStyle(.white)
        }
    }
}

/// A compact 28 pt mastery arc used in condensed layouts (e.g. card thumbnails).
struct CompactMasteryArc: View {
    /// The mastery fraction in [0, 1].
    let mastery: Double
    /// The arc stroke colour.
    let color: Color

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.15), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: 28, height: 28).rotationEffect(.degrees(-90))
            Circle().trim(from: 0, to: mastery)
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: 28, height: 28).rotationEffect(.degrees(-90))
            Text("\(Int(mastery * 100))").font(.system(size: 8, weight: .black)).foregroundStyle(color)
        }
    }
}
