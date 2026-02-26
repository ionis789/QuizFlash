//
//  LearningHabitView.swift
//  QuizFlash
//
//  Habit tracker section — 28-day heatmap, XP level bar, streak.
//  Alimentat din DailyActivityLog + UserProfile (injectat din DeckView via @Query).
//

import SwiftUI

// MARK: - LearningHabitView

struct LearningHabitView: View {
    let activityLogs: [DailyActivityLog]
    let userProfile: UserProfile?

    // MARK: - Derived data

    private var streak: Int { userProfile?.currentStreak ?? 0 }
    private var totalXP: Int { userProfile?.totalXP ?? 0 }
    private var level: Int { userProfile?.level ?? 1 }

    /// XP already earned inside the current level (0–499)
    private var xpInLevel: Int { totalXP % 500 }
    private var xpProgress: Double { Double(xpInLevel) / 500.0 }
    private var xpToNextLevel: Int { 500 - xpInLevel }

    /// Reviewed cards in the last 28 days
    private var totalRecentCards: Int { last28Days.reduce(0) { $0 + $1.cardsReviewed } }

    private var last28Days: [DayCell] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        let dict = Dictionary(uniqueKeysWithValues: activityLogs.map { ($0.dateString, $0) })

        return (0..<28).reversed().map { ago in
            let date = calendar.date(byAdding: .day, value: -ago, to: today)!
            let log = dict[fmt.string(from: date)]
            return DayCell(
                date: date,
                cardsReviewed: log?.cardsReviewed ?? 0,
                xpEarned: log?.xpEarnedToday ?? 0,
                isPerfectDay: log?.isPerfectDay ?? false,
                isToday: ago == 0
            )
        }
    }

    private var maxCards: Int { max(1, last28Days.map(\.cardsReviewed).max() ?? 1) }

    private var accentColor: Color { ThemeManager.shared.accentColor.color }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 14) {
            sectionHeader
            mainCard
        }
    }

    // MARK: - Section Header

    private var sectionHeader: some View {
        HStack {
            Text("LEARNING PROGRESS")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            Spacer()

            if streak > 0 {
                Label("\(streak) day streak", systemImage: "flame.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(streakColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(streakColor.opacity(0.15), in: Capsule())
            }
        }
        .padding(.horizontal, 20)
    }

    private var streakColor: Color {
        switch streak {
        case 0: return .secondary
        case 1...3: return .orange
        case 4...6: return .orange
        default: return .red
        }
    }

    // MARK: - Main Card

    private var mainCard: some View {
        VStack(spacing: 20) {

            // ── XP / Level row ──────────────────────────────────────────────
            xpLevelSection

            Divider()

            // ── 28-day heatmap ──────────────────────────────────────────────
            heatmapSection

        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .padding(.horizontal, 20)
    }

    // MARK: - XP Level Section

    private var xpLevelSection: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center) {
                // Level badge
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(accentColor.opacity(0.20))
                            .frame(width: 36, height: 36)
                        Text("\(level)")
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(accentColor)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Level \(level)")
                            .font(.subheadline.weight(.bold))
                        Text("\(xpToNextLevel) XP to next level")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                        Text("\(totalXP) XP")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(accentColor)
                    }
                    Text("total earned")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.13))
                        .frame(height: 9)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [accentColor.opacity(0.75), accentColor, accentColor.opacity(0.85)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: max(9, geo.size.width * xpProgress),
                            height: 9
                        )
                        .animation(.spring(response: 0.7, dampingFraction: 0.75), value: xpProgress)

                    // Glint on the progress bar
                    Capsule()
                        .fill(.white.opacity(0.25))
                        .frame(width: max(9, geo.size.width * xpProgress) * 0.5, height: 3)
                        .offset(y: -1)
                        .animation(.spring(response: 0.7, dampingFraction: 0.75), value: xpProgress)
                }
            }
            .frame(height: 9)
        }
    }

    // MARK: - Heatmap Section

    private var heatmapSection: some View {
        VStack(spacing: 10) {
            // Heatmap title row
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("28-Day Activity")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("\(totalRecentCards) cards reviewed")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                // Day-of-week labels aligned to right
                HStack(spacing: 5) {
                    ForEach(["M", "W", "F", "S"], id: \.self) { d in
                        Text(d)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(width: 120) // approximate heatmap width
            }

            // 4 rows × 7 columns
            let weeks = last28Days.chunks(of: 7)
            VStack(spacing: 5) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    HStack(spacing: 5) {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, cell in
                            HeatmapSquare(cell: cell, maxCards: maxCards, accentColor: accentColor)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)

            // Legend
            HStack(spacing: 5) {
                Text("Less")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            i == 0
                            ? AnyShapeStyle(Color.secondary.opacity(0.15))
                            : AnyShapeStyle(accentColor.opacity(0.18 + i * 0.82))
                        )
                        .frame(width: 11, height: 11)
                }
                Text("More")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        }
    }
}

// MARK: - Heatmap Square

private struct HeatmapSquare: View {
    let cell: LearningHabitView.DayCell
    let maxCards: Int
    let accentColor: Color

    private var intensity: Double {
        guard cell.cardsReviewed > 0 else { return 0 }
        return min(1.0, Double(cell.cardsReviewed) / Double(maxCards))
    }

    private var fillColor: AnyShapeStyle {
        if cell.cardsReviewed == 0 {
            return AnyShapeStyle(Color.secondary.opacity(0.14))
        }
        return AnyShapeStyle(accentColor.opacity(0.18 + intensity * 0.82))
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(fillColor)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if cell.isToday {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(accentColor, lineWidth: 1.5)
                }
                if cell.isPerfectDay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 5, weight: .black))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
    }
}

// MARK: - DayCell model

extension LearningHabitView {
    struct DayCell {
        let date: Date
        let cardsReviewed: Int
        let xpEarned: Int
        let isPerfectDay: Bool
        let isToday: Bool
    }
}

// MARK: - Array helper (avoids name collision with any future stdlib method)

private extension Array {
    func chunks(of size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
