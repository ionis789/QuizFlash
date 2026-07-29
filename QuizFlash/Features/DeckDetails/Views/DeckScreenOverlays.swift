//
//  DeckScreenOverlays.swift
//  QuizFlash
//
//  Extracted overlays, helper sheets, and local deck screen actions.
//

import SwiftUI
import SwiftData

extension DeckContentView {
    func handleEditCard(_ gridCard: GridCardInfo) {
        guard !viewModel.isSelecting else { return }
        if let model = context.model(for: gridCard.id) as? CardModel {
            presentCardEditor(for: model)
        }
    }

    func handleTogglePinned(_ gridCard: GridCardInfo) {
        viewModel.togglePinnedState(
            for: gridCard.id,
            in: deck,
            context: context
        )
    }

    func openPlayMode(_ mode: DeckPlayModeDestination) {
        dismissUnavailablePlayMode()
        guard mode == .flashcards else {
            selectedPlayMode = mode
            return
        }

        prepareFlashcardsPlayModeIfNeeded()
        guard let preparedFlashcardsPlayModeViewModel,
              preparedFlashcardsPlayModeViewModel.isSessionStarted,
              !preparedFlashcardsPlayModeViewModel.cards.isEmpty else {
            presentsFlashcardsAfterPreparation = true
            return
        }

        presentsFlashcardsAfterPreparation = false
        selectedPlayMode = mode
    }

    func prepareFlashcardsPlayModeIfNeeded() {
        guard deck.cardCount > 0 else { return }
        MathWebViewPool.shared.prewarm(
            count: 4,
            initialDelayMilliseconds: 0
        )
        if let viewModel = preparedFlashcardsPlayModeViewModel,
           viewModel.isSessionStarted,
           !viewModel.cards.isEmpty {
            if presentsFlashcardsAfterPreparation {
                presentsFlashcardsAfterPreparation = false
                selectedPlayMode = .flashcards
            }
            return
        }
        guard flashcardsPreparationTask == nil else { return }

        var flashcardSettings = deck.playModeSettings?.flashcardSettings ?? FlashcardModeSettings()
        flashcardSettings.textSize = flashcardSettings.resolvedTextSize(
            default: appPreferences.defaultTextSize
        )

        let sessionViewModel = preparedFlashcardsPlayModeViewModel ?? FlashCardsPlayModeViewModel(
            deck: deck,
            settings: flashcardSettings
        )
        preparedFlashcardsPlayModeViewModel = sessionViewModel

        flashcardsPreparationTask = Task { @MainActor in
            await sessionViewModel.startSession(container: context.container)
            await MathWebViewPool.shared.waitUntilReadyForPlayback()
            guard !Task.isCancelled else { return }
            flashcardsPreparationTask = nil
            if presentsFlashcardsAfterPreparation,
               sessionViewModel.isSessionStarted,
               !sessionViewModel.cards.isEmpty {
                presentsFlashcardsAfterPreparation = false
                selectedPlayMode = .flashcards
            }
        }
    }

    func resetPreparedFlashcardsPlayMode() {
        flashcardsPreparationTask?.cancel()
        flashcardsPreparationTask = nil
        presentsFlashcardsAfterPreparation = false
        preparedFlashcardsPlayModeViewModel = nil
    }

    func cancelPreparedFlashcardsPlayMode() {
        flashcardsPreparationTask?.cancel()
        flashcardsPreparationTask = nil
        presentsFlashcardsAfterPreparation = false
        preparedFlashcardsPlayModeViewModel?.tearDown()
        preparedFlashcardsPlayModeViewModel = nil
    }

    func presentUnavailablePlayMode(_ mode: DeckPlayModeDestination) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            unavailablePlayMode = mode
        }
    }

    func dismissUnavailablePlayMode() {
        guard unavailablePlayMode != nil else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.92)) {
            unavailablePlayMode = nil
        }
    }

    func recordCompletedPlayModeSession(_ mode: DeckPlayModeDestination) {
        let settings = DeckPlayModeSettingsStore.resolve(for: deck, in: context)
        settings.markRecentlyUsed(mode)
    }

    func refreshPlayModeRecentUsageSnapshot() {
        let settings = deck.playModeSettings
        playModeRecentUsageSnapshot = DeckPlayModeDestination.allCases.reduce(into: [:]) { result, mode in
            if let date = settings?.recentUsageDate(for: mode) {
                result[mode] = date
            }
        }
    }

    func handleDeleteCard(_ gridCard: GridCardInfo) {
        pendingDeleteCardID = gridCard.id
    }

    func exitSelectionModeForExternalAction() {
        guard viewModel.isSelecting else { return }
        withBottomChromeAnimation {
            viewModel.exitSelectionMode()
        }
    }

    func presentCardEditor(for kind: CardKind) {
        exitSelectionModeForExternalAction()
        cardEditorDestination = .create(kind: kind)
    }

    func presentCardEditor(for card: CardModel) {
        guard !viewModel.isSelecting else {
            withAnimation(.spring(response: 0.18, dampingFraction: 0.88)) {
                viewModel.toggleSelection(for: card.persistentModelID)
            }
            return
        }
        exitSelectionModeForExternalAction()
        cardEditorDestination = .edit(DraftCard.from(card))
    }

    func handleCardEditorSave(destination: CardEditorDestination, content: DraftCardContent) {
        switch destination {
        case .create, .createFromDraft:
            viewModel.addCard(content: content, to: deck, context: context)
        case .edit(let draftCard):
            guard let cardID = draftCard.originalCardID,
                  let card = context.model(for: cardID) as? CardModel else {
                cardEditorDestination = nil
                return
            }

            if card.cardContent != content {
                card.cardContent = content
                card.editedAt = Date()
                deck.editedAt = Date()
                CloudSyncCoordinator.shared.enqueueUpsert(for: deck, context: context)
                viewModel.requestSnapshotLoad(
                    deckID: deck.persistentModelID,
                    container: context.container
                )
            }
        }
    }

    @ViewBuilder
    var unavailablePlayModeOverlay: some View {
        if let unavailablePlayMode {
            let prompt = unavailablePlayMode.localizedUnavailablePrompt(
                locale: appPreferences.resolvedLocale,
                in: viewModel.playModeAvailability,
                deck: deck
            )

            ZStack(alignment: .bottom) {
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissUnavailablePlayMode()
                    }
                    .transition(.opacity)

                PlayModeUnavailableCard(
                    mode: unavailablePlayMode,
                    prompt: prompt,
                    tintColor: unavailablePlayMode.tintColor(
                        deckColor: Color(hex: deck.colorHex) ?? themeManager.accentColor.color,
                        accentColor: themeManager.accentColor.color
                    ),
                    onDismiss: dismissUnavailablePlayMode
                )
                .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
                .padding(
                    .bottom,
                    UIConstants.Size.bottomChromeBarHeight
                        + UIConstants.Layout.bottomChromeBottomPadding
                        + UIConstants.Spacing.medium
                )
                .transition(
                    .opacity
                        .combined(with: .scale(scale: 0.94, anchor: .bottom))
                )
            }
            .zIndex(260)
        }
    }

    struct PlayModeUnavailableCard: View {
        let mode: DeckPlayModeDestination
        let prompt: PlayModeUnavailablePrompt
        let tintColor: Color
        let onDismiss: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
                HStack(alignment: .center, spacing: UIConstants.Spacing.medium) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(tintColor.opacity(0.16))
                        .frame(width: 54, height: 54)
                        .overlay {
                            Image(systemName: mode.systemImage)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(tintColor)
                                .rotationEffect(mode.systemImageRotation)
                        }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(prompt.title)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(prompt.detail)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: UIConstants.Spacing.small) {
                    Button(AppLocalization.string("Not now", locale: AppPreferences.persistedResolvedLocale), action: onDismiss)
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .quizFlashButtonStyle(.surface)
                }
            }
            .padding(UIConstants.Spacing.large)
            .flashcardStyle(cornerRadius: 30, surfaceRole: .widget)
        }
    }
}
