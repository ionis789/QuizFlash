//
//  CreateViewModel.swift
//  QuizFlash
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
    
    // Înlocuim Sheet-ul cu un Overlay stabil
    var showAIOptionsOverlay = false
    
    var selectedAIPhotos: [PhotosPickerItem] = [] {
        didSet {
            if !selectedAIPhotos.isEmpty {
                showAIPickerOptions = false
                // Așteptăm puțin ca PhotosPicker să se închidă înainte să arătăm overlay-ul
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    withAnimation(.spring()) {
                        self.showAIOptionsOverlay = true
                    }
                }
            }
        }
    }
    
    var pendingPDFURL: URL? = nil
    var requestedCardCount: Int = 15

    private let aiService = AIFlashcardService()
    private let documentRenderer = DocumentRenderingService()
    
    // MARK: - State
    var deckTitle: String = ""
    var draftCards: [DraftCard] = []
    var cardToEdit: DraftCard?
    var isCreatingNewCard = false
    var showSuccessOverlay = false
    let deckToEdit: DeckModel?

    init(deckToEdit: DeckModel? = nil) {
        self.deckToEdit = deckToEdit
        if let deck = deckToEdit {
            self.deckTitle = deck.title
            self.draftCards = deck.cards.map { DraftCard.from($0) }
        }
    }
    
    func startAIGeneration() {
        if !selectedAIPhotos.isEmpty {
            processPhotosForAI()
        } else if let url = pendingPDFURL {
            processPDFForAI(url: url)
        }
    }

    // MARK: - AI Processing Pipeline
    private func processPhotosForAI() {
        aiState = .extractingText
        let items = selectedAIPhotos
        selectedAIPhotos = []

        Task {
            do {
                var images: [UIImage] = []
                for item in items {
                    if let data = try await item.loadTransferable(type: Data.self),
                       let originalImage = UIImage(data: data) {
                        // REPARAT: Compresăm și redimensionăm imaginea pentru a evita Timeout-ul la upload
                        let resizedImage = originalImage.resizedForAI(toMaxDimension: 1024)
                        images.append(resizedImage)
                    }
                }

                guard !images.isEmpty else {
                    await MainActor.run { aiState = .error("Nu am putut citi imaginile.") }
                    return
                }

                await MainActor.run { aiState = .generatingCards(progress: 0.0, foundCount: 0) }

                let generatedCards = try await aiService.generateFlashcards(
                    from: images,
                    targetCards: requestedCardCount,
                    onProgress: { progress, currentCount in
                        self.aiState = .generatingCards(progress: progress, foundCount: currentCount)
                    }
                )

                saveGeneratedCards(generatedCards)

            } catch {
                await MainActor.run { aiState = .error(error.localizedDescription) }
            }
        }
    }

    func processPDFForAI(url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            aiState = .error("Cannot access the selected PDF.")
            return
        }

        aiState = .extractingText
        pendingPDFURL = nil

        Task {
            do {
                let images = try await documentRenderer.renderPagesAsImages(fromPDFAt: url)
                url.stopAccessingSecurityScopedResource()

                await MainActor.run { aiState = .generatingCards(progress: 0.0, foundCount: 0) }

                let generatedCards = try await aiService.generateFlashcards(
                    from: images,
                    targetCards: requestedCardCount,
                    onProgress: { progress, currentCount in
                        self.aiState = .generatingCards(progress: progress, foundCount: currentCount)
                    }
                )

                saveGeneratedCards(generatedCards)

            } catch {
                url.stopAccessingSecurityScopedResource()
                await MainActor.run { aiState = .error(error.localizedDescription) }
            }
        }
    }
    
    private func saveGeneratedCards(_ generatedCards: [AIFlashcard]) {
        withAnimation(.spring()) {
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
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    func resetAIState() {
        withAnimation { aiState = .idle }
    }

    // MARK: - Card Actions
    func addCard(frontZone: ZoneModel, backZone: ZoneModel) {
        let newCard = DraftCard(frontZone: frontZone, backZone: backZone, frontType: .text, backType: .text, createdAt: Date(), editedAt: Date())
        withAnimation { draftCards.append(newCard) }
    }

    func updateCard(_ card: DraftCard, frontZone: ZoneModel, backZone: ZoneModel) {
        if let index = draftCards.firstIndex(where: { $0.id == card.id }) {
            var updatedCard = draftCards[index]
            let changed = updatedCard.frontZone != frontZone || updatedCard.backZone != backZone
            updatedCard.frontZone = frontZone
            updatedCard.backZone = backZone
            if changed { updatedCard.editedAt = Date() }
            withAnimation { draftCards[index] = updatedCard }
        }
    }

    func deleteCard(_ card: DraftCard) {
        withAnimation { draftCards.removeAll { $0.id == card.id } }
    }

    // MARK: - Save Logic
    func saveDeck(context: ModelContext, router: NavigationManager, dismiss: DismissAction) {
        let trimmedTitle = deckTitle.trimmingCharacters(in: .whitespaces)

        if let deck = deckToEdit {
            let titleChanged = deck.title != trimmedTitle
            deck.title = trimmedTitle

            var cardsChanged = false
            let draftOriginalIDs = Set(draftCards.compactMap { $0.originalCardID })

            let cardsToDelete = deck.cards.filter { !draftOriginalIDs.contains($0.id) }
            for card in cardsToDelete {
                context.delete(card)
                deck.cards.removeAll { $0.id == card.id }
                cardsChanged = true
            }

            for draft in draftCards {
                if let originalID = draft.originalCardID,
                   let existingCard = deck.cards.first(where: { $0.id == originalID }) {

                    let frontChanged = existingCard.frontZone != draft.frontZone
                    let backChanged = existingCard.backZone != draft.backZone

                    if frontChanged || backChanged {
                        existingCard.frontZone = draft.frontZone
                        existingCard.backZone = draft.backZone
                        existingCard.editedAt = Date()
                        cardsChanged = true
                    }
                } else {
                    let newCard = CardModel(frontZone: draft.frontZone, backZone: draft.backZone)
                    deck.cards.append(newCard)
                    cardsChanged = true
                }
            }

            if titleChanged || cardsChanged { deck.editedAt = Date() }

        } else {
            let newDeck = DeckModel(title: trimmedTitle, icon: "book.closed.fill", colorHex: "#FFFFFF")
            context.insert(newDeck)

            for draft in draftCards {
                let newCard = CardModel(frontZone: draft.frontZone, backZone: draft.backZone)
                newCard.deck = newDeck
            }
        }

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { showSuccessOverlay = true }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
            withAnimation(.easeOut(duration: 0.25)) { self.showSuccessOverlay = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if self.deckToEdit == nil {
                    self.resetForm()
                    router.popToRoot()
                } else { dismiss() }
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

// Extensie pentru redimensionarea pozelor uriașe din Galerie
extension UIImage {
    func resizedForAI(toMaxDimension maxDimension: CGFloat) -> UIImage {
        let size = self.size
        if size.width <= maxDimension && size.height <= maxDimension { return self }
        
        let scale = min(maxDimension / size.width, maxDimension / size.height)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        
        return renderer.image { _ in self.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
