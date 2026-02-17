//
//  CreateViewModel.swift
//  QuizFlash
//
//  Created by Ion Socol on 17.02.2026.
//
//
//  CreateViewModel.swift
//  QuizFlash
//

import SwiftUI
import SwiftData

@Observable
@MainActor
final class CreateViewModel {
    
    // MARK: - State
    var deckTitle: String = ""
    var draftCards: [DraftCard] = []
    
    // MARK: - Sheet Control
    var cardToEdit: DraftCard?
    var isCreatingNewCard = false
    
    // MARK: - UI Feedback
    var showSuccessOverlay = false
    
    let deckToEdit: DeckModel?
    
    init(deckToEdit: DeckModel? = nil) {
        self.deckToEdit = deckToEdit
        if let deck = deckToEdit {
            self.deckTitle = deck.title
            self.draftCards = deck.cards.map { DraftCard.from($0) }
        }
    }
    
    // MARK: - Card Actions
    func addCard(frontZone: ZoneModel, backZone: ZoneModel) {
        let newCard = DraftCard(
            frontZone: frontZone,
            backZone: backZone,
            frontType: .text,
            backType: .text,
            createdAt: Date(),
            editedAt: Date()
        )
        withAnimation {
            draftCards.append(newCard)
        }
    }
    
    func updateCard(_ card: DraftCard, frontZone: ZoneModel, backZone: ZoneModel) {
        if let index = draftCards.firstIndex(where: { $0.id == card.id }) {
            var updatedCard = draftCards[index]
            
            // Verificăm dacă s-a modificat efectiv ceva
            let changed = updatedCard.frontZone != frontZone || updatedCard.backZone != backZone
            
            updatedCard.frontZone = frontZone
            updatedCard.backZone = backZone
            
            if changed {
                updatedCard.editedAt = Date() // Modificăm timpul de editare pentru UI-ul curent
            }
            
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
    
    // MARK: - Save Logic
    func saveDeck(context: ModelContext, router: NavigationManager, dismiss: DismissAction) {
        let trimmedTitle = deckTitle.trimmingCharacters(in: .whitespaces)
        
        if let deck = deckToEdit {
            // Edit mode: Update existing deck (SMART SYNC)
            let titleChanged = deck.title != trimmedTitle
            deck.title = trimmedTitle
            
            var cardsChanged = false
            let draftOriginalIDs = Set(draftCards.compactMap { $0.originalCardID })
            
            // 1. Ștergem DOAR cardurile care au fost eliminate din lista de draft
            let cardsToDelete = deck.cards.filter { !draftOriginalIDs.contains($0.id) }
            for card in cardsToDelete {
                context.delete(card)
                deck.cards.removeAll { $0.id == card.id }
                cardsChanged = true
            }
            
            // 2. Actualizăm cardurile existente sau adăugăm unele noi
            for draft in draftCards {
                if let originalID = draft.originalCardID,
                   let existingCard = deck.cards.first(where: { $0.id == originalID }) {
                    
                    let frontChanged = existingCard.frontZone != draft.frontZone
                    let backChanged = existingCard.backZone != draft.backZone
                    
                    if frontChanged || backChanged {
                        existingCard.frontZone = draft.frontZone
                        existingCard.backZone = draft.backZone
                        existingCard.frontType = draft.frontType
                        existingCard.backType = draft.backType
                        existingCard.editedAt = Date() // Actualizăm în BD doar pe cel modificat
                        cardsChanged = true
                    }
                } else {
                    // 3. Card nou
                    let newCard = CardModel(
                        frontZone: draft.frontZone,
                        backZone: draft.backZone,
                        frontType: draft.frontType,
                        backType: draft.backType
                    )
                    deck.cards.append(newCard)
                    cardsChanged = true
                }
            }
            
            // Dacă au fost modificate/adăugate/șterse carduri sau titlul, edităm deck-ul
            if titleChanged || cardsChanged {
                deck.editedAt = Date()
            }
            
        } else {
            // New Deck mode
            let newDeck = DeckModel(
                title: trimmedTitle,
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
                self.showSuccessOverlay = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if self.deckToEdit == nil {
                    self.resetForm()
                    router.popToRoot()
                } else {
                    dismiss()
                }
            }
        }
    }
    
    private func resetForm() {
        deckTitle = ""
        draftCards = []
        cardToEdit = nil
        isCreatingNewCard = false
    }
}
