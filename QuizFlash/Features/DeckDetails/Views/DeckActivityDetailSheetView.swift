//
//  DeckActivityDetailSheetView.swift
//  QuizFlash
//
//  Custom-sheet detail surface for grouped deck review activity.
//

import SwiftUI

struct DeckActivityDetailSheetView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.fullScreenSheetDismiss) private var fullScreenSheetDismiss

    let summary: DeckActivityHistorySummary
    let deckTint: Color
    let safeAreaInsets: UIEdgeInsets

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
            .padding(.top, UIConstants.Spacing.extraLarge)
            .padding(.bottom, safeAreaInsets.bottom + UIConstants.Spacing.extraLarge)
        }
        .fullScreenSheetDragActivationHeight(180)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            HStack(alignment: .top, spacing: UIConstants.Spacing.medium) {
                VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                    Text("Activity")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(themeManager.textPrimary)

                    if summary.hasActivity {
                        Text("\(summary.totalRawReviewCount) passes • \(summary.totalActiveDays) days")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(themeManager.textSecondary)
                    }
                }

                Spacer(minLength: 0)

                if let fullScreenSheetDismiss {
                    Button {
                        fullScreenSheetDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(themeManager.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptySection: some View {
        DeckActivitySheetSurface {
            Text("No activity yet")
                .font(.system(size: 18, weight: .bold, design: .rounded))
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

    let day: DeckActivityDaySummary
    let deckTint: Color

    var body: some View {
        DeckActivitySheetSurface {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
                VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                    Text(day.activityLabel)
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(themeManager.textPrimary)

                    Text(summaryLine)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
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
        var parts = [
            "\(day.uniqueCardsReviewed) card" + (day.uniqueCardsReviewed == 1 ? "" : "s"),
            "\(day.rawReviewCount) pass" + (day.rawReviewCount == 1 ? "" : "es")
        ]

        if day.retryCount > 0 {
            parts.append("\(day.retryCount) " + (day.retryCount == 1 ? "retry" : "retries"))
        }

        return parts.joined(separator: " • ")
    }
}

private struct DeckActivitySheetSurface<Content: View>: View {
    @Environment(ThemeManager.self) private var themeManager

    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(UIConstants.Spacing.large)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(themeManager.roleColor(.widgetSurfaceFill))
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.035), lineWidth: 1)
                    }
            }
    }
}

private struct DeckActivityPill: View {
    @Environment(ThemeManager.self) private var themeManager

    let text: String
    let tint: Color
    let backgroundTint: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                Capsule(style: .continuous)
                    .fill(themeManager.surfacePrimary)
                    .overlay {
                        Capsule(style: .continuous)
                            .fill(backgroundTint)
                    }
            }
    }
}

private struct DeckActivityCardRow: View {
    @Environment(ThemeManager.self) private var themeManager

    let card: DeckTodayReviewedCardSummary
    let goodTint: Color

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(outcomeTint.opacity(0.92))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(card.title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(themeManager.textPrimary)
                    .lineLimit(1)

                Text("\(card.reviewCount) pass" + (card.reviewCount == 1 ? "" : "es"))
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
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(themeManager.surfacePrimary)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(outcomeTint.opacity(0.08))
                }
        }
    }

    private var outcomeLabel: String {
        switch card.finalDifficulty {
        case .again:
            return "Retry"
        case .hard:
            return "Hard"
        case .good:
            return "Good"
        case .easy:
            return "Easy"
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
