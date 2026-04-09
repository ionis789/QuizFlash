//
//  DeckWorkspaceDerivedStateBuilder.swift
//  QuizFlash
//

import SwiftUI
import SwiftData

extension DeckWorkspaceViewModel {
    func resetForm() {
        deckTitle = ""
        selectedFolder = nil
        draftCards = []
        nextDraftCardNumber = 0
        workspaceEditingDeckID = nil
        isDetachedFromInitialDeck = true
        cardEditorDestination = nil
        isSelectingCards = false
        selectedDraftCardIDs.removeAll()
        showDeleteSelectedCardsConfirmation = false
        clearAISourcePreparation()
        preparedAISource = nil
        manualAISourceAllocations = []
        pdfAnalysis = nil
        successOverlayDeckTitle = ""
        replaceDraftSessionBaseline(with: [])
    }

    func resetWorkshopAfterSuccessfulSave() {
        resetAIState()
        aiSheetDestination = nil
        showAIPickerOptions = false
        showAIPhotoPicker = false
        showAIPDFPicker = false
        selectedAIPhotos = []
        resetForm()
        replaceInitialState(title: "", selectedFolder: nil, draftCards: [])
    }

    func replaceInitialState(
        title: String,
        selectedFolder: FolderModel?,
        draftCards: [DraftCard]
    ) {
        initialDeckTitle = title
        initialDraftCards = draftCards
        initialSelectedFolder = selectedFolder
        initialSnapshot = DeckWorkspaceStateSnapshot(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            selectedFolderID: selectedFolder?.persistentModelID,
            draftCards: draftCards.map(DraftCardChangeSnapshot.init)
        )
        replaceDraftSessionBaseline(with: draftCards)
    }

    func replaceDraftSessionBaseline(with draftCards: [DraftCard]) {
        baseDraftCardIDs = Set(draftCards.map(\.id))
        sessionDraftCardIDs.removeAll()
        aiSessionDraftCardIDs.removeAll()
    }

    /// Ends any inline session grouping and shows the full draft deck as one list again.
    func integrateAllDraftCardsIntoBaseline() {
        replaceDraftSessionBaseline(with: draftCards)
    }

    func registerSessionDraftID(
        _ draftID: UUID,
        marksAsAI: Bool = false
    ) {
        baseDraftCardIDs.remove(draftID)
        sessionDraftCardIDs.insert(draftID)
        if marksAsAI {
            aiSessionDraftCardIDs.insert(draftID)
        }
    }

    var currentSnapshot: DeckWorkspaceStateSnapshot {
        DeckWorkspaceStateSnapshot(
            title: deckTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            selectedFolderID: selectedFolder?.persistentModelID,
            draftCards: draftCards.map(DraftCardChangeSnapshot.init)
        )
    }

    func reconcileDraftSelectionState() {
        let validIDs = Set(draftCards.map(\.id))
        selectedDraftCardIDs.formIntersection(validIDs)

        if draftCards.isEmpty {
            isSelectingCards = false
            showDeleteSelectedCardsConfirmation = false
        }

        if case .edit(let draftCard) = cardEditorDestination,
           !validIDs.contains(draftCard.id) {
            cardEditorDestination = nil
        }
    }

    func reconcileDraftSessionState() {
        let validIDs = Set(draftCards.map(\.id))
        baseDraftCardIDs.formIntersection(validIDs)
        sessionDraftCardIDs.formIntersection(validIDs)
        aiSessionDraftCardIDs.formIntersection(validIDs)
    }

    func allocateNextDraftCardNumber() -> Int {
        nextDraftCardNumber += 1
        return nextDraftCardNumber
    }

    static func orderedPersistedDraftCards(from deck: DeckModel) -> [DraftCard] {
        deck.cards
            .sorted {
                if $0.cardNumber == $1.cardNumber {
                    return $0.createdAt < $1.createdAt
                }
                return $0.cardNumber < $1.cardNumber
            }
            .map(persistedDraftCard(from:))
    }

    static func persistedDraftCard(from card: CardModel) -> DraftCard {
        DraftCard(
            id: stableDraftID(for: card.persistentModelID),
            originalCardID: card.persistentModelID,
            cardNumber: card.cardNumber,
            content: card.cardContent,
            isPinned: card.isPinned,
            creationSource: card.creationSource,
            conversionMetadata: card.conversionMetadata,
            createdAt: card.createdAt,
            editedAt: card.editedAt
        )
    }

    static func stableDraftID(for persistentIdentifier: PersistentIdentifier) -> UUID {
        let data = (try? JSONEncoder().encode(persistentIdentifier)) ?? Data()

        var firstHasher = Hasher()
        firstHasher.combine("draft-stable-id-primary")
        data.forEach { firstHasher.combine($0) }
        let first = UInt64(bitPattern: Int64(firstHasher.finalize()))

        var secondHasher = Hasher()
        secondHasher.combine("draft-stable-id-secondary")
        data.forEach { secondHasher.combine($0) }
        let second = UInt64(bitPattern: Int64(secondHasher.finalize()))

        let bytes: [UInt8] =
            (0..<8).map { UInt8((first >> (UInt64($0) * 8)) & 0xFF) } +
            (0..<8).map { UInt8((second >> (UInt64($0) * 8)) & 0xFF) }

        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
