//
//  DeckProgressView.swift
//  QuizFlash
//
//  Deck-detail summary surface showing progress, quick stats, and
//  the current day's reviewed-card outcomes for the visible deck.
//

import SwiftUI

// MARK: - DeckProgressView

/// Displays the deck's learning breakdown, quick aggregate stats, and the
/// compact entry point to the deck activity history.
///
/// All inputs are pre-computed by `DeckViewModel` and `CardFetchActor`.
/// The view remains rendering-only and performs no data fetching.
struct DeckProgressView: View {
    @Environment(ThemeManager.self) private var themeManager

    // MARK: - Inputs

    let progress: DeckProgressStats
    let stats: DeckStats
    let deckCardCount: Int
    let activity: DeckTodayActivitySummary
    let deckTint: Color
    let onOpenActivityHistory: () -> Void

    private var dueTint: Color {
        stats.dueCards > 0 ? themeManager.roleColor(.buttonDangerFill) : deckTint
    }

    private var summaryValueText: String {
        activity.uniqueCardsReviewed == 0 ? "No" : "\(activity.uniqueCardsReviewed)"
    }

    private var summaryLabelText: String {
        if activity.uniqueCardsReviewed == 0 {
            return "moves"
        }
        return activity.uniqueCardsReviewed == 1 ? "card moved" : "cards moved"
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 14) {
            summarySeparator
            primarySummaryBlock
            metricsBlock
            progressBlock
        }
        .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
    }

    private var summarySeparator: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
            .padding(.horizontal, 6)
            .padding(.bottom, 2)
    }

    private var primarySummaryBlock: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text(summaryValueText)
                    .font(.system(size: 56, weight: .black, design: .rounded))
                    .foregroundStyle(themeManager.textPrimary)
                    .contentTransition(.numericText())
                    .statusTextMotion(trigger: activity.uniqueCardsReviewed)

                Text(summaryLabelText)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(themeManager.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            DeckIntegratedMasteryRing(
                mastery: stats.deckMastery,
                deckTint: deckTint
            )
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
    }

    private var metricsBlock: some View {
        HStack(spacing: 12) {
            DeckMetricTile(
                highlight: dueTint,
                title: "Due",
                value: "\(stats.dueCards)",
                tint: dueTint
            )

            DeckMetricTile(
                highlight: deckTint,
                title: "Accuracy",
                value: "\(stats.accuracy)%",
                tint: themeManager.textPrimary
            )

            DeckMetricTile(
                highlight: deckTint,
                title: "Reviews",
                value: "\(stats.totalReviews)",
                tint: deckTint
            )
        }
        .padding(.top, 2)
    }

    private var progressBlock: some View {
        VStack(alignment: .trailing, spacing: 12) {
            DeckProgressSurface(
                highlight: deckTint,
                cornerRadius: 26
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    DeckSegmentedProgressBar(
                        progress: progress,
                        learningTint: deckTint,
                        animationValue: deckCardCount
                    )
                    legend
                }
            }

            DeckHistoryExpandButton(
                tint: deckTint,
                action: onOpenActivityHistory
            )
            .padding(.trailing, 6)
        }
    }

    private var legend: some View {
        HStack(spacing: 0) {
            DeckProgressLegendItem(
                color: .teal,
                count: progress.masteredCards,
                label: "Mastered"
            )
            Spacer()
            DeckProgressLegendItem(
                color: deckTint,
                count: progress.learningCards,
                label: "Learning"
            )
            Spacer()
            DeckProgressLegendItem(
                color: themeManager.textSecondary.opacity(0.42),
                count: progress.newCards,
                label: "New"
            )
        }
    }

}

// MARK: - Supporting Views

private struct DeckProgressSurface<Content: View>: View {
    @Environment(ThemeManager.self) private var themeManager

    let highlight: Color
    let cornerRadius: CGFloat
    let content: Content

    init(
        highlight: Color,
        cornerRadius: CGFloat = 30,
        @ViewBuilder content: () -> Content
    ) {
        self.highlight = highlight
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(themeManager.roleColor(.widgetSurfaceFill))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.035), lineWidth: 1)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(highlight.opacity(0.035))
                    }
                    .shadow(color: Color.black.opacity(0.34), radius: 22, x: 0, y: 14)
            }
    }
}

private struct DeckSegmentedProgressBar: View {
    let progress: DeckProgressStats
    let learningTint: Color
    let animationValue: Int

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 6) {
                if progress.masteredCards > 0 {
                    Capsule()
                        .fill(Color.teal.gradient)
                        .frame(width: max(0, geo.size.width * progress.masteredRatio - 6))
                }
                if progress.learningCards > 0 {
                    Capsule()
                        .fill(learningTint.gradient)
                        .frame(width: max(0, geo.size.width * progress.learningRatio - 6))
                }
                if progress.newCards > 0 {
                    Capsule()
                        .fill(Color.secondary.opacity(0.18))
                        .frame(width: max(0, geo.size.width * progress.newRatio - 6))
                }
            }
        }
        .frame(height: 16)
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: animationValue)
    }
}

private struct DeckProgressLegendItem: View {
    let color: Color
    let count: Int
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            HStack(spacing: 4) {
                Text("\(count)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)

                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct DeckMetricTile: View {
    let highlight: Color
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        DeckProgressSurface(
            highlight: highlight,
            cornerRadius: 24
        ) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .center)
            .multilineTextAlignment(.center)
        }
    }
}

private struct DeckIntegratedMasteryRing: View {
    let mastery: Double
    let deckTint: Color

    var body: some View {
        MasteryProgressRing(
            mastery: mastery,
            deckColor: deckTint,
            size: 144,
            strokeWidth: 14
        )
        .frame(width: 144, height: 144)
    }
}

private struct DeckHistoryExpandButton: View {
    @Environment(ThemeManager.self) private var themeManager

    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 12, weight: .black))

                Text("History")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(themeManager.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                Capsule(style: .continuous)
                    .fill(themeManager.surfacePrimary)
                    .overlay {
                        Capsule(style: .continuous)
                            .fill(tint.opacity(0.12))
                    }
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open activity history")
    }
}
