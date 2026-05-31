//
//  DeckWorkspacePersistence.swift
//  QuizFlash
//

import SwiftUI
import SwiftData

extension DeckWorkspaceViewModel {
    // MARK: - Card Actions
    // =========================================================================

    /// Appends a new draft card with the given front and back zones.
    func addCard(content: DraftCardContent, creationSource: CardCreationSource = .manual) {
        let newCard = DraftCard(
            cardNumber: allocateNextDraftCardNumber(),
            content: content,
            isPinned: false,
            creationSource: creationSource,
            createdAt: Date(),
            editedAt: Date()
        )
        withAnimation {
            draftCards.append(newCard)
        }
        registerSessionDraftID(newCard.id)
    }

    /// Updates the draft card's zone content and bumps `editedAt` if content changed.
    func updateCard(_ card: DraftCard, content: DraftCardContent) {
        guard let index = draftCards.firstIndex(where: { $0.id == card.id }) else { return }
        var updated = draftCards[index]
        let changed = updated.content != content
        updated.content = content
        if changed { updated.editedAt = Date() }
        withAnimation { draftCards[index] = updated }
    }

    /// Opens the editor in create mode for the requested card kind.
    func presentCardEditor(for kind: CardKind = .flashcard) {
        cardEditorDestination = .create(kind: kind)
    }

    /// Opens the editor in edit mode for the selected draft card.
    func presentCardEditor(for draftCard: DraftCard) {
        cardEditorDestination = .edit(draftCard)
    }

    /// Dismisses the currently presented card editor, if any.
    func dismissCardEditor() {
        cardEditorDestination = nil
    }

    /// Enters multi-card selection mode for the current draft list.
    func enterCardSelectionMode() {
        guard !draftCards.isEmpty else { return }
        isSelectingCards = true
        selectedDraftCardIDs.removeAll()
    }

    /// Toggles the selection state for a draft card.
    func toggleSelection(for draftCardID: UUID) {
        if selectedDraftCardIDs.contains(draftCardID) {
            selectedDraftCardIDs.remove(draftCardID)
        } else {
            selectedDraftCardIDs.insert(draftCardID)
        }
    }

    /// Toggles between selecting every visible draft card and clearing the selection.
    func toggleSelectAllDraftCards() {
        if areAllDraftCardsSelected {
            selectedDraftCardIDs.removeAll()
        } else {
            selectedDraftCardIDs = Set(draftCards.map(\.id))
        }
    }

    /// Exits selection mode and clears the temporary draft-card selection.
    func exitCardSelectionMode() {
        isSelectingCards = false
        selectedDraftCardIDs.removeAll()
        showDeleteSelectedCardsConfirmation = false
    }

    /// Opens the confirmation prompt for removing the current selection.
    func requestDeleteSelectedCards() {
        guard !selectedDraftCardIDs.isEmpty else { return }
        showDeleteSelectedCardsConfirmation = true
    }

    /// Removes all selected draft cards from the in-memory editor state.
    ///
    /// This deliberately does not touch SwiftData directly. Existing persisted cards
    /// are removed later by `saveDeck` via the existing diff-based reconciliation.
    func deleteSelectedCards() {
        let idsToDelete = selectedDraftCardIDs
        guard !idsToDelete.isEmpty else {
            exitCardSelectionMode()
            return
        }

        showDeleteSelectedCardsConfirmation = false
        withAnimation {
            draftCards.removeAll { idsToDelete.contains($0.id) }
        }
        isSelectingCards = false
        selectedDraftCardIDs.removeAll()
    }

    /// Restores the editor to the exact state captured when the screen opened.
    ///
    /// Used only while editing an existing deck. The reset is in-memory and
    /// intentionally avoids touching SwiftData until the user saves again.
    func revertToInitialState() {
        guard isEditingExistingDeck else { return }
        let editingDeckID = resolvedEditingDeckID

        saveOverlayTask?.cancel()
        showSuccessOverlay = false
        resetAIState()
        aiSheetDestination = nil
        showAIPickerOptions = false
        showAIPhotoPicker = false
        showAIPDFPicker = false
        selectedAIPhotos = []

        deckTitle = initialDeckTitle
        selectedFolder = initialSelectedFolder
        draftCards = initialDraftCards
        replaceDraftSessionBaseline(with: initialDraftCards)
        nextDraftCardNumber = max(
            deckToEdit?.lastAssignedCardNumber ?? 0,
            initialDraftCards.map(\.cardNumber).max() ?? 0
        )
        cardEditorDestination = nil
        isSelectingCards = false
        selectedDraftCardIDs.removeAll()
        showDeleteSelectedCardsConfirmation = false
        workspaceEditingDeckID = editingDeckID
        isDetachedFromInitialDeck = false
    }

    // MARK: - Save Deck

    /// Persists the current draft state to SwiftData.
    ///
    /// - If `deckToEdit` is set, performs an in-place update (diff-based).
    /// - Otherwise, creates a brand-new `DeckModel` and inserts all draft cards.
    ///
    /// Shows a brief success overlay before navigating away.
    func saveDeck(context: ModelContext) -> Bool {
        saveOverlayTask?.cancel()
        showSuccessOverlay = false

        let trimmedTitle = deckTitle.trimmingCharacters(in: .whitespaces)
        let resolvedSavedTitle = trimmedTitle.isEmpty
            ? AppLocalization.string("Untitled Deck", locale: AppPreferences.persistedResolvedLocale)
            : trimmedTitle
        successOverlayDeckTitle = resolvedSavedTitle

        if resolvedEditingDeckID != nil && !hasUnsavedChanges {
            return false
        }

        if let deck = deckToEdit ?? resolvedEditingDeckID.flatMap({ context.safeModel(for: $0, as: DeckModel.self) }) {
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
                    let contentChanged = existing.cardContent != draft.content
                    let numberChanged = existing.cardNumber != draft.cardNumber
                    let pinChanged = existing.isPinned != draft.isPinned
                    let sourceChanged = existing.creationSource != draft.creationSource
                    if contentChanged || numberChanged || pinChanged || sourceChanged {
                        existing.cardContent = draft.content
                        existing.cardNumber = draft.cardNumber
                        existing.isPinned = draft.isPinned
                        existing.creationSource = draft.creationSource
                        existing.editedAt = Date()
                        cardsChanged = true
                    }
                } else {
                    let newCard = CardModel(
                        content: draft.content,
                        cardNumber: draft.cardNumber,
                        isPinned: draft.isPinned,
                        creationSource: draft.creationSource
                    )
                    if let createdAt = draft.createdAt {
                        newCard.createdAt = createdAt
                    }
                    if let editedAt = draft.editedAt {
                        newCard.editedAt = editedAt
                    }
                    newCard.deck = deck
                    deck.cards.append(newCard)
                    context.insert(newCard)
                    cardsChanged = true
                }
            }
            deck.lastAssignedCardNumber = max(
                deck.lastAssignedCardNumber,
                draftCards.map(\.cardNumber).max() ?? 0
            )
            if titleChanged || cardsChanged { deck.editedAt = Date() }
            deck.cardCount = draftCards.count

        } else {
            // ── CREATE NEW DECK ───────────────────────────────────────────────
            let newDeck = DeckModel(title: trimmedTitle, colorHex: "#FFFFFF")
            context.insert(newDeck)
            newDeck.folder = selectedFolder
            selectedFolder?.deckCount += 1

            for draft in draftCards {
                let newCard = CardModel(
                    content: draft.content,
                    cardNumber: draft.cardNumber,
                    isPinned: draft.isPinned,
                    creationSource: draft.creationSource
                )
                if let createdAt = draft.createdAt {
                    newCard.createdAt = createdAt
                }
                if let editedAt = draft.editedAt {
                    newCard.editedAt = editedAt
                }
                newCard.deck = newDeck
                context.insert(newCard)
                newDeck.cards.append(newCard)
            }
            newDeck.lastAssignedCardNumber = draftCards.map(\.cardNumber).max() ?? 0
            newDeck.cardCount = draftCards.count
        }

        do {
            try context.save()
        } catch {
            presentPersistenceError(error)
            return false
        }

        withAnimation(.easeInOut(duration: UIConstants.Animation.medium)) {
            showSuccessOverlay = true
        }

        saveOverlayTask = Task { @MainActor [weak self] in
            guard let self else { return }

            try? await Task.sleep(for: .milliseconds(880))
            guard !Task.isCancelled else { return }

            withAnimation(.easeInOut(duration: UIConstants.Animation.medium)) {
                self.showSuccessOverlay = false
            }
            self.resetWorkshopAfterSuccessfulSave()
        }

        return true
    }

    /// Permanently deletes the currently edited deck and its cards from SwiftData.
    ///
    /// The delete is committed immediately with an explicit `context.save()` so
    /// the editor never leaves the database in an ambiguous state.
    func deleteDeck(
        context: ModelContext,
        router: NavigationManager,
        dismissAction: @escaping () -> Void
    ) -> Bool {
        guard let deck = deckToEdit ?? resolvedEditingDeckID.flatMap({ context.safeModel(for: $0, as: DeckModel.self) }) else {
            return false
        }

        saveOverlayTask?.cancel()
        showSuccessOverlay = false
        resetAIState()

        deck.folder?.deckCount -= 1
        context.delete(deck)

        do {
            try context.save()
        } catch {
            presentPersistenceError(error)
            return false
        }

        Task { @MainActor in
            dismissAction()
            try? await Task.sleep(for: .milliseconds(240))
            router.popToRoot()
        }

        return true
    }

}
