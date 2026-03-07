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
        VStack(spacing: 10) {
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
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(streakColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(streakColor.opacity(0.12), in: Capsule())
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
        VStack(spacing: 16) {

            // ── XP / Level row ──────────────────────────────────────────────
            xpLevelSection

            // ── Subtle divider ──────────────────────────────────────────────
            Rectangle()
                .fill(Color.secondary.opacity(0.10))
                .frame(height: 0.5)

            // ── 28-day heatmap ──────────────────────────────────────────────
            heatmapSection

        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .padding(.horizontal, 20)
    }

    // MARK: - XP Level Section

    private var xpLevelSection: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center) {
                // Level badge
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(accentColor.opacity(0.15))
                            .frame(width: 32, height: 32)
                        Text("\(level)")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(accentColor)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Level \(level)")
                            .font(.subheadline.weight(.semibold))
                        Text("\(xpToNextLevel) XP to next")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                HStack(spacing: 3) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.yellow.opacity(0.8))
                    Text("\(totalXP)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(accentColor.opacity(0.85))
                    Text("XP")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            // Progress bar — thinner, subtler
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.10))
                        .frame(height: 5)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [accentColor.opacity(0.65), accentColor.opacity(0.85)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: max(5, geo.size.width * xpProgress),
                            height: 5
                        )
                        .animation(.spring(response: 0.7, dampingFraction: 0.75), value: xpProgress)
                }
            }
            .frame(height: 5)
        }
    }

    // MARK: - Heatmap Section

    private var heatmapSection: some View {
        VStack(spacing: 8) {
            // Title row
            HStack {
                Text("28-Day Activity")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("\(totalRecentCards) reviewed")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // 4 rows × 7 columns — smaller, more airy
            let weeks = last28Days.chunks(of: 7)
            VStack(spacing: 4) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    HStack(spacing: 4) {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, cell in
                            HeatmapSquare(cell: cell, maxCards: maxCards, accentColor: accentColor)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)

            // Legend — minimal
            HStack(spacing: 4) {
                Text("Less")
                    .font(.system(size: 8))
                    .foregroundStyle(.quaternary)
                ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            i == 0
                            ? AnyShapeStyle(Color.secondary.opacity(0.10))
                            : AnyShapeStyle(accentColor.opacity(0.15 + i * 0.70))
                        )
                        .frame(width: 9, height: 9)
                }
                Text("More")
                    .font(.system(size: 8))
                    .foregroundStyle(.quaternary)
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
            return AnyShapeStyle(Color.secondary.opacity(0.08))
        }
        return AnyShapeStyle(accentColor.opacity(0.15 + intensity * 0.70))
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(fillColor)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if cell.isToday {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(accentColor.opacity(0.6), lineWidth: 1)
                }
                if cell.isPerfectDay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
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
