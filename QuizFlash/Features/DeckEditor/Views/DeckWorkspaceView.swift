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
    @Environment(\.fullScreenSheetDismiss) var fullScreenSheetDismiss
    @Environment(\.fullScreenSheetDismissCoordinator) var fullScreenSheetDismissCoordinator
    @Environment(\.scenePhase) var scenePhase
    @Environment(NavigationManager.self) var router
    @Environment(AIWorkspaceCoordinator.self) var aiWorkspaceCoordinator
    @Environment(AppPreferences.self) var appPreferences
    @Environment(DevelopmentPreferences.self) var developmentPreferences
    @Environment(SubscriptionManager.self) var subscriptionManager
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
    @State var aiAccessAlertMessage = ""
    @State var showAIAccessAlert = false
    @State var isCheckingAIAccess = false

    /// Tracks the focus state of the deck title text field.
    /// Drives the tab bar visibility rule reactively.
    @FocusState var isTitleFocused: Bool

    // MARK: - Input
    let launchAction: DeckWorkspaceLaunchAction?
    let sheetSafeAreaInsets: UIEdgeInsets?
    let onSuccessfulSave: (() -> Void)?

    // MARK: - Computed Properties
    var accent: Color { themeManager.accentColor.color }
    var locale: Locale { appPreferences.resolvedLocale }

    func localized(_ value: String.LocalizationValue) -> String {
        AppLocalization.string(value, locale: locale)
    }

    func localizedFormat(_ value: String.LocalizationValue, _ arguments: CVarArg...) -> String {
        let format = AppLocalization.string(value, locale: locale)
        return String(format: format, locale: locale, arguments: arguments)
    }

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
        viewModel.selectedFolder?.title ?? localized("Library")
    }

    private func resolvedEditorTextSize(for kind: CardKind) -> FlashcardTextSize {
        guard let settings = viewModel.deckToEdit?.playModeSettings else {
            return appPreferences.defaultTextSize
        }

        switch kind {
        case .flashcard:
            return settings.flashcardSettings.textSize
        case .quiz:
            return settings.quizSettings.textSize
        }
    }

    var draftDeckContentSummary: DraftDeckContentSummary {
        derivedDeckState.contentSummary
    }
    var aiToolbarStatusText: String? {
        switch viewModel.aiState {
        case .extractingText:
            return localized("Reading Docs...")
        case .generatingCards(_, let foundCount):
            let target = max(viewModel.aiTargetCardCount, 1)
            return foundCount > 0
                ? "AI \(foundCount)/\(target)"
                : localized("Generating AI...")
        default:
            return nil
        }
    }
    var aiVisualStatusText: String? {
        switch viewModel.aiState {
        case .extractingText:
            return localized("Reading")
        case .generatingCards(_, let foundCount):
            let target = max(viewModel.aiTargetCardCount, 1)
            return foundCount > 0 ? "\(foundCount)/\(target)" : localized("Generating")
        default:
            if viewModel.hasPausedAIGeneration {
                return aiToolbarCountText ?? localized("AI generation paused")
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
        return trimmedTitle.isEmpty ? localized("Untitled Deck") : trimmedTitle
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
        scrollState.pillVisible
            && !viewModel.draftCards.isEmpty
            && !viewModel.isSelectingCards
            && !isTitleFocused
            && viewModel.aiSheetDestination == nil
            && !viewModel.showAIPickerOptions
            && !viewModel.showSuccessOverlay
            && !hasUnifiedAISession
    }
    var shouldShowCollapsedTitle: Bool {
        scrollState.pillVisible && !viewModel.draftCards.isEmpty && !collapsedDeckTitle.isEmpty
    }
    var swipeBackEnabled: Bool {
        viewModel.aiSheetDestination == nil
            && !viewModel.showAIPickerOptions
            && !viewModel.showSuccessOverlay
            && !isTitleFocused
            && !hasUnifiedAISession
    }

    /// Contextual rule for tab bar visibility.
    ///
    /// Forces the tab bar to hide only for workspace-owned states.
    /// Custom AI sheets own tab-bar hiding through `fullScreenSheet` so dismissal can
    /// reveal the bar in sync with the sheet animation instead of waiting for the
    /// presentation binding to be cleared.
    var tabRule: TabBarVisibilityRule {
        if isTitleFocused || viewModel.isSelectingCards {
            return .hidden
        }
        return .implicit
    }

    var hasActiveGenerationRuntime: Bool {
        if case .extractingText = viewModel.aiState { return true }
        if case .generatingCards = viewModel.aiState { return true }
        return viewModel.hasPausedAIGeneration
    }

    var hasUnifiedAISession: Bool {
        hasActiveGenerationRuntime
            || viewModel.hasAISessionDraftCards
    }

    var tracksWorkspaceGenerationStatus: Bool {
        router.activeTab == .create
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
        guard hasActiveGenerationRuntime else {
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
        return []
    }

    // MARK: - Initialization
    init(
        deckToEdit: DeckModel? = nil,
        launchAction: DeckWorkspaceLaunchAction? = nil,
        sheetSafeAreaInsets: UIEdgeInsets? = nil,
        onSuccessfulSave: (() -> Void)? = nil
    ) {
        self.launchAction = launchAction
        self.sheetSafeAreaInsets = sheetSafeAreaInsets
        self.onSuccessfulSave = onSuccessfulSave
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
                fullScreenSheetDismissCoordinator?.shouldAllowDismiss = {
                    attemptInteractiveDismissValidation()
                }
                refreshDerivedDeckState()
                refreshSessionPresentationState()
                syncAIWorkspaceGenerationState()
                performLaunchActionIfNeeded()
            }
            .task {
                await subscriptionManager.refresh()
                syncAIGenerationLimit()
            }
            .onChange(of: viewModel.draftCards) { _, _ in
                refreshDerivedDeckState()
            }
            .onDisappear {
                fullScreenSheetDismissCoordinator?.shouldAllowDismiss = nil
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
            .onChange(of: subscriptionManager.isPremium) { _, _ in
                syncAIGenerationLimit()
            }
            .customTabBarVisibility(tabRule)
            .alert(localized("AI usage"), isPresented: $showAIAccessAlert) {
                Button(localized("OK"), role: .cancel) { }
            } message: {
                Text(aiAccessAlertMessage)
            }
    }

    func syncAIGenerationLimit() {
        viewModel.setMaximumAICardsPerGeneration(subscriptionManager.maxCardsPerGeneration)
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
                isPresented: $viewModel.showAIPickerOptions,
                configuration: .sheet(
                    heightMode: .custom(0.35),
                    dragActivationArea: .fullSurface,
                    showsDragIndicator: false,
                    backgroundReceivesDragProgress: true,
                    showsBackdropBlur: true,
                    showsDefaultTopProgressiveBlur: false,
                    hidesTabBar: true,
                    coversTabBar: false
                )
            ) { safeArea in
                AIGenerationSourcePickerSheetView(
                    safeAreaInsets: safeArea,
                    onPhotos: chooseAIPhotoSourceFromPicker,
                    onPDF: chooseAIPDFSourceFromPicker
                )
            } background: {
                AIGenerationSheetBackground()
            }
            .fullScreenSheet(
                item: $viewModel.aiSheetDestination,
                configuration: .sheet(
                    heightMode: .fullScreen,
                    dragActivationArea: .fixed(132),
                    backgroundReceivesDragProgress: true,
                    showsBackdropBlur: true,
                    showsDefaultTopProgressiveBlur: false,
                    hidesTabBar: true,
                    coversTabBar: true
                )
            ) { _, safeArea in
                AIGenerationSheetView(
                    viewModel: viewModel,
                    safeAreaInsets: safeArea,
                    onPrimaryAction: { completion in
                        Task { @MainActor in
                            completion(await confirmAIGenerationIfAllowed())
                        }
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
                let resolvedSafeTopInset = max(
                    outer.safeAreaInsets.top,
                    sheetSafeAreaInsets?.top ?? 0
                )
                let sheetTopChromeInset = sheetSafeAreaInsets == nil ? 0 : resolvedSafeTopInset
                let resolvedSafeBottomInset = outer.safeAreaInsets.bottom
                let heroTopPadding = sheetTopChromeInset
                    + UIConstants.Layout.createDeckPinnedToolbarTopInset
                    + UIConstants.Layout.createDeckHeroTopPadding
                let structuralTopEdgeShadowHeight = resolvedSafeTopInset + navigationBarHeight

                ZStack {
                    ZStack {
                        themeManager.groupedScreenBackground
                            .ignoresSafeArea()

                        ScrollView {
                            VStack(spacing: 0) {
                                heroHeader(topPadding: heroTopPadding)

                                cardsListContent(using: scrollProxy)
                                    .padding(.top, UIConstants.Spacing.large)
                                    .padding(.bottom, 132)
                            }
                            .tabBarAutoHideOnScroll(enabled: tabRule != .hidden)
                            .frame(minHeight: outer.size.height, alignment: .top)
                        }
                        .scrollIndicators(.hidden)
                        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
                        .scrollDismissesKeyboard(.interactively)
                        .gesture(
                            TapGesture().onEnded {
                                isTitleFocused = false
                                guard viewModel.isSelectingCards else { return }
                                exitDraftSelectionModeForExternalAction()
                            }
                        )
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
                        safeTopInset: sheetTopChromeInset
                    )
                }
                .overlay(alignment: .bottomTrailing) {
                    floatingGenerateAction(bottomInset: resolvedSafeBottomInset)
                }
                .overlay(alignment: .bottom) {
                    draftSelectionBottomBar
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
        .confirmationDialog(localized("Save changes before leaving?"), isPresented: $showUnsavedChangesDialog, titleVisibility: .visible) {
            if canSave {
                Button(localized("Save Changes")) {
                    handleSave()
                }
            }
            Button(localized("Discard Changes"), role: .destructive) {
                discardChangesAndDismiss()
            }
            Button(localized("Keep Editing"), role: .cancel) { }
        } message: {
            Text(localized("You have unsaved changes in this deck."))
        }
        .confirmationDialog(localized("Choose Card Type"), isPresented: $showAddCardTypeDialog, titleVisibility: .visible) {
            addCardTypeButtons
            Button(localized("Cancel"), role: .cancel) { }
        } message: {
            Text(localized("Pick the type of card you want to add to this deck."))
        }
        .confirmationDialog(localized("Stop AI generation?"), isPresented: $viewModel.showAICancelDialog, titleVisibility: .visible) {
            if viewModel.hasGeneratedCardsInCurrentAISession {
                Button(localizedFormat("Keep %d received cards", viewModel.aiGeneratedCardCount)) {
                    viewModel.cancelAIGeneration(keepingGeneratedCards: true)
                }
                Button(localized("Discard received cards"), role: .destructive) {
                    viewModel.cancelAIGeneration(keepingGeneratedCards: false)
                }
            } else {
                Button(localized("Stop generation"), role: .destructive) {
                    viewModel.cancelAIGeneration(keepingGeneratedCards: true)
                }
            }
            Button(localized("Continue"), role: .cancel) { }
        } message: {
            if viewModel.hasGeneratedCardsInCurrentAISession {
                Text(localized("You can stop now and keep the cards already received, or discard this AI batch completely."))
            } else {
                Text(localized("The current AI generation will stop immediately."))
            }
        }
        .alert(
            viewModel.selectedDraftCardCount == 1
                ? localizedFormat("Delete %d card?", viewModel.selectedDraftCardCount)
                : localizedFormat("Delete %d cards?", viewModel.selectedDraftCardCount),
            isPresented: $viewModel.showDeleteSelectedCardsConfirmation
        ) {
            Button(localized("Cancel"), role: .cancel) { }
            Button(localized("Delete"), role: .destructive) {
                withBottomChromeAnimation {
                    viewModel.deleteSelectedCards()
                }
            }
        } message: {
            Text(localized("This removes the selected draft cards from the editor. Existing deck data changes only after you save."))
        }
        .confirmationDialog(
            localizedFormat("Delete \"%@\"?", savedDeckTitle),
            isPresented: $showDeleteDeckConfirmation,
            titleVisibility: .visible
        ) {
            Button(localized("Delete Deck"), role: .destructive) {
                handleDeleteDeck()
            }
            Button(localized("Cancel"), role: .cancel) { }
        } message: {
            Text(localized("This permanently deletes the deck and all its cards."))
        }
        .fullScreenCover(item: $viewModel.cardEditorDestination) { destination in
            CardEditorView(
                destination: destination,
                textSizeOverride: resolvedEditorTextSize(for: destination.kind)
            ) { content in
                handleCardEditorSave(destination: destination, content: content)
            }
        }
        .alert(localized("Save Error"), isPresented: $viewModel.showPersistenceError) {
            Button(localized("OK"), role: .cancel) { }
        } message: {
            Text(viewModel.persistenceErrorMessage)
        }
    }
}
