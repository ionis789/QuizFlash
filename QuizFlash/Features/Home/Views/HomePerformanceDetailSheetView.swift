//
//  HomePerformanceDetailSheetView.swift
//  QuizFlash
//
//  Custom-sheet detail surface for the Home 7-day performance summary.
//

import SwiftUI

// MARK: - Home Performance Detail Sheet

struct HomePerformanceDetailSheetView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.fullScreenSheetDismiss) private var fullScreenSheetDismiss

    let summary: HomePastWeekPerformanceSummary
    let safeAreaInsets: UIEdgeInsets

    private var accentColor: Color {
        themeManager.roleColor(.buttonPrimaryFill)
    }

    private var dangerColor: Color {
        themeManager.roleColor(.buttonDangerFill)
    }

    private var deltaTint: Color {
        if summary.deltaPercent > 0 { return .green }
        if summary.deltaPercent < 0 { return dangerColor }
        return accentColor
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: UIConstants.Spacing.medium),
            GridItem(.flexible(), spacing: UIConstants.Spacing.medium)
        ]
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.large) {
                headerSection
                comparisonSection
                pillarsSection
                insightsSection
                explanationSection
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
                    Text("Performance")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(themeManager.textPrimary)

                    Text("7-day window ending \(HomeViewModel.labelForSelectedDay(summary.windowEndDate))")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(themeManager.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
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

            HStack(alignment: .lastTextBaseline, spacing: UIConstants.Spacing.medium) {
                Text("\(summary.scorePercent)%")
                    .font(.system(size: 66, weight: .black, design: .rounded))
                    .foregroundStyle(themeManager.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .contentTransition(.numericText(value: Double(summary.scorePercent)))

                HomePerformanceSheetDeltaBadge(
                    deltaPercent: summary.deltaPercent,
                    tint: deltaTint,
                    backgroundTint: deltaTint.opacity(0.16)
                )
                .padding(.bottom, UIConstants.Spacing.small)
            }

            Text(summary.trendLine)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(themeManager.textPrimary)

            Text(summary.supportingLine)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(themeManager.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var comparisonSection: some View {
        HomePerformanceSheetSurface {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
                Text("Previous 7 vs current 7")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(themeManager.textPrimary)

                HStack(alignment: .top, spacing: UIConstants.Spacing.medium) {
                    HomePerformanceDotMatrixGroup(
                        title: "Previous 7",
                        daySummaries: summary.previousDaySummaries,
                        tint: themeManager.textSecondary.opacity(0.55),
                        labelTint: themeManager.textSecondary
                    )

                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 1)

                    HomePerformanceDotMatrixGroup(
                        title: "Current 7",
                        daySummaries: summary.currentDaySummaries,
                        tint: accentColor,
                        labelTint: accentColor
                    )
                }
            }
        }
    }

    private var pillarsSection: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            Text("What drives the score")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(themeManager.textPrimary)

            LazyVGrid(columns: gridColumns, spacing: UIConstants.Spacing.medium) {
                HomePerformanceMetricCard(
                    title: "Accuracy",
                    value: "\(summary.accuracyPercent)%",
                    detail: "Clean finishes",
                    tint: .green
                )
                HomePerformanceMetricCard(
                    title: "Consistency",
                    value: "\(summary.consistencyPercent)%",
                    detail: summary.activeDays == 1 ? "1 active day" : "\(summary.activeDays)/7 active",
                    tint: accentColor
                )
                HomePerformanceMetricCard(
                    title: "Goal coverage",
                    value: "\(summary.goalCoveragePercent)%",
                    detail: summary.goalHitDays == 1 ? "1 goal day" : "\(summary.goalHitDays) goal days",
                    tint: .orange
                )
                HomePerformanceMetricCard(
                    title: "Efficiency",
                    value: "\(summary.efficiencyPercent)%",
                    detail: "Unique vs repeat",
                    tint: dangerColor
                )
            }
        }
    }

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            Text("This window")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(themeManager.textPrimary)

            VStack(spacing: UIConstants.Spacing.medium) {
                HomePerformanceInsightCard(
                    title: "Best day",
                    value: summary.bestDayLabel ?? "No study day yet",
                    detail: summary.bestDayScorePercent.map { "\($0)% daily score" } ?? "Start a session to generate a best day.",
                    tint: .green
                )

                HomePerformanceInsightCard(
                    title: "Weakest day",
                    value: summary.weakestDayLabel ?? "No weak day yet",
                    detail: summary.weakestDayScorePercent.map { "\($0)% daily score" } ?? "There is no active day in this window yet.",
                    tint: dangerColor
                )

                HomePerformanceInsightCard(
                    title: "Goal-hit days",
                    value: summary.goalHitDays == 1 ? "1 day" : "\(summary.goalHitDays) days",
                    detail: summary.goalHitDays == 0
                        ? "No selected-day target was fully cleared in this window."
                        : "These are the days where the selected-day goal was fully covered.",
                    tint: accentColor
                )
            }
        }
    }

    private var explanationSection: some View {
        HomePerformanceSheetSurface {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                Text("How it works")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(themeManager.textPrimary)

                Text("Performance blends clean finishes, activity consistency, daily goal coverage, and how efficiently your unique cards convert versus repeat passes.")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(themeManager.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Supporting Views

private struct HomePerformanceSheetSurface<Content: View>: View {
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

private struct HomePerformanceMetricCard: View {
    @Environment(ThemeManager.self) private var themeManager

    let title: String
    let value: String
    let detail: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(themeManager.textSecondary)

            Text(value)
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(themeManager.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Text(detail)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(themeManager.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(UIConstants.Spacing.standard)
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(themeManager.surfacePrimary)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(tint.opacity(0.12))
                }
        }
    }
}

private struct HomePerformanceInsightCard: View {
    @Environment(ThemeManager.self) private var themeManager

    let title: String
    let value: String
    let detail: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: UIConstants.Spacing.medium) {
            Circle()
                .fill(tint)
                .frame(width: 10, height: 10)
                .padding(.top, 7)

            VStack(alignment: .leading, spacing: UIConstants.Spacing.tiny) {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(themeManager.textSecondary)

                Text(value)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(themeManager.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(detail)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(themeManager.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(UIConstants.Spacing.standard)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(themeManager.roleColor(.widgetSurfaceFill))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.03), lineWidth: 1)
                }
        }
    }
}

private struct HomePerformanceDotMatrixGroup: View {
    let title: String
    let daySummaries: [HomePastWeekPerformanceDaySummary]
    let tint: Color
    let labelTint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(labelTint)

            HStack(alignment: .bottom, spacing: 6) {
                ForEach(daySummaries) { day in
                    HomePerformanceDotColumn(day: day, tint: tint, labelTint: labelTint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HomePerformanceDotColumn: View {
    @Environment(ThemeManager.self) private var themeManager

    let day: HomePastWeekPerformanceDaySummary
    let tint: Color
    let labelTint: Color

    var body: some View {
        VStack(spacing: 6) {
            VStack(spacing: 5) {
                ForEach((1...5).reversed(), id: \.self) { level in
                    Circle()
                        .fill(level <= day.visualLevel ? tint : Color.white.opacity(0.08))
                        .frame(width: 8, height: 8)
                }
            }
            .frame(height: 60, alignment: .bottom)

            Text(day.shortWeekday)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(day.didStudy ? labelTint : themeManager.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .bottom)
    }
}

private struct HomePerformanceSheetDeltaBadge: View {
    let deltaPercent: Int
    let tint: Color
    let backgroundTint: Color

    private var text: String {
        if deltaPercent > 0 {
            return "+\(deltaPercent)"
        }
        return "\(deltaPercent)"
    }

    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                Capsule(style: .continuous)
                    .fill(backgroundTint)
            }
    }
}
