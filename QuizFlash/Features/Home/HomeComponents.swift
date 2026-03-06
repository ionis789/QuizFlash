// HomeComponents.swift
// QuizFlash
//
// Reusable UI components used across the Home screen.
// Updated with Production Apple design guidelines: Hierarchy, native Gauges, Gradients, and Semantic context.

import SwiftUI
import SwiftData

// MARK: - Daily Goal Progress Card (Hero)
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

// MARK: - Recent Deck Card (Ticket Style)
/// A horizontal, sleek card optimized for side-scrolling, displaying static time information.
struct RecentDeckCardView: View {
    let deck: DeckModel
    let action: () -> Void

    /// Formats a past date as a concise static string (e.g. "2h ago", "3d ago").
    /// Computed once at render time — never updates automatically like `Text(.relative)`.
    private func relativeLabel(for date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        switch seconds {
        case ..<60: return "just now"
        case ..<3600: return "\(seconds / 60)m ago"
        case ..<86400: return "\(seconds / 3600)h ago"
        case ..<2_592_000: return "\(seconds / 86400)d ago"
        default: return "\(seconds / 2_592_000)mo ago"
        }
    }

    var body: some View {
        let deckColor = Color(hex: deck.colorHex) ?? .blue

        Button(action: action) {
            HStack(spacing: 16) {
                // Left Color Block with Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(deckColor.gradient)

                    Image(systemName: deck.icon)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                }
                    .frame(width: 60, height: 60)

                // Right Content
                VStack(alignment: .leading, spacing: 6) {
                    Text(deck.title)
                        .font(.headline.weight(.semibold))
                        .fontDesign(.rounded)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        // Safe: cardCount is a denormalized Int — no relationship fault.
                        Text("\(deck.cardCount) cards")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(deckColor.opacity(0.15))
                            .foregroundStyle(deckColor)
                            .clipShape(Capsule())

                        // Static relative label — computed once at render time.
                        // Avoids Text(.relative) which re-renders the entire card
                        // every second via SwiftUI's internal timer publisher.
                        if let lastOpened = deck.lastOpenedAt {
                            Text("• \(relativeLabel(for: lastOpened))")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
                .padding(12)
                .frame(width: 260)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: deckColor.opacity(0.1), radius: 10, x: 0, y: 4)
        }
            .buttonStyle(.plain)
    }
}

// MARK: - Folder Card (Tactile Style)
/// Designed to look more like a native iOS folder structure with depth.
struct FolderCardView: View {
    let folder: FolderModel
    let action: () -> Void

    var body: some View {
        let folderColor = Color(hex: folder.colorHex) ?? .blue

        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                // Header Area with Folder Icon
                HStack {
                    Image(systemName: "folder.fill")
                        .font(.title)
                        .foregroundStyle(folderColor.gradient)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                    .padding(.bottom, 16)

                // Title Area
                Text(folder.title)
                    .font(.headline.weight(.semibold))
                    .fontDesign(.rounded)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .padding(.bottom, 4)

                Text("\(folder.deckCount) decks")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                RoundedRectangle(cornerRadius: 40, style: .continuous)
                    .fill(
                    Color.libraryDeckRow
                        .shadow(.inner(color: Color.white.opacity(0.15), radius: 1, x: 0, y: 0))
                )
            }
                .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
                .shadow(color: .black.opacity(0.04), radius: 5, x: 0, y: 2)
        }
            .buttonStyle(.plain)
    }
}

// MARK: - Empty State View
struct EmptyStatePlaceholder: View {
    let icon: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)

            Text(message)
                .font(.subheadline.weight(.medium))
                .fontDesign(.rounded)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .background(Color(uiColor: .secondarySystemGroupedBackground).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color(uiColor: .tertiaryLabel).opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [6]))
        )
    }
}
