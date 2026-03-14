//
//  AIGenerationView.swift
//  QuizFlash
//
//  Loading states and skeleton UI displayed while AI flashcard generation runs.
//

import SwiftUI

// MARK: - AI Extracting Loading View

/// Animated scanning overlay shown during the text-extraction phase of the AI pipeline.
struct AIExtractingLoadingView: View {
    @State private var isScanning = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 60)

            ZStack {
                // Document icon
                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 64, weight: .thin))
                    .foregroundStyle(.secondary.opacity(0.4))

                // Animated scan line
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, .purple.opacity(0.8), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 70, height: 4)
                    .offset(y: isScanning ? 30 : -30)
                    .shadow(color: .purple, radius: 6, y: 0)
                    .animation(
                        .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                        value: isScanning
                    )
            }

            VStack(spacing: 8) {
                Text("Analyzing Document...")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("Extracting text and preparing AI generation")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .onAppear { isScanning = true }
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
///
/// Keeps the generation state visible without blocking the newly inserted
/// flashcards that stream into the list below it.
struct AIStreamingProgressCard: View {
    let foundCount: Int
    let targetCount: Int
    let progress: Double
    var onCancel: (() -> Void)? = nil

    @State private var shimmerPhase: CGFloat = -0.32

    private var clampedProgress: CGFloat {
        CGFloat(min(max(progress, 0), 1))
    }

    private var countText: String {
        "\(foundCount)/\(targetCount)"
    }

    private var statusText: String {
        "Cards appear as each AI batch finishes"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            HStack(alignment: .top, spacing: UIConstants.Spacing.medium) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Generating cards")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("\(foundCount) of \(targetCount) ready")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }

                Spacer(minLength: UIConstants.Spacing.small)

                HStack(spacing: UIConstants.Spacing.small) {
                    Text(countText)
                        .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.06), in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        }
                        .contentTransition(.numericText())

                    if let onCancel {
                        Button(action: onCancel) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 30, height: 30)
                                .background(Color.white.opacity(0.06), in: Circle())
                                .overlay {
                                    Circle()
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Cancel AI generation")
                    }
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.blue.opacity(0.92),
                                    Color.blue.opacity(0.88),
                                    Color.purple.opacity(0.90),
                                    Color.pink.opacity(0.84)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(20, proxy.size.width * clampedProgress))
                        .overlay(alignment: .leading) {
                            LinearGradient(
                                colors: [
                                    .clear,
                                    Color.white.opacity(0.08),
                                    Color.white.opacity(0.42),
                                    .clear
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: 96)
                            .offset(x: shimmerPhase * proxy.size.width)
                            .blendMode(.screen)
                        }
                        .clipShape(Capsule())
                        .shadow(color: Color.blue.opacity(0.18), radius: 12, y: 3)

                    if clampedProgress > 0 {
                        Circle()
                            .fill(Color.white.opacity(0.95))
                            .frame(width: 8, height: 8)
                            .blur(radius: 0.8)
                            .offset(x: max(0, (proxy.size.width * clampedProgress) - 8))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 12)
            .animation(.easeInOut(duration: 0.26), value: clampedProgress)

            Text(statusText)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, UIConstants.Spacing.large)
        .padding(.vertical, 18)
        .frame(minHeight: 138, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.libraryDeckRow)
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.04),
                                    Color.clear,
                                    Color.blue.opacity(0.06)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .onAppear {
            withAnimation(.linear(duration: 1.7).repeatForever(autoreverses: false)) {
                shimmerPhase = 1.08
            }
        }
    }
}

// MARK: - AI Streaming Card Slot

/// Replaces a skeleton placeholder in place with the real generated card.
///
/// The transition uses a large internal glow fill followed by a soft content
/// fade so the card feels illuminated into place instead of abruptly swapped.
struct AIStreamingCardSlot<Content: View>: View {
    let slotIndex: Int
    let isFilled: Bool
    let filledCardID: UUID?
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
            await startRevealAnimation(for: filledCardID)
        }
        .onAppear {
            isVisible = true
            let revealCardID = pendingRevealCardID ?? filledCardID
            Task { @MainActor in
                await startRevealAnimation(for: revealCardID)
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
    private func startRevealAnimation(for cardID: UUID?) async {
        animationTask?.cancel()

        guard isFilled, let cardID else {
            animatedCardID = nil
            pendingRevealCardID = nil
            setVisualState(skeleton: 1, content: 0, glow: 0, expansion: 0.76)
            return
        }

        guard animatedCardID != cardID || contentOpacity < 0.999 || skeletonOpacity > 0.001 else {
            pendingRevealCardID = nil
            return
        }
        animatedCardID = cardID
        setVisualState(skeleton: 1, content: 0, glow: 0, expansion: 0.76)

        animationTask = Task { @MainActor in
            withAnimation(.easeInOut(duration: 0.34)) {
                skeletonOpacity = 0.82
                glowOpacity = 0.96
                glowExpansion = 1.08
            }

            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }

            withAnimation(.easeOut(duration: 0.42)) {
                skeletonOpacity = 0
                glowOpacity = 0.42
                glowExpansion = 1.22
            }

            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }

            withAnimation(.easeIn(duration: 0.30)) {
                contentOpacity = 1
            }

            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }

            withAnimation(.easeOut(duration: 0.26)) {
                glowOpacity = 0
                glowExpansion = 1.28
            }

            pendingRevealCardID = nil
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

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.04 + (intensity * 0.14)))

            ZStack {
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.blue.opacity(0.48),
                                Color.white.opacity(0.18),
                                Color.purple.opacity(0.42),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 320, height: 240)
                    .scaleEffect(expansion)
                    .blur(radius: 54 + (intensity * 26))
                    .offset(x: -18, y: -8)

                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.white.opacity(0.18),
                                Color.pink.opacity(0.34),
                                Color.blue.opacity(0.28)
                            ],
                            startPoint: .topTrailing,
                            endPoint: .bottomLeading
                        )
                    )
                    .frame(width: 300, height: 220)
                    .scaleEffect(expansion * 0.94)
                    .blur(radius: 68 + (intensity * 30))
                    .offset(x: 22, y: 12)

                RoundedRectangle(cornerRadius: max(12, cornerRadius - 6), style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    .padding(10)
                    .blur(radius: 18)
                    .opacity(intensity * 0.46)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .opacity(intensity)
    }
}

// MARK: - Skeleton Card View

/// Single animated skeleton placeholder for one AI-generated card.
///
/// Uses a seeded RNG so bar widths are deterministic per index, avoiding
/// layout shifts on re-render while the animated border keeps the placeholder
/// visually active during streaming generation.
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
                .fill(Color.libraryDeckRow.opacity(0.94))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                }

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(phase ? 0.05 : 0.02),
                            Color.clear,
                            Color.blue.opacity(phase ? 0.03 : 0.015)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(alignment: .leading, spacing: 0) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.purple.opacity(phase ? 0.28 : 0.16),
                                Color.blue.opacity(phase ? 0.20 : 0.10)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 64, height: 20)
                    .padding(.bottom, 14)

                HStack(alignment: .top, spacing: 10) {
                    Text("Q")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.12))
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 7) {
                        SkeletonBar(widthFraction: barWidths[0], phase: phase)
                        SkeletonBar(widthFraction: barWidths[1], phase: phase)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()
                    .background(Color.primary.opacity(0.05))
                    .padding(.vertical, 12)

                HStack(alignment: .top, spacing: 10) {
                    Text("A")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.12))
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 7) {
                        SkeletonBar(widthFraction: barWidths[2], phase: phase)
                        SkeletonBar(widthFraction: barWidths[3], phase: phase)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(phase ? 0.10 : 0.16))
                        .frame(width: 60, height: 8)
                    Spacer()
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(phase ? 0.10 : 0.16))
                        .frame(width: 80, height: 8)
                }
                .padding(.top, 14)
            }
            .padding(16)
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
                        Color.primary.opacity(phase ? 0.12 : 0.18),
                        Color.primary.opacity(phase ? 0.08 : 0.12)
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
    init(seed: UInt64) { state = seed == 0 ? 1 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17; return state
    }
}
