//
//  CreateView.swift
//  QuizFlash
//
//  Created by Ion Socol on 23.12.2025.
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
            isTitleFocused = true
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
        .onTapGesture {
            hideKeyboard()
        }
        .sheet(isPresented: $isCreatingNewCard) {
            AddCardSheetView(initialFront: "", initialBack: "") { front, back in
                addCard(front: front, back: back)
            }
        }
        .sheet(item: $cardToEdit) { card in
            AddCardSheetView(initialFront: card.front, initialBack: card.back) { front, back in
                updateCard(card, newFront: front, newBack: back)
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
                    .fill(ThemeManager.shared.accentColor.color.opacity(isTitleFocused ? 0.15 : 0))
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

// MARK: - Logic
private extension CreateView {

    func loadExistingData() {
        if let deck = deckToEdit {
            deckTitle = deck.title
            draftCards = deck.cards.map { DraftCard(front: $0.frontText, back: $0.backText) }
        }
    }

    func addCard(front: String, back: String) {
        let newCard = DraftCard(front: front, back: back)
        withAnimation {
            draftCards.append(newCard)
        }
    }

    func updateCard(_ card: DraftCard, newFront: String, newBack: String) {
        if let index = draftCards.firstIndex(where: { $0.id == card.id }) {
            var updatedCard = draftCards[index]
            updatedCard.front = newFront
            updatedCard.back = newBack
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
            // Edit mode
            deck.title = deckTitle.trimmingCharacters(in: .whitespaces)
            deck.cards.removeAll()
            for draft in draftCards {
                let newCard = CardModel(frontText: draft.front, backText: draft.back)
                deck.cards.append(newCard)
            }
            deck.editedAt = Date()
        } else {
            let newDeck = DeckModel(
                title: deckTitle.trimmingCharacters(in: .whitespaces),
                icon: "book.closed.fill",
                colorHex: "#035efc"
            )
            context.insert(newDeck)
            for draft in draftCards {
                let newCard = CardModel(frontText: draft.front, backText: draft.back)
                newCard.deck = newDeck
            }
        }

        // Show success banner sliding from top
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            showSuccessOverlay = true
        }

        // Dismiss after delay
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

extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
