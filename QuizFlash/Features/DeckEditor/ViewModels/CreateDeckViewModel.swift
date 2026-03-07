//
//  CreateDeckViewModel.swift
//  QuizFlash
//
//  Manages all state and business logic for the deck creation and editing flow.
//

import SwiftUI
import SwiftData
import PhotosUI
import PDFKit

// MARK: - Create Deck View Model

/// The ViewModel for `CreateDeckView`, managing draft card state, AI generation,
/// and deck persistence for both new deck creation and existing deck editing.
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

    /// Pre-populated automatically when the user selects a PDF, before tapping Generate.
    var pdfAnalysis: PDFAnalysisInfo? = nil

    // MARK: - Generation Settings
    var requestedCardCount: Int = 15
    var extractionMode: ExtractionMode = .fast

    // MARK: - Photos
    var selectedAIPhotos: [PhotosPickerItem] = [] {
        didSet {
            guard !selectedAIPhotos.isEmpty else { return }
            showAIPickerOptions = false
            // For photos, no pre-analysis step is needed — show the options overlay directly.
            pdfAnalysis = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.spring()) { self.showAIOptionsOverlay = true }
            }
        }
    }

    var pendingPDFURL: URL? = nil

    // MARK: - Services

    private let aiService = AIFlashcardService(apiKey: "sk-a40ab294a6ea4efa91c003e8c1fccba2")

    // MARK: - Deck / Cards State
    var deckTitle: String = ""
    var draftCards: [DraftCard] = []
    var cardToEdit: DraftCard?
    var isCreatingNewCard = false
    var showSuccessOverlay = false
    let deckToEdit: DeckModel?

    // MARK: - Materialization Animation State

    /// Indices of cards that have been revealed during the staggered entry animation.
    var revealedCardIndices: Set<Int> = []

    /// True while the staggered card reveal sequence is running.
    var isMaterializing: Bool = false

    // MARK: - Scroll / Navigation State

    /// Latest scroll offset reported by the scroll view's preference key.
    ///
    /// Drives both `showInlineTitle` and `heroOpacity` computed properties.
    var scrollOffset: CGFloat = 0

    // MARK: - Derived Navigation State

    /// Returns `true` when the scroll offset is deep enough to show the condensed
    /// inline title in the navigation bar.
    var showInlineTitle: Bool { scrollOffset < -40 }

    /// Returns the opacity of the hero title area as a function of scroll offset.
    ///
    /// Fades the hero out as the user scrolls up past the collapse threshold.
    var heroOpacity: Double {
        let maxOffset: CGFloat = -10
        let minOffset: CGFloat = -60
        if scrollOffset > maxOffset { return 1.0 }
        if scrollOffset < minOffset { return 0.0 }
        return 1.0 - Double((maxOffset - scrollOffset) / (maxOffset - minOffset))
    }

    init(deckToEdit: DeckModel? = nil) {
        self.deckToEdit = deckToEdit
        if let deck = deckToEdit {
            deckTitle = deck.title
            selectedFolder = deck.folder
            draftCards = deck.cards.map { DraftCard.from($0) }
        }
    }

    // MARK: - PDF Selection and Auto-Analysis

    /// Called immediately after the user selects a PDF.
    ///
    /// Runs a PDFKit quality check in the background and populates `pdfAnalysis`
    /// before the options overlay becomes visible — no perceptible delay for the user.
    func pdfWasSelected(_ url: URL) {
        pendingPDFURL = url
        pdfAnalysis = nil

        // Run analysis in the background immediately.
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

            // Set the recommended extraction mode automatically based on PDF quality.
            self.pdfAnalysis = info
            self.extractionMode = info.recommendation

            // Open the overlay only after analysis is ready.
            withAnimation(.spring()) {
                self.showAIOptionsOverlay = true
            }
        }
    }

    // MARK: - AI Generation

    /// Starts the appropriate AI generation pipeline based on the currently
    /// selected input source (photos or PDF).
    func startAIGeneration() {
        if !selectedAIPhotos.isEmpty {
            processPhotosForAI()
        } else if let url = pendingPDFURL {
            processPDFForAI(url: url)
        }
    }

    // MARK: - Process Photos
    //
    // Fast    — On-device Vision OCR (free, fast)
    // Quality — GPT Vision, all images in a single request (accurate, understands diagrams)

    private func processPhotosForAI() {
        aiState = .extractingText
        let items = selectedAIPhotos
        selectedAIPhotos = []

        Task {
            do {
                // Load images from the PhotosPicker.
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
                    // On-device Vision OCR → extracted text → GPT text mode (cheaper).
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
                    // GPT Vision with all images in a single request (slower, understands diagrams).
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

    // MARK: - Process PDF
    //
    // Fast    — Automatic pipeline: PDFKit → on-device Vision OCR (free)
    // Quality — Render pages as images → all in a single GPT Vision request

    private func processPDFForAI(url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            aiState = .error("Could not access the PDF file.")
            return
        }

        pendingPDFURL = nil

        Task {
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let cards: [AIFlashcard]

                switch extractionMode {
                case .fast:
                    // Automatic pipeline: PDFKit → on-device Vision OCR (free).
                    aiState = .extractingText
                    let extraction = await DocumentTextExtractor.extract(from: url)

                    guard let text = extraction.text, !text.isEmpty else {
                        // Extracted text quality is too low — fall back to Quality mode automatically.
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
                    // Render all pages → single GPT Vision request.
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

    // MARK: - Materialization Animation

    /// Triggers the staggered card reveal animation after AI generation completes.
    ///
    /// Each card slides in with a spring animation, staggered by 100 ms per index.
    /// Haptic feedback fires at the start and end of the sequence.
    func startMaterializationSequence() {
        guard !isMaterializing else { return }
        isMaterializing = true
        revealedCardIndices.removeAll()
        let count = draftCards.count
        for i in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.10) {
                withAnimation(.spring(response: 0.48, dampingFraction: 0.72)) {
                    self.revealedCardIndices.insert(i)
                }
                if i == 0 || i == count - 1 {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(count) * 0.10 + 0.5) {
            self.isMaterializing = false
        }
    }

    // MARK: - Reset AI State

    /// Resets the AI pipeline state to `.idle` with an animation.
    func resetAIState() {
        withAnimation { aiState = .idle }
    }

    // =========================================================================
    // MARK: - Card Actions
    // =========================================================================

    /// Appends a new draft card with the given front and back zones.
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

    /// Updates the draft card's zone content and bumps `editedAt` if content changed.
    func updateCard(_ card: DraftCard, frontZone: ZoneModel, backZone: ZoneModel) {
        guard let index = draftCards.firstIndex(where: { $0.id == card.id }) else { return }
        var updated = draftCards[index]
        let changed = updated.frontZone != frontZone || updated.backZone != backZone
        updated.frontZone = frontZone
        updated.backZone = backZone
        if changed { updated.editedAt = Date() }
        withAnimation { draftCards[index] = updated }
    }

    /// Removes the specified draft card from the list.
    func deleteCard(_ card: DraftCard) {
        withAnimation { draftCards.removeAll { $0.id == card.id } }
    }

    // MARK: - Save Deck

    /// Persists the current draft state to SwiftData.
    ///
    /// - If `deckToEdit` is set, performs an in-place update (diff-based).
    /// - Otherwise, creates a brand-new `DeckModel` and inserts all draft cards.
    ///
    /// Shows a brief success overlay before navigating away.
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

// MARK: - UIImage Resize Helper

extension UIImage {
    /// Resizes the image to fit within `maxDimension` × `maxDimension` while preserving aspect ratio.
    ///
    /// Used before sending images to the AI service to reduce request payload size.
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

// MARK: - DocumentTextExtractor Page Count Helper

extension DocumentTextExtractor {
    /// Counts the number of pages in the PDF at the given URL.
    ///
    /// Runs in a non-isolated async context to avoid blocking the `MainActor`.
    static func pdfPageCount(url: URL) async -> Int {
        PDFDocument(url: url)?.pageCount ?? 0
    }
}
