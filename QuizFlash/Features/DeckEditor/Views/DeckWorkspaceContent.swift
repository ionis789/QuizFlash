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
        if viewModel.isSelectingCards && !viewModel.draftCards.isEmpty {
            BottomChromeContainer(
                kind: .selection,
                bottomPadding: BottomChromeInsets.selectionInEditor(
                    viewSafeBottom: viewSafeBottom,
                    physicalSafeBottom: physicalSafeBottom,
                    isPresentedInFullScreenSheet: sheetSafeAreaInsets != nil
                )
            ) {
                DeckWorkspaceSelectionBottomBar(
                    selectedCount: viewModel.selectedDraftCardCount,
                    allSelected: viewModel.areAllDraftCardsSelected,
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
        LazyVStack(spacing: UIConstants.Spacing.medium) {
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

    func mainCardsListContent(using scrollProxy: ScrollViewProxy) -> AnyView {
        if viewModel.draftCards.isEmpty && !hasActiveGenerationRuntime {
            return AnyView(emptyStateView.transition(.opacity))
        }

        return AnyView(activeCardsListContent)
    }

    @ViewBuilder
    var activeCardsListContent: some View {
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

    @ViewBuilder
    var unifiedRuntimeCard: some View {
        if case .extractingText = viewModel.aiState {
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

        if viewModel.isGenerating || viewModel.hasPausedAIGeneration {
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
                isTitleFocused = false
                viewModel.presentCardEditor(for: card)
            },
            onToggleSelection: {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                    viewModel.toggleSelection(for: card.id)
                }
            }
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
        VStack(spacing: UIConstants.Spacing.large) {
            Button {
                presentAIGenerationSourcePicker()
            } label: {
                EmptyDeckPromptIllustration(
                    accent: accent,
                    actionColor: themeManager.roleColor(.buttonDangerForeground)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canStartLocalGeneration)
            .opacity(canStartLocalGeneration ? 1 : 0.48)
            .accessibilityLabel(localized("Generate cards with AI"))
            .padding(.bottom, UIConstants.Spacing.small)

            Button {
                presentAIGenerationSourcePicker()
            } label: {
                Text(localized("Generate with AI"))
                    .font(.system(size: 25, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                .foregroundStyle(themeManager.roleColor(.buttonDangerForeground))
                .padding(.horizontal, UIConstants.Spacing.standard)
                .padding(.vertical, 6)
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canStartLocalGeneration)
            .opacity(canStartLocalGeneration ? 1 : 0.48)
            .accessibilityLabel(localized("Generate cards with AI"))

            HStack(spacing: 9) {
                Color.secondary.opacity(0.24)
                    .frame(width: 28, height: 1)
                Text(localized("or"))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary.opacity(0.72))
                Color.secondary.opacity(0.24)
                    .frame(width: 28, height: 1)
            }
            .accessibilityLabel(localized("or"))

            Button {
                isTitleFocused = false
                showAddCardTypeDialog = true
            } label: {
                HStack(spacing: 9) {
                    Text(localized("Add manually"))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.86))

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(.secondary.opacity(0.62))
                }
                .padding(.horizontal, UIConstants.Spacing.small)
                .padding(.vertical, 8)
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(localized("Add manually"))
        }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 64)
            .background(Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    func presentAIGenerationSourcePicker() {
        isTitleFocused = false
        exitDraftSelectionModeForExternalAction()

        guard !viewModel.showAIPickerOptions,
              viewModel.aiSheetDestination == nil,
              !viewModel.showAIPhotoPicker,
              !viewModel.showAIPDFPicker,
              !viewModel.isPreparingAISource,
              !viewModel.hasPendingAISource,
              !hasUnifiedAISession else { return }

        viewModel.showAIPickerOptions = true
        Task {
            await CloudAIProxyClient.shared.prefetchPromptBundle()
        }
    }

    func confirmAIGenerationIfAllowed() async -> Bool {
        guard !isCheckingAIAccess else { return false }

        isCheckingAIAccess = true
        defer { isCheckingAIAccess = false }

        do {
            await subscriptionManager.refresh()
            syncAIGenerationLimit()
            guard canUseAIGeneration() else { return false }

            let targetCardCount = viewModel.targetCardCount(for: viewModel.resolvedAISourceAllocations)
            guard targetCardCount > 0 else { return false }

#if DEBUG
            viewModel.debugAIPromptBundle = try await CloudAIProxyClient.shared.currentPromptBundle()
            try await subscriptionManager.consumeAIGenerationQuota(targetCards: targetCardCount)
            syncAIGenerationLimit()
#else
            let cloudSession = try await CloudAIProxyClient.shared.startGeneration(targetCards: targetCardCount)
            viewModel.cloudAIGenerationSession = cloudSession
            subscriptionManager.applyCloudAIQuotaState(cloudSession.quota)
#endif
            viewModel.confirmAIGenerationFromSheet()
            return true
        } catch {
            aiAccessAlertMessage = error.localizedDescription
            showAIAccessAlert = true
            return false
        }
    }

    private func canUseAIGeneration() -> Bool {
        guard let message = subscriptionManager.aiGenerationLimitMessage(locale: locale) else {
            return true
        }

        aiAccessAlertMessage = message
        showAIAccessAlert = true
        return false
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
        let didStartDismissFlow = viewModel.saveDeck(
            context: context,
            onSuccessfulSave: onSuccessfulSave
        )
        if !didStartDismissFlow {
            allowDismissWithoutConfirmation = false
        } else {
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

        if let fullScreenSheetDismiss {
            fullScreenSheetDismiss()
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

            if appPreferences.createDeckSortOrder == .type {
                if lhs.kind != rhs.kind {
                    return lhs.kind.sortPriority < rhs.kind.sortPriority
                }

                if lhs.cardNumber != rhs.cardNumber {
                    return lhs.cardNumber < rhs.cardNumber
                }

                if lhsDate != rhsDate {
                    return lhsDate < rhsDate
                }

                return lhs.id.uuidString < rhs.id.uuidString
            }

            if lhsDate != rhsDate {
                return appPreferences.createDeckSortOrder.usesNewestFallback
                    ? lhsDate > rhsDate
                    : lhsDate < rhsDate
            }

            if lhs.cardNumber != rhs.cardNumber {
                return appPreferences.createDeckSortOrder.usesNewestFallback
                    ? lhs.cardNumber > rhs.cardNumber
                    : lhs.cardNumber < rhs.cardNumber
            }

            return appPreferences.createDeckSortOrder.usesNewestFallback
                ? lhs.id.uuidString > rhs.id.uuidString
                : lhs.id.uuidString < rhs.id.uuidString
        }
    }

    func refreshSessionPresentationState() {
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
                  !viewModel.showAIPickerOptions,
                  !viewModel.hasPendingAISource else { return }
            viewModel.showAIPickerOptions = true
        }
    }
}

private struct EmptyDeckPromptIllustration: View {
    let accent: Color
    let actionColor: Color

    var body: some View {
        ZStack {
            backCard
                .offset(x: -28, y: 12)
                .rotationEffect(.degrees(-9))

            middleCard
                .offset(x: 22, y: 6)
                .rotationEffect(.degrees(7))

            frontCard
        }
        .frame(width: 180, height: 168)
        .accessibilityHidden(true)
    }

    private var backCard: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(Color.primary.opacity(0.045))
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(accent.opacity(0.16), lineWidth: 1.5)
            }
            .frame(width: 108, height: 132)
    }

    private var middleCard: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(Color.primary.opacity(0.065))
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(actionColor.opacity(0.2), lineWidth: 1.5)
            }
            .frame(width: 108, height: 132)
    }

    private var frontCard: some View {
        RoundedRectangle(cornerRadius: 32, style: .continuous)
            .fill(Color.primary.opacity(0.1))
            .overlay {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                actionColor.opacity(0.52),
                                accent.opacity(0.42),
                                Color.white.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
            }
            .overlay {
                VStack(spacing: 12) {
                    HStack(spacing: 20) {
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(0.48))
                            .frame(width: 17, height: 5)
                            .rotationEffect(.degrees(-14))

                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(0.48))
                            .frame(width: 17, height: 5)
                            .rotationEffect(.degrees(14))
                    }

                    EmptyDeckFrown()
                        .stroke(Color.primary.opacity(0.42), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                        .frame(width: 42, height: 16)
                }
                .offset(y: 8)
            }
            .shadow(color: actionColor.opacity(0.18), radius: 22, x: 0, y: 12)
            .frame(width: 118, height: 142)
    }
}

private struct EmptyDeckFrown: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 2, y: rect.maxY - 4))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - 2, y: rect.maxY - 4),
            control: CGPoint(x: rect.midX, y: rect.midY - 2)
        )
        return path
    }
}

private extension CardKind {
    var sortPriority: Int {
        switch self {
        case .flashcard:
            return 0
        case .quiz:
            return 1
        }
    }
}

private extension CreateDeckSortOrder {
    var usesNewestFallback: Bool {
        self == .newest
    }
}

 struct DeckWorkspaceDerivedState: Equatable {
    let contentSummary: DraftDeckContentSummary

    static let empty = DeckWorkspaceDerivedState(cards: [])

    init(cards: [DraftCard]) {
        contentSummary = DraftDeckContentSummary(cards: cards)
    }
}

@Observable
final class DeckWorkspaceScrollState {
    var pillVisible: Bool = false
}
