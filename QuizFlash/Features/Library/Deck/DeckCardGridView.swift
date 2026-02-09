//
//  DeckCardGridView.swift
//  QuizFlash
//
//  Created by Ion Socol on 08.02.2026.
//

import SwiftUI
import SwiftData

struct DeckCardGridView: View {
    // Models for sections
    struct CardSection: Identifiable {
        let id: String
        let title: String
        let cards: [CardModel]
        var dateForSorting: Date? = nil
    }

    let cards: [CardSection]
    let isSelecting: Bool
    let selectedCards: Set<PersistentIdentifier>

    // Actions
    var onToggleSelection: (CardModel) -> Void
    var onTapCard: (CardModel) -> Void
    var onLongPressCard: (CardModel) -> Void


    private var accent: Color { ThemeManager.shared.accentColor.color }
    private let gridColumns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    var body: some View {
        LazyVStack(spacing: 0, pinnedViews: []) {
            if cards.isEmpty && !isSelecting {
                emptyState
            } else {
                ForEach(cards) { section in
                    Section {
                        LazyVGrid(columns: gridColumns, spacing: 16) {
                            ForEach(section.cards) { card in
                                cardCell(for: card)

                            }
                        }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 16)
                    } header: {
                        if section.id != "all" {
                            Text(section.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(.ultraThinMaterial, in: Capsule())
                                .padding(.bottom, 16)


                        }
                    }
                }
            }
        }
    }

    // MARK: - Card Cell Logic
    @ViewBuilder
    private func cardCell(for card: CardModel) -> some View {
        let isSelected = selectedCards.contains(card.id)

        ZStack(alignment: .topLeading) {
            // 1. Content Button
            Button {
                if isSelecting {
                    onToggleSelection(card)
                } else {
                    onTapCard(card)
                }
            } label: {
                FlipCardPreview(card: card, isPreviewMode: true, isFlipped: .constant(false))
                // Visual changes on Selection
                .background {
                    if isSelecting && isSelected {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .stroke(.gray.opacity(0.7), lineWidth: 2)
                            .transition(.opacity)
                    }
                }
                    .scaleEffect(isSelecting && isSelected ? 0.9 : 1)
                    .animation(.spring(response: 0.32, dampingFraction: 0.85), value: isSelected)
            }
                .buttonStyle(ScaleButtonStyle())
                .contextMenu {
                // Hide context menu while multi-select is active.
                if !isSelecting {
                    Button(role: .destructive) {
                        onLongPressCard(card)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }

            // 2. Selection Indicator (Overlay)
            if isSelecting {
                Button {
                    onToggleSelection(card)
                } label: {
                    ZStack {
                        Circle()
                            .strokeBorder(
                            isSelected ? accent : Color.secondary.opacity(0.3),
                            lineWidth: 2
                        )

                        if isSelected {
                            Circle()
                                .fill(accent)

                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .transition(.scale)
                        }
                    }
                        .frame(width: 28, height: 28)
                        .background(.ultraThinMaterial, in: Circle())
                        .offset(x: 100, y: 10)
                }
                    .padding(12)
                    .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isSelected)
            }
        }
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)

            Text("No cards yet")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Text("Tap + to add your first card")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
            .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
            .padding(.horizontal, 20)
    }
}
