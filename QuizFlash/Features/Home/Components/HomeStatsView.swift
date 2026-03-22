// HomeStatsView.swift
// QuizFlash
//
// Reusable stat card components for the Home screen's Daily Activity section.

import SwiftUI
import SwiftData

// MARK: - Home Analytics Hero

/// Premium analytics hero for the Home dashboard, focused on the selected day.
struct HomeAnalyticsHeroCard: View {

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
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(overview.selectedDateLabel)
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background {
                            Capsule()
                                .fill(Color.primary.opacity(0.06))
                        }

                    Text(overview.headline)
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(overview.detailLine)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                HomeGoalProgressRing(
                    progress: overview.goalCompletionFraction,
                    centerValue: "\(overview.cardsReviewed)",
                    centerLabel: "/\(overview.dailyGoal)",
                    tint: completionTint
                )
            }

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
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.libraryDeckRow,
                            Color.libraryDeckRow.opacity(0.94),
                            completionTint.opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 16, y: 8)
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
            }

            Text(summary.detailLine)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
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
                    tint: accentColor
                )
                HomeInlineStatPill(
                    label: "XP",
                    value: "\(summary.totalXPEarned)",
                    tint: .orange
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
        .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 5)
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
        .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 5)
    }
}

// MARK: - Daily Goal Progress Card

/// A prominent hero card that visualises the user's daily study progress using a native `Gauge`.
///
/// The gauge tint picks up the currently active theme accent colour automatically,
/// switching to green once the daily goal is reached.
///
/// - Parameters:
///   - cardsReviewed: The number of cards reviewed so far today.
///   - dailyGoal: The target number of cards to review today.
struct DailyGoalProgressCard: View {

    // MARK: - Input

    let cardsReviewed: Int
    let dailyGoal: Int

    // MARK: - Derived State

    private var progress: Double {
        let safeGoal = max(dailyGoal, 1)
        return min(Double(cardsReviewed) / Double(safeGoal), 1.0)
    }

    private var isCompleted: Bool {
        cardsReviewed >= dailyGoal
    }

    /// The theme accent colour; resolves the current selection from `ThemeManager`.
    private var accentColor: Color {
        ThemeManager.shared.accentColor.color
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 20) {

            // MARK: Circular Gauge

            // Uses the theme accent colour instead of a hardcoded value.
            // Turns green when the daily goal has been reached.
            Gauge(value: progress) {
                EmptyView()
            } currentValueLabel: {
                Text("\(Int(progress * 100))%")
                    .font(.caption.weight(.bold))
                    .fontDesign(.rounded)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(isCompleted ? .green : accentColor)
            .scaleEffect(1.4)
            .padding(.leading, 8)

            // MARK: Text Labels

            VStack(alignment: .leading, spacing: 4) {
                Text(isCompleted ? "Goal Reached! 🎉" : "Daily Goal")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(cardsReviewed)")
                        .font(.title2.weight(.heavy))
                        .fontDesign(.rounded)
                        .foregroundStyle(isCompleted ? .green : .primary)

                    Text("/ \(dailyGoal) cards")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(20)
        .widgetStyle(cornerRadius: 24)
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Mini Stat Card

/// A compact, square card for secondary daily metrics such as XP, Streak, and Learned cards.
///
/// The icon and tint colour are provided by the caller, allowing semantic colours
/// (e.g. orange for XP, red for streak) to be set at the call site rather than
/// hardcoded inside this generic component.
///
/// - Parameters:
///   - title: The metric label displayed below the value (e.g. "XP", "Streak").
///   - value: The stringified metric value (e.g. "42", "7").
///   - icon: An SF Symbols identifier for the metric icon.
///   - color: The tint colour for the icon and gradient rendering.
struct MiniStatCardView: View {

    // MARK: - Input

    let title: String
    let value: String
    let icon: String
    let color: Color

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color.gradient)
                .symbolRenderingMode(.multicolor)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline.weight(.heavy))
                    .fontDesign(.rounded)
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)

                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .widgetStyle(cornerRadius: 18)
        .shadow(color: .black.opacity(0.03), radius: 6, x: 0, y: 3)
    }
}

// MARK: - Hero Support Views

private struct HomeGoalProgressRing: View {
    let progress: Double
    let centerValue: String
    let centerLabel: String
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 12)

            Circle()
                .trim(from: 0, to: max(min(progress, 1), 0))
                .stroke(
                    AngularGradient(
                        colors: [tint.opacity(0.55), tint],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 2) {
                Text(centerValue)
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)

                Text(centerLabel)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 108, height: 108)
    }
}

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

            Text(detail)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(tint.opacity(0.12))
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

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.caption.weight(.heavy))
                .foregroundStyle(tint)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(Color.primary.opacity(0.06))
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
