//
//  AIGenerationView.swift
//  QuizFlash
//
//  Loading and progress UI displayed while AI flashcard generation runs.
//

import SwiftUI

private let kAIGenerationStatusCardHeight: CGFloat = 212

// MARK: - AI Extracting Loading View

/// Minimal loading card shown while the source is read before cards start streaming.
struct AIExtractingLoadingView: View {
    var elapsedStartDate: Date? = nil
    var elapsedAccumulatedDuration: TimeInterval = 0
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

                if elapsedStartDate != nil || elapsedAccumulatedDuration > 0 {
                    AIGenerationElapsedTimeLabel(
                        startDate: elapsedStartDate,
                        accumulatedDuration: elapsedAccumulatedDuration
                    )
                }
            }
        }
        .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
        .padding(.top, UIConstants.Spacing.huge)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { isActive = true }
    }
}

// MARK: - AI Streaming Text Status

/// Text-only generation state shown while AI batches are still pending.
struct AIStreamingTextStatusView: View {
    let title: String

    var body: some View {
        AIShimmeringStatusText(title)
            .font(.system(size: 34, weight: .heavy, design: .rounded))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
            .padding(.top, UIConstants.Spacing.huge)
            .padding(.bottom, UIConstants.Spacing.extraLarge)
    }
}

struct AIShimmeringStatusText: View {
    let title: String
    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .foregroundStyle(.white.opacity(0.32))
            .overlay {
                if reduceMotion {
                    Text(title)
                        .foregroundStyle(.primary)
                } else {
                    shimmerLayer
                }
            }
            .accessibilityLabel(title)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
    }

    private var shimmerLayer: some View {
        GeometryReader { geometry in
            Text(title)
                .foregroundStyle(.white)
                .mask(alignment: .leading) {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white.opacity(0.12), location: 0.28),
                            .init(color: .white, location: 0.5),
                            .init(color: .white.opacity(0.12), location: 0.72),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: max(geometry.size.width * 0.62, 120))
                    .offset(
                        x: isAnimating
                            ? geometry.size.width * 1.15
                            : -geometry.size.width * 0.68
                    )
                }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - AI Streaming Progress Card

/// Compact progress card shown while AI batches arrive incrementally.
struct AIStreamingProgressCard: View {
    let foundCount: Int
    let targetCount: Int
    let progress: Double
    var title: String = "Generating cards"
    var subtitleOverride: String? = nil
    var accentColor: Color? = nil
    var footnote: String = "Cards appear in place as each batch finishes"
    var elapsedStartDate: Date? = nil
    var elapsedAccumulatedDuration: TimeInterval = 0
    var onCancel: (() -> Void)? = nil
    var onPause: (() -> Void)? = nil

    private var accent: Color { accentColor ?? ThemeManager.shared.accentColor.color }

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
        if let subtitleOverride {
            return subtitleOverride
        }
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
                            Text(title)
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)

                            ProgressActivityDots(color: accent)
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
                        Text(footnote)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)

                    if elapsedStartDate != nil || elapsedAccumulatedDuration > 0 {
                        AIGenerationElapsedTimeLabel(
                            startDate: elapsedStartDate,
                            accumulatedDuration: elapsedAccumulatedDuration
                        )
                    }
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
    var title: String = "Generation paused"
    var subtitle: String = "Continue from the last completed batch when you're ready."
    var accentColor: Color? = nil
    var elapsedStartDate: Date? = nil
    var elapsedAccumulatedDuration: TimeInterval = 0
    let onResume: () -> Void

    private var accent: Color { accentColor ?? ThemeManager.shared.accentColor.color }

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
                        Text(title)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

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

                    if elapsedStartDate != nil || elapsedAccumulatedDuration > 0 {
                        AIGenerationElapsedTimeLabel(
                            startDate: elapsedStartDate,
                            accumulatedDuration: elapsedAccumulatedDuration
                        )
                    }
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
            .duoSurface(cornerRadius: 28)
    }
}

private struct AIGenerationCountBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(.primary)
            .frame(minWidth: 52)
            .duoMetricPill()
            .fixedSize(horizontal: true, vertical: false)
    }
}

private struct AIGenerationElapsedTimeLabel: View {
    let startDate: Date?
    let accumulatedDuration: TimeInterval

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Label(
                formattedElapsedTime(at: context.date),
                systemImage: "timer"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func formattedElapsedTime(at referenceDate: Date) -> String {
        let liveDuration = startDate.map { max(0, referenceDate.timeIntervalSince($0)) } ?? 0
        let totalSeconds = Int((accumulatedDuration + liveDuration).rounded(.down))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%02d:%02d", minutes, seconds)
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
