//
//  DeckProgressView.swift
//  QuizFlash
//
//  A dumb UI component that renders the deck's progress breakdown.
//  All calculations are pre-computed by `DeckViewModel` and passed in
//  via a `DeckProgressStats` value type — this view contains zero business logic.
//

import SwiftUI

// MARK: - DeckProgressView

/// Displays a segmented progress bar and legend for card learning states,
/// plus a row of quick aggregate stats (due count, accuracy, review count).
///
/// Accepts pre-computed values from `DeckViewModel`; it does **not** read
/// `[GridCardInfo]` or perform any filtering/counting internally.
struct DeckProgressView: View {

    // MARK: - Inputs

    /// Pre-computed progress breakdown from `DeckViewModel.progressStats`.
    let progress: DeckProgressStats
    /// Aggregate spaced-repetition stats from `DeckViewModel.currentStats`.
    let stats: DeckStats
    /// Total number of cards in the deck (used to animate the bar on count changes).
    let deckCardCount: Int

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            // Section header matching the standard iOS HIG caption style.
            Text("DECK PROGRESS")
                .font(.caption.weight(.heavy))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, UIConstants.Layout.heroScreenEdgeInset)

            VStack(spacing: 24) {

                // MARK: Segmented Progress Bar
                GeometryReader { geo in
                    HStack(spacing: 6) {
                        if progress.masteredCards > 0 {
                            Capsule()
                                .fill(Color.teal.gradient)
                                .frame(width: max(0, geo.size.width * progress.masteredRatio - 6))
                        }
                        if progress.learningCards > 0 {
                            Capsule()
                                .fill(Color.orange.gradient)
                                .frame(width: max(0, geo.size.width * progress.learningRatio - 6))
                        }
                        if progress.newCards > 0 {
                            Capsule()
                                .fill(Color.secondary.opacity(0.15))
                                .frame(width: max(0, geo.size.width * progress.newRatio - 6))
                        }
                    }
                }
                .frame(height: 16)
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: deckCardCount)

                // MARK: Legend
                HStack(spacing: 0) {
                    LegendItem(color: .teal,             count: progress.masteredCards, label: "Mastered")
                    Spacer()
                    LegendItem(color: .orange,           count: progress.learningCards, label: "Learning")
                    Spacer()
                    LegendItem(color: .gray.opacity(0.5), count: progress.newCards,     label: "New")
                }

                Divider()
                    .overlay(.white.opacity(0.05))

                // MARK: Quick Stats Row
                HStack {
                    QuickStat(title: "Due Today", value: "\(stats.dueCards)",    color: stats.dueCards > 0 ? .red : .primary)
                    Spacer()
                    QuickStat(title: "Accuracy",  value: "\(stats.accuracy)%",  color: .primary)
                    Spacer()
                    QuickStat(title: "Reviews",   value: "\(stats.totalReviews)", color: .primary)
                }
            }
            .padding(24)
            .widgetStyle()
            .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
        }
    }
}

// MARK: - Private Subcomponents

/// A single coloured dot + count + label row used in the progress legend.
private struct LegendItem: View {
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

/// A large-value + caption label used in the quick-stats row.
private struct QuickStat: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}
