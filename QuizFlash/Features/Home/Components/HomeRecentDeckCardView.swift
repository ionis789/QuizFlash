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

    // MARK: - Input

    /// The deck to display.
    let deck: DeckModel

    /// Called when the user taps the card.
    let action: () -> Void

    // MARK: - Body

    var body: some View {
        let deckColor = Color(hex: deck.colorHex) ?? ThemeManager.shared.accentColor.color

        Button(action: action) {
            HStack(spacing: 16) {

                // MARK: Color Block with Icon

                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(deckColor.gradient)

                    Image(systemName: deck.icon)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 60, height: 60)

                // MARK: Text Content

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

                        // Relative time label — computed once at render time by the VM.
                        if let lastOpened = deck.lastOpenedAt {
                            Text("• \(HomeViewModel.relativeTimeLabel(for: lastOpened))")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
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
            .padding(14)
            .frame(width: 260)
            .widgetStyle(cornerRadius: 24)
        }
        .buttonStyle(.plain)
    }
}
