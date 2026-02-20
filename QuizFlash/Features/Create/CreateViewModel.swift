//
//  CreateViewModel.swift
//  QuizFlash
//
//  Created by Ion Socol on 17.02.2026.
//

import SwiftUI
import SwiftData
import PhotosUI

@Observable
@MainActor
final class CreateViewModel {

    // MARK: - AI State
    var aiState: AIGenerationState = .idle
    var showAIPickerOptions = false
    var showAIPhotoPicker = false
    var showAIPDFPicker = false
    var selectedAIPhoto: PhotosPickerItem? = nil {
        didSet { if let item = selectedAIPhoto { processPhotoForAI(item) } }
    }
    
    // Private services
    private let textExtractor = TextExtractionService()
    private let aiService = AIFlashcardService()

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

    // MARK: - AI Processing Pipeline
    
    func processPhotoForAI(_ item: PhotosPickerItem) {
        aiState = .extractingText
        
        Task {
            do {
                // 1. Load image data
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    throw TextExtractionError.invalidImage 
                }
                
                // 2. Extract Text (Actor handles off-main-thread)
                let text = try await textExtractor.extractText(from: image)
                
                // 3. Pass to AI
                await generateCardsFromText(text)
                
            } catch {
                await MainActor.run { aiState = .error(error.localizedDescription) }
            }
            // Clear selection
            selectedAIPhoto = nil
        }
    }
    
    func processPDFForAI(url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            aiState = .error("Cannot access the selected PDF.")
            return
        }
        
        aiState = .extractingText
        
        Task {
            do {
                // 1. Extract Text (Actor handles off-main-thread)
                let text = try await textExtractor.extractText(fromPDFAt: url)
                url.stopAccessingSecurityScopedResource()
                
                // 2. Pass to AI
                await generateCardsFromText(text)
                
            } catch {
                url.stopAccessingSecurityScopedResource()
                await MainActor.run { aiState = .error(error.localizedDescription) }
            }
        }
    }
    
    private func generateCardsFromText(_ text: String) async {
        guard !text.isEmpty else {
            await MainActor.run { aiState = .error("No readable text found. Please try a clearer document.") }
            return
        }
        
        await MainActor.run { aiState = .generatingCards(progress: 0, foundCount: 0) }
        
        do {
            // Call AI Service
            let generatedCards = try await aiService.generateFlashcards(from: text)
            
            await MainActor.run {
                // Map AI models to your App models and inject them with animation
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    for aiCard in generatedCards {
                        let newDraft = DraftCard(
                            frontZone: .text(aiCard.question),
                            backZone: .text(aiCard.answer),
                            frontType: .text,
                            backType: .text,
                            createdAt: Date(),
                            editedAt: Date()
                        )
                        self.draftCards.append(newDraft)
                    }
                    self.aiState = .idle
                }
                
                // Trigger success haptic
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        } catch {
            await MainActor.run { aiState = .error(error.localizedDescription) }
        }
    }
    
    func resetAIState() {
        withAnimation { aiState = .idle }
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
