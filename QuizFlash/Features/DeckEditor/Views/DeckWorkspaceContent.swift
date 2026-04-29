//
//  DeckWorkspaceContent.swift
//  QuizFlash
//

import SwiftUI
import SwiftData

extension DeckWorkspaceView {
    var runtimeCardTransition: AnyTransition { .opacity }

    func updateViewSafeBottom(using viewInset: CGFloat) {
        guard abs(viewSafeBottom - viewInset) > 0.5 else { return }
        viewSafeBottom = viewInset
    }

    func capturePhysicalSafeBottomIfNeeded() {
        guard !hasCapturedPhysicalSafeBottom else { return }
        hasCapturedPhysicalSafeBottom = true

        physicalSafeBottom = UIApplication.shared
            .connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows
            .first(where: { $0.isKeyWindow })?
            .safeAreaInsets.bottom ?? 0
    }

    @ViewBuilder
    var draftSelectionBottomBar: some View {
        if !isShowingWorkspaceConvert && viewModel.isSelectingCards && !viewModel.draftCards.isEmpty {
            BottomChromeContainer(
                kind: .selection,
                bottomPadding: BottomChromeInsets.selectionInEditor(
                    viewSafeBottom: viewSafeBottom,
                    physicalSafeBottom: physicalSafeBottom,
                    isPresentedInFullScreenSheet: false
                )
            ) {
                DeckWorkspaceSelectionBottomBar(
                    selectedCount: viewModel.selectedDraftCardCount,
                    allSelected: viewModel.areAllDraftCardsSelected,
                    onDone: {
                        withBottomChromeAnimation {
                            viewModel.exitCardSelectionMode()
                        }
                    },
                    onToggleSelectAll: {
                        withAnimation(.selectionToolbarSpring) {
                            viewModel.toggleSelectAllDraftCards()
                        }
                    },
                    onDelete: {
                        viewModel.requestDeleteSelectedCards()
                    }
                )
            }
            .transition(.bottomChrome)
            .zIndex(30)
            .animation(.bottomChromeSpring, value: viewModel.isSelectingCards)
        }
    }

    // MARK: 2. Cards List Content
    func cardsListContent(using scrollProxy: ScrollViewProxy) -> some View {
        LazyVStack(spacing: 16) {
            mainCardsListContent(using: scrollProxy)
        }
            .padding(.horizontal, UIConstants.Layout.cardListEdgeInset)
            .animation(
                hasUnifiedAISession
                    ? .spring(response: 0.48, dampingFraction: 0.82, blendDuration: 0.08)
                    : .spring(response: 0.36, dampingFraction: 0.84),
                value: viewModel.draftCards.map(\.id)
            )
            .animation(
                .spring(response: 0.56, dampingFraction: 0.8, blendDuration: 0.1),
                value: hasUnifiedAISession
            )
            .animation(.easeInOut(duration: 0.35), value: viewModel.draftCards.isEmpty)
    }

    @ViewBuilder
    func mainCardsListContent(using scrollProxy: ScrollViewProxy) -> some View {
        if viewModel.draftCards.isEmpty
            && !hasActiveGenerationRuntime
            && activeEditorConversionProgress == nil
            && activeEditorPausedConversionProgress == nil {
            emptyStateView.transition(.opacity)
        } else {
            unifiedRuntimeCard

            if hasUnifiedAISession {
                if !displayedDraftRowsBeforeAISlots.isEmpty {
                    draftCardRows(displayedDraftRowsBeforeAISlots)
                }

                aiPendingSlots

                inlineHistoricalCardsToggle(
                    title: localized("Earlier cards"),
                    hiddenCount: hiddenSessionCardsCount
                )

                if !displayedHistoricalDraftCards.isEmpty {
                    draftCardRows(displayedHistoricalDraftCards)
                }
            } else if !viewModel.draftCards.isEmpty {
                draftCardRows(displayedDraftRowsBeforeAISlots)
            }
        }
    }

    @ViewBuilder
    var unifiedRuntimeCard: some View {
        if aiWorkspaceCoordinator.canResumeConversion,
          let pausedConversionProgress = activeEditorPausedConversionProgress {
            let remainingCount = max(
                pausedConversionProgress.totalCount - pausedConversionProgress.completedCount,
                0
            )
            AIPausedResumeCard(
                foundCount: pausedConversionProgress.createdCount,
                targetCount: max(pausedConversionProgress.totalCount, 1),
                remainingCount: remainingCount,
                progress: pausedConversionProgress.fractionCompleted,
                title: localized("Conversion paused"),
                subtitle: localized("Continue from the last completed batch when you're ready."),
                accentColor: .orange,
                onResume: {
                    aiWorkspaceCoordinator.resumeConversion(context: context)
                }
            )
            .transition(runtimeCardTransition)
        } else if let conversionProgress = activeEditorConversionProgress {
            AIStreamingProgressCard(
                foundCount: conversionProgress.createdCount,
                targetCount: max(conversionProgress.totalCount, 1),
                progress: conversionProgress.fractionCompleted,
                title: "Converting cards",
                subtitleOverride: conversionProgress.statusMessage,
                accentColor: .orange,
                footnote: showsInlineConversionSessionCards
                    ? "Cards appear in place as each converted batch finishes"
                    : "AI converts the selected cards and saves the result as it goes",
                onCancel: aiWorkspaceCoordinator.canCancelConversion ? {
                    aiWorkspaceCoordinator.requestConversionCancel()
                } : nil,
                onPause: aiWorkspaceCoordinator.canPauseConversion ? {
                    aiWorkspaceCoordinator.pauseConversion()
                } : nil
            )
            .transition(runtimeCardTransition)
        } else if case .extractingText = viewModel.aiState {
            AIExtractingLoadingView(
                elapsedStartDate: viewModel.aiGenerationStartedAt,
                elapsedAccumulatedDuration: viewModel.aiAccumulatedGenerationDuration
            )
                .transition(runtimeCardTransition)
        } else if viewModel.hasPausedAIGeneration {
            let progress = min(1.0, Double(viewModel.aiGeneratedCardCount) / Double(max(viewModel.aiTargetCardCount, 1)))
            AIPausedResumeCard(
                foundCount: viewModel.aiGeneratedCardCount,
                targetCount: max(viewModel.aiTargetCardCount, 1),
                remainingCount: max(viewModel.pausedRemainingCardCount, 0),
                progress: progress,
                elapsedStartDate: viewModel.aiGenerationStartedAt,
                elapsedAccumulatedDuration: viewModel.aiAccumulatedGenerationDuration,
                onResume: {
                    viewModel.resumePausedAIGeneration()
                }
            )
            .transition(runtimeCardTransition)
        } else if case .generatingCards(let progress, let foundCount) = viewModel.aiState {
            AIStreamingProgressCard(
                foundCount: foundCount,
                targetCount: max(viewModel.aiTargetCardCount, 1),
                progress: progress,
                elapsedStartDate: viewModel.aiGenerationStartedAt,
                elapsedAccumulatedDuration: viewModel.aiAccumulatedGenerationDuration,
                onCancel: {
                    viewModel.requestAIGenerationCancel()
                },
                onPause: {
                    viewModel.pauseAIGeneration()
                }
            )
            .transition(runtimeCardTransition)
        }
    }

    @ViewBuilder
    var aiPendingSlots: some View {
        let createdCount = sortedAISessionDraftCards.count

        if showsInlineConversionSessionCards,
           let conversionProgress = activeEditorConversionProgress ?? activeEditorPausedConversionProgress {
            let leadingRowCount = displayedDraftRowsBeforeAISlots.count

            if createdCount == 0 {
                streamingPendingMessage(
                    title: localized("First converted cards are on the way"),
                    subtitle: conversionProgress.statusMessage
                )
            } else {
                draftCardRows(
                    sortedAISessionDraftCards,
                    startingIndex: leadingRowCount
                )
            }
        } else if viewModel.isGenerating || viewModel.hasPausedAIGeneration {
            let leadingRowCount = displayedDraftRowsBeforeAISlots.count

            if createdCount == 0 {
                streamingPendingMessage(
                    title: localized("First cards are on the way"),
                    subtitle: localized("The first AI results will appear here in a moment.")
                )
            } else {
                draftCardRows(
                    sortedAISessionDraftCards,
                    startingIndex: leadingRowCount
                )
            }
        }
    }

    @ViewBuilder
    func streamingPendingMessage(
        title: String,
        subtitle: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .transition(
            .asymmetric(
                insertion: .offset(y: -12).combined(with: .opacity),
                removal: .opacity
            )
        )
    }

    @ViewBuilder
    func inlineHistoricalCardsToggle(
        title: String,
        hiddenCount: Int
    ) -> some View {
        if canToggleHistoricalSessionCards, hiddenCount > 0 || !isHistoricalCardsCollapsed {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                    isHistoricalCardsCollapsed.toggle()
                }
            } label: {
                HStack(spacing: UIConstants.Spacing.small) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text(
                        isHistoricalCardsCollapsed
                            ? localizedFormat("%d hidden", hiddenCount)
                            : localized("Showing all")
                    )
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                    Spacer(minLength: 0)

                    Text(isHistoricalCardsCollapsed ? localized("Show") : localized("Hide"))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isHistoricalCardsCollapsed ? 0 : 180))
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    func draftCardRows(
        _ cards: [DraftCard],
        startingIndex: Int = 0
    ) -> some View {
        ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
            draftCardRow(card, index: startingIndex + index + 1)
        }
    }

    @ViewBuilder
    func draftCardRow(
        _ card: DraftCard,
        index: Int
    ) -> some View {
        let row = DetailedCardRowView(
            card: card,
            index: index,
            isSelecting: viewModel.isSelectingCards,
            isSelected: viewModel.selectedDraftCardIDs.contains(card.id),
            onPrimaryTap: {
                if viewModel.isSelectingCards {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                        viewModel.toggleSelection(for: card.id)
                    }
                } else {
                    isTitleFocused = false
                    viewModel.presentCardEditor(for: card)
                }
            },
            onOpenRecommendedConversion: nil
        )
        .equatable()
            .transition(
                !viewModel.isSelectingCards
                    ? .asymmetric(
                        insertion: .offset(y: -18)
                            .combined(with: .opacity)
                            .combined(with: .scale(scale: 0.88, anchor: .top)),
                        removal: .offset(y: -14)
                            .combined(with: .opacity)
                            .combined(with: .scale(scale: 0.94, anchor: .top))
                    )
                    : .identity
            )
            .id(card.id)

        row
    }

    var emptyStateView: some View {
        VStack(spacing: 14) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tertiary)
            Text(localized("No cards yet"))
                .font(.headline)
                .foregroundStyle(.primary)
            Text(localized("Tap + to add a card, or generate cards with AI."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
            .background(Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .onTapGesture {
                isTitleFocused = false
                showAddCardTypeDialog = true
        }
    }

    func presentAIGenerationSourcePicker() {
        isTitleFocused = false
        exitDraftSelectionModeForExternalAction()
        viewModel.showAIPickerOptions = true
    }

    func chooseAIPhotoSourceFromPicker() {
        isTitleFocused = false
        viewModel.showAIPickerOptions = false
        viewModel.showAIPhotoPicker = true
    }

    func chooseAIPDFSourceFromPicker() {
        isTitleFocused = false
        viewModel.showAIPickerOptions = false
        viewModel.showAIPDFPicker = true
    }

    func openCardEditor(for kind: CardKind) {
        isTitleFocused = false
        exitDraftSelectionModeForExternalAction()
        showAddCardTypeDialog = false
        viewModel.presentCardEditor(for: kind)
    }

    var successOverlay: some View {
        VStack {
            HStack {
                HStack(spacing: UIConstants.Spacing.small + 2) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(accent)

                    Text(localized("Saved"))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    Rectangle()
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 1, height: 12)

                    Text(savedDeckTitle)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: 170, alignment: .leading)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .frame(maxWidth: successOverlayMaxWidth)
                .background {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.03))
                        }
                }
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.05), lineWidth: 0.75)
                }
                .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
                .blur(radius: viewModel.showSuccessOverlay ? 0 : 10)
                .scaleEffect(viewModel.showSuccessOverlay ? 1 : 0.985, anchor: .top)
                .opacity(viewModel.showSuccessOverlay ? 1 : 0)
                .offset(y: viewModel.showSuccessOverlay ? 0 : -12)
                .animation(successOverlayAnimation, value: viewModel.showSuccessOverlay)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
            .padding(.top, successOverlayTopPadding)

            Spacer()
        }
        .allowsHitTesting(false)
    }

    func handleSave() {
        isTitleFocused = false
        exitDraftSelectionModeForExternalAction()
        allowDismissWithoutConfirmation = true
        let didStartDismissFlow = viewModel.saveDeck(context: context)
        if !didStartDismissFlow {
            allowDismissWithoutConfirmation = false
        } else {
            aiWorkspaceCoordinator.dismissConversionOutcome()
            refreshSessionPresentationState()
        }
    }

    func startWorkspaceConversion() {
        isTitleFocused = false
        exitDraftSelectionModeForExternalAction()
        aiWorkspaceCoordinator.startConversion(context: context)
    }

    func handleDeleteDeck() {
        isTitleFocused = false
        exitDraftSelectionModeForExternalAction()
        allowDismissWithoutConfirmation = true
        let didDelete = viewModel.deleteDeck(
            context: context,
            router: router,
            dismissAction: dismissPresentation
        )
        if !didDelete {
            allowDismissWithoutConfirmation = false
        }
    }

    func handleCardEditorSave(destination: CardEditorDestination, content: DraftCardContent) {
        switch destination {
        case .create, .createFromDraft:
            viewModel.addCard(content: content)
        case .edit(let draftCard):
            viewModel.updateCard(draftCard, content: content)
        }

        viewModel.dismissCardEditor()
    }

    func requestDismiss() {
        exitDraftSelectionModeForExternalAction()
        guard attemptInteractiveDismissValidation() else { return }
        allowDismissWithoutConfirmation = true
        dismissPresentation()
    }

    func attemptInteractiveDismissValidation() -> Bool {
        guard !allowDismissWithoutConfirmation else { return true }
        guard viewModel.hasUnsavedChanges else { return true }
        Task { @MainActor in
            showUnsavedChangesDialog = true
        }
        return false
    }

    func discardChangesAndDismiss() {
        allowDismissWithoutConfirmation = true
        dismissPresentation()
    }

    func dismissPresentation() {
        if isShowingWorkspaceConvert {
            aiWorkspaceCoordinator.dismissConversionConfiguration()
        }

        let shouldResetCreateWorkspace =
            router.activeTab == .create
            && router.createPath.isEmpty
            && viewModel.isEditingExistingDeck

        if shouldResetCreateWorkspace {
            withAnimation(.circularProgressSpring) {
                router.showEmptyCreateWorkspace()
            }
            return
        }

        dismiss()
    }

    func syncAIWorkspaceGenerationState() {
        guard tracksWorkspaceGenerationStatus else { return }
        aiWorkspaceCoordinator.syncGenerationState(
            aiState: viewModel.aiState,
            hasPausedGeneration: viewModel.hasPausedAIGeneration,
            generatedCardCount: viewModel.aiGeneratedCardCount,
            targetCardCount: viewModel.aiTargetCardCount,
            deckTitle: collapsedDeckTitle
        )
    }

    func syncActiveConversionEditorState() {
        guard hostsSourceDeckConversionRuntime,
              let sourceDeckID = aiWorkspaceCoordinator.workspaceDeckContext?.sourceDeckID,
              let deck = context.safeModel(for: sourceDeckID, as: DeckModel.self) else { return }

        let keepsInlineConversionSession =
            aiWorkspaceCoordinator.conversionProgress != nil
            || aiWorkspaceCoordinator.pausedConversionSession != nil
        let isSameDeckConversion = aiWorkspaceCoordinator.workspaceDeckContext?.destination == .sameDeck

        viewModel.mergePersistedDeckState(
            deck,
            markNewCardsAsAISession: isSameDeckConversion && keepsInlineConversionSession
        )

        if isSameDeckConversion && !keepsInlineConversionSession {
            viewModel.integrateAllDraftCardsIntoBaseline()
        }
    }

    func refreshDerivedDeckState() {
        derivedDeckState = DeckWorkspaceDerivedState(cards: viewModel.draftCards)
    }

    func exitDraftSelectionModeForExternalAction() {
        guard viewModel.isSelectingCards else { return }
        withBottomChromeAnimation {
            viewModel.exitCardSelectionMode()
        }
    }

    func sortDraftCards(_ cards: [DraftCard]) -> [DraftCard] {
        cards.sorted { lhs, rhs in
            let lhsDate = lhs.createdAt ?? .distantPast
            let rhsDate = rhs.createdAt ?? .distantPast

            if lhsDate != rhsDate {
                return appPreferences.createDeckSortOrder == .newest
                    ? lhsDate > rhsDate
                    : lhsDate < rhsDate
            }

            if lhs.cardNumber != rhs.cardNumber {
                return appPreferences.createDeckSortOrder == .newest
                    ? lhs.cardNumber > rhs.cardNumber
                    : lhs.cardNumber < rhs.cardNumber
            }

            return appPreferences.createDeckSortOrder == .newest
                ? lhs.id.uuidString > rhs.id.uuidString
                : lhs.id.uuidString < rhs.id.uuidString
        }
    }

    func refreshSessionPresentationState() {
        guard appPreferences.autoCollapseEarlierCardsInAISession else { return }
        if hasUnifiedAISession,
           !viewModel.baseDraftCards.isEmpty,
           !viewModel.sessionDraftCards.isEmpty {
            isHistoricalCardsCollapsed = true
        }
    }

    func performLaunchActionIfNeeded() {
        guard !hasHandledLaunchAction else { return }
        hasHandledLaunchAction = true

        guard launchAction == .showAIGenerationOptions else { return }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            guard !viewModel.hasPausedAIGeneration,
                  viewModel.aiSheetDestination == nil,
                  !aiWorkspaceCoordinator.hasVisibleConversionWorkspaceState,
                  !viewModel.showAIPickerOptions,
                  !viewModel.hasPendingAISource else { return }
            viewModel.showAIPickerOptions = true
        }
    }
}

 struct DeckWorkspaceDerivedState: Equatable {
    let contentSummary: DraftDeckContentSummary
    let readinessSummary: DeckReadinessSummary
    let recommendedCards: [CardKind: [DraftCard]]

    static let empty = DeckWorkspaceDerivedState(cards: [])

    init(cards: [DraftCard]) {
        contentSummary = DraftDeckContentSummary(cards: cards)
        readinessSummary = CardReadinessDiagnostics.summary(for: cards)

        var recommendedCards: [CardKind: [DraftCard]] = [:]
        for card in cards {
            let targets = Set(
                CardReadinessDiagnostics.diagnostics(for: card.content)
                    .compactMap(\.recommendedConversionTargetKind)
            )
            for targetKind in targets {
                recommendedCards[targetKind, default: []].append(card)
            }
        }
        self.recommendedCards = recommendedCards
    }
}

@Observable
final class DeckWorkspaceScrollState {
    var pillVisible: Bool = false
}
