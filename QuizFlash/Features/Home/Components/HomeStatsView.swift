// HomeStatsView.swift
// QuizFlash
//
// Reusable analytics card components for the Home dashboard.

import SwiftUI

// MARK: - Home Calendar Overview Card

/// Dense iPad-oriented summary card shown next to the Home calendar.
struct HomeCalendarOverviewCard: View {
    @Environment(ThemeManager.self) private var themeManager

    let overview: HomeSelectedDayOverviewSummary
    let weeklyMomentum: HomeWeeklyMomentumSummary
    let layoutMode: HomeLayoutMode

    private var accentColor: Color {
        themeManager.accentColor.color
    }

    private var completionTint: Color {
        overview.didReachGoal ? .green : accentColor
    }

    private var usesRegularMetrics: Bool {
        layoutMode.usesRegularMetrics
    }

    private var utilityHeadline: String {
        if overview.didReachGoal {
            return "Day closed"
        }
        if overview.cardsReviewed == 0 {
            return "Fresh study window"
        }
        if !overview.hasGoal {
            return "\(overview.cardsReviewed) cards reviewed"
        }
        return "\(overview.remainingCardsToGoal) cards to goal"
    }

    private var utilityDetail: String {
        if overview.didReachGoal {
            return "Today's target is complete. You can use the slot to review weak cards."
        }
        return overview.detailLine
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(overview.selectedDateLabel)
                        .font(.caption.weight(.black))
                        .foregroundStyle(themeManager.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                        }

                    Text(utilityHeadline)
                        .font(.system(size: usesRegularMetrics ? 22 : 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(themeManager.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)

                    Text(utilityDetail)
                        .font(.system(size: usesRegularMetrics ? 15 : 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(themeManager.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if overview.hasGoal {
                    AnimatedProgressRing(
                        progress: overview.goalCompletionFraction,
                        trackColor: themeManager.textPrimary.opacity(0.10),
                        progressColor: completionTint,
                        size: usesRegularMetrics ? 84 : 88,
                        strokeWidth: 10
                    ) { _ in
                        VStack(spacing: 2) {
                            Text(overview.didReachGoal ? "Done" : "\(overview.remainingCardsToGoal)")
                                .font(.system(size: 22, weight: .heavy, design: .rounded))
                                .foregroundStyle(themeManager.textPrimary)

                            Text(overview.didReachGoal ? "Today" : "To goal")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(themeManager.textSecondary)
                        }
                    }
                }
            }

            HStack(spacing: usesRegularMetrics ? 8 : 10) {
                HomeCalendarCompactMetricTile(
                    title: "XP",
                    value: "\(overview.totalXP)",
                    detail: "\(overview.xpEarnedToday) XP",
                    tint: .blue,
                    usesRegularMetrics: usesRegularMetrics
                )

                HomeCalendarCompactMetricTile(
                    title: "Cards",
                    value: "\(overview.cardsReviewed)",
                    detail: overview.hasGoal
                        ? (overview.didReachGoal ? "target hit" : "\(overview.dailyGoal ?? 0) goal")
                        : "reviewed",
                    tint: completionTint,
                    usesRegularMetrics: usesRegularMetrics
                )

                HomeCalendarCompactMetricTile(
                    title: "Week",
                    value: "\(weeklyMomentum.activeDays)/7",
                    detail: weeklyMomentum.goalHitDays == 0 ? "active days" : "\(weeklyMomentum.goalHitDays) hits",
                    tint: .orange,
                    usesRegularMetrics: usesRegularMetrics
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(usesRegularMetrics ? 16 : 18)
        .flashcardStyle(cornerRadius: 28, surfaceRole: .widget)
    }
}

// MARK: - Home Calendar Setup Card

/// Compact onboarding companion shown next to the iPad calendar before any deck exists.
struct HomeCalendarSetupCard: View {
    @Environment(ThemeManager.self) private var themeManager

    let folderCount: Int

    private var accentColor: Color {
        themeManager.accentColor.color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Getting Started")
                .font(.caption.weight(.black))
                .foregroundStyle(themeManager.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                }

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Create your first deck")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(themeManager.textPrimary)
                        .lineLimit(2)

                    Text("Once you add a deck, this area will turn into a live study snapshot with progress and calendar cues.")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(themeManager.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(accentColor.opacity(0.14))
                    .frame(width: 72, height: 72)
                    .overlay {
                        Image(systemName: "rectangle.stack.badge.plus")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(accentColor)
                    }
            }

            HStack(spacing: 10) {
                HomeInlineStatPill(
                    label: "Next",
                    value: "Create deck",
                    tint: accentColor
                )

                if folderCount > 0 {
                    HomeInlineStatPill(
                        label: "Folders",
                        value: "\(folderCount)",
                        tint: .orange
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .flashcardStyle(cornerRadius: 28, surfaceRole: .widget)
    }
}

// MARK: - Workspace Prompt Card

/// General onboarding prompt used when Home should guide the user instead of showing empty analytics.
struct HomeWorkspacePromptCard: View {
    let eyebrow: String
    let title: String
    let detail: String
    let icon: String
    let tint: Color
    let usesRegularMetrics: Bool
    let buttonTitle: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(tint.opacity(0.14))
                    .frame(width: 58, height: 58)
                    .overlay {
                        Image(systemName: icon)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(tint)
                    }

                VStack(alignment: .leading, spacing: 6) {
                    Text(eyebrow)
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)

                    Text(title)
                        .font(.system(.title3, design: .rounded, weight: .heavy))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(detail)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if let buttonTitle, let action {
                Button(action: action) {
                    Text(buttonTitle)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: UIConstants.Size.buttonHeight)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, minHeight: usesRegularMetrics ? 234 : 0, alignment: .topLeading)
        .padding(usesRegularMetrics ? 20 : 18)
        .flashcardStyle(cornerRadius: 26, surfaceRole: .widget)
    }
}

// MARK: - Home Analytics Hero

/// Premium analytics hero for the Home dashboard, focused on the selected day.
struct HomeAnalyticsHeroCard: View {
    // MARK: - Input

    let overview: HomeSelectedDayOverviewSummary
    let weeklyMomentum: HomeWeeklyMomentumSummary
    let usesRegularMetrics: Bool

    // MARK: - Derived State

    private var accentColor: Color {
        ThemeManager.shared.accentColor.color
    }

    private var completionTint: Color {
        overview.didReachGoal ? .green : accentColor
    }

    private var narrativeColumnMinHeight: CGFloat {
        usesRegularMetrics ? 192 : 164
    }

    private var metricRowHeight: CGFloat {
        usesRegularMetrics ? 118 : 108
    }

    private var cardMinHeight: CGFloat {
        usesRegularMetrics ? 342 : 300
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
                        .font(.system(size: usesRegularMetrics ? 32 : 28, weight: .heavy, design: .rounded))
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

                if overview.hasGoal {
                    AnimatedProgressRing(
                        progress: overview.goalCompletionFraction,
                        trackColor: Color.primary.opacity(0.10),
                        progressColor: completionTint,
                        size: usesRegularMetrics ? 108 : 92,
                        strokeWidth: 12
                    ) { _ in
                        VStack(spacing: 2) {
                            Text("\(overview.cardsReviewed)")
                                .font(.system(size: usesRegularMetrics ? 26 : 22, weight: .heavy, design: .rounded))
                                .foregroundStyle(.primary)
                                .statusTextMotion(trigger: overview.cardsReviewed)

                            Text("/\(overview.dailyGoal ?? 0)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                                .statusTextMotion(trigger: overview.dailyGoal ?? 0)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: narrativeColumnMinHeight, alignment: .top)

            HStack(spacing: 12) {
                HomeHeroMetricTile(
                    title: "XP",
                    value: "\(overview.totalXP)",
                    detail: "\(overview.xpEarnedToday) today",
                    tint: .blue
                )

                HomeHeroMetricTile(
                    title: overview.hasGoal ? "To Goal" : "Reviewed",
                    value: overview.hasGoal
                        ? (overview.didReachGoal ? "Done" : "\(overview.remainingCardsToGoal)")
                        : "\(overview.cardsReviewed)",
                    detail: overview.hasGoal
                        ? (overview.didReachGoal ? "Target cleared" : "cards left")
                        : "cards",
                    tint: completionTint
                )

                HomeHeroMetricTile(
                    title: "Week",
                    value: "\(weeklyMomentum.activeDays)/7",
                    detail: overview.hasGoal && weeklyMomentum.goalHitDays > 0
                        ? "\(weeklyMomentum.goalHitDays) goal hits"
                        : "active days",
                    tint: .orange
                )
            }
            .frame(height: metricRowHeight, alignment: .top)
        }
        .frame(maxWidth: .infinity, minHeight: cardMinHeight, alignment: .topLeading)
        .padding(usesRegularMetrics ? 20 : 18)
        .flashcardStyle(cornerRadius: 30, surfaceRole: .widget)
    }
}

// MARK: - Weekly Momentum Card

/// Compact 7-day momentum card that mirrors the current study rhythm.
struct HomeWeeklyMomentumCard: View {
    @Environment(ThemeManager.self) private var themeManager

    // MARK: - Input

    let summary: HomeWeeklyMomentumSummary
    let usesRegularMetrics: Bool

    // MARK: - Derived State

    private var accentColor: Color {
        themeManager.accentColor.color
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Weekly Momentum")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(themeManager.textPrimary)

                    Text(summary.headline)
                        .font(.system(.title3, design: .rounded, weight: .heavy))
                        .foregroundStyle(themeManager.textPrimary)
                }

                Spacer()

                Text(summary.consistencyFraction, format: .percent.precision(.fractionLength(0)))
                    .font(.system(.headline, design: .rounded, weight: .heavy))
                    .foregroundStyle(accentColor)
                    .statusTextMotion(trigger: summary.goalHitDays)
            }

            HStack(alignment: .bottom, spacing: 10) {
                ForEach(summary.daySummaries) { day in
                    HomeWeeklyMomentumBar(
                        day: day,
                        accentColor: accentColor,
                        usesRegularMetrics: usesRegularMetrics
                    )
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
        .frame(maxWidth: .infinity, minHeight: usesRegularMetrics ? 306 : 0, alignment: .topLeading)
        .padding(usesRegularMetrics ? 20 : 18)
        .flashcardStyle(cornerRadius: 26, surfaceRole: .widget)
    }
}

// MARK: - Selected Day Insights

/// Action-oriented card that tells the user what the selected day means and what to do next.
struct HomeSelectedDayInsightsCard: View {
    @Environment(ThemeManager.self) private var themeManager

    let summary: HomeSelectedDayInsightSummary
    let usesRegularMetrics: Bool

    private var accentColor: Color {
        themeManager.accentColor.color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Selected Day Insights")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(themeManager.textPrimary)

                    Text(summary.headline)
                        .font(.system(.title3, design: .rounded, weight: .heavy))
                        .foregroundStyle(themeManager.textPrimary)
                }

                Spacer()

                Text(summary.xpEarned == 0 ? "Open" : "\(summary.xpEarned) XP")
                    .font(.caption.weight(.black))
                    .foregroundStyle(summary.xpEarned == 0 ? themeManager.textSecondary : accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background((summary.xpEarned == 0 ? themeManager.textPrimary : accentColor).opacity(0.10), in: Capsule())
            }

            Text(summary.detailLine)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(themeManager.textSecondary)
                .frame(minHeight: usesRegularMetrics ? 56 : 48, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                HomeInsightLine(icon: "bolt.fill", text: summary.recommendationLine, tint: accentColor)
                HomeInsightLine(icon: "waveform.path.ecg", text: summary.paceLine, tint: .orange)
            }

            HStack(spacing: 12) {
                HomeInlineStatPill(label: "XP", value: "\(summary.xpEarned)", tint: .orange)
                HomeInlineStatPill(label: "New", value: "\(summary.newCardsLearned)", tint: .purple)
                HomeInlineStatPill(label: "Pace", value: summary.xpEarned == 0 ? "Open" : "Active", tint: accentColor)
            }
        }
        .frame(maxWidth: .infinity, minHeight: usesRegularMetrics ? 306 : 0, alignment: .topLeading)
        .padding(usesRegularMetrics ? 20 : 18)
        .flashcardStyle(cornerRadius: 26, surfaceRole: .widget)
    }
}

// MARK: - Hero Support Views

private struct HomeHeroMetricTile: View {
    @Environment(ThemeManager.self) private var themeManager

    let title: String
    let value: String
    let detail: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(themeManager.textSecondary)
                .textCase(.uppercase)

            Text(value)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(themeManager.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .statusTextMotion(trigger: value)

            Text(detail)
                .font(.caption.weight(.medium))
                .foregroundStyle(themeManager.textSecondary)
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

private struct HomeOverviewMiniTile: View {
    @Environment(ThemeManager.self) private var themeManager

    let title: String
    let value: String
    let detail: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(themeManager.textSecondary)
                .textCase(.uppercase)

            Text(value)
                .font(.system(size: 21, weight: .heavy, design: .rounded))
                .foregroundStyle(themeManager.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Text(detail)
                .font(.caption.weight(.medium))
                .foregroundStyle(themeManager.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(tint.opacity(0.12))
        }
    }
}

private struct HomeCalendarCompactMetricTile: View {
    @Environment(ThemeManager.self) private var themeManager

    let title: String
    let value: String
    let detail: String
    let tint: Color
    let usesRegularMetrics: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(themeManager.textSecondary)
                .textCase(.uppercase)

            Text(value)
                .font(.system(size: usesRegularMetrics ? 18 : 19, weight: .heavy, design: .rounded))
                .foregroundStyle(themeManager.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(detail)
                .font(.caption.weight(.medium))
                .foregroundStyle(themeManager.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, usesRegularMetrics ? 10 : 12)
        .padding(.vertical, usesRegularMetrics ? 9 : 10)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(0.12))
        }
    }
}

private struct HomeWeeklyMomentumBar: View {
    @Environment(ThemeManager.self) private var themeManager

    let day: HomeWeeklyDaySummary
    let accentColor: Color
    let usesRegularMetrics: Bool

    private var fillColor: Color {
        if day.didReachGoal { return .green }
        if day.isSelectedDay { return accentColor }
        if day.didStudy { return accentColor.opacity(0.65) }
        return themeManager.textSecondary.opacity(0.22)
    }

    private var barHeight: CGFloat {
        let baseHeight: CGFloat = usesRegularMetrics ? 26 : 22
        let variableHeight: CGFloat = usesRegularMetrics ? 46 : 42
        return baseHeight + (variableHeight * day.intensityFraction)
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(day.shortWeekday)
                .font(.caption2.weight(.bold))
                .foregroundStyle(day.isSelectedDay ? themeManager.textPrimary : themeManager.textSecondary)

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(fillColor)
                .frame(width: usesRegularMetrics ? 32 : 28, height: barHeight)
                .overlay(alignment: .bottom) {
                    if day.isSelectedDay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.35), lineWidth: 1)
                    }
                }

            Text("\(day.cardsReviewed)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(themeManager.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct HomeInlineStatPill: View {
    @Environment(ThemeManager.self) private var themeManager

    let label: String
    let value: String
    let tint: Color
    var animatesValue = false

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(themeManager.textSecondary)

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
                .fill(themeManager.textPrimary.opacity(0.06))
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
    @Environment(ThemeManager.self) private var themeManager

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
                .foregroundStyle(themeManager.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
