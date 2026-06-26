//
//  DeckProgressView.swift
//  QuizFlash
//
//  Deck-detail summary surface showing progress, quick stats, and
//  the current day's reviewed-card outcomes for the visible deck.
//

import SwiftUI

// MARK: - DeckProgressView

/// Displays the deck's learning breakdown and quick aggregate stats.
///
/// All inputs are pre-computed by `DeckViewModel` and `CardFetchActor`.
/// The view remains rendering-only and performs no data fetching.
struct DeckProgressView: View {
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager

    // MARK: - Inputs

    let progress: DeckProgressStats
    let stats: DeckStats
    let activity: DeckTodayActivitySummary
    let deckTint: Color

    private var dueTint: Color {
        stats.dueCards > 0 ? themeManager.roleColor(.buttonDangerFill) : deckTint
    }

    private var locale: Locale { appPreferences.resolvedLocale }

    private func localized(_ value: String.LocalizationValue) -> String {
        AppLocalization.string(value, locale: locale)
    }

    private var summaryValueText: String {
        activity.uniqueCardsReviewed == 0 ? localized("No") : "\(activity.uniqueCardsReviewed)"
    }

    private var summaryLabelText: String {
        if activity.uniqueCardsReviewed == 0 {
            return localized("moves")
        }
        return activity.uniqueCardsReviewed == 1 ? localized("card moved") : localized("cards moved")
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 14) {
            summarySeparator
            primarySummaryBlock
            metricsBlock
        }
        .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
    }

    private var summarySeparator: some View {
        AppSectionSeparator()
            .padding(.bottom, 2)
    }

    private var primarySummaryBlock: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text(summaryValueText)
                    .font(.system(size: 56, weight: .black))
                    .foregroundStyle(themeManager.textPrimary)

                Text(summaryLabelText)
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(themeManager.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .transaction { transaction in
                transaction.animation = nil
            }

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
                title: localized("Due"),
                value: "\(stats.dueCards)",
                tint: dueTint
            )

            DeckMetricTile(
                highlight: deckTint,
                title: localized("Accuracy"),
                value: "\(stats.accuracy)%",
                tint: themeManager.textPrimary
            )

            DeckMetricTile(
                highlight: deckTint,
                title: localized("Reviews"),
                value: "\(stats.totalReviews)",
                tint: deckTint
            )
        }
        .padding(.top, 2)
        .transaction { transaction in
            transaction.animation = nil
        }
    }

}

// MARK: - Supporting Views

private struct DeckProgressSurface<Content: View>: View {
    let highlight: Color
    let cornerRadius: CGFloat
    let contentPadding: CGFloat
    let content: Content

    init(
        highlight: Color,
        cornerRadius: CGFloat = 30,
        contentPadding: CGFloat = 20,
        @ViewBuilder content: () -> Content
    ) {
        self.highlight = highlight
        self.cornerRadius = cornerRadius
        self.contentPadding = contentPadding
        self.content = content()
    }

    var body: some View {
        content
            .padding(contentPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .duoSurface(cornerRadius: cornerRadius, tint: highlight)
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
            cornerRadius: 24,
            contentPadding: 10
        ) {
            VStack(spacing: 5) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.system(size: 26, weight: .black))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .center)
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
