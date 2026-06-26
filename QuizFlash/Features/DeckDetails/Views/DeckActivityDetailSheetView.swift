//
//  DeckActivityDetailSheetView.swift
//  QuizFlash
//
//  Custom-sheet detail surface for grouped deck review activity.
//

import SwiftUI

struct DeckActivityDetailSheetView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(\.fullScreenSheetTopChromeClearance) private var topChromeClearance

    let summary: DeckActivityHistorySummary
    let deckTint: Color
    let safeAreaInsets: UIEdgeInsets

    private var locale: Locale { appPreferences.resolvedLocale }
    private var headerTrailingReserve: CGFloat { 76 }
    private var contentTopPadding: CGFloat {
        max(topChromeClearance, UIConstants.Spacing.medium)
    }

    private func localized(_ value: String.LocalizationValue) -> String {
        AppLocalization.string(value, locale: locale)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: UIConstants.Spacing.large) {
                headerSection

                if summary.hasActivity {
                    ForEach(summary.daySummaries) { day in
                        DeckActivityDaySection(
                            day: day,
                            deckTint: deckTint
                        )
                    }
                } else {
                    emptySection
                }
            }
            .padding(.horizontal, UIConstants.Spacing.large)
            .padding(.top, contentTopPadding)
            .padding(.bottom, safeAreaInsets.bottom + UIConstants.Spacing.extraLarge)
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            Text(localized("Activity"))
                .font(.system(size: 28, weight: .black))
                .foregroundStyle(themeManager.textPrimary)

            if summary.hasActivity {
                Text(activitySummaryLine)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(themeManager.textSecondary)
            }
        }
        .padding(.trailing, headerTrailingReserve)
    }

    private var activitySummaryLine: String {
        let passes = AppLocalization.numbered(
            summary.totalRawReviewCount,
            singular: "%d pass",
            plural: "%d passes",
            locale: locale
        )
        let days = AppLocalization.numbered(
            summary.totalActiveDays,
            singular: "%d day",
            plural: "%d days",
            locale: locale
        )
        return "\(passes) • \(days)"
    }

    private var emptySection: some View {
        DeckActivitySheetSurface {
            Text(localized("No activity yet"))
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(themeManager.textSecondary)
        }
    }
}

struct DeckActivitySheetBackground: View {
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        themeManager.groupedScreenBackground
    }
}

private struct DeckActivityDaySection: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AppPreferences.self) private var appPreferences

    let day: DeckActivityDaySummary
    let deckTint: Color

    private var locale: Locale { appPreferences.resolvedLocale }

    var body: some View {
        DeckActivitySheetSurface {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
                VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                    Text(day.activityLabel)
                        .font(.system(size: 22, weight: .black))
                        .foregroundStyle(themeManager.textPrimary)

                    Text(summaryLine)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(themeManager.textSecondary)
                }

                LazyVStack(spacing: UIConstants.Spacing.small) {
                    ForEach(day.cards) { card in
                        DeckActivityCardRow(
                            card: card,
                            goodTint: deckTint
                        )
                    }
                }
            }
        }
    }

    private var summaryLine: String {
        let cards = AppLocalization.numbered(
            day.uniqueCardsReviewed,
            singular: "%d card",
            plural: "%d cards",
            locale: locale
        )
        let passes = AppLocalization.numbered(
            day.rawReviewCount,
            singular: "%d pass",
            plural: "%d passes",
            locale: locale
        )
        var parts = [
            cards,
            passes
        ]

        if day.retryCount > 0 {
            parts.append(
                AppLocalization.numbered(
                    day.retryCount,
                    singular: "%d retry",
                    plural: "%d retries",
                    locale: locale
                )
            )
        }

        return parts.joined(separator: " • ")
    }
}

private struct DeckActivitySheetSurface<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(UIConstants.Spacing.large)
            .frame(maxWidth: .infinity, alignment: .leading)
            .duoSurface(cornerRadius: 28)
    }
}

private struct DeckActivityPill: View {
    let text: String
    let tint: Color
    let backgroundTint: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .duoMetricPill(tint: tint)
            .background(backgroundTint, in: Capsule(style: .continuous))
    }
}

private struct DeckActivityCardRow: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AppPreferences.self) private var appPreferences

    let card: DeckTodayReviewedCardSummary
    let goodTint: Color

    private var locale: Locale { appPreferences.resolvedLocale }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(outcomeTint.opacity(0.92))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(card.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(themeManager.textPrimary)
                    .lineLimit(1)

                Text(reviewCountLine)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(themeManager.textSecondary)
            }

            Spacer(minLength: 0)

            DeckActivityPill(
                text: outcomeLabel,
                tint: outcomeTint,
                backgroundTint: outcomeTint.opacity(0.18)
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .duoControlSurface(cornerRadius: 22, tint: outcomeTint)
    }

    private var reviewCountLine: String {
        AppLocalization.numbered(
            card.reviewCount,
            singular: "%d pass",
            plural: "%d passes",
            locale: locale
        )
    }

    private var outcomeLabel: String {
        switch card.finalDifficulty {
        case .again:
            return AppLocalization.string("Retry", locale: locale)
        case .hard:
            return AppLocalization.string("Hard", locale: locale)
        case .good:
            return AppLocalization.string("Good", locale: locale)
        case .easy:
            return AppLocalization.string("Easy", locale: locale)
        }
    }

    private var outcomeTint: Color {
        switch card.finalDifficulty {
        case .again:
            return themeManager.roleColor(.buttonDangerFill)
        case .hard:
            return .orange
        case .good:
            return goodTint
        case .easy:
            return .green
        }
    }
}
