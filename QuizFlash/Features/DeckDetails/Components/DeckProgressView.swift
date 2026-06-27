//
//  DeckProgressView.swift
//  QuizFlash
//
//  Deck-detail summary surface showing accuracy and learning progress
//  for the visible deck.
//

import SwiftUI

// MARK: - DeckProgressView

/// Displays the deck's learning breakdown and accuracy summary.
///
/// All inputs are pre-computed by `DeckViewModel` and `CardFetchActor`.
/// The view remains rendering-only and performs no data fetching.
struct DeckProgressView: View {
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager

    // MARK: - Inputs

    let stats: DeckStats
    let deckTint: Color

    private var locale: Locale { appPreferences.resolvedLocale }

    private func localized(_ value: String.LocalizationValue) -> String {
        AppLocalization.string(value, locale: locale)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 14) {
            summarySeparator
            progressSummaryBlock
        }
        .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
    }

    private var summarySeparator: some View {
        AppSectionSeparator()
            .padding(.bottom, 2)
    }

    private var progressSummaryBlock: some View {
        HStack(alignment: .center, spacing: 28) {
            accuracySummary
                .frame(maxWidth: .infinity, alignment: .leading)
            DeckIntegratedMasteryRing(
                mastery: stats.deckMastery,
                deckTint: deckTint,
                progressTitle: localized("Progress")
            )
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var accuracySummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(localized("Accuracy"))
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(themeManager.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.76)

            Text("\(stats.accuracy)%")
                .font(.system(size: 52, weight: .black))
                .foregroundStyle(themeManager.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText(value: Double(stats.accuracy)))
        }
        .multilineTextAlignment(.leading)
    }
}

private struct DeckIntegratedMasteryRing: View {
    let mastery: Double
    let deckTint: Color
    let progressTitle: String

    var body: some View {
        AnimatedProgressRing(
            progress: mastery,
            trackColor: deckTint.opacity(0.2),
            progressColor: masteryColor(mastery),
            size: 144,
            strokeWidth: 14
        ) { animatedProgress in
            VStack(spacing: 4) {
                Text("\(Int(animatedProgress * 100))%")
                    .font(.system(size: 30, weight: .black))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText(value: animatedProgress * 100))

                Text(progressTitle)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: 96)
            .multilineTextAlignment(.center)
        }
        .frame(width: 144, height: 144)
    }
}
