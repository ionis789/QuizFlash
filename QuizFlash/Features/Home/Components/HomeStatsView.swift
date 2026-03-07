
import SwiftUI
import SwiftData

// MARK: - Daily Goal Progress Card (Hero) 'Daily Activity'
/// A prominent hero card that visualizes the user's daily progress using a native Gauge.
struct DailyGoalProgressCard: View {
    let cardsReviewed: Int
    let dailyGoal: Int

    private var progress: Double {
        let safeGoal = max(dailyGoal, 1)
        return min(Double(cardsReviewed) / Double(safeGoal), 1.0)
    }

    private var isCompleted: Bool {
        cardsReviewed >= dailyGoal
    }

    var body: some View {
        HStack(spacing: 20) {
            // Native Apple circular gauge
            Gauge(value: progress) {
                EmptyView()
            } currentValueLabel: {
                Text("\(Int(progress * 100))%")
                    .font(.caption.weight(.bold))
                    .fontDesign(.rounded)
            }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(isCompleted ? .green : .blue)
                .scaleEffect(1.4) // Make it prominent
            .padding(.leading, 8)

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
/// A compact, square-ish card for secondary metrics (XP, Streak, Learned).
struct MiniStatCardView: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

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




