// HomeDeckHealthCards.swift
// QuizFlash
//
// Deck-health analytics cards for the Home dashboard.

import SwiftUI
import SwiftData

// MARK: - Home Deck Health Section

/// Home section that surfaces the top decks needing attention right now.
struct HomeDeckHealthSection: View {
    let summaries: [HomeDeckHealthSummary]
    let onOpenDeck: (PersistentIdentifier) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Deck Health")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(.primary)

                    Text("See which decks need intervention before they slow down your progress.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Text("\(summaries.count) focus")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }

            VStack(spacing: 14) {
                ForEach(summaries) { summary in
                    HomeDeckHealthCard(
                        summary: summary,
                        onTap: { onOpenDeck(summary.id) }
                    )
                }
            }
        }
    }
}

// MARK: - Home Deck Health Card

/// Rich deck-level status card used on Home to highlight where the next study session should go.
private struct HomeDeckHealthCard: View {
    let summary: HomeDeckHealthSummary
    let onTap: () -> Void

    private var accentColor: Color {
        Color(hex: summary.colorHex) ?? ThemeManager.shared.accentColor.color
    }

    private var masteryLabel: String {
        "\(Int((summary.masteryFraction * 100).rounded()))%"
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(accentColor.opacity(0.16))

                        Image(systemName: summary.icon)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(accentColor)
                    }
                    .frame(width: 56, height: 56)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(summary.title)
                                .font(.system(.headline, design: .rounded, weight: .bold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            if summary.linkedGoalCount > 0 {
                                HomeDeckHealthBadge(
                                    text: "\(summary.linkedGoalCount) goal" + (summary.linkedGoalCount == 1 ? "" : "s"),
                                    tint: accentColor
                                )
                            }
                        }

                        Text(summary.headline)
                            .font(.system(.title3, design: .rounded, weight: .heavy))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(summary.detailLine)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    HomeDeckMasteryMeter(
                        progress: summary.masteryFraction,
                        valueLabel: masteryLabel,
                        tint: accentColor
                    )
                }

                HStack(spacing: 10) {
                    HomeDeckHealthStatPill(label: "Due", value: "\(summary.dueCards)", tint: .orange)
                    HomeDeckHealthStatPill(label: "New", value: "\(summary.newCards)", tint: accentColor)
                    HomeDeckHealthStatPill(label: "Stable", value: "\(summary.stableCards)", tint: .green)
                    HomeDeckHealthStatPill(label: "Acc", value: "\(summary.reviewAccuracy)%", tint: .blue)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HomeDeckHealthInsightLine(icon: "bolt.fill", text: summary.actionLine, tint: accentColor)

                    if let focusPrompt = summary.focusPrompt, !focusPrompt.isEmpty {
                        HomeDeckHealthInsightLine(icon: "text.quote", text: focusPrompt, tint: .orange)
                    }
                }

                HStack(spacing: 10) {
                    if let lastOpenedLabel = summary.lastOpenedLabel {
                        HomeDeckHealthFooterPill(
                            icon: "clock.arrow.circlepath",
                            text: lastOpenedLabel,
                            tint: .secondary
                        )
                    }

                    if summary.isRecentlyOpened {
                        HomeDeckHealthFooterPill(
                            icon: "sparkles.rectangle.stack",
                            text: "Recent deck",
                            tint: accentColor
                        )
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(accentColor)
                        .padding(10)
                        .background(accentColor.opacity(0.12), in: Circle())
                }
            }
            .padding(18)
            .widgetStyle(cornerRadius: 26)
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(accentColor.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: accentColor.opacity(0.10), radius: 14, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Support Views

private struct HomeDeckMasteryMeter: View {
    let progress: Double
    let valueLabel: String
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 10)

            Circle()
                .trim(from: 0, to: max(min(progress, 1), 0))
                .stroke(
                    AngularGradient(
                        colors: [tint.opacity(0.45), tint],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 2) {
                Text(valueLabel)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Mastery")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 70, height: 70)
    }
}

private struct HomeDeckHealthBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.black))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct HomeDeckHealthStatPill: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.caption.weight(.heavy))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct HomeDeckHealthInsightLine: View {
    let icon: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
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

private struct HomeDeckHealthFooterPill: View {
    let icon: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)

            Text(text)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.05), in: Capsule())
    }
}
