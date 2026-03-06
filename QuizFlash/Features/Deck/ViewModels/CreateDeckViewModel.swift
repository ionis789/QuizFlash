//
//  CreateViewModel.swift
//  QuizFlash
//

import SwiftUI
import SwiftData
import PhotosUI
import PDFKit

@Observable
@MainActor
final class CreateDeckViewModel {

    // MARK: - AI State
    var aiState: AIGenerationState = .idle

    // MARK: - AI Picker UI
    var showAIPickerOptions = false
    var showAIPhotoPicker = false
    var showAIPDFPicker = false
    var showAIOptionsOverlay = false
    var isGenerating: Bool { aiState != .idle }
    var selectedFolder: FolderModel? = nil

    // MARK: - PDF Analysis
    // Populat automat când utilizatorul alege un PDF, înainte să apese Generează
    var pdfAnalysis: PDFAnalysisInfo? = nil

    // MARK: - Generation Settings
    var requestedCardCount: Int = 15
    var extractionMode: ExtractionMode = .fast

    // MARK: - Photos
    var selectedAIPhotos: [PhotosPickerItem] = [] {
        didSet {
            guard !selectedAIPhotos.isEmpty else { return }
            showAIPickerOptions = false
            // Pentru poze nu facem analiză — arătăm direct overlay-ul
            pdfAnalysis = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.spring()) { self.showAIOptionsOverlay = true }
            }
        }
    }

    var pendingPDFURL: URL? = nil

    // MARK: - Services
//    private let aiService = AIFlashcardService(apiKey: "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")
    private let aiService = AIFlashcardService(apiKey: "sk-a40ab294a6ea4efa91c003e8c1fccba2")

    // MARK: - Deck / Cards State
    var deckTitle: String = ""
    var draftCards: [DraftCard] = []
    var cardToEdit: DraftCard?
    var isCreatingNewCard = false
    var showSuccessOverlay = false
    let deckToEdit: DeckModel?

    init(deckToEdit: DeckModel? = nil) {
        self.deckToEdit = deckToEdit
        if let deck = deckToEdit {
            deckTitle = deck.title
            selectedFolder = deck.folder
            draftCards = deck.cards.map { DraftCard.from($0) }
        }
    }

    // =========================================================================
    // MARK: - PDF Selection + Auto-Analysis
    // Apelat din CreateView imediat ce utilizatorul a ales un PDF.
    // Rulează PDFKit quality check în background și populează pdfAnalysis
    // înainte ca overlay-ul să fie vizibil — fără delay perceptibil.
    // =========================================================================

    func pdfWasSelected(_ url: URL) {
        pendingPDFURL = url
        pdfAnalysis = nil

        // Rulăm analiza în background imediat
        Task {
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }

            let quality = DocumentTextExtractor.pdfKitQuality(for: url)
            let pageCount = await DocumentTextExtractor.pdfPageCount(url: url)
            let chars = DocumentTextExtractor.extractWithPDFKit(from: url)?.count ?? 0

            let info = PDFAnalysisInfo(
                quality: quality,
                pageCount: pageCount,
                extractedChars: chars
            )

            // Setăm automat modul recomandat
            self.pdfAnalysis = info
            self.extractionMode = info.recommendation

            // Deschidem overlay-ul abia după ce avem analiza
            withAnimation(.spring()) {
                self.showAIOptionsOverlay = true
            }
        }
    }

    // =========================================================================
    // MARK: - Start Generation
    // =========================================================================

    func startAIGeneration() {
        if !selectedAIPhotos.isEmpty {
            processPhotosForAI()
        } else if let url = pendingPDFURL {
            processPDFForAI(url: url)
        }
    }

    // =========================================================================
    // MARK: - Process Photos
    // Fast  → Vision OCR pe device (gratuit)
    // Quality → GPT Vision, toate imaginile într-un singur request
    // =========================================================================

    private func processPhotosForAI() {
        aiState = .extractingText
        let items = selectedAIPhotos
        selectedAIPhotos = []

        Task {
            do {
                // Încărcăm imaginile din PhotosPicker
                var images: [UIImage] = []
                for item in items {
                    if let data = try await item.loadTransferable(type: Data.self),
                        let image = UIImage(data: data) {
                        images.append(image.resizedForAI(toMaxDimension: 1024))
                    }
                }
                guard !images.isEmpty else { throw AIServiceError.parsingFailed }

                let cards: [AIFlashcard]

                switch extractionMode {
                case .fast:
                    // Vision OCR pe device → text → GPT text mode (ieftin)
                    let extraction = await DocumentTextExtractor.extract(from: images)
                    guard let text = extraction.text, !text.isEmpty else {
                        throw AIServiceError.parsingFailed
                    }
                    aiState = .generatingCards(progress: 0, foundCount: 0)
                    cards = try await aiService.generateFlashcards(
                        fromText: text,
                        targetCards: requestedCardCount
                    )

                case .quality:
                    // GPT Vision cu toate imaginile (mai scump, mai lent, înțelege diagrame)
                    aiState = .generatingCards(progress: 0, foundCount: 0)
                    cards = try await aiService.generateFlashcards(
                        from: images,
                        targetCards: requestedCardCount
                    )
                }

                saveGeneratedCards(cards)

            } catch {
                aiState = .error(error.localizedDescription)
            }
        }
    }

    // =========================================================================
    // MARK: - Process PDF
    // Fast    → DocumentTextExtractor pipeline: PDFKit → Vision OCR
    // Quality → Render pagini → GPT Vision, toate într-un singur request
    // =========================================================================

    private func processPDFForAI(url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            aiState = .error("Nu am putut accesa fișierul PDF.")
            return
        }

        pendingPDFURL = nil

        Task {
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let cards: [AIFlashcard]

                switch extractionMode {
                case .fast:
                    // Pipeline automat: PDFKit → Vision OCR pe device (gratuit)
                    aiState = .extractingText
                    let extraction = await DocumentTextExtractor.extract(from: url)

                    guard let text = extraction.text, !text.isEmpty else {
                        // Textul e prea slab — fallback automat la Quality
                        aiState = .generatingCards(progress: 0, foundCount: 0)
                        let images = await DocumentTextExtractor.renderPDFPages(from: url)
                        cards = try await aiService.generateFlashcards(
                            from: images,
                            targetCards: requestedCardCount
                        )
                        saveGeneratedCards(cards)
                        return
                    }

                    aiState = .generatingCards(progress: 0, foundCount: 0)
                    cards = try await aiService.generateFlashcards(
                        fromText: text,
                        targetCards: requestedCardCount
                    )

                case .quality:
                    // Render toate paginile → un singur request GPT Vision
                    aiState = .extractingText
                    let images = await DocumentTextExtractor.renderPDFPages(from: url, dpi: 150)
                    guard !images.isEmpty else { throw AIServiceError.parsingFailed }

                    aiState = .generatingCards(progress: 0, foundCount: 0)
                    cards = try await aiService.generateFlashcards(
                        from: images,
                        targetCards: requestedCardCount
                    )
                }

                saveGeneratedCards(cards)

            } catch {
                aiState = .error(error.localizedDescription)
            }
        }
    }

    // =========================================================================
    // MARK: - Save Cards
    // =========================================================================

    private func saveGeneratedCards(_ generatedCards: [AIFlashcard]) {
        withAnimation(.spring()) {
            for aiCard in generatedCards {
                let frontZone = AIZoneParser.parse(text: aiCard.question)
                let backZone = AIZoneParser.parse(text: aiCard.answer)
                let newDraft = DraftCard(
                    frontZone: frontZone,
                    backZone: backZone,
                    frontType: .text,
                    backType: .text,
                    createdAt: Date(),
                    editedAt: Date()
                )
                draftCards.append(newDraft)
            }
            aiState = .idle
            pdfAnalysis = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    func resetAIState() {
        withAnimation { aiState = .idle }
    }

    // =========================================================================
    // MARK: - Card Actions
    // =========================================================================

    func addCard(frontZone: ZoneModel, backZone: ZoneModel) {
        let newCard = DraftCard(
            frontZone: frontZone,
            backZone: backZone,
            frontType: .text,
            backType: .text,
            createdAt: Date(),
            editedAt: Date()
        )
        withAnimation { draftCards.append(newCard) }
    }

    func updateCard(_ card: DraftCard, frontZone: ZoneModel, backZone: ZoneModel) {
        guard let index = draftCards.firstIndex(where: { $0.id == card.id }) else { return }
        var updated = draftCards[index]
        let changed = updated.frontZone != frontZone || updated.backZone != backZone
        updated.frontZone = frontZone
        updated.backZone = backZone
        if changed { updated.editedAt = Date() }
        withAnimation { draftCards[index] = updated }
    }

    func deleteCard(_ card: DraftCard) {
        withAnimation { draftCards.removeAll { $0.id == card.id } }
    }

    // =========================================================================
    // MARK: - Save Deck
    // =========================================================================

    // =========================================================================
    // MARK: - Save Deck
    // =========================================================================

    func saveDeck(context: ModelContext, router: NavigationManager, dismiss: DismissAction) {
        let trimmedTitle = deckTitle.trimmingCharacters(in: .whitespaces)

        if let deck = deckToEdit {
            // ── UPDATE EXISTING DECK ──────────────────────────────────────────
            let titleChanged = deck.title != trimmedTitle
            deck.title = trimmedTitle

            if deck.folder != selectedFolder {
                deck.folder?.deckCount -= 1
                selectedFolder?.deckCount += 1
                deck.folder = selectedFolder
            }

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
                    let existing = deck.cards.first(where: { $0.id == originalID }) {
                    let frontChanged = existing.frontZone != draft.frontZone
                    let backChanged = existing.backZone != draft.backZone
                    if frontChanged || backChanged {
                        existing.frontZone = draft.frontZone
                        existing.backZone = draft.backZone
                        existing.editedAt = Date()
                        cardsChanged = true
                    }
                } else {
                    deck.lastAssignedCardNumber += 1
                    let newCard = CardModel(
                        frontZone: draft.frontZone,
                        backZone: draft.backZone,
                        cardNumber: deck.lastAssignedCardNumber
                    )
                    newCard.deck = deck
                    deck.cards.append(newCard)
                    context.insert(newCard)
                    cardsChanged = true
                }
            }
            if titleChanged || cardsChanged { deck.editedAt = Date() }
            deck.cardCount = deck.cards.count

        } else {
            // ── CREATE NEW DECK ───────────────────────────────────────────────
            let newDeck = DeckModel(title: trimmedTitle, icon: "book.closed.fill", colorHex: "#FFFFFF")
            context.insert(newDeck)
            newDeck.folder = selectedFolder
            selectedFolder?.deckCount += 1

            for draft in draftCards {
                newDeck.lastAssignedCardNumber += 1
                let newCard = CardModel(
                    frontZone: draft.frontZone,
                    backZone: draft.backZone,
                    cardNumber: newDeck.lastAssignedCardNumber
                )
                newCard.deck = newDeck
                context.insert(newCard)
                newDeck.cards.append(newCard)
            }
            newDeck.cardCount = newDeck.cards.count



            try? context.save()
        }

        // ── UI Triggers & Navigation ──────────────────────────────────────────
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            showSuccessOverlay = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
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
        pdfAnalysis = nil
    }
}

// MARK: - UIImage resize helper
extension UIImage {
    func resizedForAI(toMaxDimension maxDimension: CGFloat) -> UIImage {
        let size = self.size
        guard size.width > maxDimension || size.height > maxDimension else { return self }
        let scale = min(maxDimension / size.width, maxDimension / size.height)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1.0
        return UIGraphicsImageRenderer(size: newSize, format: format)
            .image { _ in self.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}

// MARK: - DocumentTextExtractor helper pentru pdfPageCount (non-isolated)
extension DocumentTextExtractor {
    static func pdfPageCount(url: URL) async -> Int {
        PDFDocument(url: url)?.pageCount ?? 0
    }
}
