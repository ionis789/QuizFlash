//
//  AIGenerationView.swift
//  QuizFlash
//
//  Loading states and skeleton UI displayed while AI flashcard generation runs.
//

import SwiftUI

private let kAIGenerationStatusCardHeight: CGFloat = 212

// MARK: - AI Extracting Loading View

/// Minimal loading card shown while the source is read before cards start streaming.
struct AIExtractingLoadingView: View {
    @State private var isActive = false

    private var accent: Color { ThemeManager.shared.accentColor.color }

    var body: some View {
        AIGenerationSurface {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.large) {
                ZStack {
                    RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .frame(width: 72, height: 72)

                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                    Text("Preparing your material")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("Reading the source and setting up the generation pipeline.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                AISimpleProgressBar(
                    fraction: 0,
                    color: accent,
                    isIndeterminate: true
                )

                Text("This usually takes a moment before the first cards start to stream in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
        .padding(.top, UIConstants.Spacing.huge)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { isActive = true }
    }
}

// MARK: - AI Generation Skeleton List

/// A staggered list of skeleton cards shown while AI generates flashcards.
struct AIGenerationSkeletonList: View {
    let cardCount: Int
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 14) {
            ForEach(0..<cardCount, id: \.self) { index in
                AISkeletonCardView(index: index, globalAppeared: appeared)
                    .padding(.horizontal, 16)
                    .opacity(appeared ? 1 : 0)
                    .scaleEffect(appeared ? 1 : 0.94, anchor: .bottom)
                    .offset(y: appeared ? 0 : 20)
                    .animation(
                        .spring(response: 0.5, dampingFraction: 0.8)
                            .delay(Double(index) * 0.06),
                        value: appeared
                    )
            }
        }
        .onAppear { appeared = true }
    }
}

// MARK: - AI Streaming Progress Card

/// Compact progress card shown while AI batches arrive incrementally.
struct AIStreamingProgressCard: View {
    let foundCount: Int
    let targetCount: Int
    let progress: Double
    var onCancel: (() -> Void)? = nil
    var onPause: (() -> Void)? = nil

    private var accent: Color { ThemeManager.shared.accentColor.color }

    private var clampedProgress: CGFloat {
        CGFloat(min(max(progress, 0), 1))
    }

    private var countText: String {
        "\(foundCount)/\(targetCount)"
    }

    private var remainingCount: Int {
        max(targetCount - foundCount, 0)
    }

    private var subtitle: String {
        if foundCount == 0 {
            return "The first cards will appear here as soon as the model finishes the opening batch."
        }
        if remainingCount == 0 {
            return "All cards are in. Finishing the last pass."
        }
        return "\(remainingCount) card\(remainingCount == 1 ? "" : "s") remaining in this run."
    }

    var body: some View {
        AIGenerationSurface {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
                HStack(alignment: .top, spacing: UIConstants.Spacing.medium) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: UIConstants.Spacing.small) {
                            Text("Generating cards")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)

                            AIGenerationActivityDots(color: accent)
                        }

                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer(minLength: UIConstants.Spacing.small)

                    AIGenerationCountBadge(text: countText)
                }

                AISimpleProgressBar(
                    fraction: clampedProgress,
                    color: accent,
                    isIndeterminate: foundCount == 0
                )

                HStack(spacing: UIConstants.Spacing.small) {
                    if let onPause {
                        AIGenerationRoundButton(
                            systemImage: "pause.fill",
                            tint: accent,
                            action: onPause
                        )
                        .accessibilityLabel("Pause AI generation")
                    }

                    if let onCancel {
                        AIGenerationRoundButton(
                            systemImage: "xmark",
                            tint: .secondary,
                            action: onCancel
                        )
                        .accessibilityLabel("Cancel AI generation")
                    }

                    Spacer(minLength: UIConstants.Spacing.small)

                    HStack(spacing: UIConstants.Spacing.small) {
                        Image(systemName: "sparkles.rectangle.stack")
                            .font(.caption)
                        Text("Cards appear in place as each batch finishes")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
                .frame(height: 36)
            }
        }
        .frame(height: kAIGenerationStatusCardHeight)
    }
}

// MARK: - AI Paused Resume Card

/// Resume card shown when a paused generation can continue from disk or memory.
struct AIPausedResumeCard: View {
    let foundCount: Int
    let targetCount: Int
    let remainingCount: Int
    let progress: Double
    let onResume: () -> Void

    private var accent: Color { ThemeManager.shared.accentColor.color }

    private var clampedProgress: CGFloat {
        CGFloat(min(max(progress, 0), 1))
    }

    private var countText: String {
        "\(foundCount)/\(targetCount)"
    }

    var body: some View {
        AIGenerationSurface {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
                HStack(alignment: .top, spacing: UIConstants.Spacing.medium) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Generation paused")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text("Continue from the last completed batch when you're ready.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer(minLength: UIConstants.Spacing.small)

                    AIGenerationCountBadge(text: countText)
                }

                AISimpleProgressBar(
                    fraction: clampedProgress,
                    color: accent
                )

                HStack(spacing: UIConstants.Spacing.small) {
                    Button(action: onResume) {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 11, weight: .bold, design: .rounded))

                            Text("Continue")
                                .font(.subheadline.weight(.bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(accent, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: UIConstants.Spacing.small)

                    Label(
                        "\(remainingCount) card\(remainingCount == 1 ? "" : "s") still pending",
                        systemImage: "pause.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(height: 36)
            }
        }
        .frame(height: kAIGenerationStatusCardHeight)
    }
}

private struct AIGenerationSurface<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(UIConstants.Spacing.large)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.05), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
            }
    }
}

private struct AIGenerationCountBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            }
            .statusTextMotion(trigger: text)
            .fixedSize(horizontal: true, vertical: false)
    }
}

private struct AIGenerationRoundButton: View {
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(Color(uiColor: .tertiarySystemFill), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

struct AIGenerationActivityDots: View {
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: false)) { context in
            let time = context.date.timeIntervalSinceReferenceDate

            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    let phase = time - (Double(index) * 0.18)
                    let pulse = max(0.25, (sin(phase * 4.0) + 1) / 2)

                    Circle()
                        .fill(color.opacity(0.35 + (pulse * 0.55)))
                        .frame(width: 6, height: 6)
                        .scaleEffect(0.78 + (pulse * 0.36))
                }
            }
        }
        .frame(height: 8)
    }
}

// MARK: - AI Streaming Card Slot

/// Replaces a skeleton placeholder in place with the real generated card.
struct AIStreamingCardSlot<Content: View>: View {
    let slotIndex: Int
    let isFilled: Bool
    let filledCardID: UUID?
    let shouldAnimateReveal: Bool
    var onRevealFinished: ((UUID) -> Void)? = nil
    @ViewBuilder let content: () -> Content

    private let cornerRadius: CGFloat = 30
    @State private var animatedCardID: UUID?
    @State private var skeletonOpacity: Double = 1
    @State private var contentOpacity: Double = 0
    @State private var glowOpacity: Double = 0
    @State private var glowExpansion: CGFloat = 0.76
    @State private var animationTask: Task<Void, Never>?
    @State private var isVisible = false
    @State private var pendingRevealCardID: UUID?

    var body: some View {
        ZStack {
            AISkeletonCardView(index: slotIndex, globalAppeared: true)
                .opacity(isFilled ? skeletonOpacity : 1)

            if isFilled {
                content()
                    .id(filledCardID)
                    .opacity(max(0.001, contentOpacity))
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

                AIInternalGlowFillOverlay(
                    cornerRadius: cornerRadius,
                    intensity: glowOpacity,
                    expansion: glowExpansion
                )
                .allowsHitTesting(false)
            }
        }
        .frame(height: UIConstants.Size.draftCardRowHeight)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: filledCardID) {
            pendingRevealCardID = filledCardID
            guard isVisible else { return }
            await startRevealAnimation(
                for: filledCardID,
                shouldAnimate: shouldAnimateReveal
            )
        }
        .onAppear {
            isVisible = true
            let revealCardID = pendingRevealCardID ?? filledCardID
            Task { @MainActor in
                await startRevealAnimation(
                    for: revealCardID,
                    shouldAnimate: shouldAnimateReveal
                )
            }
        }
        .onDisappear {
            isVisible = false
            animationTask?.cancel()
            animationTask = nil

            guard isFilled, contentOpacity < 0.999 else { return }
            pendingRevealCardID = filledCardID
            animatedCardID = nil
            setVisualState(skeleton: 1, content: 0, glow: 0, expansion: 0.76)
        }
    }

    @MainActor
    private func startRevealAnimation(
        for cardID: UUID?,
        shouldAnimate: Bool
    ) async {
        animationTask?.cancel()

        guard isFilled, let cardID else {
            animatedCardID = nil
            pendingRevealCardID = nil
            setVisualState(skeleton: 1, content: 0, glow: 0, expansion: 0.76)
            return
        }

        if !shouldAnimate {
            animatedCardID = cardID
            pendingRevealCardID = nil
            setVisualState(skeleton: 0, content: 1, glow: 0, expansion: 1)
            return
        }

        guard animatedCardID != cardID || contentOpacity < 0.999 || skeletonOpacity > 0.001 else {
            pendingRevealCardID = nil
            return
        }

        animatedCardID = cardID
        setVisualState(skeleton: 1, content: 0, glow: 0, expansion: 0.76)

        animationTask = Task { @MainActor in
            withAnimation(.easeInOut(duration: 0.18)) {
                skeletonOpacity = 0.68
                glowOpacity = 0.72
                glowExpansion = 1.02
            }

            try? await Task.sleep(nanoseconds: 140_000_000)
            guard !Task.isCancelled else { return }

            withAnimation(.easeOut(duration: 0.22)) {
                skeletonOpacity = 0
                contentOpacity = 1
                glowOpacity = 0.22
                glowExpansion = 1.08
            }

            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }

            withAnimation(.easeOut(duration: 0.18)) {
                glowOpacity = 0
                glowExpansion = 1.12
            }

            pendingRevealCardID = nil
            onRevealFinished?(cardID)
            animationTask = nil
        }
    }

    @MainActor
    private func setVisualState(
        skeleton: Double,
        content: Double,
        glow: Double,
        expansion: CGFloat
    ) {
        skeletonOpacity = skeleton
        contentOpacity = content
        glowOpacity = glow
        glowExpansion = expansion
    }
}

private struct AIInternalGlowFillOverlay: View {
    let cornerRadius: CGFloat
    let intensity: Double
    let expansion: CGFloat

    private var accent: Color { ThemeManager.shared.accentColor.color }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.02 + (intensity * 0.06)))

            ZStack {
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(0.26),
                                Color.white.opacity(0.10),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 260, height: 180)
                    .scaleEffect(expansion)
                    .blur(radius: 42 + (intensity * 18))
                    .offset(x: -14, y: -4)

                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.white.opacity(0.14),
                                accent.opacity(0.14)
                            ],
                            startPoint: .topTrailing,
                            endPoint: .bottomLeading
                        )
                    )
                    .frame(width: 240, height: 160)
                    .scaleEffect(expansion * 0.96)
                    .blur(radius: 52 + (intensity * 20))
                    .offset(x: 18, y: 10)

                RoundedRectangle(cornerRadius: max(12, cornerRadius - 6), style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                    .padding(10)
                    .blur(radius: 12)
                    .opacity(intensity * 0.34)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .opacity(intensity)
    }
}

// MARK: - Skeleton Card View

/// Simple, shared progress bar matching the style used during generation.
private struct AISimpleProgressBar: View {
    let fraction: CGFloat
    let color: Color
    var isIndeterminate: Bool = false

    @State private var animateIndicator = false

    private var clampedFraction: CGFloat {
        max(0, min(fraction, 1))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(uiColor: .tertiarySystemFill))

                if isIndeterminate {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.26),
                                    color.opacity(0.78),
                                    Color.white.opacity(0.10)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(44, proxy.size.width * 0.22))
                        .offset(x: animateIndicator ? proxy.size.width * 0.78 : 0)
                        .animation(
                            .easeInOut(duration: 1.05).repeatForever(autoreverses: true),
                            value: animateIndicator
                        )
                } else if clampedFraction > 0 {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    color.opacity(0.72),
                                    color.opacity(0.92)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: max(
                                0,
                                min(
                                    proxy.size.width,
                                    proxy.size.width * clampedFraction
                                )
                            )
                        )
                        .animation(.easeInOut(duration: 0.35), value: clampedFraction)
                }
            }
        }
        .frame(height: 6)
        .onAppear { animateIndicator = true }
    }
}

/// Single animated skeleton placeholder for one AI-generated card.
struct AISkeletonCardView: View {
    let index: Int
    let globalAppeared: Bool

    private let cornerRadius: CGFloat = 30

    @State private var phase = false

    private let barWidths: [CGFloat]

    init(index: Int, globalAppeared: Bool) {
        self.index = index
        self.globalAppeared = globalAppeared
        var rng = SeededRNG(seed: UInt64(index &* 31337 &+ 1))
        barWidths = (0..<4).map { _ in CGFloat.random(in: 0.45...0.90, using: &rng) }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                }

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(phase ? 0.08 : 0.03),
                            Color.clear,
                            Color.white.opacity(phase ? 0.03 : 0.01)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .frame(width: 58, height: 16)

                    Spacer()

                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemFill).opacity(phase ? 0.95 : 0.72))
                        .frame(width: 74, height: 16)
                }

                HStack(alignment: .top, spacing: 10) {
                    Text("Q")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.secondary.opacity(0.45))
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 8) {
                        SkeletonBar(widthFraction: barWidths[0], phase: phase)
                        SkeletonBar(widthFraction: barWidths[1], phase: phase)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Rectangle()
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .frame(height: 1)

                HStack(alignment: .top, spacing: 10) {
                    Text("A")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.secondary.opacity(0.45))
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 8) {
                        SkeletonBar(widthFraction: barWidths[2], phase: phase)
                        SkeletonBar(widthFraction: barWidths[3], phase: phase)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemFill).opacity(phase ? 0.95 : 0.72))
                        .frame(width: 56, height: 8)

                    Spacer()

                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemFill).opacity(phase ? 0.95 : 0.72))
                        .frame(width: 84, height: 8)
                }
            }
            .padding(18)
        }
        .frame(height: UIConstants.Size.draftCardRowHeight)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onAppear {
            guard globalAppeared, !phase else { return }
            withAnimation(.easeInOut(duration: 1.25).repeatForever(autoreverses: true)) {
                phase = true
            }
        }
    }
}

// MARK: - Skeleton Bar

private struct SkeletonBar: View {
    let widthFraction: CGFloat
    let phase: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(uiColor: .tertiarySystemFill).opacity(phase ? 1.0 : 0.78),
                        Color.white.opacity(phase ? 0.10 : 0.04)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(maxWidth: .infinity, minHeight: 11, maxHeight: 11, alignment: .leading)
            .scaleEffect(x: widthFraction, y: 1, anchor: .leading)
    }
}

// MARK: - Seeded RNG

/// A deterministic pseudo-random number generator seeded per card index.
/// Ensures skeleton bar widths are stable across re-renders.
private struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 1 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
