// HomeStatsView.swift
// QuizFlash
//
// Reusable analytics card components for the Home dashboard.

import SwiftUI

// MARK: - Home Analytics Hero

/// Premium analytics hero for the Home dashboard, focused on the selected day.
struct HomeAnalyticsHeroCard: View {
    private let narrativeColumnMinHeight: CGFloat = 192
    private let metricRowHeight: CGFloat = 118
    private let cardMinHeight: CGFloat = 342

    // MARK: - Input

    let overview: HomeSelectedDayOverviewSummary
    let weeklyMomentum: HomeWeeklyMomentumSummary

    // MARK: - Derived State

    private var accentColor: Color {
        ThemeManager.shared.accentColor.color
    }

    private var completionTint: Color {
        overview.didReachGoal ? .green : accentColor
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(overview.selectedDateLabel)
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background {
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                        }

                    Text(overview.headline)
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineSpacing(-2)
                        .lineLimit(3)
                        .minimumScaleFactor(0.82)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(overview.detailLine)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: narrativeColumnMinHeight, alignment: .topLeading)

                Spacer(minLength: 0)

                AnimatedProgressRing(
                    progress: overview.goalCompletionFraction,
                    trackColor: Color.primary.opacity(0.10),
                    progressColor: completionTint,
                    size: 108,
                    strokeWidth: 12
                ) { _ in
                    VStack(spacing: 2) {
                        Text("\(overview.cardsReviewed)")
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .foregroundStyle(.primary)
                            .statusTextMotion(trigger: overview.cardsReviewed)

                        Text("/\(overview.dailyGoal)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .statusTextMotion(trigger: overview.dailyGoal)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: narrativeColumnMinHeight, alignment: .top)

            HStack(spacing: 12) {
                HomeHeroMetricTile(
                    title: "Level",
                    value: "\(overview.level)",
                    detail: "\(overview.totalXP) XP",
                    tint: .blue
                )

                HomeHeroMetricTile(
                    title: "To Goal",
                    value: overview.didReachGoal ? "Done" : "\(overview.remainingCardsToGoal)",
                    detail: overview.didReachGoal ? "Target cleared" : "cards left",
                    tint: completionTint
                )

                HomeHeroMetricTile(
                    title: "Week",
                    value: "\(weeklyMomentum.activeDays)/7",
                    detail: weeklyMomentum.goalHitDays == 0 ? "active days" : "\(weeklyMomentum.goalHitDays) goal hits",
                    tint: .orange
                )
            }
            .frame(height: metricRowHeight, alignment: .top)
        }
        .frame(maxWidth: .infinity, minHeight: cardMinHeight, alignment: .topLeading)
        .padding(20)
        .widgetStyle(cornerRadius: 30)
    }
}

// MARK: - Weekly Momentum Card

/// Compact 7-day momentum card that mirrors the current study rhythm.
struct HomeWeeklyMomentumCard: View {

    // MARK: - Input

    let summary: HomeWeeklyMomentumSummary

    // MARK: - Derived State

    private var accentColor: Color {
        ThemeManager.shared.accentColor.color
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Weekly Momentum")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(.primary)

                    Text(summary.headline)
                        .font(.system(.title3, design: .rounded, weight: .heavy))
                        .foregroundStyle(.primary)
                }

                Spacer()

                Text(summary.consistencyFraction, format: .percent.precision(.fractionLength(0)))
                    .font(.system(.headline, design: .rounded, weight: .heavy))
                    .foregroundStyle(accentColor)
                    .statusTextMotion(trigger: summary.goalHitDays)
            }

            Text(summary.detailLine)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(minHeight: 44, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .bottom, spacing: 10) {
                ForEach(summary.daySummaries) { day in
                    HomeWeeklyMomentumBar(day: day, accentColor: accentColor)
                }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 12) {
                HomeInlineStatPill(
                    label: "Cards",
                    value: "\(summary.totalCardsReviewed)",
                    tint: accentColor,
                    animatesValue: true
                )
                HomeInlineStatPill(
                    label: "XP",
                    value: "\(summary.totalXPEarned)",
                    tint: .orange,
                    animatesValue: true
                )

                if let bestDayLabel = summary.bestDayLabel {
                    HomeInlineStatPill(
                        label: "Best",
                        value: bestDayLabel,
                        tint: .green
                    )
                }
            }
        }
        .padding(18)
        .widgetStyle(cornerRadius: 26)
    }
}

// MARK: - Selected Day Insights

/// Action-oriented card that tells the user what the selected day means and what to do next.
struct HomeSelectedDayInsightsCard: View {
    let summary: HomeSelectedDayInsightSummary

    private var accentColor: Color {
        ThemeManager.shared.accentColor.color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Selected Day Insights")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(.primary)

                    Text(summary.headline)
                        .font(.system(.title3, design: .rounded, weight: .heavy))
                        .foregroundStyle(.primary)
                }

                Spacer()

                Text(summary.selectedDayExamCount == 0 ? "Open" : "\(summary.selectedDayExamCount) goals")
                    .font(.caption.weight(.black))
                    .foregroundStyle(summary.selectedDayExamCount == 0 ? .secondary : accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background((summary.selectedDayExamCount == 0 ? Color.primary : accentColor).opacity(0.10), in: Capsule())
            }

            Text(summary.detailLine)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(minHeight: 48, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                HomeInsightLine(icon: "bolt.fill", text: summary.recommendationLine, tint: accentColor)
                HomeInsightLine(icon: "waveform.path.ecg", text: summary.paceLine, tint: .orange)
                HomeInsightLine(icon: "calendar.badge.clock", text: summary.examContextLine, tint: .blue)
            }

            HStack(spacing: 12) {
                HomeInlineStatPill(label: "XP", value: "\(summary.xpEarned)", tint: .orange)
                HomeInlineStatPill(label: "New", value: "\(summary.newCardsLearned)", tint: .purple)
                HomeInlineStatPill(label: "Goals", value: "\(summary.selectedDayExamCount)", tint: accentColor)
            }
        }
        .padding(18)
        .widgetStyle(cornerRadius: 26)
    }
}

// MARK: - Hero Support Views

private struct HomeHeroMetricTile: View {
    let title: String
    let value: String
    let detail: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(value)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .statusTextMotion(trigger: value)

            Text(detail)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 118, maxHeight: 118, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(tint.opacity(0.12))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        }
    }
}

private struct HomeWeeklyMomentumBar: View {
    let day: HomeWeeklyDaySummary
    let accentColor: Color

    private var fillColor: Color {
        if day.didReachGoal { return .green }
        if day.isSelectedDay { return accentColor }
        if day.didStudy { return accentColor.opacity(0.65) }
        return .secondary.opacity(0.22)
    }

    private var barHeight: CGFloat {
        let baseHeight: CGFloat = 22
        let variableHeight: CGFloat = 42
        return baseHeight + (variableHeight * day.intensityFraction)
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(day.shortWeekday)
                .font(.caption2.weight(.bold))
                .foregroundStyle(day.isSelectedDay ? .primary : .secondary)

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(fillColor)
                .frame(width: 28, height: barHeight)
                .overlay(alignment: .bottom) {
                    if day.isSelectedDay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.35), lineWidth: 1)
                    }
                }

            Text("\(day.cardsReviewed)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct HomeInlineStatPill: View {
    let label: String
    let value: String
    let tint: Color
    var animatesValue = false

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.caption.weight(.heavy))
                .foregroundStyle(tint)
                .lineLimit(1)
                .modifier(HomeOptionalStatusTextMotion(isEnabled: animatesValue, trigger: value))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(Color.primary.opacity(0.06))
        }
    }
}

private struct HomeOptionalStatusTextMotion<Trigger: Equatable>: ViewModifier {
    let isEnabled: Bool
    let trigger: Trigger

    func body(content: Content) -> some View {
        if isEnabled {
            content.statusTextMotion(trigger: trigger)
        } else {
            content
        }
    }
}

private struct HomeInsightLine: View {
    let icon: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 18, height: 18)
                .padding(6)
                .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
