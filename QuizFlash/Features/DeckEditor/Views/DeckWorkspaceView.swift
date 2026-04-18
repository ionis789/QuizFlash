//
//  DeckWorkspaceView.swift
//  QuizFlash
//
//  Abstract:
//  Primary entry point for creating or editing a deck.
//  Delegates all state and business logic to `DeckWorkspaceViewModel`.
//  Manages only local UI concerns: keyboard focus and tab-bar visibility.
//

import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

let kDeckWorkspaceChromeSpace = "DeckWorkspaceChromeSpace"

enum DeckWorkspaceLaunchAction: Equatable {
    case showAIGenerationOptions
}

struct DeckWorkspaceView: View {
    // MARK: - Environment
    @Environment(\.modelContext) var context
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) var scenePhase
    @Environment(NavigationManager.self) var router
    @Environment(AIWorkspaceCoordinator.self) var aiWorkspaceCoordinator
    @Environment(AppPreferences.self) var appPreferences
    @Environment(ThemeManager.self) var themeManager

    /// Fetches all available folders to populate the destination picker.
    @Query(sort: \FolderModel.createdAt, order: .reverse) var folders: [FolderModel]
    @Query(sort: \DeckModel.editedAt, order: .reverse) var sourceDecks: [DeckModel]

    // MARK: - State
    @State var viewModel: DeckWorkspaceViewModel
    @State var scrollState = DeckWorkspaceScrollState()
    @State var derivedDeckState = DeckWorkspaceDerivedState.empty
    @State var navigationBarHeight: CGFloat = UIConstants.Size.actionButton
    @State var viewSafeBottom: CGFloat = 0
    @State var physicalSafeBottom: CGFloat = 0
    @State var showUnsavedChangesDialog = false
    @State var showDeleteDeckConfirmation = false
    @State var showAddCardTypeDialog = false
    @State var allowDismissWithoutConfirmation = false
    @State var hasCapturedPhysicalSafeBottom = false
    @State var isHistoricalCardsCollapsed = true
    @State var hasHandledLaunchAction = false

    /// Tracks the focus state of the deck title text field.
    /// Drives the tab bar visibility rule reactively.
    @FocusState var isTitleFocused: Bool

    // MARK: - Input
    let launchAction: DeckWorkspaceLaunchAction?

    // MARK: - Computed Properties
    var accent: Color { themeManager.accentColor.color }
    var canSave: Bool {
        let hasTitle = !viewModel.deckTitle.trimmingCharacters(in: .whitespaces).isEmpty
        if viewModel.isEditingExistingDeck {
            return hasTitle && viewModel.hasUnsavedChanges
        }
        return hasTitle && !viewModel.draftCards.isEmpty
    }
    var collapsedDeckTitle: String {
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
        navigationBarHeight + UIConstants.Spacing.large
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
    var tabBarOffset: CGFloat {
        max(0, viewSafeBottom - physicalSafeBottom)
    }
    var canStartLocalGeneration: Bool {
        !hasUnifiedAISession
    }
    var shouldShowFloatingGenerate: Bool {
        !isShowingWorkspaceConvert
            && scrollState.pillVisible
            && !viewModel.draftCards.isEmpty
            && !viewModel.isSelectingCards
            && !isTitleFocused
            && viewModel.aiSheetDestination == nil
            && !viewModel.showSuccessOverlay
            && !hasUnifiedAISession
    }
    var shouldShowCollapsedTitle: Bool {
        scrollState.pillVisible && !viewModel.draftCards.isEmpty && !collapsedDeckTitle.isEmpty
    }
    var swipeBackEnabled: Bool {
        viewModel.aiSheetDestination == nil
            && !viewModel.showSuccessOverlay
            && !isTitleFocused
            && !hasUnifiedAISession
    }

    /// Contextual rule for tab bar visibility.
    ///
    /// Forces the tab bar to hide only while the keyboard is active.
    /// Materialization (card reveal animation) intentionally leaves the bar visible.
    var tabRule: TabBarVisibilityRule {
        if isShowingWorkspaceConvert {
            return .implicit
        }
        if isTitleFocused || viewModel.aiSheetDestination != nil || viewModel.isSelectingCards {
            return .hidden
        }
        return .implicit
    }

    var hasActiveGenerationRuntime: Bool {
        if case .extractingText = viewModel.aiState { return true }
        if case .generatingCards = viewModel.aiState { return true }
        return viewModel.hasPausedAIGeneration
    }

    var activeEditorConversionProgress: DeckCardConversionProgress? {
        guard hostsSourceDeckConversionRuntime else { return nil }
        return aiWorkspaceCoordinator.conversionProgress
    }

    var activeEditorPausedConversionProgress: DeckCardConversionProgress? {
        guard hostsSourceDeckConversionRuntime else { return nil }
        return aiWorkspaceCoordinator.pausedConversionSession?.progress
    }

    var showsInlineConversionSessionCards: Bool {
        hostsSourceDeckConversionRuntime
            && aiWorkspaceCoordinator.workspaceDeckContext?.destination == .sameDeck
            && (activeEditorConversionProgress != nil || activeEditorPausedConversionProgress != nil)
    }

    var hasUnifiedAISession: Bool {
        hasActiveGenerationRuntime
            || showsInlineConversionSessionCards
            || viewModel.hasAISessionDraftCards
    }

    var hostsSourceDeckConversionRuntime: Bool {
        guard aiWorkspaceCoordinator.hasVisibleConversionWorkspaceState else { return false }
        return viewModel.resolvedEditingDeckID == aiWorkspaceCoordinator.workspaceDeckContext?.sourceDeckID
    }

    var tracksWorkspaceGenerationStatus: Bool {
        router.activeTab == .create
    }

    var isShowingWorkspaceConvert: Bool {
        guard viewModel.isEditingExistingDeck,
              let sourceDeckID = aiWorkspaceCoordinator.conversionSeed?.sourceDeckID else {
            return false
        }
        return sourceDeckID == viewModel.resolvedEditingDeckID
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
        guard hasActiveGenerationRuntime || showsInlineConversionSessionCards else {
            return displayedDraftCards
        }
        return displayedDraftCards.filter { !viewModel.aiSessionDraftCardIDs.contains($0.id) }
    }

    var displayedHistoricalDraftCards: [DraftCard] {
        guard hasUnifiedAISession, !isHistoricalCardsCollapsed else { return [] }
        return sortDraftCards(resolvedHistoricalDraftCards)
    }

    var sortedAISessionDraftCards: [DraftCard] {
        sortDraftCards(viewModel.aiSessionDraftCards)
    }

    var canToggleHistoricalSessionCards: Bool {
        hasUnifiedAISession && historicalSessionCardsCount > 0
    }

    var hiddenSessionCardsCount: Int {
        guard hasUnifiedAISession, isHistoricalCardsCollapsed else { return 0 }
        return historicalSessionCardsCount
    }

    var historicalSessionCardsCount: Int {
        resolvedHistoricalDraftCards.count
    }

    var resolvedHistoricalDraftCards: [DraftCard] {
        if !viewModel.baseDraftCards.isEmpty {
            return viewModel.baseDraftCards
        }

        guard showsInlineConversionSessionCards,
              let destinationBaseCardIDs = aiWorkspaceCoordinator.workspaceDeckContext?.destinationBaseCardIDs,
              !destinationBaseCardIDs.isEmpty else {
            return []
        }

        let baselineOriginalIDs = Set(destinationBaseCardIDs)
        return viewModel.draftCards.filter { draft in
            guard let originalCardID = draft.originalCardID else { return false }
            return baselineOriginalIDs.contains(originalCardID)
                && !viewModel.sessionDraftCardIDs.contains(draft.id)
        }
    }

    // MARK: - Initialization
    init(
        deckToEdit: DeckModel? = nil,
        launchAction: DeckWorkspaceLaunchAction? = nil
    ) {
        self.launchAction = launchAction
        _viewModel = State(initialValue: DeckWorkspaceViewModel(deckToEdit: deckToEdit))
    }

    var body: some View {
        generationStateSyncedContent
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
            .onChange(of: aiWorkspaceCoordinator.conversionProgress) { _, _ in
                syncActiveConversionEditorState()
            }
            .onChange(of: aiWorkspaceCoordinator.conversionSummary) { _, _ in
                syncActiveConversionEditorState()
            }
            .onChange(of: aiWorkspaceCoordinator.workspaceDeckContext) { _, _ in
                syncActiveConversionEditorState()
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
                attachment: .window
            ) {
                requestDismiss()
            }
            .onAppear {
                refreshDerivedDeckState()
                refreshSessionPresentationState()
                syncAIWorkspaceGenerationState()
                syncActiveConversionEditorState()
                performLaunchActionIfNeeded()
            }
            .onChange(of: viewModel.draftCards) { _, _ in
                refreshDerivedDeckState()
            }
            .onDisappear {
                if isShowingWorkspaceConvert {
                    aiWorkspaceCoordinator.dismissConversionConfiguration()
                }
                guard viewModel.aiSheetDestination == nil,
                      viewModel.cardEditorDestination == nil else { return }
                ImageCache.shared.clearCache()
            }
            .onChange(of: viewModel.isEditingExistingDeck) { oldValue, newValue in
                guard oldValue,
                      !newValue,
                      router.activeTab == .create,
                      router.createPath.isEmpty,
                      router.createWorkspaceEditingDeckID != nil else { return }
                router.clearCreateWorkspaceEditingContext()
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
                item: $viewModel.aiSheetDestination,
                configuration: .chrome(dragActivationArea: .fixed(180))
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
    }

    @ViewBuilder
    var viewContent: some View {
        ScrollViewReader { scrollProxy in
            GeometryReader { outer in
                let resolvedSafeTopInset = outer.safeAreaInsets.top
                let resolvedSafeBottomInset = outer.safeAreaInsets.bottom
                let heroTopPadding = UIConstants.Layout.createDeckPinnedToolbarTopInset
                    + UIConstants.Layout.createDeckHeroTopPadding
                let structuralTopEdgeShadowHeight = resolvedSafeTopInset + navigationBarHeight

                ZStack {
                    ZStack {
                        themeManager.groupedScreenBackground
                            .ignoresSafeArea()

                        ScrollView {
                            VStack(spacing: 0) {
                                heroHeader(topPadding: heroTopPadding)

                                if isShowingWorkspaceConvert {
                                    DeckConversionEditor(
                                        sourceDecks: sourceDecks,
                                        managesSeedFromDeckList: false,
                                        showsDeckPicker: false,
                                        showsRuntimeSummary: false
                                    )
                                    .padding(.horizontal, UIConstants.Layout.cardListEdgeInset)
                                    .padding(.top, UIConstants.Spacing.small)
                                    .padding(.bottom, 132)
                                } else {
                                    cardsListContent(using: scrollProxy)
                                        .padding(.top, UIConstants.Spacing.large)
                                        .padding(.bottom, 132)
                                }
                            }
                            .tabBarAutoHideOnScroll(enabled: tabRule != .hidden)
                            .frame(minHeight: outer.size.height, alignment: .top)
                        }
                        .scrollIndicators(.hidden)
                        .scrollDismissesKeyboard(.interactively)
                        .onTapGesture {
                            isTitleFocused = false
                        }
                    }
                    .screenTopEdgeShadow(
                        topHeight: structuralTopEdgeShadowHeight,
                        topRevealProgress: shouldShowCollapsedTitle ? 1 : 0,
                        debugScreenID: "deck.workspace",
                        style: .progressiveBlur()
                    )

                    successOverlay
                        .zIndex(100)
                }
                .overlay(alignment: .top) {
                    navigationChrome(
                        containerWidth: outer.size.width,
                        safeTopInset: resolvedSafeTopInset
                    )
                }
                .overlay(alignment: .bottomTrailing) {
                    if !isShowingWorkspaceConvert {
                        floatingGenerateAction(bottomInset: resolvedSafeBottomInset)
                    }
                }
                .overlay(alignment: .bottom) {
                    if isShowingWorkspaceConvert {
                        EmptyView()
                    } else {
                        draftSelectionBottomBar
                    }
                }
                .coordinateSpace(name: kDeckWorkspaceChromeSpace)
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
        .alert("Save Error", isPresented: $viewModel.showPersistenceError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.persistenceErrorMessage)
        }
    }
}
