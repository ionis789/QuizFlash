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

private let kCreateDeckChromeSpace = "CreateDeckChromeSpace"

private struct CreateDeckWorkspaceSeedSignature: Equatable {
    let sourceDeckID: PersistentIdentifier
    let destination: DeckCardConversionDestinationOption
    let liveDeckID: PersistentIdentifier?
}

struct CreateDeckView: View {
    // MARK: - Environment
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fullScreenSheetDismiss) private var fullScreenSheetDismiss
    @Environment(\.fullScreenSheetDismissCoordinator) private var fullScreenSheetDismissCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @Environment(NavigationManager.self) private var router
    @Environment(AIWorkspaceCoordinator.self) private var aiWorkspaceCoordinator
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager

    /// Fetches all available folders to populate the destination picker.
    @Query(sort: \FolderModel.createdAt, order: .reverse) private var folders: [FolderModel]
    @Query(sort: \DeckModel.editedAt, order: .reverse) private var sourceDecks: [DeckModel]

    // MARK: - State
    @State private var viewModel: CreateDeckViewModel
    @State private var scrollState = CreateDeckScrollState()
    @State private var derivedDeckState = CreateDeckDerivedState.empty
    @State private var navigationBarHeight: CGFloat = UIConstants.Size.actionButton
    @State private var viewSafeBottom: CGFloat = 0
    @State private var physicalSafeBottom: CGFloat = 0
    @State private var showUnsavedChangesDialog = false
    @State private var showDeleteDeckConfirmation = false
    @State private var showAddCardTypeDialog = false
    @State private var allowDismissWithoutConfirmation = false
    @State private var hasCapturedPhysicalSafeBottom = false
    @State private var isHistoricalCardsCollapsed = true
    @State private var hasSeededWorkspaceEditorState = false
    @State private var workspaceSeedSignature: CreateDeckWorkspaceSeedSignature?

    /// Tracks the focus state of the deck title text field.
    /// Drives the tab bar visibility rule reactively.
    @FocusState private var isTitleFocused: Bool

    // MARK: - Input
    private let presentedSafeAreaInsets: UIEdgeInsets?
    private let isAIWorkspaceHost: Bool

    // MARK: - Computed Properties
    private var accent: Color { ThemeManager.shared.accentColor.color }
    private var canSave: Bool {
        let hasTitle = !viewModel.deckTitle.trimmingCharacters(in: .whitespaces).isEmpty
        if viewModel.isEditingExistingDeck {
            return hasTitle && viewModel.hasUnsavedChanges
        }
        return hasTitle && !viewModel.draftCards.isEmpty
    }
    private var collapsedDeckTitle: String {
        if let workspaceTitle = conversionWorkspaceContext?.displayTitle,
           !workspaceTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return workspaceTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return viewModel.deckTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var destinationTitle: String {
        viewModel.selectedFolder?.title ?? "Library"
    }
    private var draftDeckContentSummary: DraftDeckContentSummary {
        derivedDeckState.contentSummary
    }

    private var draftDeckReadinessSummary: DeckReadinessSummary {
        derivedDeckState.readinessSummary
    }
    private var draftReadinessRecommendedTargets: [CardKind] {
        draftDeckReadinessSummary.recommendedConversions.map(\.targetKind)
    }
    private var aiToolbarStatusText: String? {
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
    private var aiVisualStatusText: String? {
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
    private var aiToolbarTint: Color {
        if case .extractingText = viewModel.aiState {
            return .orange
        }
        return accent
    }
    private var successOverlayMaxWidth: CGFloat {
        min(UIScreen.main.bounds.width - (UIConstants.Layout.screenEdgeInset * 2), 320)
    }
    private var savedDeckTitle: String {
        let overlayTitle = viewModel.successOverlayDeckTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !overlayTitle.isEmpty {
            return overlayTitle
        }
        let trimmedTitle = viewModel.deckTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? "Untitled Deck" : trimmedTitle
    }
    private var successOverlayTopPadding: CGFloat {
        navigationBarHeight + (fullScreenSheetDismiss == nil ? UIConstants.Spacing.large : UIConstants.Spacing.extraLarge)
    }
    private var successOverlayAnimation: Animation {
        .smooth(duration: UIConstants.Animation.medium, extraBounce: 0)
    }
    private var aiToolbarCountText: String? {
        switch viewModel.aiState {
        case .generatingCards(_, let foundCount):
            guard foundCount > 0 else { return nil }
            return "\(foundCount)/\(max(viewModel.aiTargetCardCount, 1))"
        default:
            guard viewModel.hasPausedAIGeneration, viewModel.aiGeneratedCardCount > 0 else { return nil }
            return "\(viewModel.aiGeneratedCardCount)/\(max(viewModel.aiTargetCardCount, 1))"
        }
    }
    private var conversionWorkspaceContext: AIWorkspaceDeckContext? {
        guard isAIWorkspaceHost else { return nil }
        return aiWorkspaceCoordinator.workspaceDeckContext
    }
    private var isShowingConversionWorkspace: Bool { conversionWorkspaceContext != nil }
    private var isShowingConversionConfiguration: Bool {
        isAIWorkspaceHost && aiWorkspaceCoordinator.conversionSheetToken != nil && aiWorkspaceCoordinator.conversionSeed != nil
    }
    private var tabBarOffset: CGFloat {
        max(0, viewSafeBottom - physicalSafeBottom)
    }
    private var canStartLocalGeneration: Bool {
        !hasUnifiedAISession
            && (!isAIWorkspaceHost || !aiWorkspaceCoordinator.hasBlockingJob || aiWorkspaceCoordinator.generationStatus != nil)
    }
    private var shouldShowFloatingGenerate: Bool {
        scrollState.pillVisible
            && !viewModel.draftCards.isEmpty
            && !viewModel.isSelectingCards
            && !isTitleFocused
            && viewModel.aiSheetDestination == nil
            && !viewModel.showSuccessOverlay
            && !hasUnifiedAISession
            && !isShowingConversionConfiguration
    }
    private var shouldShowCollapsedTitle: Bool {
        scrollState.pillVisible && !viewModel.draftCards.isEmpty && !collapsedDeckTitle.isEmpty
    }
    private var canUseInteractiveDismiss: Bool {
        fullScreenSheetDismiss != nil
            && viewModel.aiSheetDestination == nil
            && !viewModel.showSuccessOverlay
            && !isTitleFocused
            && !hasUnifiedAISession
            && !isShowingConversionConfiguration
    }
    private var swipeBackEnabled: Bool {
        fullScreenSheetDismiss != nil ? canUseInteractiveDismiss : true
    }
    private var swipeBackAttachment: SwipeBackAttachment {
        fullScreenSheetDismiss != nil ? .localHost : .window
    }

    /// Contextual rule for tab bar visibility.
    ///
    /// Forces the tab bar to hide only while the keyboard is active.
    /// Materialization (card reveal animation) intentionally leaves the bar visible.
    private var tabRule: TabBarVisibilityRule {
        if isTitleFocused || viewModel.aiSheetDestination != nil || viewModel.isSelectingCards || isShowingConversionConfiguration {
            return .hidden
        }
        return .implicit
    }

    private var canOpenConversionMenu: Bool {
        !sourceDecks.isEmpty
            && !viewModel.isGenerating
            && (!isAIWorkspaceHost || !aiWorkspaceCoordinator.hasBlockingJob || isShowingConversionConfiguration || isShowingConversionWorkspace)
    }
    private var hasActiveGenerationRuntime: Bool {
        if case .extractingText = viewModel.aiState { return true }
        if case .generatingCards = viewModel.aiState { return true }
        return viewModel.hasPausedAIGeneration
    }

    private var hasActiveConversionRuntime: Bool {
        aiWorkspaceCoordinator.conversionProgress != nil || aiWorkspaceCoordinator.canResumeConversion
    }

    private var hasUnifiedAISession: Bool {
        hasActiveGenerationRuntime
            || hasActiveConversionRuntime
            || viewModel.hasAISessionDraftCards
            || isShowingConversionWorkspace
    }

    private var displayedDraftCards: [DraftCard] {
        if hasUnifiedAISession {
            return sortDraftCards(viewModel.sessionDraftCards)
        }
        return sortDraftCards(viewModel.draftCards)
    }

    private var displayedDraftRowsBeforeAISlots: [DraftCard] {
        guard hasUnifiedAISession else {
            return displayedDraftCards
        }
        guard hasActiveGenerationRuntime || hasActiveConversionRuntime else {
            return displayedDraftCards
        }
        return displayedDraftCards.filter { !viewModel.aiSessionDraftCardIDs.contains($0.id) }
    }

    private var displayedHistoricalDraftCards: [DraftCard] {
        guard hasUnifiedAISession, !isHistoricalCardsCollapsed else { return [] }
        return sortDraftCards(viewModel.baseDraftCards)
    }

    private var sortedAISessionDraftCards: [DraftCard] {
        sortDraftCards(viewModel.aiSessionDraftCards)
    }

    private var canToggleHistoricalSessionCards: Bool {
        hasUnifiedAISession && !viewModel.baseDraftCards.isEmpty
    }

    private var hiddenSessionCardsCount: Int {
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

    private var conversionStateSyncedContent: some View {
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

    private var generationStateSyncedContent: some View {
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

    private var appearanceBoundContent: some View {
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

    private var pickerBoundContent: some View {
        generationSheetContent
            .photosPicker(isPresented: $viewModel.showAIPhotoPicker, selection: $viewModel.selectedAIPhotos, matching: .images)
            .fileImporter(isPresented: $viewModel.showAIPDFPicker, allowedContentTypes: [.pdf], allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first { viewModel.pdfWasSelected(url) }
            }
    }

    private var generationSheetContent: some View {
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
    }

    @ViewBuilder
    private var viewContent: some View {
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
                    conversionConfigurationOverlay
                        .zIndex(140)
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

// MARK: - Subviews
private extension CreateDeckView {

    // MARK: 1. Header Chrome
    func heroHeader(topPadding: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.large) {
            TextField("Untitled Deck", text: $viewModel.deckTitle, axis: .vertical)
                .font(.system(size: 42, weight: .heavy, design: .rounded))
                .textFieldStyle(.plain)
                .foregroundStyle(.primary)
                .lineLimit(1...2)
                .layoutPriority(1)
                .focused($isTitleFocused)
                .submitLabel(.done)
                .onSubmit { isTitleFocused = false }

            headerMetadataRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, UIConstants.Layout.heroScreenEdgeInset)
        .padding(.top, topPadding)
        .padding(.bottom, UIConstants.Spacing.extraLarge)
    }

    @ViewBuilder
    private func navigationChrome(
        containerWidth: CGFloat,
        safeTopInset: CGFloat
    ) -> some View {
        let horizontalInset = UIConstants.Layout.compactScreenEdgeInset

        if fullScreenSheetDismiss != nil {
            VStack(spacing: UIConstants.Spacing.small) {
                Capsule()
                    .fill(Color.white.opacity(0.22))
                    .frame(width: 56, height: 5)
                    .accessibilityHidden(true)

                navigationBarContent(containerWidth: containerWidth)
            }
            .padding(.top, safeTopInset + UIConstants.Spacing.tiny)
            .padding(.horizontal, horizontalInset)
            .background(navigationBarHeightReader)
        } else {
            navigationBarContent(containerWidth: containerWidth)
                .topNavigationChrome(horizontalInset: horizontalInset)
                .background(navigationBarHeightReader)
        }
    }

    private func navigationBarContent(containerWidth: CGFloat) -> some View {
        let horizontalInset = UIConstants.Layout.compactScreenEdgeInset
        let availableChromeWidth = max(0, containerWidth - (horizontalInset * 2))
        let leadingControlWidth = UIConstants.Size.actionButton
        let trailingControlWidth = (UIConstants.Size.actionButton * 2) + UIConstants.Spacing.small
        let sideClearance = max(leadingControlWidth, trailingControlWidth)
        let maxTitleWidth = max(
            UIConstants.Size.buttonHeight,
            availableChromeWidth - (sideClearance * 2) - (UIConstants.Spacing.small * 2)
        )

        return ZStack(alignment: .center) {
            CreateDeckCollapsedTitlePill(
                title: collapsedDeckTitle,
                maxWidth: maxTitleWidth,
                isVisible: shouldShowCollapsedTitle
            )
                .allowsHitTesting(false)

            HStack(alignment: .center, spacing: UIConstants.Spacing.medium) {
                doneButton

                Spacer(minLength: 0)

                HStack(spacing: UIConstants.Spacing.small) {
                    addCardButton
                    moreActionsButton
                }
            }
        }
    }

    private var navigationBarHeightReader: some View {
        Color.clear
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { newHeight in
                if abs(navigationBarHeight - newHeight) > 0.5 {
                    navigationBarHeight = newHeight
                }
            }
    }

    private var headerMetadataRow: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            HStack(alignment: .center, spacing: UIConstants.Spacing.medium) {
                destinationMetadataControl
                .layoutPriority(1)

                Spacer(minLength: 0)

                HStack(spacing: UIConstants.Spacing.small) {
                    mockAIActionControl
                    generateActionControl
                    convertActionControl
                }
                .opacity(shouldShowInlineHeaderActions ? 1 : 0)
                .allowsHitTesting(shouldShowInlineHeaderActions)
                .accessibilityHidden(!shouldShowInlineHeaderActions)
            }

            if !viewModel.draftCards.isEmpty {
                headerStatsStrip
                if !isShowingConversionWorkspace && !draftReadinessRecommendedTargets.isEmpty {
                    draftReadinessMenuStrip
                }
            }
        }
        .background {
            Color.clear
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.frame(in: .named(kCreateDeckChromeSpace)).maxY
                } action: { maxY in
                    let isAbove = maxY < 0
                    if scrollState.pillVisible != isAbove {
                        scrollState.pillVisible = isAbove
                    }
                }
        }
    }

    private var shouldShowInlineHeaderActions: Bool {
        !hasUnifiedAISession
            && !viewModel.isSelectingCards
            && !shouldShowFloatingGenerate
            && !isShowingConversionConfiguration
    }

    private var destinationMetadataControl: some View {
        Menu {
            Button {
                isTitleFocused = false
                exitDraftSelectionModeForExternalAction()
                viewModel.selectedFolder = nil
            } label: {
                Label("Library (All Decks)", systemImage: "tray.full")
            }

            if !folders.isEmpty {
                Divider()

                ForEach(folders) { folder in
                    Button {
                        isTitleFocused = false
                        exitDraftSelectionModeForExternalAction()
                        viewModel.selectedFolder = folder
                    } label: {
                        Label(folder.title, systemImage: "folder")
                    }
                }
            }
        } label: {
            HStack(alignment: .center, spacing: UIConstants.Spacing.small) {
                Text(destinationTitle)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Image(systemName: "chevron.down.compact")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(viewModel.selectedFolder == nil ? "Choose destination folder, currently Library" : "Choose destination folder, currently \(viewModel.selectedFolder?.title ?? "Library")")
    }

    private var headerStatsStrip: some View {
        let summary = draftDeckContentSummary
        let readinessSummary = draftDeckReadinessSummary

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: UIConstants.Spacing.small) {
                CreateDeckHeaderStatChip(symbol: "rectangle.stack", text: "\(summary.cardCount) cards")
                CreateDeckHeaderStatChip(symbol: "square.grid.2x2", text: "zones(\(summary.filledContentBlockCount))")
                if summary.flashcardCount > 0 {
                    CreateDeckHeaderStatChip(symbol: "rectangle.on.rectangle", text: "\(summary.flashcardCount) flashcards")
                }
                if summary.matchCount > 0 {
                    CreateDeckHeaderStatChip(symbol: "square.grid.2x2.fill", text: "\(summary.matchCount) match")
                }
                if summary.quizCount > 0 {
                    CreateDeckHeaderStatChip(symbol: "checklist", text: "\(summary.quizCount) quiz")
                }
                if summary.writeCount > 0 {
                    CreateDeckHeaderStatChip(symbol: "pencil.line", text: "\(summary.writeCount) write")
                }
                CreateDeckHeaderStatChip(symbol: "textformat", text: "\(summary.characterCount) chars")
                CreateDeckHeaderStatChip(symbol: "photo", text: "\(summary.photoCount) photos")
                CreateDeckHeaderStatChip(symbol: "pencil.and.outline", text: "\(summary.sketchCount) sketches")
                CreateDeckHeaderStatChip(symbol: "hand.tap", text: "\(summary.manualCardCount) manual")
                CreateDeckHeaderStatChip(symbol: "sparkles", text: "\(summary.aiCardCount) AI", tint: accent)
                ForEach(readinessSummary.items) { item in
                    CreateDeckHeaderStatChip(
                        symbol: item.kind.symbol,
                        text: item.title,
                        tint: item.kind.tint
                    )
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private var draftReadinessMenuStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: UIConstants.Spacing.small) {
                ForEach(draftReadinessRecommendedTargets, id: \.self) { targetKind in
                    let recommendedCards = recommendedDraftCards(for: targetKind)
                    if !recommendedCards.isEmpty {
                        Menu {
                            ForEach(recommendedCards, id: \.id) { card in
                                Button {
                                    presentDraftRecommendedConversion(for: card, targetKind: targetKind)
                                } label: {
                                    Label(
                                        "Card \(card.cardNumber > 0 ? card.cardNumber : 0)",
                                        systemImage: targetKind.conversionSystemImage
                                    )
                                }
                            }
                        } label: {
                            CreateDeckHeaderStatChip(
                                symbol: targetKind.conversionSystemImage,
                                text: "Convert \(recommendedCards.count) to \(targetKind.displayTitle)",
                                tint: targetKind == .match ? .orange : accent
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private var doneButton: some View {
        CreateDeckChromeButton(
            action: handleSave,
            isEnabled: canSave,
            accessibilityLabel: "Save deck"
        ) {
            CreateDeckChromeButtonLabel(symbol: "checkmark", tint: canSave ? accent : .secondary)
        }
    }

    @ViewBuilder
    private var mockAIActionControl: some View {
        if !viewModel.isGenerating && !viewModel.isSelectingCards {
            CreateDeckCapsuleButton(
                action: {
                    isTitleFocused = false
                    exitDraftSelectionModeForExternalAction()
                    viewModel.startMockAIGeneration()
                },
                isEnabled: canStartLocalGeneration,
                accessibilityLabel: "Run mock AI generation"
            ) {
                HStack(spacing: UIConstants.Spacing.small) {
                    Image(systemName: "bolt.badge.clock")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Text("Mock AI")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundStyle(.blue)
            }
        }
    }

    @ViewBuilder
    private var generateActionControl: some View {
        if let statusText = aiVisualStatusText {
            CreateDeckCapsuleContainer {
                HStack(spacing: UIConstants.Spacing.small) {
                    CreateDeckAIStatusIndicator(
                        countText: aiToolbarCountText,
                        tint: aiToolbarTint
                    )

                    Button {
                        if viewModel.hasPausedAIGeneration {
                            viewModel.resumePausedAIGeneration()
                        } else {
                            viewModel.pauseAIGeneration()
                        }
                    } label: {
                        Image(systemName: viewModel.hasPausedAIGeneration ? "play.fill" : "pause.fill")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(aiToolbarTint)
                        .frame(width: 24, height: 24)
                        .background(Color(uiColor: .tertiarySystemFill), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(viewModel.hasPausedAIGeneration ? "Resume AI generation" : "Pause AI generation")

                    Button {
                        viewModel.requestAIGenerationCancel()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                            .background(Color(uiColor: .tertiarySystemFill), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel AI generation")
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .accessibilityLabel(aiToolbarStatusText ?? statusText)
        } else {
            CreateDeckCapsuleButton(
                action: {
                    isTitleFocused = false
                    exitDraftSelectionModeForExternalAction()
                    viewModel.showAIPickerOptions = true
                },
                isEnabled: canStartLocalGeneration,
                accessibilityLabel: "Generate cards with AI"
            ) {
                HStack(spacing: UIConstants.Spacing.small) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Text("Generate")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundStyle(accent)
            }
        }
    }

    @ViewBuilder
    private var convertActionControl: some View {
        if !viewModel.isGenerating && !viewModel.isSelectingCards {
            CreateDeckCapsuleButton(
                action: presentConversionConfiguration,
                isEnabled: canOpenConversionMenu,
                accessibilityLabel: "Convert cards with AI"
            ) {
                HStack(spacing: UIConstants.Spacing.small) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Text("Convert")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundStyle(.orange)
            }
        }
    }

    private var addCardButton: some View {
        Menu {
            addCardTypeButtons
        } label: {
            CreateDeckChromeCircleSurface {
                CreateDeckChromeButtonLabel(symbol: "plus", tint: accent)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choose card type")
    }

    private func floatingGenerateAction(bottomInset: CGFloat) -> some View {
        let adjustedBottomInset = max(bottomInset - tabBarOffset, UIConstants.Spacing.standard)

        return generateActionControl
            .padding(.trailing, UIConstants.Layout.compactScreenEdgeInset)
            .padding(
                .bottom,
                adjustedBottomInset
                    + UIConstants.Size.capsuleHeight
                    + UIConstants.Spacing.medium
            )
            .opacity(shouldShowFloatingGenerate ? 1 : 0)
            .offset(y: shouldShowFloatingGenerate ? 0 : 18)
            .scaleEffect(shouldShowFloatingGenerate ? 1 : 0.92, anchor: .trailing)
            .allowsHitTesting(shouldShowFloatingGenerate)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: shouldShowFloatingGenerate)
    }

    @ViewBuilder
    private var conversionConfigurationOverlay: some View {
        if isShowingConversionConfiguration {
            GeometryReader { proxy in
                ZStack {
                    themeManager.groupedScreenBackground
                        .opacity(0.985)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            aiWorkspaceCoordinator.dismissConversionConfiguration()
                        }

                    VStack(spacing: 0) {
                        Spacer(minLength: max(proxy.safeAreaInsets.top, UIConstants.Spacing.huge))

                        AIWorkspaceConversionConfigurationCard(
                            coordinator: aiWorkspaceCoordinator,
                            sourceDecks: sourceDecks,
                            onSelectSourceDeck: { deck in
                                reseedConversion(for: deck)
                            }
                        ) {
                            aiWorkspaceCoordinator.startConversion(context: context)
                        }
                        .padding(.horizontal, UIConstants.Layout.screenEdgeInset)

                        Spacer(minLength: max(proxy.safeAreaInsets.bottom, UIConstants.Spacing.huge))
                    }
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    private var moreMenuContents: some View {
        Group {
            Menu {
                ForEach(CreateDeckSortOrder.allCases) { sortOrder in
                    Button {
                        appPreferences.createDeckSortOrder = sortOrder
                    } label: {
                        if appPreferences.createDeckSortOrder == sortOrder {
                            Label(sortOrder.title, systemImage: "checkmark")
                        } else {
                            Text(sortOrder.title)
                        }
                    }
                }
            } label: {
                Label("Sort Cards", systemImage: "arrow.up.arrow.down")
            }
            .disabled(viewModel.draftCards.count < 2)

            if viewModel.isEditingExistingDeck {
                Button {
                    isTitleFocused = false
                    withAnimation(.easeInOut(duration: UIConstants.Animation.standard)) {
                        viewModel.revertToInitialState()
                    }
                } label: {
                    Label("Undo Changes", systemImage: "arrow.uturn.backward")
                }
                .disabled(!viewModel.canUndoChanges)

                Button(role: .destructive) {
                    isTitleFocused = false
                    showDeleteDeckConfirmation = true
                } label: {
                    Label("Delete Deck", systemImage: "trash")
                }
                .disabled(!viewModel.canDeleteDeck)

                Divider()
            }

            Button(viewModel.isSelectingCards ? "Done Selecting" : "Select Cards") {
                isTitleFocused = false
                withBottomChromeAnimation {
                    if viewModel.isSelectingCards {
                        viewModel.exitCardSelectionMode()
                    } else {
                        viewModel.enterCardSelectionMode()
                    }
                }
            }
            .disabled(!viewModel.isSelectingCards && (viewModel.isGenerating || viewModel.draftCards.isEmpty))
        }
    }

    private var addCardTypeButtons: some View {
        Group {
            Button {
                openCardEditor(for: .flashcard)
            } label: {
                Label("Flashcard", systemImage: "rectangle.on.rectangle")
            }

            Button {
                openCardEditor(for: .quiz)
            } label: {
                Label("Quiz", systemImage: "checklist")
            }

            Button {
                openCardEditor(for: .match)
            } label: {
                Label("Match", systemImage: "square.grid.2x2.fill")
            }

            Button {
                openCardEditor(for: .write)
            } label: {
                Label("Write", systemImage: "pencil.line")
            }
        }
    }

    private var moreActionsButton: some View {
        Menu(content: { moreMenuContents }) {
            CreateDeckChromeCircleSurface {
                CreateDeckChromeButtonLabel(symbol: "ellipsis", tint: accent)
            }
        }
            .buttonStyle(.plain)
            .accessibilityLabel("More actions")
    }

    private func updateViewSafeBottom(using viewInset: CGFloat) {
        guard abs(viewSafeBottom - viewInset) > 0.5 else { return }
        viewSafeBottom = viewInset
    }

    private func capturePhysicalSafeBottomIfNeeded() {
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
    private var draftSelectionBottomBar: some View {
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
    private func mainCardsListContent(using scrollProxy: ScrollViewProxy) -> some View {
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
    private var unifiedRuntimeCard: some View {
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
    private var aiPendingSlots: some View {
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
    private func inlineHistoricalCardsToggle(
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
    private func conversionPendingSlots(
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
    private func draftCardRows(
        _ cards: [DraftCard]
    ) -> some View {
        ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
            draftCardRow(card, index: index + 1)
        }
    }

    @ViewBuilder
    private func draftCardRow(
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

    private func openCardEditor(for kind: CardKind) {
        isTitleFocused = false
        exitDraftSelectionModeForExternalAction()
        showAddCardTypeDialog = false
        viewModel.presentCardEditor(for: kind)
    }

    private func presentConversionConfiguration() {
        isTitleFocused = false
        guard let sourceDeck = preferredConversionSourceDeck else { return }
        reseedConversion(for: sourceDeck)
    }

    private var preferredConversionSourceDeck: DeckModel? {
        if let seed = aiWorkspaceCoordinator.conversionSeed,
           let matchingDeck = sourceDecks.first(where: { $0.persistentModelID == seed.sourceDeckID }) {
            return matchingDeck
        }

        if let deckToEdit = viewModel.deckToEdit {
            return deckToEdit
        }

        return sourceDecks.first
    }

    private func reseedConversion(for sourceDeck: DeckModel) {
        guard let request = makeConversionRequest(for: sourceDeck) else { return }
        exitDraftSelectionModeForExternalAction()
        _ = aiWorkspaceCoordinator.seedConversion(
            request: request,
            sourceDeck: sourceDeck,
            activatesWorkspaceContext: false
        )
        isHistoricalCardsCollapsed = true
    }

    private func makeConversionRequest(for sourceDeck: DeckModel) -> DeckCardConversionRequest? {
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

    private func defaultConversionTargetKind(for sourceKinds: [CardKind]) -> CardKind {
        let sourceKindSet = Set(sourceKinds)
        let orderedTargets: [CardKind] = [.match, .quiz, .write, .flashcard]
        return orderedTargets.first(where: { !sourceKindSet.contains($0) }) ?? .match
    }

    private func recommendedDraftCards(for targetKind: CardKind) -> [DraftCard] {
        derivedDeckState.recommendedCards[targetKind] ?? []
    }

    private func presentDraftRecommendedConversion(for card: DraftCard, targetKind: CardKind) {
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

    private func handleSave() {
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

    private func handleDeleteDeck() {
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

    private func handleCardEditorSave(destination: CardEditorDestination, content: DraftCardContent) {
        switch destination {
        case .create, .createFromDraft:
            viewModel.addCard(content: content)
        case .edit(let draftCard):
            viewModel.updateCard(draftCard, content: content)
        }

        viewModel.dismissCardEditor()
    }

    private func requestDismiss() {
        exitDraftSelectionModeForExternalAction()
        guard attemptInteractiveDismissValidation() else { return }
        allowDismissWithoutConfirmation = true
        dismissPresentation()
    }

    private func attemptInteractiveDismissValidation() -> Bool {
        guard !allowDismissWithoutConfirmation else { return true }
        guard viewModel.hasUnsavedChanges else { return true }
        Task { @MainActor in
            showUnsavedChangesDialog = true
        }
        return false
    }

    private func discardChangesAndDismiss() {
        allowDismissWithoutConfirmation = true
        dismissPresentation()
    }

    private func dismissPresentation() {
        if let fullScreenSheetDismiss {
            fullScreenSheetDismiss()
        } else {
            dismiss()
        }
    }

    private func syncAIWorkspaceGenerationState() {
        guard isAIWorkspaceHost else { return }
        aiWorkspaceCoordinator.syncGenerationState(
            aiState: viewModel.aiState,
            hasPausedGeneration: viewModel.hasPausedAIGeneration,
            generatedCardCount: viewModel.aiGeneratedCardCount,
            targetCardCount: viewModel.aiTargetCardCount,
            deckTitle: collapsedDeckTitle
        )
    }

    private func refreshDerivedDeckState() {
        derivedDeckState = CreateDeckDerivedState(cards: viewModel.draftCards)
    }

    private func exitDraftSelectionModeForExternalAction() {
        guard viewModel.isSelectingCards else { return }
        withBottomChromeAnimation {
            viewModel.exitCardSelectionMode()
        }
    }

    private func sortDraftCards(_ cards: [DraftCard]) -> [DraftCard] {
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

    private func refreshSessionPresentationState() {
        guard appPreferences.autoCollapseEarlierCardsInAISession else { return }
        if hasUnifiedAISession,
           !viewModel.baseDraftCards.isEmpty,
           !viewModel.sessionDraftCards.isEmpty {
            isHistoricalCardsCollapsed = true
        }
    }

    private func refreshWorkspaceDeckPresentation() {
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

    private func workspaceDraftCard(from card: CardModel) -> DraftCard {
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

private struct CreateDeckDerivedState: Equatable {
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

private struct CreateDeckSheetEdgeShadow: View {
    let topHeight: CGFloat

    @Environment(\.fullScreenSheetDragProgress) private var fullScreenSheetDragProgress

    private var opacity: Double {
        1 - min(fullScreenSheetDragProgress / 0.025, 1.0)
    }

    var body: some View {
        EdgeShadowOverlay(
            topHeight: topHeight,
            bottomHeight: 0,
            kMaxAlphaTop: 0.68,
            kMaxAlphaBottom: 0
        )
        .opacity(opacity)
    }
}

private struct AISourcePreparationOverlay: View {
    let state: AISourcePreparationState
    let accent: Color

    @State private var animatePulse = false

    private var title: String {
        switch state {
        case .photos:
            return "Preparing images"
        case .pdf:
            return "Preparing document"
        }
    }

    private var subtitle: String {
        switch state {
        case .photos(let itemCount):
            return itemCount == 1
                ? "Running OCR and building the AI preview."
                : "Running OCR across \(itemCount) images and building the AI preview."
        case .pdf:
            return "Reading pages, generating thumbnails and checking text quality."
        }
    }

    private var eyebrow: String {
        switch state {
        case .photos(let itemCount):
            return itemCount == 1 ? "1 image selected" : "\(itemCount) images selected"
        case .pdf:
            return "PDF selected"
        }
    }

    private var symbolName: String {
        switch state {
        case .photos:
            return "photo.on.rectangle.angled"
        case .pdf:
            return "doc.text.viewfinder"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            HStack(alignment: .center, spacing: UIConstants.Spacing.medium) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.14))
                        .frame(width: 46, height: 46)
                        .scaleEffect(animatePulse ? 1.04 : 0.96)

                    Circle()
                        .stroke(accent.opacity(0.28), lineWidth: 1)
                        .frame(width: 46, height: 46)

                    Image(systemName: symbolName)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(eyebrow.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .tracking(0.4)
                        .lineLimit(1)

                    Text(title)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Spacer(minLength: UIConstants.Spacing.small)

                AIPreparationDots(tint: accent)
            }

            Text(subtitle)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            AIPreparationIndeterminateBar(tint: accent)
        }
        .padding(20)
        .frame(maxWidth: 360, alignment: .leading)
        .widgetStyle(cornerRadius: 30)
        .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                animatePulse = true
            }
        }
    }
}

private struct AIPreparationDots: View {
    let tint: Color

    @State private var activeIndex = 0

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(tint.opacity(activeIndex == index ? 0.95 : 0.28))
                    .frame(width: activeIndex == index ? 7 : 6, height: activeIndex == index ? 7 : 6)
                    .offset(y: activeIndex == index ? -1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: activeIndex)
            }
        }
        .frame(width: 34, height: 18)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(320))
                activeIndex = (activeIndex + 1) % 3
            }
        }
    }
}

private struct AIPreparationIndeterminateBar: View {
    let tint: Color

    @State private var animateIndicator = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(uiColor: .tertiarySystemFill))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.1),
                                tint.opacity(0.75),
                                Color.white.opacity(0.16)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(48, proxy.size.width * 0.28))
                    .offset(x: animateIndicator ? proxy.size.width * 0.72 : 0)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: animateIndicator)
            }
        }
        .frame(height: 6)
        .onAppear { animateIndicator = true }
    }
}

// MARK: - Create Deck Sheet Background

struct CreateDeckSheetBackground: View {
    var body: some View {
        StandardSheetTopStripBackground()
            .ignoresSafeArea()
    }
}

private struct CreateDeckSelectionBottomBar: View {
    let selectedCount: Int
    let allSelected: Bool
    let onDone: () -> Void
    let onToggleSelectAll: () -> Void
    let onDelete: () -> Void

    private var hasSelection: Bool {
        selectedCount > 0
    }

    private var selectionSummary: String {
        if selectedCount == 0 {
            return "Tap cards"
        }
        return selectedCount == 1 ? "1 selected" : "\(selectedCount) selected"
    }

    private var summaryTint: Color {
        selectedCount == 0 ? .secondary : .primary
    }

    private var accent: Color {
        ThemeManager.shared.accentColor.color
    }

    var body: some View {
        HStack(spacing: UIConstants.Spacing.small) {
            SelectionToolbarCapsuleButton(
                action: onDone,
                accessibilityLabel: "Done selecting draft cards"
            ) {
                Text("Done")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .layoutPriority(1)

            Text(selectionSummary)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(summaryTint)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .monospacedDigit()
                .frame(width: 118, alignment: .leading)

            SelectionToolbarTextButton(
                title: allSelected ? "Clear" : "Select All",
                accessibilityLabel: allSelected ? "Clear all selected cards" : "Select all cards",
                tint: allSelected ? .primary : accent,
                action: onToggleSelectAll
            )

            Spacer(minLength: 0)

            SelectionToolbarIconButton(
                isEnabled: hasSelection,
                accessibilityLabel: "Delete \(selectedCount) selected card\(selectedCount == 1 ? "" : "s")",
                action: onDelete
            ) {
                Image(systemName: "trash")
                    .font(.system(size: UIConstants.Size.selectionToolbarIcon, weight: .semibold))
                    .foregroundStyle(hasSelection ? Color.red : Color.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

private struct CreateDeckHeaderStatChip: View {
    let symbol: String
    let text: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))

            Text(text)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.05), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.05), lineWidth: 0.75)
        }
    }
}

// MARK: - CreateDeckChromeButton

private struct CreateDeckChromeButton<Label: View>: View {
    let action: () -> Void
    var isEnabled: Bool = true
    let accessibilityLabel: String
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            CreateDeckChromeCircleSurface(content: label)
        }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.55)
            .accessibilityLabel(accessibilityLabel)
    }
}

private struct CreateDeckChromeCircleSurface<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(width: UIConstants.Size.actionButton, height: UIConstants.Size.actionButton)
            .glassButton(shape: .circle)
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.75)
            }
            .clipShape(Circle())
            .compositingGroup()
    }
}

private struct CreateDeckCapsuleButton<Label: View>: View {
    let action: () -> Void
    var isEnabled: Bool = true
    let accessibilityLabel: String
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            CreateDeckCapsuleContainer(content: label)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct CreateDeckCapsuleContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, UIConstants.Spacing.standard)
            .frame(minWidth: UIConstants.Size.capsuleHeight)
            .frame(height: UIConstants.Size.capsuleHeight)
            .glassButton(shape: .capsule)
    }
}

private struct CreateDeckAIStatusIndicator: View {
    let countText: String?
    let tint: Color

    var body: some View {
        VStack(spacing: countText == nil ? 0 : 2) {
            if let countText {
                Text(countText)
                    .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.primary)
                    .statusTextMotion(trigger: countText)
                    .transition(
                        .move(edge: .bottom)
                            .combined(with: .opacity)
                            .combined(with: .scale(scale: 0.9, anchor: .bottom))
                    )
            }

            AIGenerationActivityDots(color: tint)
                .frame(minWidth: 22)
        }
        .fixedSize(horizontal: true, vertical: false)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: countText)
    }
}

private struct CreateDeckChromeButtonLabel: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: UIConstants.Size.actionIcon, weight: .bold))
            .fontDesign(.rounded)
            .foregroundStyle(tint)
            .frame(width: UIConstants.Size.actionButton, height: UIConstants.Size.actionButton)
    }
}

private struct CreateDeckCollapsedTitlePill: View {
    let title: String
    let maxWidth: CGFloat
    let isVisible: Bool

    @State private var measuredTextWidth: CGFloat = 0

    private let maximumVisualWidth: CGFloat = 220
    private var hasTitle: Bool { !title.isEmpty }
    private var horizontalPadding: CGFloat { hasTitle ? UIConstants.Spacing.standard : 0 }
    private var resolvedWidth: CGFloat {
        let intrinsicWidth = measuredTextWidth + (horizontalPadding * 2)
        let cappedMaxWidth = min(maxWidth, maximumVisualWidth)
        return min(cappedMaxWidth, max(UIConstants.Size.buttonHeight, intrinsicWidth))
    }

    var body: some View {
        ZStack {
            if hasTitle {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.width
                    } action: { newWidth in
                        if abs(measuredTextWidth - newWidth) > 0.5 {
                            measuredTextWidth = newWidth
                        }
                    }
            }

            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.92)
                .frame(width: max(0, resolvedWidth - (horizontalPadding * 2)))
        }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, UIConstants.Spacing.small)
            .frame(width: resolvedWidth)
            .frame(height: UIConstants.Size.capsuleHeight)
            .glassButton(shape: .capsule)
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible ? 1 : 0.82, anchor: .top)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isVisible)
            .accessibilityLabel(title.isEmpty ? "Untitled Deck" : title)
    }
}

@Observable
private final class CreateDeckScrollState {
    var pillVisible: Bool = false
}
