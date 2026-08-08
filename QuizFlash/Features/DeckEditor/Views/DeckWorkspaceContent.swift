//
//  DeckWorkspaceContent.swift
//  QuizFlash
//

import SwiftUI
import SwiftData

extension DeckWorkspaceView {
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
                ? nil
                : .spring(response: 0.36, dampingFraction: 0.84),
            value: hasUnifiedAISession ? [] : viewModel.draftCards.map(\.id)
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
    var aiPendingSlots: some View {
        let createdCount = sortedAISessionDraftCards.count

        Group {
            if viewModel.isGenerating || viewModel.hasPausedAIGeneration {
                let leadingRowCount = displayedDraftRowsBeforeAISlots.count

                if createdCount == 0, viewModel.isGenerating {
                    EmptyDeckPromptIllustration(
                        accent: accent,
                        actionColor: themeManager.roleColor(.buttonDangerForeground),
                        surfaceColor: themeManager.roleColor(.cardSurfaceFill),
                        animatesWhileWaiting: true
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, UIConstants.Spacing.small)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.94)),
                            removal: .offset(y: -10)
                                .combined(with: .scale(scale: 0.82))
                                .combined(with: .opacity)
                        )
                    )
                } else if createdCount > 0 {
                    draftCardRows(
                        sortedAISessionDraftCards,
                        startingIndex: leadingRowCount
                    )
                }
            }
        }
        .animation(.smooth(duration: UIConstants.Animation.slow, extraBounce: 0), value: createdCount)
        .animation(.smooth(duration: UIConstants.Animation.slow, extraBounce: 0), value: viewModel.aiGenerationDisplayPhase)
    }

    @ViewBuilder
    func streamingPendingMessage(
        title: String,
        subtitle: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.system(size: 14, weight: .medium))
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
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.primary)

                    Text(
                        isHistoricalCardsCollapsed
                            ? localizedFormat("%d hidden", hiddenCount)
                            : localized("Showing all")
                    )
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                    Spacer(minLength: 0)

                    Text(isHistoricalCardsCollapsed ? localized("Show") : localized("Hide"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.secondary)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
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
                    insertion: .offset(y: 18)
                        .combined(with: .opacity)
                        .combined(with: .scale(scale: 0.96, anchor: .bottom)),
                    removal: .offset(y: 12)
                        .combined(with: .opacity)
                        .combined(with: .scale(scale: 0.98, anchor: .bottom))
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
                    actionColor: themeManager.roleColor(.buttonDangerForeground),
                    surfaceColor: themeManager.roleColor(.cardSurfaceFill)
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
                    .font(.system(size: 25, weight: .heavy))
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
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.secondary.opacity(0.72))
                Color.secondary.opacity(0.24)
                    .frame(width: 28, height: 1)
            }
            .accessibilityLabel(localized("or"))

            Button {
                isTitleFocused = false
                showAddCardTypePicker = true
            } label: {
                Text(localized("Add manually"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary.opacity(0.86))
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

            let cloudSession = try await CloudAIProxyClient.shared.startGeneration(targetCards: targetCardCount)
            viewModel.cloudAIGenerationSession = cloudSession
            subscriptionManager.applyCloudAIQuotaState(cloudSession.quota)
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
        PDFImportDebugStore.clear()
        PDFImportDebugStore.record("chooseAIPDFSourceFromPicker")
        viewModel.showAIPickerOptions = false
        viewModel.showAIPDFPicker = true
        PDFImportDebugStore.record(
            "chooseAIPDFSourceFromPicker flags set",
            details: [
                "showAIPickerOptions": String(viewModel.showAIPickerOptions),
                "showAIPDFPicker": String(viewModel.showAIPDFPicker),
            ]
        )
    }

    func openCardEditor(for kind: CardKind) {
        isTitleFocused = false
        exitDraftSelectionModeForExternalAction()
        showAddCardTypePicker = false
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
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)

                    Rectangle()
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 1, height: 12)

                    Text(savedDeckTitle)
                        .font(.system(size: 15, weight: .medium))
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
        let start = CFAbsoluteTimeGetCurrent()
        ZoneEditorDebugStore.shared.recordDismissFlow(
            "workspace.handle-save.start",
            details: "destination=\(destination.id) kind=\(destination.kind.rawValue) drafts=\(viewModel.draftCards.count)"
        )
        ZoneEditorDebugStore.shared.recordSheetDismissTrace(
            "workspace.handle-save.start",
            details: "destination=\(destination.id) kind=\(destination.kind.rawValue) drafts=\(viewModel.draftCards.count)"
        )
        switch destination {
        case .create, .createFromDraft:
            viewModel.addCard(content: content)
        case .edit(let draftCard):
            viewModel.updateCard(draftCard, content: content)
        }
        ZoneEditorDebugStore.shared.recordDismissFlow(
            "workspace.handle-save.after-mutation",
            details: "elapsed=\(Int((CFAbsoluteTimeGetCurrent() - start) * 1_000))ms drafts=\(viewModel.draftCards.count)"
        )
        ZoneEditorDebugStore.shared.recordSheetDismissTrace(
            "workspace.handle-save.after-mutation",
            details: "elapsed=\(Int((CFAbsoluteTimeGetCurrent() - start) * 1_000))ms drafts=\(viewModel.draftCards.count)"
        )

        viewModel.dismissCardEditor()
        ZoneEditorDebugStore.shared.recordDismissFlow(
            "workspace.handle-save.after-dismiss-request",
            details: "elapsed=\(Int((CFAbsoluteTimeGetCurrent() - start) * 1_000))ms destination=\(viewModel.cardEditorDestination?.id ?? "nil")"
        )
        ZoneEditorDebugStore.shared.recordSheetDismissTrace(
            "workspace.handle-save.after-dismiss-request",
            details: "elapsed=\(Int((CFAbsoluteTimeGetCurrent() - start) * 1_000))ms destination=\(viewModel.cardEditorDestination?.id ?? "nil")"
        )
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
        aiWorkspaceCoordinator.syncGenerationState(
            ownerID: aiWorkspaceOwnerID,
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

    func sortAISessionDraftCards(_ cards: [DraftCard]) -> [DraftCard] {
        cards.sorted { lhs, rhs in
            if lhs.cardNumber != rhs.cardNumber {
                return lhs.cardNumber < rhs.cardNumber
            }

            let lhsDate = lhs.createdAt ?? .distantPast
            let rhsDate = rhs.createdAt ?? .distantPast
            if lhsDate != rhsDate {
                return lhsDate < rhsDate
            }

            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    func sortDraftCardsPreservingCompletedAIGenerationOrder(_ cards: [DraftCard]) -> [DraftCard] {
        let completedRanks = Dictionary(
            uniqueKeysWithValues: completedAIGenerationDraftOrder.enumerated().map { ($0.element, $0.offset) }
        )
        let fallbackRanks = Dictionary(
            uniqueKeysWithValues: sortDraftCards(cards).enumerated().map { ($0.element.id, $0.offset) }
        )

        return cards.sorted { lhs, rhs in
            switch (completedRanks[lhs.id], completedRanks[rhs.id]) {
            case let (lhsRank?, rhsRank?):
                return lhsRank < rhsRank
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return fallbackRanks[lhs.id, default: 0] < fallbackRanks[rhs.id, default: 0]
            }
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
    let surfaceColor: Color
    var animatesWhileWaiting = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isFloating = false

    var body: some View {
        ZStack {
            backCard
                .offset(x: isFloating ? -14 : -30, y: 12)
                .rotationEffect(.degrees(isFloating ? -4 : -11))
                .scaleEffect(isFloating ? 0.98 : 1)

            middleCard
                .offset(x: isFloating ? -2 : 24, y: 8)
                .rotationEffect(.degrees(isFloating ? 13 : 11))
                .scaleEffect(isFloating ? 1 : 0.98)

            frontCard
                .offset(x: isFloating ? 12 : -3)
                .rotationEffect(.degrees(isFloating ? -2 : 2))
                .scaleEffect(isFloating ? 0.99 : 1)
        }
        .frame(width: 180, height: 168)
        .accessibilityHidden(true)
        .onAppear {
            guard animatesWhileWaiting, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: true)) {
                isFloating = true
            }
        }
    }

    private var backCard: some View {
        loadingCard(
            width: 108,
            height: 132,
            cornerRadius: 30,
            border: AnyShapeStyle(accent),
            lineWidth: 1.35
        )
    }

    private var middleCard: some View {
        loadingCard(
            width: 108,
            height: 132,
            cornerRadius: 30,
            border: AnyShapeStyle(actionColor),
            lineWidth: 1.35
        )
    }

    private var frontCard: some View {
        loadingCard(
            width: 118,
            height: 142,
            cornerRadius: 32,
            border: AnyShapeStyle(
                LinearGradient(
                    colors: [
                        actionColor,
                        accent,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            ),
            lineWidth: 1.45,
            duration: 2.2
        ) {
            VStack(alignment: .leading, spacing: 9) {
                promptLine(width: 55, opacity: 0.64)
                promptLine(width: 74, opacity: 0.46)
                promptLine(width: 44, opacity: 0.34)
            }
            .padding(.top, 37)
            .padding(.leading, 27)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .shadow(color: actionColor.opacity(0.18), radius: 22, x: 0, y: 12)
    }

    private func loadingCard(
        width: CGFloat,
        height: CGFloat,
        cornerRadius: CGFloat,
        border: AnyShapeStyle,
        lineWidth: CGFloat,
        beamBlur: CGFloat = 8,
        duration: TimeInterval = 2.7
    ) -> some View {
        loadingCard(
            width: width,
            height: height,
            cornerRadius: cornerRadius,
            border: border,
            lineWidth: lineWidth,
            beamBlur: beamBlur,
            duration: duration
        ) {
            EmptyView()
        }
    }

    private func loadingCard<Content: View>(
        width: CGFloat,
        height: CGFloat,
        cornerRadius: CGFloat,
        border: AnyShapeStyle,
        lineWidth: CGFloat,
        beamBlur: CGFloat = 8,
        duration: TimeInterval = 2.7,
        @ViewBuilder content: () -> Content
    ) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(surfaceColor)
            .frame(width: width, height: height)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(border, lineWidth: lineWidth)
                    .allowsHitTesting(false)
            }
            .aiGenerationBorderBeam(
                accent: accent,
                cornerRadius: cornerRadius,
                beamBlur: beamBlur,
                lineWidth: lineWidth,
                duration: duration,
                isEnabled: animatesWhileWaiting
            )
            .overlay(content: content)
    }

    private func promptLine(width: CGFloat, opacity: Double) -> some View {
        Capsule(style: .continuous)
            .fill(Color.white.opacity(opacity))
            .frame(width: width, height: 5)
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
