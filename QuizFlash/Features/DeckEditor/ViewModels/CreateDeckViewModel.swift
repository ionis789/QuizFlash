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

/// The destination currently presented in the AI configuration sheet.
enum AIGenerationSheetDestination: String, Identifiable {
    case prepareGeneration

    var id: String { rawValue }
}

enum AISourcePreparationState: Equatable {
    case photos(itemCount: Int)
    case pdf
}

enum PendingAISourceSelection {
    case photos([PhotosPickerItem])
    case pdf(URL)
}

enum CardEditorDestination: Identifiable, Equatable {
    case create(kind: CardKind)
    case createFromDraft(kind: CardKind, sourceCard: DraftCard)
    case edit(DraftCard)

    var id: String {
        switch self {
        case .create(let kind):
            return "create-\(kind.rawValue)"
        case .createFromDraft(let kind, let sourceCard):
            return "create-from-\(sourceCard.id.uuidString)-\(kind.rawValue)"
        case .edit(let draftCard):
            return "edit-\(draftCard.id.uuidString)"
        }
    }

    var kind: CardKind {
        switch self {
        case .create(let kind):
            return kind
        case .createFromDraft(let kind, _):
            return kind
        case .edit(let draftCard):
            return draftCard.kind
        }
    }

    var draftCard: DraftCard? {
        switch self {
        case .create:
            return nil
        case .createFromDraft(_, let sourceCard):
            return sourceCard
        case .edit(let draftCard):
            return draftCard
        }
    }
}

// MARK: - AI Source Preparation

/// One previewable source item shown inside the AI generation sheet.
struct AIGenerationSourcePreviewItem: Identifiable {
    let id = UUID()
    let index: Int
    let title: String
    let characterCount: Int
    let thumbnail: UIImage?
}

/// Fully prepared source payload reused by the generation sheet and the final
/// AI pipeline so selection analysis is not recomputed unnecessarily.
struct AIPreparedGenerationSource {
    enum Kind {
        case photos
        case pdf
    }

    let kind: Kind
    let previewItems: [AIGenerationSourcePreviewItem]
    let textSegments: [AITextSourceSegment]
    let images: [UIImage]
    let pdfURL: URL?

    var isPDF: Bool { kind == .pdf }
    var itemCount: Int { previewItems.count }
    var totalCharacterCount: Int { previewItems.reduce(0) { $0 + $1.characterCount } }
    var itemLabels: [String] { previewItems.map(\.title) }
}

struct DraftCardChangeSnapshot: Equatable {
    let originalCardID: PersistentIdentifier?
    let cardNumber: Int
    let content: DraftCardContent
    let isPinned: Bool
    let creationSource: CardCreationSource

    init(card: DraftCard) {
        originalCardID = card.originalCardID
        cardNumber = card.cardNumber
        content = card.content
        isPinned = card.isPinned
        creationSource = card.creationSource
    }
}

struct CreateDeckStateSnapshot: Equatable {
    let title: String
    let selectedFolderID: PersistentIdentifier?
    let draftCards: [DraftCardChangeSnapshot]
}

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
    var aiSheetDestination: AIGenerationSheetDestination? = nil
    var showAICancelDialog = false
    var aiSourcePreparationState: AISourcePreparationState? = nil

    var isGenerating: Bool { aiState != .idle || hasPausedAIGeneration }
    var isPreparingAISource: Bool { aiSourcePreparationState != nil }
    var selectedFolder: FolderModel? = nil

    // MARK: - PDF Analysis

    /// Pre-populated automatically when the user selects a PDF, before tapping Generate.
    var pdfAnalysis: PDFAnalysisInfo? = nil

    // MARK: - Generation Settings
    var requestedCardCount: Int = 15
    var extractionMode: ExtractionMode = .fast
    var aiGenerationOptions = AIGenerationOptions()
    var preparedAISource: AIPreparedGenerationSource? = nil
    var manualAISourceAllocations: [AISourceRangeAllocation] = []
    var aiGeneratedCardCount: Int = 0
    var aiTargetCardCount: Int = 0
    var aiGenerationBaseCardCount: Int = 0
    var aiGenerationStartedAt: Date? = nil
    var aiAccumulatedGenerationDuration: TimeInterval = 0

    var hasPendingAISource: Bool {
        preparedAISource != nil
    }

    var hasGeneratedCardsInCurrentAISession: Bool {
        aiGeneratedCardCount > 0
    }

    var hasIncompleteAIGenerationSession: Bool {
        if isAIGenerationPaused || isAIGenerationPausedForBackground {
            return true
        }

        guard preparedAISource != nil else { return false }
        guard aiGenerationTask == nil else { return false }
        guard aiTargetCardCount > 0 else { return false }
        guard aiGeneratedCardCount < aiTargetCardCount else { return false }

        if case .idle = aiState {
            return false
        }
        if case .error = aiState { return false }

        return true
    }

    var hasPausedAIGeneration: Bool {
        let hasRemainingTarget = aiTargetCardCount > 0 || !remainingAIAllocations.isEmpty
        return (isAIGenerationPaused || isAIGenerationPausedForBackground)
            && aiGenerationTask == nil
            && hasRemainingTarget
    }

    var pausedRemainingCardCount: Int {
        let remainingFromAllocations = targetCardCount(for: remainingAIAllocations.filter { $0.cardCount > 0 })
        let remainingFromProgress = max(aiTargetCardCount - aiGeneratedCardCount, 0)
        return max(remainingFromAllocations, remainingFromProgress)
    }

    var isPreparedSourcePDF: Bool {
        preparedAISource?.isPDF == true
    }

    var hasAIGenerationClock: Bool {
        aiGenerationStartedAt != nil || aiAccumulatedGenerationDuration > 0
    }

    var canConfirmAIGeneration: Bool {
        guard preparedAISource != nil else { return false }

        switch aiGenerationOptions.sourceDistributionMode {
        case .auto:
            return requestedCardCount > 0
        case .manual:
            return manualAllocationValidationMessage == nil && manualAllocatedCardCount > 0
        }
    }

    var manualAllocationValidationMessage: String? {
        guard let source = preparedAISource else { return "No source selected." }
        let allocations = normalizedManualAllocations(for: source.itemCount)
        guard !allocations.isEmpty else { return "Add at least one range." }

        if hasOverlappingAllocations(allocations) {
            return "Manual ranges overlap. Make each range distinct."
        }

        return nil
    }

    var manualAllocatedCardCount: Int {
        guard let source = preparedAISource else { return 0 }
        return normalizedManualAllocations(for: source.itemCount)
            .reduce(0) { $0 + $1.cardCount }
    }

    var resolvedAISourceAllocations: [AISourceRangeAllocation] {
        guard let source = preparedAISource else { return [] }

        switch aiGenerationOptions.sourceDistributionMode {
        case .auto:
            return automaticAllocations(
                for: source.previewItems.map(\.characterCount),
                totalCards: requestedCardCount
            )
        case .manual:
            return normalizedManualAllocations(for: source.itemCount)
        }
    }

    var summarizedAISourceAllocations: [AISourceRangeAllocation] {
        mergeAllocationsWithSameRange(resolvedAISourceAllocations)
    }

    // MARK: - Photos
    var selectedAIPhotos: [PhotosPickerItem] = [] {
        didSet {
            guard !selectedAIPhotos.isEmpty else { return }
            showAIPickerOptions = false
            let items = selectedAIPhotos
            selectedAIPhotos = []
            pdfAnalysis = nil
            beginAISourcePreparation(.photos(itemCount: items.count))
            scheduleAIGenerationSheetPresentation()
            aiSourcePreparationTask?.cancel()
            aiSourcePreparationTask = nil
            pendingAISourceSelection = .photos(items)
        }
    }

    // MARK: - Services

    @ObservationIgnored let aiProviderStore: AIProviderStore
    @ObservationIgnored let aiBackgroundCoordinator: AIGenerationBackgroundCoordinator
    @ObservationIgnored var aiGenerationTask: Task<Void, Never>?
    @ObservationIgnored var aiSourcePreparationTask: Task<Void, Never>?
    @ObservationIgnored var pendingAISourceSelection: PendingAISourceSelection?
    @ObservationIgnored var aiRevealTask: Task<Void, Error>?
    @ObservationIgnored var aiDeckTitleTask: Task<Void, Never>?
    @ObservationIgnored var aiSessionPersistenceTask: Task<Void, Never>?
    @ObservationIgnored var saveOverlayTask: Task<Void, Never>?

    @ObservationIgnored var pendingAIDeckTitleRequestID: UUID?
    @ObservationIgnored var pendingAIGeneratedCards: [AIFlashcard] = []
    @ObservationIgnored var aiDidFinishReceivingGeneratedCards = false
    @ObservationIgnored var aiGeneratedShortfallCount = 0
    @ObservationIgnored var clearsPendingAISourceOnSheetDismiss = false
    @ObservationIgnored var aiGenerationSessionID: UUID?
    var remainingAIAllocations: [AISourceRangeAllocation] = []
    var isAIGenerationPausedForBackground = false
    var isAIGenerationPaused = false
    var isManualPauseInProgress = false

    // MARK: - Deck / Cards State
    var deckTitle: String = ""
    var draftCards: [DraftCard] = [] {
        didSet {
            reconcileDraftSelectionState()
            reconcileDraftSessionState()
        }
    }
    var cardEditorDestination: CardEditorDestination?
    var showSuccessOverlay = false
    var successOverlayDeckTitle = ""
    var isSelectingCards = false
    var selectedDraftCardIDs: Set<UUID> = []
    var showDeleteSelectedCardsConfirmation = false
    let deckToEdit: DeckModel?
    var initialSnapshot: CreateDeckStateSnapshot
    @ObservationIgnored var initialDeckTitle: String
    @ObservationIgnored var initialDraftCards: [DraftCard]
    @ObservationIgnored var initialSelectedFolder: FolderModel?
    @ObservationIgnored var nextDraftCardNumber: Int
    @ObservationIgnored var workspaceEditingDeckID: PersistentIdentifier?
    var isDetachedFromInitialDeck = false
    var baseDraftCardIDs: Set<UUID> = []
    var sessionDraftCardIDs: Set<UUID> = []
    var aiSessionDraftCardIDs: Set<UUID> = []

    var selectedDraftCardCount: Int {
        selectedDraftCardIDs.count
    }

    var areAllDraftCardsSelected: Bool {
        !draftCards.isEmpty && selectedDraftCardIDs.count == draftCards.count
    }

    var hasUnsavedChanges: Bool {
        currentSnapshot != initialSnapshot
    }

    var sessionDraftCards: [DraftCard] {
        draftCards.filter { sessionDraftCardIDs.contains($0.id) }
    }

    var baseDraftCards: [DraftCard] {
        draftCards.filter { baseDraftCardIDs.contains($0.id) }
    }

    var aiSessionDraftCards: [DraftCard] {
        draftCards.filter { aiSessionDraftCardIDs.contains($0.id) }
    }

    var hasAISessionDraftCards: Bool {
        !aiSessionDraftCardIDs.isEmpty
    }

    var resolvedEditingDeckID: PersistentIdentifier? {
        if let workspaceEditingDeckID {
            return workspaceEditingDeckID
        }
        guard !isDetachedFromInitialDeck else { return nil }
        return deckToEdit?.persistentModelID
    }

    var isEditingExistingDeck: Bool {
        resolvedEditingDeckID != nil
    }

    var canUndoChanges: Bool {
        isEditingExistingDeck && hasUnsavedChanges && !isGenerating
    }

    var canDeleteDeck: Bool {
        deckToEdit != nil && !isGenerating
    }

    convenience init(deckToEdit: DeckModel? = nil) {
        self.init(
            deckToEdit: deckToEdit,
            aiProviderStore: AIProviderStore.shared,
            aiBackgroundCoordinator: .shared
        )
    }

    init(
        deckToEdit: DeckModel?,
        aiProviderStore: AIProviderStore,
        aiBackgroundCoordinator: AIGenerationBackgroundCoordinator
    ) {
        self.aiProviderStore = aiProviderStore
        self.aiBackgroundCoordinator = aiBackgroundCoordinator
        self.deckToEdit = deckToEdit
        let initialTitle: String
        let initialFolder: FolderModel?
        let initialDrafts: [DraftCard]

        if let deck = deckToEdit {
            deckTitle = deck.title
            selectedFolder = deck.folder
            draftCards = Self.orderedPersistedDraftCards(from: deck)
            initialTitle = deck.title
            initialFolder = deck.folder
            initialDrafts = Self.orderedPersistedDraftCards(from: deck)
        } else {
            initialTitle = ""
            initialFolder = nil
            initialDrafts = []
        }

        initialSnapshot = CreateDeckStateSnapshot(
            title: initialTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            selectedFolderID: initialFolder?.persistentModelID,
            draftCards: initialDrafts.map(DraftCardChangeSnapshot.init)
        )
        initialDeckTitle = initialTitle
        initialDraftCards = initialDrafts
        initialSelectedFolder = initialFolder
        baseDraftCardIDs = Set(initialDrafts.map(\.id))
        sessionDraftCardIDs = []
        aiSessionDraftCardIDs = []
        nextDraftCardNumber = max(
            deckToEdit?.lastAssignedCardNumber ?? 0,
            initialDrafts.map(\.cardNumber).max() ?? 0
        )
        
        Task { [weak self] in
            await self?.checkForPausedSession()
        }
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
