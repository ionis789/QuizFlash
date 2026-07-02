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
    var horizontalInset: CGFloat = UIConstants.Layout.screenEdgeInset

    @State private var displayedAccuracy = 0
    @State private var displayedMastery = 0.0

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
        .padding(.horizontal, horizontalInset)
        .onAppear {
            animateDisplayedStats()
        }
        .onChange(of: stats.accuracy) { _, newValue in
            withAnimation(.selectionToolbarSpring) {
                displayedAccuracy = newValue
            }
        }
        .onChange(of: stats.deckMastery) { _, newValue in
            displayedMastery = newValue
        }
    }

    private var summarySeparator: some View {
        AppSectionSeparator()
            .padding(.bottom, 2)
    }

    private var progressSummaryBlock: some View {
        HStack(alignment: .center, spacing: 28) {
            accuracySummary
                .frame(maxWidth: .infinity, alignment: .center)
            DeckIntegratedMasteryRing(
                mastery: displayedMastery,
                deckTint: deckTint,
                progressTitle: localized("Progress")
            )
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
    }

    private var accuracySummary: some View {
        VStack(alignment: .center, spacing: 6) {
            Text(localized("Accuracy"))
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(themeManager.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.76)

            Text("\(displayedAccuracy)%")
                .font(.system(size: 52, weight: .black))
                .foregroundStyle(themeManager.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .statusTextMotion(trigger: displayedAccuracy)
        }
        .multilineTextAlignment(.center)
    }

    private func animateDisplayedStats() {
        withAnimation(.selectionToolbarSpring) {
            displayedAccuracy = stats.accuracy
        }
        displayedMastery = stats.deckMastery
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
            let progressPercent = Int(animatedProgress * 100)
            VStack(spacing: 4) {
                Text("\(progressPercent)%")
                    .font(.system(size: 30, weight: .black))
                    .foregroundStyle(.primary)
                    .statusTextMotion(trigger: progressPercent)

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
