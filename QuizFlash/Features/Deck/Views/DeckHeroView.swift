//
//  DeckHeroView.swift
//  QuizFlash
//
//  Premium glassmorphic hero — expanded + compact sticky mode
//

import SwiftUI

// MARK: - DeckHeroView

struct DeckHeroView: View {
    let deck: DeckModel
    let stats: DeckStats
    let isCompact: Bool
    var onEdit: () -> Void

    private var deckColor: Color {
        Color(hex: deck.colorHex) ?? .blue
    }

    var body: some View {
        if isCompact {
            compactHeader
        } else {
            expandedHero
        }
    }

    // MARK: - Expanded Hero

    private var expandedHero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [deckColor.opacity(0.55), deckColor.opacity(0.25), Color.black.opacity(0.55)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            CustomBlurView(effect: .systemUltraThinMaterialDark) { _ in }
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .opacity(0.65)

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [deckColor.opacity(0.30), deckColor.opacity(0.08), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.45), .white.opacity(0.10), deckColor.opacity(0.25), deckColor.opacity(0.50)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    DeckIconBadge(icon: deck.icon, color: deckColor, size: 54)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(deck.title)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(formattedDate)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                    }

                    Spacer()

                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.white.opacity(0.14), in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.22), lineWidth: 1))
                    }
                }

                Rectangle()
                    .fill(.white.opacity(0.12))
                    .frame(height: 1)

                HStack(spacing: 0) {
                    HeroStatCell(icon: "rectangle.stack.fill", value: "\(stats.totalCards)", label: "Cards", tint: .white.opacity(0.9))
                    HeroStatCell(
                        icon: "exclamationmark.circle.fill",
                        value: "\(stats.dueCards)",
                        label: "Due Now",
                        tint: stats.dueCards > 0 ? .red : .white.opacity(0.35)
                    )
                    HeroMasteryCell(mastery: stats.deckMastery)
                    HeroStatCell(
                        icon: "flame.fill",
                        value: "\(stats.todayReviewed)",
                        label: "Today",
                        tint: stats.todayReviewed > 0 ? .orange : .white.opacity(0.35)
                    )
                }
            }
            .padding(22)
        }
        .shadow(color: deckColor.opacity(0.45), radius: 22, x: 0, y: 10)
        .shadow(color: .black.opacity(0.30), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: - Compact Sticky Header

    private var compactHeader: some View {
        HStack(spacing: 12) {
            DeckIconBadge(icon: deck.icon, color: deckColor, size: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text(deck.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("\(Int(stats.deckMastery * 100))% mastered")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer()

            if stats.dueCards > 0 {
                HStack(spacing: 4) {
                    Circle().fill(.red).frame(width: 6, height: 6)
                    Text("\(stats.dueCards) due")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.red)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.red.opacity(0.15), in: Capsule())
            }

            CompactMasteryArc(mastery: stats.deckMastery, color: masteryColor(stats.deckMastery))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            ZStack {
                CustomBlurView(effect: .systemUltraThinMaterialDark) { _ in }
                deckColor.opacity(0.20)
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.25), deckColor.opacity(0.30)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: deckColor.opacity(0.35), radius: 12, x: 0, y: 4)
        .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 2)
        .padding(.horizontal, 16)
    }

    private var formattedDate: String {
        let f = DateFormatter(); f.dateStyle = .medium
        return "Created \(f.string(from: deck.createdAt))"
    }
}

// MARK: - Mastery colour (shared across components)

func masteryColor(_ mastery: Double) -> Color {
    switch mastery {
    case ..<0.25: return .red
    case 0.25..<0.50: return .orange
    case 0.50..<0.75: return .yellow
    case 0.75..<0.90: return .teal
    default: return .green
    }
}

// MARK: - Deck Icon Badge (shared)

struct DeckIconBadge: View {
    let icon: String
    let color: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.28)).frame(width: size, height: size)
            Circle().stroke(color.opacity(0.50), lineWidth: 1).frame(width: size, height: size)
            Image(systemName: icon.isEmpty ? "sparkles.rectangle.stack.fill" : icon)
                .font(.system(size: size * 0.40, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Hero Stat Cell

private struct HeroStatCell: View {
    let icon: String
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.50))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Hero Mastery Cell (arc ring inside stat row)

private struct HeroMasteryCell: View {
    let mastery: Double

    private var masteryInt: Int { Int(mastery * 100) }
    private var color: Color { masteryColor(mastery) }

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .trim(from: 0, to: 1)
                    .stroke(.white.opacity(0.12), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 32, height: 32)
                    .rotationEffect(.degrees(-90))

                Circle()
                    .trim(from: 0, to: mastery)
                    .stroke(
                        LinearGradient(colors: [color.opacity(0.7), color], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 32, height: 32)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.8, dampingFraction: 0.75), value: mastery)

                Text("\(masteryInt)")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(color)
            }

            Text("\(masteryInt)%")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
            Text("Mastery")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.50))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Compact Mastery Arc (mini header)

private struct CompactMasteryArc: View {
    let mastery: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 1)
                .stroke(.white.opacity(0.15), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: 28, height: 28)
                .rotationEffect(.degrees(-90))

            Circle()
                .trim(from: 0, to: mastery)
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: 28, height: 28)
                .rotationEffect(.degrees(-90))

            Text("\(Int(mastery * 100))")
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(color)
        }
    }
}
