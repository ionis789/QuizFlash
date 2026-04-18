// HomeRecentDeckCardView.swift
// QuizFlash
//
// A horizontal ticket-style card for the Recently Opened carousel in HomeDashboardView.

import SwiftUI

// MARK: - Recent Deck Card

/// A compact, fixed-width card that represents a recently opened deck.
///
/// Designed for horizontal scroll carousels. The relative time label is computed
/// once at render time by `HomeViewModel.relativeTimeLabel(for:)` — avoiding the
/// `Text(.relative)` re-render trap that would update every card every second via
/// SwiftUI's internal timer publisher.
struct HomeRecentDeckCardView: View {
    @Environment(ThemeManager.self) private var themeManager

    // MARK: - Input

    /// The deck to display.
    let deck: DeckModel
    let usesRegularMetrics: Bool

    /// Called when the user taps the card.
    let action: () -> Void

    // MARK: - Body

    var body: some View {
        let deckColor = Color(hex: deck.colorHex) ?? ThemeManager.shared.accentColor.color

        Button(action: action) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(deck.title)
                        .font(.headline.weight(.semibold))
                        .fontDesign(.rounded)
                        .foregroundStyle(themeManager.textPrimary)
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

                        // Relative time label — computed once at render time by the VM.
                        if let lastOpened = deck.lastOpenedAt {
                            Text("• \(HomeViewModel.relativeTimeLabel(for: lastOpened))")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(themeManager.textSecondary)
                        }
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(deckColor)
                    .padding(10)
                    .background(deckColor.opacity(0.12), in: Circle())
            }
            .padding(usesRegularMetrics ? 16 : 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .flashcardStyle(cornerRadius: 24, surfaceRole: .widget)
        }
        .buttonStyle(.plain)
    }
}
