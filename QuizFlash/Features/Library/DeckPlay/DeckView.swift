//
//  DeckView.swift
//  QuizFlash
//
//  Created by Ion Socol on 08.01.2026.
//

import SwiftUI
import SwiftData

struct DeckView: View {
    @Environment(\.modelContext) var context
    @Bindable var deck: DeckModel

    @State private var isAddingCard = false
    @State private var isPresentingEdit = false
    @State private var isPlayingQuiz = false
    @State private var isSelecting = false
    @State private var selectedCards: Set<PersistentIdentifier> = []
    @State private var showDeleteConfirmation = false
    
    private var accentColor: Color {
        ThemeManager.shared.accentColor.color
    }
    
    private var deckColor: Color {
        Color(hex: deck.colorHex) ?? accentColor
    }

    private var gridColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
    }
    
    private var sortedCards: [CardModel] {
        deck.cards.sorted { $0.createdAt > $1.createdAt }
    }
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: deck.creationDate)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Fixed header
            headerSection
            
            // Scrollable cards list only
            ScrollView {
                VStack(spacing: 16) {
                    // Play modes
                    playModesSection
                    
                    // Selection toolbar for cards
                    cardsToolbar
                    
                    // Cards section
                    cardsSection
                }
                .padding(.bottom, 100)
            }
            .scrollIndicators(.hidden)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isSelecting)
        .confirmationDialog(
            "Delete \(selectedCards.count) card\(selectedCards.count == 1 ? "" : "s")?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteSelectedCards()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .sheet(isPresented: $isAddingCard) {
            AddCardSheetView { front, back in
                let newCard = CardModel(frontText: front, backText: back)
                deck.cards.append(newCard)
                context.insert(newCard)
                deck.lastEditedDate = Date()
            }
        }
        .sheet(isPresented: $isPresentingEdit) {
            CreateView(deckToEdit: deck)
        }
        .fullScreenCover(isPresented: $isPlayingQuiz) {
            NavigationStack {
                DefaultModePlay(deck: deck)
            }
        }
    }
    
    // MARK: - Header Section (Fixed)
    private var headerSection: some View {
        VStack(spacing: 16) {
            // Icon + Title
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [deckColor.opacity(0.7), deckColor.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: deck.icon.isEmpty ? "sparkles.rectangle.stack.fill" : deck.icon)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(deck.title)
                        .font(.title3.weight(.bold))
                        .lineLimit(1)
                    
                    HStack(spacing: 8) {
                        Label("\(deck.cards.count)", systemImage: "rectangle.stack")
                        Text("•")
                        Text(formattedDate)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Edit button
                Button {
                    isPresentingEdit = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.subheadline.weight(.semibold))
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }
    
    // MARK: - Play Modes Section
    private var playModesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PLAY MODES")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ModeButton(title: "Default", systemImage: "play.fill", color: accentColor, isActive: true) {
                        if !deck.cards.isEmpty {
                            isPlayingQuiz = true
                        }
                    }
                    .disabled(deck.cards.isEmpty)
                    .opacity(deck.cards.isEmpty ? 0.5 : 1)

                    ModeButton(title: "Timed", systemImage: "timer", color: accentColor, isActive: false, action: {})
                        .disabled(true)
                        .opacity(0.4)

                    ModeButton(title: "Match", systemImage: "square.grid.2x2", color: accentColor, isActive: false, action: {})
                        .disabled(true)
                        .opacity(0.4)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
        }
    }
    
    // MARK: - Cards Toolbar
    private var cardsToolbar: some View {
        HStack(spacing: 12) {
            Text("CARDS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            
            Spacer()
            
            if !deck.cards.isEmpty {
                // Select/Done button
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        isSelecting.toggle()
                        if !isSelecting {
                            selectedCards.removeAll()
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isSelecting ? "checkmark" : "checkmark.circle")
                            .font(.subheadline.weight(.semibold))
                        Text(isSelecting ? "Done" : "Select")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(isSelecting ? accentColor.opacity(0.15) : Color(uiColor: .secondarySystemGroupedBackground))
                    )
                    .foregroundStyle(isSelecting ? accentColor : .primary)
                }
                
                // Delete button (appears when selecting and has items)
                if isSelecting && !selectedCards.isEmpty {
                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                                .font(.subheadline.weight(.semibold))
                            Text("(\(selectedCards.count))")
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.red.opacity(0.12))
                        )
                        .foregroundStyle(.red)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            
            // Add button
            Button {
                isAddingCard = true
            } label: {
                Image(systemName: "plus")
                    .font(.subheadline.weight(.semibold))
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Cards Section
    private var cardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if deck.cards.isEmpty {
                emptyStateView
            } else {
                LazyVGrid(columns: gridColumns, spacing: 16) {
                    ForEach(sortedCards) { card in
                        cardCell(for: card)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
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
        .padding(.vertical, 40)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .padding(.horizontal, 20)
        .onTapGesture {
            isAddingCard = true
        }
    }
    
    // MARK: - Card Cell
    @ViewBuilder
    private func cardCell(for card: CardModel) -> some View {
        ZStack(alignment: .topLeading) {
            FlipCardPreview(card: card, isPreviewMode: true, isFlipped: .constant(false))
            
            if isSelecting {
                // Selection circle overlay
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        toggleSelection(card)
                    }
                } label: {
                    ZStack {
                        Circle()
                            .strokeBorder(
                                selectedCards.contains(card.id) ? accentColor : Color.secondary.opacity(0.3),
                                lineWidth: 2
                            )
                            .frame(width: 28, height: 28)
                        
                        if selectedCards.contains(card.id) {
                            Circle()
                                .fill(accentColor)
                                .frame(width: 28, height: 28)
                            
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 34, height: 34)
                    )
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedCards.contains(card.id))
                }
                .padding(10)
                .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .onTapGesture {
            if isSelecting {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    toggleSelection(card)
                }
            }
        }
    }
    
    // MARK: - Actions
    private func toggleSelection(_ card: CardModel) {
        if selectedCards.contains(card.id) {
            selectedCards.remove(card.id)
        } else {
            selectedCards.insert(card.id)
        }
    }
    
    private func deleteSelectedCards() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            for card in deck.cards where selectedCards.contains(card.id) {
                context.delete(card)
                deck.cards.removeAll { $0.id == card.id }
            }
            selectedCards.removeAll()
            isSelecting = false
            deck.lastEditedDate = Date()
        }
    }
}

// MARK: - Supporting Views

private struct StatPill: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

private struct ModeButton: View {
    let title: String
    let systemImage: String
    let color: Color
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))

                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isActive
                        ? color.opacity(0.15)
                        : Color(uiColor: .secondarySystemGroupedBackground))
            )
            .foregroundStyle(isActive ? color : .secondary)
        }
    }
}
