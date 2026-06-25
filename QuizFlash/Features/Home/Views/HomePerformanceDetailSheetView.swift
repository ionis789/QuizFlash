//
//  HomePerformanceDetailSheetView.swift
//  QuizFlash
//
//  Custom-sheet detail surface for the Home calendar-week performance summary.
//

import SwiftUI

// MARK: - Home Performance Detail Sheet

struct HomePerformanceDetailSheetView: View {
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.fullScreenSheetTopChromeClearance) private var topChromeClearance

    let summary: HomePastWeekPerformanceSummary
    let safeAreaInsets: UIEdgeInsets

    private var accentColor: Color {
        themeManager.roleColor(.buttonPrimaryFill)
    }

    private var locale: Locale {
        appPreferences.resolvedLocale
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: UIConstants.Spacing.medium),
            GridItem(.flexible(), spacing: UIConstants.Spacing.medium)
        ]
    }

    private var headerTrailingReserve: CGFloat {
        76
    }

    private var hasPreviousWeekActivity: Bool {
        summary.previousDaySummaries.contains(where: \.didStudy)
    }

    private var contentTopPadding: CGFloat {
        max(topChromeClearance + 84, UIConstants.Spacing.huge)
    }

    private func localized(_ value: String.LocalizationValue) -> String {
        AppLocalization.string(value, locale: locale)
    }

    private func localizedFormat(_ value: String.LocalizationValue, _ arguments: CVarArg...) -> String {
        let format = AppLocalization.string(value, locale: locale)
        return String(format: format, locale: locale, arguments: arguments)
    }

    private var windowEndingLine: String {
        localizedFormat(
            "Week of %@",
            HomeViewModel.labelForSelectedDay(summary.weekStartDate)
        )
    }

    private var localizedTrendLine: String {
        guard summary.activeDays > 0 else {
            return localized("Needs attention")
        }

        switch summary.trend {
        case .improving:
            return localized("Improving day by day")
        case .steady:
            return localized("Stable this week")
        case .slipping:
            return localized("Needs attention")
        }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.large) {
                if summary.hasActivity {
                    headerSection
                    overviewMetricsSection
                    comparisonSection
                } else {
                    emptyStateSection
                }
            }
            .padding(.horizontal, UIConstants.Spacing.large)
            .padding(.top, contentTopPadding)
            .padding(.bottom, safeAreaInsets.bottom + UIConstants.Spacing.extraLarge)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
            Text(localized("Study detail"))
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundStyle(themeManager.textPrimary)

            Text(windowEndingLine)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(themeManager.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(localizedTrendLine)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(accentColor)
                .padding(.top, UIConstants.Spacing.small)
        }
            .padding(.trailing, headerTrailingReserve)
    }

    private var overviewMetricsSection: some View {
        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: UIConstants.Spacing.medium) {
            HomePerformancePlainMetric(
                title: localized("Good rate"),
                value: "\(summary.accuracyPercent)%"
            )
            HomePerformancePlainMetric(
                title: localized("Active days"),
                value: "\(summary.activeDays)/\(summary.scoredDayCount)"
            )
            if summary.hasGoal {
                HomePerformancePlainMetric(
                    title: localized("Goal days"),
                    value: "\(summary.goalHitDays)"
                )
            }
        }
        .padding(.top, UIConstants.Spacing.small)
    }

    private var comparisonSection: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            HomePerformanceBarSection(
                title: localized("Current week"),
                daySummaries: summary.currentDaySummaries,
                labelTint: accentColor
            )

            if hasPreviousWeekActivity {
                AppSectionSeparator()
                    .padding(.vertical, UIConstants.Spacing.small)

                HomePerformanceBarSection(
                    title: localized("Last week"),
                    daySummaries: summary.previousDaySummaries,
                    labelTint: themeManager.textSecondary
                )
            }
        }
        .padding(.top, UIConstants.Spacing.medium)
    }

    private var emptyStateSection: some View {
        VStack(alignment: .center, spacing: UIConstants.Spacing.large) {
            Text(localized("Study detail"))
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundStyle(themeManager.textPrimary)
                .multilineTextAlignment(.center)

            Text(windowEndingLine)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(themeManager.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(localized("No activity yet"))
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .foregroundStyle(themeManager.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, UIConstants.Spacing.medium)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, UIConstants.Spacing.large)
    }
}

// MARK: - Supporting Views

private struct HomePerformancePlainMetric: View {
    @Environment(ThemeManager.self) private var themeManager

    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(themeManager.textSecondary)
                .lineLimit(2)

            Text(value)
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(themeManager.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HomePerformanceBarSection: View {
    let title: String
    let daySummaries: [HomePastWeekPerformanceDaySummary]
    let labelTint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            Text(title)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(labelTint)

            HomePerformanceBarRow(
                daySummaries: daySummaries
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HomePerformanceBarRow: View {
    let daySummaries: [HomePastWeekPerformanceDaySummary]

    private let columnSpacing: CGFloat = UIConstants.Spacing.small

    private var maxOutcomeTotal: Int {
        max(daySummaries.map { $0.landedCount + $0.retryCount }.max() ?? 0, 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let itemCount = max(daySummaries.count, 1)
            let spacingTotal = columnSpacing * CGFloat(max(itemCount - 1, 0))
            let columnWidth = max((proxy.size.width - spacingTotal) / CGFloat(itemCount), 1)

            HStack(alignment: .bottom, spacing: columnSpacing) {
                ForEach(daySummaries) { day in
                    HomePerformanceBarColumn(
                        day: day,
                        maxOutcomeTotal: maxOutcomeTotal
                    )
                    .frame(width: columnWidth)
                }
            }
            .frame(width: proxy.size.width, height: HomePerformanceBarColumn.totalHeight, alignment: .bottom)
        }
        .frame(height: HomePerformanceBarColumn.totalHeight)
        .frame(maxWidth: .infinity)
    }
}

private struct HomePerformanceBarColumn: View {
    @Environment(ThemeManager.self) private var themeManager

    static let totalHeight: CGFloat = 166

    let day: HomePastWeekPerformanceDaySummary
    let maxOutcomeTotal: Int

    private var goodTint: Color {
        .green
    }

    private var retryTint: Color {
        Color(red: 1.0, green: 0.78, blue: 0.8)
    }

    private var outcomeTotal: Int {
        day.landedCount + day.retryCount
    }

    private var totalRatio: CGFloat {
        guard outcomeTotal > 0 else { return 0 }
        return CGFloat(outcomeTotal) / CGFloat(max(maxOutcomeTotal, 1))
    }

    var body: some View {
        VStack(spacing: 10) {
            Text(day.shortWeekday)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(themeManager.textSecondary)
                .lineLimit(1)

            HomePerformanceStackedBar(
                landedCount: day.landedCount,
                retryCount: day.retryCount,
                totalRatio: totalRatio,
                goodTint: goodTint,
                retryTint: retryTint
            )
        }
        .frame(maxWidth: .infinity, alignment: .bottom)
    }
}

private struct HomePerformanceStackedBar: View {
    @Environment(ThemeManager.self) private var themeManager

    let landedCount: Int
    let retryCount: Int
    let totalRatio: CGFloat
    let goodTint: Color
    let retryTint: Color

    private let barHeight: CGFloat = 128
    private let minActiveHeight: CGFloat = 36
    private let minReadableSegmentHeight: CGFloat = 30

    private var totalCount: Int {
        landedCount + retryCount
    }

    private var activeHeight: CGFloat {
        guard totalCount > 0 else { return 0 }
        let scaledHeight = barHeight * max(min(totalRatio, 1), 0)
        let readableHeight = CGFloat(nonZeroSegmentCount) * minReadableSegmentHeight
        return max(minActiveHeight, readableHeight, scaledHeight)
    }

    private var nonZeroSegmentCount: Int {
        [landedCount, retryCount].filter { $0 > 0 }.count
    }

    private var segmentHeights: (retry: CGFloat, landed: CGFloat) {
        guard totalCount > 0 else { return (retry: 0, landed: 0) }
        guard landedCount > 0, retryCount > 0 else {
            return (
                retry: retryCount > 0 ? activeHeight : 0,
                landed: landedCount > 0 ? activeHeight : 0
            )
        }

        let rawRetry = activeHeight * CGFloat(retryCount) / CGFloat(totalCount)
        let rawLanded = activeHeight * CGFloat(landedCount) / CGFloat(totalCount)
        var retry = max(minReadableSegmentHeight, rawRetry)
        var landed = max(minReadableSegmentHeight, rawLanded)
        let overflow = max((retry + landed) - activeHeight, 0)

        if overflow > 0 {
            if retry > landed {
                retry = max(minReadableSegmentHeight, retry - overflow)
            } else {
                landed = max(minReadableSegmentHeight, landed - overflow)
            }
        }

        return (retry: retry, landed: landed)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Capsule(style: .continuous)
                .fill(themeManager.roleColor(.buttonPrimaryFill).opacity(0.16))
                .frame(height: barHeight)

            VStack(spacing: 0) {
                if retryCount > 0 {
                    HomePerformanceBarSegment(
                        value: retryCount,
                        height: segmentHeights.retry,
                        fill: retryTint,
                        textColor: Color.black.opacity(0.68)
                    )
                }

                if landedCount > 0 {
                    HomePerformanceBarSegment(
                        value: landedCount,
                        height: segmentHeights.landed,
                        fill: goodTint,
                        textColor: themeManager.textPrimary
                    )
                }
            }
            .frame(height: activeHeight, alignment: .bottom)
            .frame(maxWidth: .infinity)
            .clipShape(Capsule(style: .continuous))

            if totalCount == 0 {
                Text("0")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(themeManager.textSecondary.opacity(0.55))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .frame(height: barHeight)
        .frame(maxWidth: .infinity)
    }
}

private struct HomePerformanceBarSegment: View {
    let value: Int
    let height: CGFloat
    let fill: Color
    let textColor: Color

    var body: some View {
        ZStack {
            fill

            Text("\(value)")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(height: height)
    }
}
