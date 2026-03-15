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

struct CreateDeckView: View {
    // MARK: - Environment
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fullScreenSheetDismiss) private var fullScreenSheetDismiss
    @Environment(\.fullScreenSheetDismissCoordinator) private var fullScreenSheetDismissCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @Environment(NavigationManager.self) private var router

    /// Fetches all available folders to populate the destination picker.
    @Query(sort: \FolderModel.createdAt, order: .reverse) private var folders: [FolderModel]

    // MARK: - State
    @State private var viewModel: CreateDeckViewModel
    @State private var scrollState = CreateDeckScrollState()
    @State private var leadingControlWidth: CGFloat = UIConstants.Size.actionButton
    @State private var trailingControlWidth: CGFloat = (UIConstants.Size.actionButton * 2) + UIConstants.Spacing.small
    @State private var navigationBarHeight: CGFloat = UIConstants.Size.actionButton
    @State private var viewSafeBottom: CGFloat = 0
    @State private var physicalSafeBottom: CGFloat = 0
    @State private var showUnsavedChangesDialog = false
    @State private var allowDismissWithoutConfirmation = false

    /// Tracks the focus state of the deck title text field.
    /// Drives the tab bar visibility rule reactively.
    @FocusState private var isTitleFocused: Bool

    // MARK: - Input
    private let presentedSafeAreaInsets: UIEdgeInsets?

    // MARK: - Computed Properties
    private var accent: Color { ThemeManager.shared.accentColor.color }
    private var canSave: Bool {
        !viewModel.deckTitle.trimmingCharacters(in: .whitespaces).isEmpty && !viewModel.draftCards.isEmpty
    }
    private var collapsedDeckTitle: String {
        viewModel.deckTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var destinationTitle: String {
        viewModel.selectedFolder?.title ?? "Library"
    }
    private var cardCountText: String {
        let count = viewModel.draftCards.count
        return "\(count) card\(count == 1 ? "" : "s")"
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
        if viewModel.hasPausedAIGeneration {
            return "Paused"
        }

        switch viewModel.aiState {
        case .extractingText:
            return "Reading"
        case .generatingCards(_, let foundCount):
            let target = max(viewModel.aiTargetCardCount, 1)
            return foundCount > 0 ? "\(foundCount)/\(target)" : "Generating"
        default:
            return nil
        }
    }
    private var aiToolbarTint: Color {
        if case .extractingText = viewModel.aiState {
            return .orange
        }
        return accent
    }
    private var aiToolbarCountText: String? {
        guard !viewModel.hasPausedAIGeneration else { return nil }

        switch viewModel.aiState {
        case .generatingCards(_, let foundCount):
            guard foundCount > 0 else { return nil }
            return "\(foundCount)/\(max(viewModel.aiTargetCardCount, 1))"
        default:
            return nil
        }
    }
    private var tabBarOffset: CGFloat {
        max(0, viewSafeBottom - physicalSafeBottom)
    }
    private var shouldShowFloatingGenerate: Bool {
        scrollState.pillVisible
            && !viewModel.draftCards.isEmpty
            && !isTitleFocused
            && viewModel.aiSheetDestination == nil
            && !viewModel.showSuccessOverlay
    }
    private var shouldShowCollapsedTitle: Bool {
        scrollState.pillVisible && !viewModel.draftCards.isEmpty && !collapsedDeckTitle.isEmpty
    }
    private var canUseInteractiveDismiss: Bool {
        fullScreenSheetDismiss != nil
            && viewModel.aiSheetDestination == nil
            && !viewModel.showSuccessOverlay
            && !isTitleFocused
    }

    /// Contextual rule for tab bar visibility.
    ///
    /// Forces the tab bar to hide only while the keyboard is active.
    /// Materialization (card reveal animation) intentionally leaves the bar visible.
    private var tabRule: TabBarVisibilityRule {
        if isTitleFocused || viewModel.aiSheetDestination != nil {
            return .hidden
        }
        return .implicit
    }

    // MARK: - Initialization
    init(deckToEdit: DeckModel? = nil, safeAreaInsets: UIEdgeInsets? = nil) {
        self.presentedSafeAreaInsets = safeAreaInsets
        _viewModel = State(initialValue: CreateDeckViewModel(deckToEdit: deckToEdit))
    }

    var body: some View {
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
            .photosPicker(isPresented: $viewModel.showAIPhotoPicker, selection: $viewModel.selectedAIPhotos, matching: .images)
            .fileImporter(isPresented: $viewModel.showAIPDFPicker, allowedContentTypes: [.pdf], allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first { viewModel.pdfWasSelected(url) }
            }
            .onChange(of: viewModel.aiSheetDestination) { oldValue, newValue in
                if oldValue != nil, newValue == nil {
                    viewModel.handleAISheetDismissed()
                }
            }
            .swipeBack(enabled: canUseInteractiveDismiss) {
                requestDismiss()
            }
            .fullScreenSheetDragActivationHeight(
                fullScreenSheetDismiss != nil ? navigationBarHeight : nil
            )
            .onAppear {
                fullScreenSheetDismissCoordinator?.shouldAllowDismiss = {
                    attemptInteractiveDismissValidation()
                }
            }
            .onDisappear {
                if fullScreenSheetDismissCoordinator?.shouldAllowDismiss != nil {
                    fullScreenSheetDismissCoordinator?.shouldAllowDismiss = nil
                }
                guard viewModel.aiSheetDestination == nil,
                      !viewModel.isCreatingNewCard,
                      viewModel.cardToEdit == nil else { return }
                ImageCache.shared.clearCache()
            }
            .customTabBarVisibility(tabRule)
    }

    @ViewBuilder
    private var viewContent: some View {
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

            ZStack {
                if fullScreenSheetDismiss == nil {
                    Color(uiColor: .systemGroupedBackground)
                        .ignoresSafeArea()
                }

                ScrollView {
                    VStack(spacing: 0) {
                        heroHeader(topPadding: heroTopPadding)

                        cardsListContent
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

                if viewModel.showSuccessOverlay {
                    successOverlay.zIndex(100)
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
            .coordinateSpace(name: kCreateDeckChromeSpace)
        }
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        updateBottomSafeArea(using: geo.safeAreaInsets.bottom)
                    }
                    .onChange(of: geo.safeAreaInsets.bottom) { _, newValue in
                        updateBottomSafeArea(using: newValue)
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
        .fullScreenCover(isPresented: $viewModel.isCreatingNewCard) {
            CreateCardView { frontZone, backZone in
                viewModel.addCard(frontZone: frontZone, backZone: backZone)
            }
        }
        .fullScreenCover(item: $viewModel.cardToEdit) { card in
            CreateCardView(frontZone: card.frontZone, backZone: card.backZone) { f, b in
                viewModel.updateCard(card, frontZone: f, backZone: b)
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
                    .fill(Color.white.opacity(0.2))
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
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.width
                    } action: { newWidth in
                        if abs(leadingControlWidth - newWidth) > 0.5 {
                            leadingControlWidth = newWidth
                        }
                    }

                Spacer(minLength: 0)

                HStack(spacing: UIConstants.Spacing.small) {
                    addCardButton
                    moreActionsButton
                }
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { newWidth in
                    if abs(trailingControlWidth - newWidth) > 0.5 {
                        trailingControlWidth = newWidth
                    }
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
        HStack(alignment: .center, spacing: UIConstants.Spacing.medium) {
            destinationMetadataControl
                .layoutPriority(1)

            Spacer(minLength: 0)

            HStack(spacing: UIConstants.Spacing.small) {
                mockAIActionControl
                generateActionControl
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

    private var destinationMetadataControl: some View {
        Menu {
            Button {
                isTitleFocused = false
                viewModel.selectedFolder = nil
            } label: {
                Label("Library (All Decks)", systemImage: "tray.full")
            }

            if !folders.isEmpty {
                Divider()

                ForEach(folders) { folder in
                    Button {
                        isTitleFocused = false
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

                Text(cardCountText)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
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
        if !viewModel.isGenerating {
            CreateDeckCapsuleButton(
                action: {
                    isTitleFocused = false
                    viewModel.startMockAIGeneration()
                },
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
                    if viewModel.hasPausedAIGeneration {
                        Text(statusText)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    } else {
                        CreateDeckAIStatusIndicator(
                            countText: aiToolbarCountText,
                            tint: aiToolbarTint
                        )
                    }

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
                    viewModel.showAIPickerOptions = true
                },
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

    private var addCardButton: some View {
        CreateDeckChromeButton(
            action: {
                isTitleFocused = false
                viewModel.isCreatingNewCard = true
            },
            accessibilityLabel: "Add card"
        ) {
            CreateDeckChromeButtonLabel(symbol: "plus", tint: accent)
        }
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

    private var moreMenuContents: some View {
        Group {
            Button("Select Cards") { }
                .disabled(true)
            Button("Delete Deck", role: .destructive) { }
                .disabled(true)
        }
    }

    private var moreActionsButton: some View {
        Menu(content: { moreMenuContents }) {
            CreateDeckChromeButtonLabel(symbol: "ellipsis", tint: accent)
                .glassButton(shape: .circle)
        }
            .buttonStyle(.plain)
            .accessibilityLabel("More actions")
    }

    private func updateBottomSafeArea(using viewInset: CGFloat) {
        viewSafeBottom = viewInset
        physicalSafeBottom = UIApplication.shared
            .connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows
            .first(where: { $0.isKeyWindow })?
            .safeAreaInsets.bottom ?? 0
    }

    // MARK: 2. Cards List Content
    var cardsListContent: some View {
        Group {
            if viewModel.hasPausedAIGeneration {
                let progress = min(1.0, Double(viewModel.aiGeneratedCardCount) / Double(max(viewModel.aiTargetCardCount, 1)))
                LazyVStack(spacing: 16) {
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

                    if !existingDraftCardsDuringAIGeneration.isEmpty {
                        ForEach(Array(existingDraftCardsDuringAIGeneration.enumerated()), id: \.element.id) { index, card in
                            draftCardRow(card, index: index + 1)
                        }
                    }

                    aiGenerationCardSlots()
                }
            } else if case .extractingText = viewModel.aiState {
                AIExtractingLoadingView().transition(.asymmetric(insertion: .opacity, removal: .opacity))
            } else if case .generatingCards(let progress, let foundCount) = viewModel.aiState {
                LazyVStack(spacing: 16) {
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

                    if !existingDraftCardsDuringAIGeneration.isEmpty {
                        ForEach(Array(existingDraftCardsDuringAIGeneration.enumerated()), id: \.element.id) { index, card in
                            draftCardRow(card, index: index + 1)
                        }
                    }

                    aiGenerationCardSlots()
                }
            } else if viewModel.draftCards.isEmpty {
                emptyStateView.transition(.opacity)
            } else {
                LazyVStack(spacing: 16) {
                    draftCardRows()
                }
            }
        }
            .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
            .animation(
                viewModel.isGenerating ? nil : .spring(response: 0.36, dampingFraction: 0.84),
                value: viewModel.draftCards.map(\.id)
            )
            .animation(.easeInOut(duration: 0.35), value: viewModel.draftCards.isEmpty)
    }

    private var existingDraftCardsDuringAIGeneration: ArraySlice<DraftCard> {
        let cappedBaseCount = min(viewModel.aiGenerationBaseCardCount, viewModel.draftCards.count)
        return viewModel.draftCards.prefix(cappedBaseCount)
    }

    private var generatedDraftCardsDuringAIGeneration: ArraySlice<DraftCard> {
        let cappedBaseCount = min(viewModel.aiGenerationBaseCardCount, viewModel.draftCards.count)
        return viewModel.draftCards.dropFirst(cappedBaseCount)
    }

    @ViewBuilder
    private func aiGenerationCardSlots() -> some View {
        let generatedCards = Array(generatedDraftCardsDuringAIGeneration)
        let baseCount = existingDraftCardsDuringAIGeneration.count
        let slotCount = max(viewModel.aiTargetCardCount, generatedCards.count)

        ForEach(0..<slotCount, id: \.self) { slotIndex in
            let card = slotIndex < generatedCards.count ? generatedCards[slotIndex] : nil
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
                    draftCardRow(card, index: baseCount + slotIndex + 1, appliesTransition: false)
                }
            }
        }
    }

    @ViewBuilder
    private func draftCardRows() -> some View {
        ForEach(Array(viewModel.draftCards.enumerated()), id: \.element.id) { index, card in
            draftCardRow(card, index: index + 1)
        }
    }

    private func draftCardRow(
        _ card: DraftCard,
        index: Int,
        appliesTransition: Bool = true
    ) -> some View {
        DetailedCardRowView(
            card: card,
            index: index,
            fixedHeight: appliesTransition ? nil : UIConstants.Size.draftCardRowHeight
        )
            .contentShape(Rectangle())
            .onTapGesture {
                isTitleFocused = false
                viewModel.cardToEdit = card
            }
            .contextMenu {
                Button { viewModel.cardToEdit = card } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        viewModel.deleteCard(card)
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .transition(
                appliesTransition
                    ? .asymmetric(
                        insertion: .move(edge: .bottom)
                            .combined(with: .opacity)
                            .combined(with: .scale(scale: 0.96)),
                        removal: .scale(scale: 0.92).combined(with: .opacity)
                    )
                    : .identity
            )
    }

    var emptyStateView: some View {
        VStack(spacing: 14) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No cards yet")
                .font(.headline)
                .foregroundStyle(.primary)
            Text("Tap + to add your first card manually, or use Auto AI to generate them instantly.")
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
            viewModel.isCreatingNewCard = true
        }
    }

    var successOverlay: some View {
        ZStack {
            Color.clear.background(.ultraThinMaterial).ignoresSafeArea()
            VStack {
                Spacer(minLength: 60)
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce, value: viewModel.showSuccessOverlay)
                    Text("Deck Saved!")
                        .font(.title2.weight(.bold))
                    Text("\(viewModel.draftCards.count) card\(viewModel.draftCards.count == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                    .padding(.vertical, 32)
                    .padding(.horizontal, 48)
                    .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color(uiColor: .systemBackground))
                        .shadow(color: .black.opacity(0.12), radius: 30, y: 15)
                )
                    .scaleEffect(viewModel.showSuccessOverlay ? 1 : 0.7, anchor: .top)
                    .opacity(viewModel.showSuccessOverlay ? 1 : 0)
                    .offset(y: viewModel.showSuccessOverlay ? 0 : -80)
                    .animation(.spring(response: 0.7, dampingFraction: 0.8), value: viewModel.showSuccessOverlay)
                Spacer()
            }
        }
            .transition(.opacity)
            .allowsHitTesting(false)
    }

    private func handleSave() {
        isTitleFocused = false
        allowDismissWithoutConfirmation = true
        let didStartDismissFlow = viewModel.saveDeck(
            context: context,
            router: router,
            dismissAction: dismissPresentation
        )
        if !didStartDismissFlow {
            allowDismissWithoutConfirmation = false
        }
    }

    private func requestDismiss() {
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
}

// MARK: - Create Deck Sheet Background

struct CreateDeckSheetBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if colorScheme == .dark {
                Color.black
            } else {
                Color(uiColor: .systemGroupedBackground)
            }

            LinearGradient(
                stops: [
                    .init(color: Color(white: colorScheme == .dark ? 0.08 : 0.76), location: 0.00),
                    .init(color: Color(white: colorScheme == .dark ? 0.08 : 0.76), location: 0.05),
                    .init(color: .clear, location: 0.24)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
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
            label()
                .frame(width: UIConstants.Size.actionButton, height: UIConstants.Size.actionButton)
                .glassButton(shape: .circle)
        }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.55)
            .accessibilityLabel(accessibilityLabel)
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
                    .contentTransition(.numericText())
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
