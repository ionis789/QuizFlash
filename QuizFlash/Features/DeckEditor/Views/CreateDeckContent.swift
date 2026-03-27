//
//  CreateDeckContent.swift
//  QuizFlash
//

import SwiftUI
import SwiftData

extension CreateDeckView {

    func updateViewSafeBottom(using viewInset: CGFloat) {
        guard abs(viewSafeBottom - viewInset) > 0.5 else { return }
        viewSafeBottom = viewInset
    }

    func capturePhysicalSafeBottomIfNeeded() {
        guard !hasCapturedPhysicalSafeBottom else { return }
        hasCapturedPhysicalSafeBottom = true

        if let presentedBottomInset = presentedSafeAreaInsets?.bottom, presentedBottomInset > 0 {
            physicalSafeBottom = presentedBottomInset
            return
        }

        physicalSafeBottom = UIApplication.shared
            .connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows
            .first(where: { $0.isKeyWindow })?
            .safeAreaInsets.bottom ?? 0
    }

    @ViewBuilder
    var draftSelectionBottomBar: some View {
        if viewModel.isSelectingCards && !viewModel.draftCards.isEmpty {
            let isPresentedInFullScreenSheet = fullScreenSheetDismiss != nil
            BottomChromeContainer(
                kind: .selection,
                bottomPadding: BottomChromeInsets.selectionInEditor(
                    viewSafeBottom: viewSafeBottom,
                    physicalSafeBottom: physicalSafeBottom,
                    isPresentedInFullScreenSheet: isPresentedInFullScreenSheet
                ),
                ignoresBottomSafeArea: isPresentedInFullScreenSheet
            ) {
                CreateDeckSelectionBottomBar(
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
                viewModel.isGenerating ? nil : .spring(response: 0.36, dampingFraction: 0.84),
                value: viewModel.draftCards.map(\.id)
            )
            .animation(.easeInOut(duration: 0.35), value: viewModel.draftCards.isEmpty)
    }

    @ViewBuilder
    func mainCardsListContent(using scrollProxy: ScrollViewProxy) -> some View {
        if viewModel.draftCards.isEmpty && !hasActiveGenerationRuntime && !hasActiveConversionRuntime {
            emptyStateView.transition(.opacity)
        } else {
            unifiedRuntimeCard

            if hasUnifiedAISession {
                if !displayedDraftRowsBeforeAISlots.isEmpty {
                    draftCardRows(displayedDraftRowsBeforeAISlots)
                }

                aiPendingSlots

                inlineHistoricalCardsToggle(
                    title: "Earlier cards",
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
        if case .extractingText = viewModel.aiState {
            AIExtractingLoadingView()
                .transition(.asymmetric(insertion: .opacity, removal: .opacity))
        } else if viewModel.hasPausedAIGeneration {
            let progress = min(1.0, Double(viewModel.aiGeneratedCardCount) / Double(max(viewModel.aiTargetCardCount, 1)))
            AIPausedResumeCard(
                foundCount: viewModel.aiGeneratedCardCount,
                targetCount: max(viewModel.aiTargetCardCount, 1),
                remainingCount: max(viewModel.pausedRemainingCardCount, 0),
                progress: progress,
                onResume: {
                    viewModel.resumePausedAIGeneration()
                }
            )
            .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
        } else if case .generatingCards(let progress, let foundCount) = viewModel.aiState {
            AIStreamingProgressCard(
                foundCount: foundCount,
                targetCount: max(viewModel.aiTargetCardCount, 1),
                progress: progress,
                onCancel: {
                    viewModel.requestAIGenerationCancel()
                },
                onPause: {
                    viewModel.pauseAIGeneration()
                }
            )
            .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
        } else if aiWorkspaceCoordinator.canResumeConversion,
                  let progress = aiWorkspaceCoordinator.conversionProgress {
            AIPausedResumeCard(
                foundCount: progress.createdCount,
                targetCount: max(progress.totalCount, 1),
                remainingCount: max(progress.totalCount - progress.completedCount, 0),
                progress: progress.fractionCompleted,
                title: "Generation paused",
                subtitle: "Continue from the last completed batch when you're ready.",
                accentColor: .orange,
                onResume: {
                    aiWorkspaceCoordinator.resumeConversion(context: context)
                }
            )
            .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
        } else if let progress = aiWorkspaceCoordinator.conversionProgress {
            AIStreamingProgressCard(
                foundCount: progress.createdCount,
                targetCount: max(progress.totalCount, 1),
                progress: progress.fractionCompleted,
                subtitleOverride: progress.statusMessage,
                accentColor: .orange,
                onCancel: {
                    aiWorkspaceCoordinator.requestConversionCancel()
                },
                onPause: {
                    aiWorkspaceCoordinator.pauseConversion()
                }
            )
            .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
        }
    }

    @ViewBuilder
    var aiPendingSlots: some View {
        let createdCount = sortedAISessionDraftCards.count

        if viewModel.isGenerating || viewModel.hasPausedAIGeneration {
            let slotCount = max(viewModel.aiTargetCardCount, createdCount)
            let leadingRowCount = displayedDraftRowsBeforeAISlots.count

            ForEach(0..<slotCount, id: \.self) { slotIndex in
                let card = slotIndex < sortedAISessionDraftCards.count ? sortedAISessionDraftCards[slotIndex] : nil
                AIStreamingCardSlot(
                    slotIndex: slotIndex,
                    isFilled: card != nil,
                    filledCardID: card?.id,
                    shouldAnimateReveal: card.map { !viewModel.hasCompletedAIGeneratedCardReveal(id: $0.id) } ?? false,
                    onRevealFinished: { revealedCardID in
                        viewModel.markAIGeneratedCardRevealCompleted(id: revealedCardID)
                    }
                ) {
                    if let card {
                        draftCardRow(
                            card,
                            index: leadingRowCount + slotIndex + 1,
                            appliesTransition: false
                        )
                    }
                }
            }
        } else if let progress = aiWorkspaceCoordinator.conversionProgress {
            let leadingRowCount = displayedDraftRowsBeforeAISlots.count
            let slotCount = max(progress.totalCount, createdCount)

            ForEach(0..<slotCount, id: \.self) { slotIndex in
                let card = slotIndex < sortedAISessionDraftCards.count ? sortedAISessionDraftCards[slotIndex] : nil
                AIStreamingCardSlot(
                    slotIndex: slotIndex,
                    isFilled: card != nil,
                    filledCardID: card?.id,
                    shouldAnimateReveal: false
                ) {
                    if let card {
                        draftCardRow(
                            card,
                            index: leadingRowCount + slotIndex + 1,
                            appliesTransition: false
                        )
                    }
                }
            }
        }
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
                            ? "\(hiddenCount) hidden"
                            : "Showing all"
                    )
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                    Spacer(minLength: 0)

                    Text(isHistoricalCardsCollapsed ? "Show" : "Hide")
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
    func conversionPendingSlots(
        createdCount: Int,
        targetCount: Int
    ) -> some View {
        let remainingCount = max(0, targetCount - createdCount)

        ForEach(0..<remainingCount, id: \.self) { slotIndex in
            AIStreamingCardSlot(
                slotIndex: createdCount + slotIndex,
                isFilled: false,
                filledCardID: nil,
                shouldAnimateReveal: false
            ) {
                EmptyView()
            }
        }
    }

    @ViewBuilder
    func draftCardRows(
        _ cards: [DraftCard]
    ) -> some View {
        ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
            draftCardRow(card, index: index + 1)
        }
    }

    @ViewBuilder
    func draftCardRow(
        _ card: DraftCard,
        index: Int,
        appliesTransition: Bool = true
    ) -> some View {
        let row = DetailedCardRowView(
            card: card,
            index: index,
            fixedHeight: appliesTransition ? nil : UIConstants.Size.draftCardRowHeight,
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
            onOpenRecommendedConversion: { targetKind in
                presentDraftRecommendedConversion(for: card, targetKind: targetKind)
            }
        )
        .equatable()
            .transition(
                (appliesTransition && !viewModel.isSelectingCards)
                    ? .asymmetric(
                        insertion: .move(edge: .bottom)
                            .combined(with: .opacity)
                            .combined(with: .scale(scale: 0.96)),
                        removal: .scale(scale: 0.92).combined(with: .opacity)
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
            Text("No cards yet")
                .font(.headline)
                .foregroundStyle(.primary)
            Text("Tap + to choose Flashcard, Match, Quiz, or Write, or use Auto AI to generate cards instantly.")
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

    func openCardEditor(for kind: CardKind) {
        isTitleFocused = false
        exitDraftSelectionModeForExternalAction()
        showAddCardTypeDialog = false
        viewModel.presentCardEditor(for: kind)
    }

    func presentConversionConfiguration() {
        isTitleFocused = false
        guard let sourceDeck = preferredConversionSourceDeck else { return }
        reseedConversion(for: sourceDeck)
    }

    var preferredConversionSourceDeck: DeckModel? {
        if let seed = aiWorkspaceCoordinator.conversionSeed,
           let matchingDeck = sourceDecks.first(where: { $0.persistentModelID == seed.sourceDeckID }) {
            return matchingDeck
        }

        if let deckToEdit = viewModel.deckToEdit {
            return deckToEdit
        }

        return sourceDecks.first
    }

    func reseedConversion(for sourceDeck: DeckModel) {
        guard let request = makeConversionRequest(for: sourceDeck) else { return }
        exitDraftSelectionModeForExternalAction()
        _ = aiWorkspaceCoordinator.seedConversion(
            request: request,
            sourceDeck: sourceDeck,
            activatesWorkspaceContext: false
        )
        isHistoricalCardsCollapsed = true
    }

    func makeConversionRequest(for sourceDeck: DeckModel) -> DeckCardConversionRequest? {
        let orderedCards = sourceDeck.cards.sorted {
            if $0.cardNumber == $1.cardNumber {
                return $0.createdAt < $1.createdAt
            }
            return $0.cardNumber < $1.cardNumber
        }

        let wholeDeckSources = orderedCards.map {
            DeckCardConversionSourceDescriptor(id: $0.persistentModelID, kind: $0.kind)
        }
        let recommendedSources = orderedCards
            .filter { card in
                CardReadinessDiagnostics.diagnostics(for: card)
                    .contains { $0.recommendedConversionTargetKind != nil }
            }
            .map { DeckCardConversionSourceDescriptor(id: $0.persistentModelID, kind: $0.kind) }

        guard !wholeDeckSources.isEmpty else { return nil }

        var availableScopes: [DeckCardConversionScopeOption] = [.wholeDeck]
        if !recommendedSources.isEmpty {
            availableScopes.insert(.recommendedCards, at: 0)
        }

        let preferredTargetKind = aiWorkspaceCoordinator.conversionSeed?.request.targetKind
        let sourceKinds = wholeDeckSources.map(\.kind)
        let targetKind = preferredTargetKind ?? defaultConversionTargetKind(for: sourceKinds)
        let sourceKindFilters = Set(
            wholeDeckSources
                .map(\.kind)
                .filter { $0 != targetKind }
        )

        let existingRequest = aiWorkspaceCoordinator.conversionSeed?.request

        return DeckCardConversionRequest(
            availableScopes: availableScopes,
            wholeDeckSources: wholeDeckSources,
            recommendedSources: recommendedSources,
            selectedSources: [],
            singleSources: [],
            scope: availableScopes.contains(existingRequest?.scope ?? .wholeDeck)
                ? (existingRequest?.scope ?? .wholeDeck)
                : .wholeDeck,
            sourceKindFilters: existingRequest?.sourceKindFilters ?? sourceKindFilters,
            targetKind: targetKind,
            destination: existingRequest?.destination ?? .sameDeck,
            newDeckTitle: existingRequest?.newDeckTitle ?? "\(sourceDeck.title) \(targetKind.displayTitle)s"
        )
    }

    func defaultConversionTargetKind(for sourceKinds: [CardKind]) -> CardKind {
        let sourceKindSet = Set(sourceKinds)
        let orderedTargets: [CardKind] = [.match, .quiz, .write, .flashcard]
        return orderedTargets.first(where: { !sourceKindSet.contains($0) }) ?? .match
    }

    func recommendedDraftCards(for targetKind: CardKind) -> [DraftCard] {
        derivedDeckState.recommendedCards[targetKind] ?? []
    }

    func presentDraftRecommendedConversion(for card: DraftCard, targetKind: CardKind) {
        isTitleFocused = false
        exitDraftSelectionModeForExternalAction()
        viewModel.presentCardConversionEditor(for: card, targetKind: targetKind)
    }

    var successOverlay: some View {
        VStack {
            HStack {
                HStack(spacing: UIConstants.Spacing.small + 2) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(accent)

                    Text("Saved")
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
        if let fullScreenSheetDismiss {
            fullScreenSheetDismiss()
        } else {
            dismiss()
        }
    }

    func syncAIWorkspaceGenerationState() {
        guard isAIWorkspaceHost else { return }
        aiWorkspaceCoordinator.syncGenerationState(
            aiState: viewModel.aiState,
            hasPausedGeneration: viewModel.hasPausedAIGeneration,
            generatedCardCount: viewModel.aiGeneratedCardCount,
            targetCardCount: viewModel.aiTargetCardCount,
            deckTitle: collapsedDeckTitle
        )
    }

    func refreshDerivedDeckState() {
        derivedDeckState = CreateDeckDerivedState(cards: viewModel.draftCards)
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

    func refreshWorkspaceDeckPresentation() {
        guard let workspaceContext = conversionWorkspaceContext else {
            hasSeededWorkspaceEditorState = false
            workspaceSeedSignature = nil
            refreshSessionPresentationState()
            return
        }

        let liveDeckID = workspaceContext.liveDeckID ?? (
            workspaceContext.destination == .sameDeck ? workspaceContext.sourceDeckID : nil
        )
        let seedSignature = CreateDeckWorkspaceSeedSignature(
            sourceDeckID: workspaceContext.sourceDeckID,
            destination: workspaceContext.destination,
            liveDeckID: liveDeckID
        )
        if workspaceSeedSignature != seedSignature {
            workspaceSeedSignature = seedSignature
            hasSeededWorkspaceEditorState = false
        }

        let sourceDeck = context.safeModel(for: workspaceContext.sourceDeckID, as: DeckModel.self)

        guard let liveDeckID,
              let deck = context.safeModel(for: liveDeckID, as: DeckModel.self) else {
            viewModel.seedEditorState(
                editingDeckID: nil,
                title: workspaceContext.displayTitle,
                selectedFolder: sourceDeck?.folder,
                draftCards: [],
                resetsBaseline: !hasSeededWorkspaceEditorState
            )
            hasSeededWorkspaceEditorState = true
            refreshSessionPresentationState()
            return
        }

        let orderedCards = deck.cards.sorted {
            if $0.cardNumber == $1.cardNumber {
                return $0.createdAt < $1.createdAt
            }
            return $0.cardNumber < $1.cardNumber
        }

        if !hasSeededWorkspaceEditorState {
            viewModel.seedEditorState(
                editingDeckID: deck.persistentModelID,
                title: deck.title,
                selectedFolder: deck.folder,
                draftCards: orderedCards.map(workspaceDraftCard(from:)),
                resetsBaseline: workspaceContext.destination == .sameDeck
            )
            hasSeededWorkspaceEditorState = true
        } else {
            viewModel.mergePersistedDeckState(deck, markNewCardsAsAISession: true)
        }
        refreshSessionPresentationState()
    }

    func workspaceDraftCard(from card: CardModel) -> DraftCard {
        DraftCard(
            id: CreateDeckViewModel.stableDraftID(for: card.persistentModelID),
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
}

 struct CreateDeckDerivedState: Equatable {
    let contentSummary: DraftDeckContentSummary
    let readinessSummary: DeckReadinessSummary
    let recommendedCards: [CardKind: [DraftCard]]

    static let empty = CreateDeckDerivedState(cards: [])

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
final class CreateDeckScrollState {
    var pillVisible: Bool = false
}
