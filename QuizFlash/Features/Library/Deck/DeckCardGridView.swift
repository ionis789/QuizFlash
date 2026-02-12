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

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var accent: Color { ThemeManager.shared.accentColor.color }
    
    // Adaptive columns based on screen size
    private var gridColumns: [GridItem] {
        if horizontalSizeClass == .regular {
            return [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 16)]
        }
        return [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
    }

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

    // MARK: - Card Cell
    @ViewBuilder
    private func cardCell(for card: CardModel) -> some View {
        let isSelected = selectedCards.contains(card.id)

        Button {
            if isSelecting {
                onToggleSelection(card)
            } else {
                onTapCard(card)
            }
        } label: {
            MiniCardPreview(card: card, isSelected: isSelecting && isSelected)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if isSelecting {
                SelectionBubble(isSelected: isSelected, accent: accent)
                    .padding(10)
            }
        }
        .scaleEffect(isSelecting && isSelected ? 0.96 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
        .contextMenu {
            if !isSelecting {
                Button(role: .destructive) {
                    onLongPressCard(card)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
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

// MARK: - Mini Card Preview (Simple thumbnail)

private struct MiniCardPreview: View {
    let card: CardModel
    var isSelected: Bool = false
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var accent: Color { ThemeManager.shared.accentColor.color }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Question preview
            questionPreview
            
            Spacer(minLength: 0)
            
            // Bottom info
            HStack(spacing: 6) {
                if hasImages {
                    Image(systemName: "photo")
                        .font(.caption2)
                }
                if hasSketch {
                    Image(systemName: "scribble.variable")
                        .font(.caption2)
                }
                Spacer()
                Text("Q&A")
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 120)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? accent : borderColor, lineWidth: isSelected ? 2 : 0.5)
        )
    }
    
    @ViewBuilder
    private var questionPreview: some View {
        let zone = card.frontZone
        let text = getFirstText(from: zone) ?? ""
        let imageData = getFirstImage(from: zone)
        
        if let data = imageData, let img = UIImage(data: data) {
            // Show image thumbnail
            HStack(spacing: 10) {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                if !text.isEmpty {
                    Text(text)
                        .font(.subheadline)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
        } else if !text.isEmpty {
            Text(text)
                .font(.subheadline)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        } else {
            Text("Empty card")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
    }
    
    private var hasImages: Bool {
        getFirstImage(from: card.frontZone) != nil || getFirstImage(from: card.backZone) != nil
    }
    
    private var hasSketch: Bool {
        hasSketchContent(in: card.frontZone) || hasSketchContent(in: card.backZone)
    }
    
    private var cardBackground: some ShapeStyle {
        colorScheme == .dark
            ? AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground))
            : AnyShapeStyle(Color.white)
    }
    
    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }
    
    // MARK: - Helpers
    
    private func getFirstText(from zone: ZoneModel) -> String? {
        if zone.isLeaf {
            if zone.contentType == .text && !zone.text.isEmpty {
                return zone.text
            }
        } else if let children = zone.children {
            for child in children {
                if let text = getFirstText(from: child) {
                    return text
                }
            }
        }
        return nil
    }
    
    private func getFirstImage(from zone: ZoneModel) -> Data? {
        if zone.isLeaf {
            if (zone.contentType == .image || zone.contentType == .sketch) && zone.imageData != nil {
                return zone.imageData
            }
        } else if let children = zone.children {
            for child in children {
                if let data = getFirstImage(from: child) {
                    return data
                }
            }
        }
        return nil
    }
    
    private func hasSketchContent(in zone: ZoneModel) -> Bool {
        if zone.isLeaf {
            return zone.contentType == .sketch && zone.imageData != nil
        } else if let children = zone.children {
            return children.contains { hasSketchContent(in: $0) }
        }
        return false
    }
}

// MARK: - Selection Bubble

private struct SelectionBubble: View {
    let isSelected: Bool
    let accent: Color
    
    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(isSelected ? accent : Color.secondary.opacity(0.3), lineWidth: 2)
            
            if isSelected {
                Circle()
                    .fill(accent)
                
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 24, height: 24)
        .background(.ultraThinMaterial, in: Circle())
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
    }
}
