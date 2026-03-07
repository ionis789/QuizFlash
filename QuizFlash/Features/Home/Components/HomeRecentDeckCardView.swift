//
//  RecentDeckCardView.swift
//  QuizFlash
//
//  Created by Ion Socol on 07.03.2026.
//

import SwiftUI

// MARK: - Recent Deck Card (Ticket Style)
/// A horizontal, sleek card optimized for side-scrolling, displaying static time information.
struct HomeRecentDeckCardView: View {
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
