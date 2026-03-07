// HomeStatsView.swift
// QuizFlash
//
// Reusable stat card components for the Home screen's Daily Activity section.

import SwiftUI
import SwiftData

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
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
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
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.03), radius: 6, x: 0, y: 3)
    }
}
