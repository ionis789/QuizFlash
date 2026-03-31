//
//  CreateDeckView.swift
//  QuizFlash
//
//  Abstract:
//  Primary entry point for creating or editing a deck.
//  Delegates all state and business logic to `CreateDeckViewModel`.
//  Manages only local UI concerns: keyboard focus and tab-bar visibility.
//

import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

let kCreateDeckChromeSpace = "CreateDeckChromeSpace"

struct CreateDeckWorkspaceSeedSignature: Equatable {
    let sourceDeckID: PersistentIdentifier
    let destination: DeckCardConversionDestinationOption
    let liveDeckID: PersistentIdentifier?
}

struct CreateDeckView: View {
    // MARK: - Environment
    @Environment(\.modelContext) var context
    @Environment(\.dismiss) var dismiss
    @Environment(\.fullScreenSheetDismiss) var fullScreenSheetDismiss
    @Environment(\.fullScreenSheetDismissCoordinator) var fullScreenSheetDismissCoordinator
    @Environment(\.scenePhase) var scenePhase
    @Environment(NavigationManager.self) var router
    @Environment(AIWorkspaceCoordinator.self) var aiWorkspaceCoordinator
    @Environment(AppPreferences.self) var appPreferences
    @Environment(ThemeManager.self) var themeManager

    /// Fetches all available folders to populate the destination picker.
    @Query(sort: \FolderModel.createdAt, order: .reverse) var folders: [FolderModel]
    @Query(sort: \DeckModel.editedAt, order: .reverse) var sourceDecks: [DeckModel]

    // MARK: - State
    @State var viewModel: CreateDeckViewModel
    @State var scrollState = CreateDeckScrollState()
    @State var derivedDeckState = CreateDeckDerivedState.empty
    @State var navigationBarHeight: CGFloat = UIConstants.Size.actionButton
    @State var viewSafeBottom: CGFloat = 0
    @State var physicalSafeBottom: CGFloat = 0
    @State var showUnsavedChangesDialog = false
    @State var showDeleteDeckConfirmation = false
    @State var showAddCardTypeDialog = false
    @State var allowDismissWithoutConfirmation = false
    @State var hasCapturedPhysicalSafeBottom = false
    @State var isHistoricalCardsCollapsed = true
    @State var hasSeededWorkspaceEditorState = false
    @State var workspaceSeedSignature: CreateDeckWorkspaceSeedSignature?

    /// Tracks the focus state of the deck title text field.
    /// Drives the tab bar visibility rule reactively.
    @FocusState var isTitleFocused: Bool

    // MARK: - Input
    let presentedSafeAreaInsets: UIEdgeInsets?
    let isAIWorkspaceHost: Bool

    // MARK: - Computed Properties
    var accent: Color { ThemeManager.shared.accentColor.color }
    var canSave: Bool {
        let hasTitle = !viewModel.deckTitle.trimmingCharacters(in: .whitespaces).isEmpty
        if viewModel.isEditingExistingDeck {
            return hasTitle && viewModel.hasUnsavedChanges
        }
        return hasTitle && !viewModel.draftCards.isEmpty
    }
    var collapsedDeckTitle: String {
        if let workspaceTitle = conversionWorkspaceContext?.displayTitle,
           !workspaceTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return workspaceTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return viewModel.deckTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    var destinationTitle: String {
        viewModel.selectedFolder?.title ?? "Library"
    }
    var draftDeckContentSummary: DraftDeckContentSummary {
        derivedDeckState.contentSummary
    }

    var draftDeckReadinessSummary: DeckReadinessSummary {
        derivedDeckState.readinessSummary
    }
    var draftReadinessRecommendedTargets: [CardKind] {
        draftDeckReadinessSummary.recommendedConversions.map(\.targetKind)
    }
    var aiToolbarStatusText: String? {
        switch viewModel.aiState {
        case .extractingText:
            return "Reading Docs..."
        case .generatingCards(_, let foundCount):
            let target = max(viewModel.aiTargetCardCount, 1)
            return foundCount > 0 ? "AI \(foundCount)/\(target)" : "Generating AI..."
        default:
            return nil
        }
    }
    var aiVisualStatusText: String? {
        switch viewModel.aiState {
        case .extractingText:
            return "Reading"
        case .generatingCards(_, let foundCount):
            let target = max(viewModel.aiTargetCardCount, 1)
            return foundCount > 0 ? "\(foundCount)/\(target)" : "Generating"
        default:
            if viewModel.hasPausedAIGeneration {
                return aiToolbarCountText ?? "AI generation paused"
            }
            return nil
        }
    }
    var aiToolbarTint: Color {
        if case .extractingText = viewModel.aiState {
            return .orange
        }
        return accent
    }
    var successOverlayMaxWidth: CGFloat {
        min(UIScreen.main.bounds.width - (UIConstants.Layout.screenEdgeInset * 2), 320)
    }
    var savedDeckTitle: String {
        let overlayTitle = viewModel.successOverlayDeckTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !overlayTitle.isEmpty {
            return overlayTitle
        }
        let trimmedTitle = viewModel.deckTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? "Untitled Deck" : trimmedTitle
    }
    var successOverlayTopPadding: CGFloat {
        navigationBarHeight + (fullScreenSheetDismiss == nil ? UIConstants.Spacing.large : UIConstants.Spacing.extraLarge)
    }
    var successOverlayAnimation: Animation {
        .smooth(duration: UIConstants.Animation.medium, extraBounce: 0)
    }
    var aiToolbarCountText: String? {
        switch viewModel.aiState {
        case .generatingCards(_, let foundCount):
            guard foundCount > 0 else { return nil }
            return "\(foundCount)/\(max(viewModel.aiTargetCardCount, 1))"
        default:
            guard viewModel.hasPausedAIGeneration, viewModel.aiGeneratedCardCount > 0 else { return nil }
            return "\(viewModel.aiGeneratedCardCount)/\(max(viewModel.aiTargetCardCount, 1))"
        }
    }
    var conversionWorkspaceContext: AIWorkspaceDeckContext? {
        guard isAIWorkspaceHost else { return nil }
        return aiWorkspaceCoordinator.workspaceDeckContext
    }
    var isShowingConversionWorkspace: Bool { conversionWorkspaceContext != nil }
    var isShowingConversionConfiguration: Bool {
        aiWorkspaceCoordinator.conversionSheetToken != nil && aiWorkspaceCoordinator.conversionSeed != nil
    }
    var conversionConfigurationSheetBinding: Binding<AIWorkspaceConversionSheetToken?> {
        Binding(
            get: { aiWorkspaceCoordinator.conversionSheetToken },
            set: { newValue in
                if newValue == nil {
                    aiWorkspaceCoordinator.dismissConversionConfiguration()
                } else {
                    aiWorkspaceCoordinator.conversionSheetToken = newValue
                }
            }
        )
    }
    var tabBarOffset: CGFloat {
        max(0, viewSafeBottom - physicalSafeBottom)
    }
    var canStartLocalGeneration: Bool {
        !hasUnifiedAISession
            && (!isAIWorkspaceHost || !aiWorkspaceCoordinator.hasBlockingJob || aiWorkspaceCoordinator.generationStatus != nil)
    }
    var shouldShowFloatingGenerate: Bool {
        scrollState.pillVisible
            && !viewModel.draftCards.isEmpty
            && !viewModel.isSelectingCards
            && !isTitleFocused
            && viewModel.aiSheetDestination == nil
            && !viewModel.showSuccessOverlay
            && !hasUnifiedAISession
            && !isShowingConversionConfiguration
    }
    var shouldShowCollapsedTitle: Bool {
        scrollState.pillVisible && !viewModel.draftCards.isEmpty && !collapsedDeckTitle.isEmpty
    }
    var canUseInteractiveDismiss: Bool {
        fullScreenSheetDismiss != nil
            && viewModel.aiSheetDestination == nil
            && !viewModel.showSuccessOverlay
            && !isTitleFocused
            && !hasUnifiedAISession
            && !isShowingConversionConfiguration
    }
    var swipeBackEnabled: Bool {
        fullScreenSheetDismiss != nil ? canUseInteractiveDismiss : true
    }
    var swipeBackAttachment: SwipeBackAttachment {
        fullScreenSheetDismiss != nil ? .localHost : .window
    }

    /// Contextual rule for tab bar visibility.
    ///
    /// Forces the tab bar to hide only while the keyboard is active.
    /// Materialization (card reveal animation) intentionally leaves the bar visible.
    var tabRule: TabBarVisibilityRule {
        if isTitleFocused || viewModel.aiSheetDestination != nil || viewModel.isSelectingCards || isShowingConversionConfiguration {
            return .hidden
        }
        return .implicit
    }

    var canOpenConversionMenu: Bool {
        !sourceDecks.isEmpty
            && !viewModel.isGenerating
            && (!isAIWorkspaceHost || !aiWorkspaceCoordinator.hasBlockingJob || isShowingConversionConfiguration || isShowingConversionWorkspace)
    }
    var hasActiveGenerationRuntime: Bool {
        if case .extractingText = viewModel.aiState { return true }
        if case .generatingCards = viewModel.aiState { return true }
        return viewModel.hasPausedAIGeneration
    }

    var hasActiveConversionRuntime: Bool {
        aiWorkspaceCoordinator.conversionProgress != nil || aiWorkspaceCoordinator.canResumeConversion
    }

    var hasUnifiedAISession: Bool {
        hasActiveGenerationRuntime
            || hasActiveConversionRuntime
            || viewModel.hasAISessionDraftCards
            || isShowingConversionWorkspace
    }

    var displayedDraftCards: [DraftCard] {
        if hasUnifiedAISession {
            return sortDraftCards(viewModel.sessionDraftCards)
        }
        return sortDraftCards(viewModel.draftCards)
    }

    var displayedDraftRowsBeforeAISlots: [DraftCard] {
        guard hasUnifiedAISession else {
            return displayedDraftCards
        }
        guard hasActiveGenerationRuntime || hasActiveConversionRuntime else {
            return displayedDraftCards
        }
        return displayedDraftCards.filter { !viewModel.aiSessionDraftCardIDs.contains($0.id) }
    }

    var displayedHistoricalDraftCards: [DraftCard] {
        guard hasUnifiedAISession, !isHistoricalCardsCollapsed else { return [] }
        return sortDraftCards(viewModel.baseDraftCards)
    }

    var sortedAISessionDraftCards: [DraftCard] {
        sortDraftCards(viewModel.aiSessionDraftCards)
    }

    var canToggleHistoricalSessionCards: Bool {
        hasUnifiedAISession && !viewModel.baseDraftCards.isEmpty
    }

    var hiddenSessionCardsCount: Int {
        guard hasUnifiedAISession, isHistoricalCardsCollapsed else { return 0 }
        return viewModel.baseDraftCards.count
    }

    // MARK: - Initialization
    init(deckToEdit: DeckModel? = nil, safeAreaInsets: UIEdgeInsets? = nil) {
        self.isAIWorkspaceHost = false
        self.presentedSafeAreaInsets = safeAreaInsets
        _viewModel = State(initialValue: CreateDeckViewModel(deckToEdit: deckToEdit))
    }

    init(
        deckToEdit: DeckModel? = nil,
        safeAreaInsets: UIEdgeInsets? = nil,
        isAIWorkspaceHost: Bool
    ) {
        self.isAIWorkspaceHost = isAIWorkspaceHost
        self.presentedSafeAreaInsets = safeAreaInsets
        _viewModel = State(initialValue: CreateDeckViewModel(deckToEdit: deckToEdit))
    }

    var body: some View {
        conversionStateSyncedContent
    }

    var conversionStateSyncedContent: some View {
        generationStateSyncedContent
            .onChange(of: aiWorkspaceCoordinator.workspaceDeckContext) { _, _ in
                refreshWorkspaceDeckPresentation()
            }
            .onChange(of: aiWorkspaceCoordinator.conversionProgress) { _, _ in
                refreshWorkspaceDeckPresentation()
            }
            .onChange(of: aiWorkspaceCoordinator.conversionSummary) { _, _ in
                refreshWorkspaceDeckPresentation()
            }
            .onChange(of: aiWorkspaceCoordinator.conversionErrorMessage) { _, _ in
                refreshWorkspaceDeckPresentation()
            }
            .onChange(of: aiWorkspaceCoordinator.conversionSheetToken) { _, _ in
                refreshSessionPresentationState()
            }
    }

    var generationStateSyncedContent: some View {
        appearanceBoundContent
            .onChange(of: viewModel.aiState) { _, _ in
                syncAIWorkspaceGenerationState()
            }
            .onChange(of: viewModel.aiGeneratedCardCount) { _, _ in
                syncAIWorkspaceGenerationState()
            }
            .onChange(of: viewModel.aiTargetCardCount) { _, _ in
                syncAIWorkspaceGenerationState()
            }
            .onChange(of: viewModel.hasPausedAIGeneration) { _, _ in
                syncAIWorkspaceGenerationState()
            }
            .onChange(of: viewModel.deckTitle) { _, _ in
                syncAIWorkspaceGenerationState()
            }
            .onChange(of: viewModel.draftCards) { _, _ in
                refreshSessionPresentationState()
            }
            .onChange(of: viewModel.aiState) { _, _ in
                refreshSessionPresentationState()
            }
            .onChange(of: viewModel.aiGeneratedCardCount) { _, _ in
                refreshSessionPresentationState()
            }
            .onChange(of: viewModel.hasPausedAIGeneration) { _, _ in
                refreshSessionPresentationState()
            }
            .onChange(of: appPreferences.autoCollapseEarlierCardsInAISession) { _, newValue in
                if newValue {
                    refreshSessionPresentationState()
                } else {
                    isHistoricalCardsCollapsed = false
                }
            }
    }

    var appearanceBoundContent: some View {
        AnyView(pickerBoundContent)
            .onChange(of: viewModel.aiSheetDestination) { oldValue, newValue in
                if oldValue != nil, newValue == nil {
                    viewModel.handleAISheetDismissed()
                }
            }
            .swipeBack(
                enabled: swipeBackEnabled,
                attachment: swipeBackAttachment
            ) {
                requestDismiss()
            }
            .onAppear {
                refreshDerivedDeckState()
                refreshWorkspaceDeckPresentation()
                refreshSessionPresentationState()
                syncAIWorkspaceGenerationState()
                fullScreenSheetDismissCoordinator?.shouldAllowDismiss = {
                    attemptInteractiveDismissValidation()
                }
            }
            .onChange(of: viewModel.draftCards) { _, _ in
                refreshDerivedDeckState()
            }
            .onDisappear {
                if fullScreenSheetDismissCoordinator?.shouldAllowDismiss != nil {
                    fullScreenSheetDismissCoordinator?.shouldAllowDismiss = nil
                }
                guard viewModel.aiSheetDestination == nil,
                      viewModel.cardEditorDestination == nil else { return }
                ImageCache.shared.clearCache()
            }
            .customTabBarVisibility(tabRule)
    }

    var pickerBoundContent: some View {
        generationSheetContent
            .photosPicker(isPresented: $viewModel.showAIPhotoPicker, selection: $viewModel.selectedAIPhotos, matching: .images)
            .fileImporter(isPresented: $viewModel.showAIPDFPicker, allowedContentTypes: [.pdf], allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first { viewModel.pdfWasSelected(url) }
            }
    }

    var generationSheetContent: some View {
        viewContent
            .fullScreenSheet(
                ignoresSafeArea: true,
                item: $viewModel.aiSheetDestination,
                dragDismissActivationHeight: 180
            ) { _, safeArea in
                AIGenerationSheetView(
                    viewModel: viewModel,
                    safeAreaInsets: safeArea,
                    onPrimaryAction: {
                        viewModel.confirmAIGenerationFromSheet()
                    },
                    onCancel: {
                        viewModel.dismissAISheet(clearPendingSourceSelection: true)
                    }
                )
            } background: {
                AIGenerationSheetBackground()
            }
            .sheet(item: conversionConfigurationSheetBinding) { _ in
                AIWorkspaceConversionSheetView(
                    coordinator: aiWorkspaceCoordinator,
                    sourceDecks: sourceDecks,
                    onSelectSourceDeck: { deck in
                        reseedConversion(for: deck)
                    }
                ) {
                    aiWorkspaceCoordinator.startConversion(context: context)
                }
                .presentationDetents([.fraction(0.6)])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(34)
                .presentationBackground(.clear)
            }
    }

    @ViewBuilder
    var viewContent: some View {
        ScrollViewReader { scrollProxy in
            GeometryReader { outer in
                let resolvedSafeTopInset = max(presentedSafeAreaInsets?.top ?? 0, outer.safeAreaInsets.top)
                let resolvedSafeBottomInset = max(presentedSafeAreaInsets?.bottom ?? 0, outer.safeAreaInsets.bottom)
                let estimatedSheetChromeHeight = resolvedSafeTopInset
                    + UIConstants.Spacing.tiny
                    + 5
                    + UIConstants.Spacing.small
                    + UIConstants.Size.capsuleHeight
                let sheetHeroTopPadding = max(navigationBarHeight, estimatedSheetChromeHeight) + UIConstants.Spacing.large
                let standardHeroTopPadding = UIConstants.Layout.createDeckPinnedToolbarTopInset
                    + UIConstants.Layout.createDeckHeroTopPadding
                let heroTopPadding = fullScreenSheetDismiss != nil ? sheetHeroTopPadding : standardHeroTopPadding
                let sheetDragActivationHeight = fullScreenSheetDismiss != nil
                    ? heroTopPadding + 180
                    : nil

                ZStack {
                    if fullScreenSheetDismiss != nil {
                        Color.clear
                    } else {
                        themeManager.groupedScreenBackground
                            .ignoresSafeArea()
                    }

                    ScrollView {
                        VStack(spacing: 0) {
                            heroHeader(topPadding: heroTopPadding)

                            cardsListContent(using: scrollProxy)
                                .padding(.top, UIConstants.Spacing.large)
                                .padding(.bottom, 132)
                        }
                        .frame(minHeight: outer.size.height, alignment: .top)
                    }
                    .scrollIndicators(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                    .onTapGesture {
                        isTitleFocused = false
                    }

                    successOverlay
                        .zIndex(100)
                }
                .overlay {
                    if fullScreenSheetDismiss != nil {
                        CreateDeckSheetEdgeShadow(
                            topHeight: resolvedSafeTopInset + navigationBarHeight + 28
                        )
                        .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .top) {
                    navigationChrome(
                        containerWidth: outer.size.width,
                        safeTopInset: resolvedSafeTopInset
                    )
                }
                .overlay(alignment: .bottomTrailing) {
                    floatingGenerateAction(bottomInset: resolvedSafeBottomInset)
                }
                .overlay(alignment: .bottom) {
                    draftSelectionBottomBar
                }
                .coordinateSpace(name: kCreateDeckChromeSpace)
                .fullScreenSheetDragActivationHeight(sheetDragActivationHeight)
            }
        }
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        capturePhysicalSafeBottomIfNeeded()
                        updateViewSafeBottom(using: geo.safeAreaInsets.bottom)
                    }
                    .onChange(of: geo.safeAreaInsets.bottom) { _, newValue in
                        updateViewSafeBottom(using: newValue)
                    }
            }
        }
        .environment(scrollState)
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog("Save changes before leaving?", isPresented: $showUnsavedChangesDialog, titleVisibility: .visible) {
            if canSave {
                Button("Save Changes") {
                    handleSave()
                }
            }
            Button("Discard Changes", role: .destructive) {
                discardChangesAndDismiss()
            }
            Button("Keep Editing", role: .cancel) { }
        } message: {
            Text("You have unsaved changes in this deck.")
        }
        .confirmationDialog("Generate Cards with AI", isPresented: $viewModel.showAIPickerOptions, titleVisibility: .visible) {
            Button("Choose Photos") { viewModel.showAIPhotoPicker = true }
            Button("Choose PDF") { viewModel.showAIPDFPicker = true }
            Button("Cancel", role: .cancel) { }
        } message: { Text("Extract text from images or documents.") }
        .confirmationDialog("Choose Card Type", isPresented: $showAddCardTypeDialog, titleVisibility: .visible) {
            addCardTypeButtons
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Pick the type of card you want to add to this deck.")
        }
        .confirmationDialog("Stop AI generation?", isPresented: $viewModel.showAICancelDialog, titleVisibility: .visible) {
            if viewModel.hasGeneratedCardsInCurrentAISession {
                Button("Keep \(viewModel.aiGeneratedCardCount) received cards") {
                    viewModel.cancelAIGeneration(keepingGeneratedCards: true)
                }
                Button("Discard received cards", role: .destructive) {
                    viewModel.cancelAIGeneration(keepingGeneratedCards: false)
                }
            } else {
                Button("Stop generation", role: .destructive) {
                    viewModel.cancelAIGeneration(keepingGeneratedCards: true)
                }
            }
            Button("Continue", role: .cancel) { }
        } message: {
            if viewModel.hasGeneratedCardsInCurrentAISession {
                Text("You can stop now and keep the cards already received, or discard this AI batch completely.")
            } else {
                Text("The current AI generation will stop immediately.")
            }
        }
        .alert(
            "Delete \(viewModel.selectedDraftCardCount) card\(viewModel.selectedDraftCardCount == 1 ? "" : "s")?",
            isPresented: $viewModel.showDeleteSelectedCardsConfirmation
        ) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                withBottomChromeAnimation {
                    viewModel.deleteSelectedCards()
                }
            }
        } message: {
            Text("This removes the selected draft cards from the editor. Existing deck data changes only after you save.")
        }
        .confirmationDialog(
            "Delete \"\(savedDeckTitle)\"?",
            isPresented: $showDeleteDeckConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Deck", role: .destructive) {
                handleDeleteDeck()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently deletes the deck and all its cards.")
        }
        .fullScreenCover(item: $viewModel.cardEditorDestination) { destination in
            CardEditorView(destination: destination) { content in
                handleCardEditorSave(destination: destination, content: content)
            }
        }
    }
}
