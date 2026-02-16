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
    @Environment(NavigationManager.self) var router

    var deckToEdit: DeckModel?

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

            // Success overlay: blur background + centered card, then dismiss to Library
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
            AddCardSheetView { frontZone, backZone in
                addCard(frontZone: frontZone, backZone: backZone)
            }
        }
        .fullScreenCover(item: $cardToEdit) { card in
            AddCardSheetView(
                frontZone: card.frontZone,
                backZone: card.backZone
            ) { frontZone, backZone in
                updateCard(card, frontZone: frontZone, backZone: backZone)
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
                LazyVStack(spacing: 12) {
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
                            .transition(.scale(scale: 0.96).combined(with: .opacity))
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
        ZStack {
            // Blur pe tot ecranul
            Color.clear.background(.ultraThinMaterial).ignoresSafeArea()
            VStack {
                Spacer(minLength: 60)
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce, value: showSuccessOverlay)
                    Text("Deck Saved!")
                        .font(.title2.weight(.bold))
                    Text("\(draftCards.count) card\(draftCards.count == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 28)
                .padding(.horizontal, 44)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.regularMaterial)
                        .shadow(color: .black.opacity(0.18), radius: 24, y: 12)
                )
                .scaleEffect(showSuccessOverlay ? 1 : 0.7, anchor: .top)
                .opacity(showSuccessOverlay ? 1 : 0)
                .offset(y: showSuccessOverlay ? 0 : -80)
                .animation(.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0.15), value: showSuccessOverlay)
                Spacer()
            }
        }
        .transition(.opacity)
        .zIndex(100)
        .allowsHitTesting(false)
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

    func addCard(frontZone: ZoneModel, backZone: ZoneModel) {
        let newCard = DraftCard(
            frontZone: frontZone,
            backZone: backZone,
            frontType: .text,
            backType: .text
        )
        withAnimation {
            draftCards.append(newCard)
        }
    }

    func updateCard(_ card: DraftCard, frontZone: ZoneModel, backZone: ZoneModel) {
        if let index = draftCards.firstIndex(where: { $0.id == card.id }) {
            var updatedCard = draftCards[index]
            updatedCard.frontZone = frontZone
            updatedCard.backZone = backZone
            
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
                    frontZone: draft.frontZone,
                    backZone: draft.backZone,
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
                    frontZone: draft.frontZone,
                    backZone: draft.backZone,
                    frontType: draft.frontType,
                    backType: draft.backType
                )
                newCard.deck = newDeck
            }
        }

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            showSuccessOverlay = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
            withAnimation(.easeOut(duration: 0.25)) {
                showSuccessOverlay = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if deckToEdit == nil {
                    resetForm()
                    router.popToRoot()
                } else {
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
