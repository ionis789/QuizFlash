//
//  CreateView.swift
//  QuizFlash
//
//  Created by Ion Socol on 23.12.2025.
//
//  Deck creation and editing view with Apple Notes-style card editor.
//

import SwiftUI
import SwiftData

struct CreateView: View {
    @Environment(\.modelContext) var context
    @Environment(\.dismiss) var dismiss

    var deckToEdit: DeckModel?
    var onSwitchToLibrary: (() -> Void)?

    // MARK: - State
    @State private var deckTitle: String = ""
    @State private var draftCards: [DraftCard] = []

    // Sheet Control
    @State private var cardToEdit: DraftCard?
    @State private var isCreatingNewCard = false

    // UI Feedback
    @State private var showSuccessOverlay = false
    
    @FocusState private var isTitleFocused: Bool
    
    private var accent: Color { ThemeManager.shared.accentColor.color }

    var body: some View {
        ZStack {
            // Background - tap to dismiss keyboard
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    isTitleFocused = false
                }

            // Content
            ScrollView {
                VStack(spacing: 24) {
                    deckInfoSection
                    cardsListSection
                    Color.clear.frame(height: 80)
                }
            }
            .scrollDismissesKeyboard(.interactively)

            // Success overlay - slides from top
            if showSuccessOverlay {
                successOverlay
                    .zIndex(100)
            }
        }
        .onAppear {
            // Focus on title only if new deck
            if deckToEdit == nil && deckTitle.isEmpty {
                isTitleFocused = true
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: draftCards.count)
        .navigationTitle(deckToEdit == nil ? "Create Deck" : "Edit Deck")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Save") {
                    saveDeck()
                }
                .fontWeight(.semibold)
                .disabled(deckTitle.trimmingCharacters(in: .whitespaces).isEmpty || draftCards.isEmpty)
            }

            if deckToEdit != nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear(perform: loadExistingData)
        // Full screen cover for card creation/editing (iPad support)
        .fullScreenCover(isPresented: $isCreatingNewCard) {
            AddCardSheetView { frontContent, backContent in
                addCard(frontContent: frontContent, backContent: backContent)
            }
        }
        .fullScreenCover(item: $cardToEdit) { card in
            AddCardSheetView(
                frontContent: card.frontContent,
                backContent: card.backContent
            ) { frontContent, backContent in
                updateCard(card, frontContent: frontContent, backContent: backContent)
            }
        }
    }
}

// MARK: - Subviews
private extension CreateView {

    var deckInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DECK TITLE")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            HStack(spacing: 12) {
                TextField("Enter deck title...", text: $deckTitle)
                    .font(.body)
                    .focused($isTitleFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        isTitleFocused = false
                    }
                
                if !deckTitle.isEmpty && isTitleFocused {
                    Button {
                        deckTitle = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(accent.opacity(isTitleFocused ? 0.15 : 0))
                    .padding(-2)
            )
            .scaleEffect(isTitleFocused ? 1.01 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isTitleFocused)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    var cardsListSection: some View {
        VStack(spacing: 14) {
            // Header
            HStack {
                Text("CARDS")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text("(\(draftCards.count))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer()

                Button {
                    isTitleFocused = false
                    isCreatingNewCard = true
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .padding(.horizontal, 24)

            if draftCards.isEmpty {
                emptyStateView
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(draftCards) { card in
                        CardRowView(card: card)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                isTitleFocused = false
                                cardToEdit = card
                            }
                            .contextMenu {
                                Button {
                                    cardToEdit = card
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }

                                Button(role: .destructive) {
                                    deleteCard(card)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .transition(.scale(scale: 0.95).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    var emptyStateView: some View {
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
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 20)
        .onTapGesture {
            isTitleFocused = false
            isCreatingNewCard = true
        }
    }

    var successOverlay: some View {
        VStack {
            // Success banner from top
            VStack(spacing: 16) {
                HStack(spacing: 14) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce, value: showSuccessOverlay)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Deck Saved!")
                            .font(.subheadline.weight(.semibold))
                        
                        Text("\(draftCards.count) cards added")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
                )
                .padding(.horizontal, 20)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            
            Spacer()
        }
        .padding(.top, 8)
    }
}

// MARK: - Logic & Helpers
private extension CreateView {

    func loadExistingData() {
        if let deck = deckToEdit {
            deckTitle = deck.title
            draftCards = deck.cards.map { DraftCard.from($0) }
        }
    }

    func addCard(frontContent: CardSideContent, backContent: CardSideContent) {
        let newCard = DraftCard(
            frontContent: frontContent,
            backContent: backContent,
            frontType: .text,
            backType: .text
        )
        withAnimation {
            draftCards.append(newCard)
        }
    }

    func updateCard(_ card: DraftCard, frontContent: CardSideContent, backContent: CardSideContent) {
        if let index = draftCards.firstIndex(where: { $0.id == card.id }) {
            var updatedCard = draftCards[index]
            updatedCard.frontContent = frontContent
            updatedCard.backContent = backContent
            
            withAnimation {
                draftCards[index] = updatedCard
            }
        }
    }

    func deleteCard(_ card: DraftCard) {
        withAnimation {
            draftCards.removeAll { $0.id == card.id }
        }
    }

    func saveDeck() {
        isTitleFocused = false
        
        if let deck = deckToEdit {
            // Edit mode: Update existing deck
            deck.title = deckTitle.trimmingCharacters(in: .whitespaces)
            deck.cards.removeAll()
            
            for draft in draftCards {
                let newCard = CardModel(
                    frontContent: draft.frontContent,
                    backContent: draft.backContent,
                    frontType: draft.frontType,
                    backType: draft.backType
                )
                deck.cards.append(newCard)
            }
            deck.editedAt = Date()
        } else {
            // New Deck
            let newDeck = DeckModel(
                title: deckTitle.trimmingCharacters(in: .whitespaces),
                icon: "book.closed.fill",
                colorHex: "#FFFFFF"
            )
            context.insert(newDeck)
            
            for draft in draftCards {
                let newCard = CardModel(
                    frontContent: draft.frontContent,
                    backContent: draft.backContent,
                    frontType: draft.frontType,
                    backType: draft.backType
                )
                newCard.deck = newDeck
            }
        }

        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            showSuccessOverlay = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeOut(duration: 0.3)) {
                showSuccessOverlay = false
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                if deckToEdit == nil {
                    resetForm()
                }
                
                if let switchAction = onSwitchToLibrary {
                    switchAction()
                } else if deckToEdit != nil {
                    dismiss()
                }
            }
        }
    }

    func resetForm() {
        deckTitle = ""
        draftCards = []
        cardToEdit = nil
        isCreatingNewCard = false
    }
}
