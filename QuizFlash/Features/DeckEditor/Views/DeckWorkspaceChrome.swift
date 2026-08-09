//
//  DeckWorkspaceChrome.swift
//  QuizFlash
//

import SwiftUI
import SwiftData
import UIKit

// MARK: - Subviews
extension DeckWorkspaceView {
    // MARK: 1. Header Chrome
    func heroHeader(topPadding: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.large) {
            heroTitleControl

            if shouldShowHeaderMetadataRow {
                headerMetadataRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, UIConstants.Layout.heroScreenEdgeInset)
        .padding(.top, topPadding)
        .padding(.bottom, UIConstants.Spacing.extraLarge)
    }

    @ViewBuilder
    private var heroTitleControl: some View {
        if (hasUnifiedAISession || preservesCompletedAIHeroPresentation) && !isTitleFocused {
            generationHeroTitle
        } else {
            editableHeroTitleField
        }
    }

    private var editableHeroTitleField: some View {
        TextField(localized("Untitled Deck"), text: $viewModel.deckTitle, axis: .vertical)
            .font(.system(size: 42, weight: .heavy))
            .textFieldStyle(.plain)
            .foregroundStyle(.primary)
            .lineLimit(1 ... 2)
            .layoutPriority(1)
            .focused($isTitleFocused)
            .submitLabel(.done)
            .onSubmit { isTitleFocused = false }
            .frame(minHeight: heroTitleReservedHeight, alignment: .leading)
            .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .leading)))
            .animation(generationPhaseAnimation, value: heroTitleReservedHeight)
    }

    private var generationHeroTitle: some View {
        let resolvedTitle = collapsedDeckTitle
        let isResolved = !resolvedTitle.isEmpty
        let displayTitle = isResolved ? resolvedTitle : localized("Untitled Deck")

        return ZStack(alignment: .leading) {
            if isResolved {
                Text(displayTitle)
                    .id("resolved-\(displayTitle)")
                    .transition(heroTitleTextTransition(insertsResolvedTitle: true))
            } else {
                Text(displayTitle)
                    .id("pending-title")
                    .transition(heroTitleTextTransition(insertsResolvedTitle: false))
            }
        }
        .font(.system(size: 42, weight: .heavy))
        .foregroundStyle(isResolved ? Color.primary : Color.secondary.opacity(0.68))
        .lineLimit(1 ... 2)
        .layoutPriority(1)
        .frame(maxWidth: .infinity, minHeight: heroTitleReservedHeight, alignment: .leading)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(generationPhaseAnimation) {
                isTitleFocused = true
            }
        }
        .animation(generationPhaseAnimation, value: generationMotionKey)
        .animation(generationPhaseAnimation, value: displayTitle)
    }

    private func heroTitleTextTransition(insertsResolvedTitle: Bool) -> AnyTransition {
        let insertion = AnyTransition.opacity
            .combined(with: .scale(scale: insertsResolvedTitle ? 0.985 : 1.01, anchor: .leading))
        let removal = AnyTransition.opacity
            .combined(with: .scale(scale: insertsResolvedTitle ? 1.01 : 0.985, anchor: .leading))

        return .asymmetric(insertion: insertion, removal: removal)
    }

    @ViewBuilder
    func navigationChrome(
        containerWidth _: CGFloat,
        safeTopInset: CGFloat
    ) -> some View {
        let horizontalInset = UIConstants.Layout.compactScreenEdgeInset

        if safeTopInset > 0 {
            navigationBarContent(horizontalInset: horizontalInset, appliesTopNavigationChrome: false)
                .padding(.horizontal, horizontalInset)
                .padding(.top, safeTopInset + UIConstants.Layout.deckNavigationTopPadding)
        } else {
            navigationBarContent(horizontalInset: horizontalInset, appliesTopNavigationChrome: true)
        }
    }

    func navigationBarContent(horizontalInset: CGFloat, appliesTopNavigationChrome: Bool) -> some View {
        CollapsibleTitleNavigationBar(
            coordinateSpaceName: kDeckWorkspaceChromeSpace,
            horizontalInset: horizontalInset,
            appliesTopNavigationChrome: appliesTopNavigationChrome,
            onHeightChange: { newHeight in
                if abs(navigationBarHeight - newHeight) > 0.5 {
                    navigationBarHeight = newHeight
                }
            }
        ) {
            workspaceLeadingControl
        } center: { maxTitleWidth in
            CreateDeckCollapsedTitlePill(
                title: collapsedDeckTitle,
                maxWidth: maxTitleWidth,
                isVisible: shouldShowCollapsedTitle,
                fallbackTitle: localized("Untitled Deck")
            )
        } trailing: {
            if shouldShowTopAIGenerationControls {
                topAIGenerationControls
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .trailing)),
                            removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .trailing))
                        )
                    )
            } else {
                HStack(spacing: UIConstants.Spacing.small) {
                    addCardButton
                    moreActionsButton
                }
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .trailing)),
                        removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .trailing))
                    )
                )
            }
        }
        .animation(.easeInOut(duration: UIConstants.Animation.standard), value: shouldShowTopAIGenerationControls)
    }

    @ViewBuilder
    private var workspaceLeadingControl: some View {
        if viewModel.isEditingExistingDeck && !viewModel.hasUnsavedChanges {
            dismissWorkspaceButton
        } else {
            doneButton
        }
    }

    private var dismissWorkspaceButton: some View {
        ChromeSoftCircleSymbolButton(
            systemName: "xmark",
            accessibilityLabel: localized("Cancel editing deck"),
            action: {
                isTitleFocused = false
                requestDismiss()
            },
            size: UIConstants.Size.actionButton
        )
    }

    var headerMetadataRow: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            generationMetadataActionRow
                .frame(minHeight: UIConstants.Size.capsuleHeight)
                .animation(.easeInOut(duration: UIConstants.Animation.standard), value: shouldShowGenerationHeaderStatus)
                .animation(generationPhaseAnimation, value: generationCompletionDisplayState)
                .animation(generationPhaseAnimation, value: shouldRevealAIGenerateActions)
                .animation(generationPhaseAnimation, value: viewModel.draftCards.isEmpty)

            if !viewModel.draftCards.isEmpty {
                headerStatsStrip
                    .transition(
                        .asymmetric(
                            insertion: .offset(y: -8).combined(with: .opacity),
                            removal: .opacity
                        )
                    )
            }
        }
        .animation(generationPhaseAnimation, value: viewModel.draftCards.isEmpty)
        .animation(generationPhaseAnimation, value: generationMotionKey)
        .background {
            Color.clear
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.frame(in: .named(kDeckWorkspaceChromeSpace)).maxY
                } action: { maxY in
                    let isAbove = maxY < 0
                    if scrollState.pillVisible != isAbove {
                        scrollState.pillVisible = isAbove
                    }
                }
        }
    }

    var shouldShowHeaderMetadataRow: Bool {
        !viewModel.draftCards.isEmpty
            || shouldShowGenerationHeaderStatus
            || shouldShowMockAIHeaderAction
    }

    var shouldShowGenerationHeaderStatus: Bool {
        viewModel.aiGenerationDisplayPhase != nil || generationCompletionDisplayState != .none
    }

    var shouldShowMockAIHeaderAction: Bool {
        developmentPreferences.deckWorkspaceMockAIEnabled
            && !hasUnifiedAISession
            && !viewModel.isSelectingCards
            && !shouldShowFloatingGenerate
    }

    var shouldShowPrimaryGenerateAction: Bool {
        !hasUnifiedAISession
            && shouldRevealAIGenerateActions
            && !shouldShowFloatingGenerate
    }

    var completionControlShowsGenerateMore: Bool {
        generationCompletionDisplayState == .none
            && shouldShowPrimaryGenerateAction
    }

    var completionControlIsVisible: Bool {
        generationCompletionDisplayState == .done
            || completionControlShowsGenerateMore
    }

    var shouldShowTopAIGenerationControls: Bool {
        viewModel.aiGenerationDisplayPhase != nil
    }

    var heroTitleReservedHeight: CGFloat {
        guard hasUnifiedAISession || preservesCompletedAIHeroPresentation else { return 0 }
        return ceil(UIFont.systemFont(ofSize: 42, weight: .heavy).lineHeight * 2)
    }

    var heroTitleTransitionIdentity: String {
        guard hasActiveGenerationRuntime, !isTitleFocused else { return "manual-title" }
        let title = viewModel.deckTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "ai-title-pending" : "ai-title-resolved"
    }

    var destinationMetadataControl: some View {
        Menu {
            Button {
                isTitleFocused = false
                exitDraftSelectionModeForExternalAction()
                viewModel.selectedFolder = nil
            } label: {
                Label(localized("Library (All Decks)"), systemImage: "tray.full")
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
            HStack(alignment: .center, spacing: UIConstants.Spacing.small + 2) {
                Image(systemName: viewModel.selectedFolder == nil ? "tray.full" : "folder.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(accent)

                VStack(alignment: .leading, spacing: 1) {
//                    Text(localized("Save to"))
//                        .font(.system(size: 11, weight: .heavy))
//                        .foregroundStyle(.secondary)
//                        .textCase(.uppercase)

                    Text(destinationTitle)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Image(systemName: "chevron.down.compact")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.leading, UIConstants.Spacing.small)
            .padding(.trailing, UIConstants.Spacing.tiny)
            .contentShape(Capsule(style: .continuous))
        }
        .quizFlashButtonStyle(.surface, shape: .capsule, size: UIConstants.Size.capsuleHeight)
        .accessibilityLabel(
            viewModel.selectedFolder == nil
                ? localized("Choose destination folder, currently Library")
                : localizedFormat(
                    "Choose destination folder, currently %@",
                    viewModel.selectedFolder?.title ?? localized("Library")
                )
        )
    }

    var headerStatsStrip: some View {
        let summary = draftDeckContentSummary

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: UIConstants.Spacing.small) {
                if summary.cardCount > 0 {
                    CreateDeckHeaderStatChip(symbol: "rectangle.stack.fill", text: localizedFormat("%d cards", summary.cardCount))
                }
                if summary.flashcardCount > 0 {
                    CreateDeckHeaderStatChip(symbol: "rectangle.on.rectangle.angled", text: localizedFormat("%d flashcards", summary.flashcardCount), rotation: Angle(degrees: 90))
                }
                if summary.quizCount > 0 {
                    CreateDeckHeaderStatChip(symbol: "questionmark.square.dashed", text: localizedFormat("%d quiz", summary.quizCount))
                }
                if summary.photoCount > 0 {
                    CreateDeckHeaderStatChip(symbol: "photo", text: localizedFormat("%d photos", summary.photoCount))
                }
                if summary.sketchCount > 0 {
                    CreateDeckHeaderStatChip(symbol: "pencil.and.outline", text: localizedFormat("%d sketches", summary.sketchCount))
                }
                if summary.aiCardCount > 0 {
                    CreateDeckHeaderStatChip(symbol: "sparkles", text: localizedFormat("%d AI", summary.aiCardCount), tint: accent)
                }
                if summary.manualCardCount > 0 {
                    CreateDeckHeaderStatChip(symbol: "hand.tap", text: localizedFormat("%d manual", summary.manualCardCount))
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    var doneButton: some View {
        CreateDeckChromeButton(
            action: handleSave,
            isEnabled: canSave,
            chrome: .surface,
            accessibilityLabel: localized("Save deck")
        ) {
            CreateDeckChromeButtonLabel(
                symbol: "checkmark",
                tint: canSave ? themeManager.successPrimary : .secondary
            )
            .animation(generationPhaseAnimation, value: generationMotionKey)
        }
    }

    @ViewBuilder
    var generationMetadataActionRow: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: UIConstants.Spacing.medium) {
                generationHeaderStatusControl
                Spacer(minLength: 0)
            }
            .opacity(shouldShowGenerationProgressStatus ? 1 : 0)
            .scaleEffect(shouldShowGenerationProgressStatus ? 1 : 0.985, anchor: .leading)
            .allowsHitTesting(false)
            .animation(.easeOut(duration: UIConstants.Animation.standard), value: shouldShowGenerationProgressStatus)

            if !viewModel.draftCards.isEmpty {
                HStack(spacing: UIConstants.Spacing.medium) {
                    if completionControlShowsGenerateMore {
                        Spacer(minLength: 0)

                        if shouldShowMockAIHeaderAction {
                            mockAIActionControl
                        }
                    }

                    CompletionGenerateMoreControl(
                        showsGenerateMore: completionControlShowsGenerateMore,
                        isVisible: completionControlIsVisible,
                        isEnabled: canStartLocalGeneration,
                        doneLabel: localized("Done"),
                        generateMoreLabel: localized("Generate more"),
                        accessibilityLabel: localized("Generate cards with AI"),
                        action: {
                            presentAIGenerationSourcePicker()
                        }
                    )

                    if !completionControlShowsGenerateMore {
                        Spacer(minLength: 0)
                    }
                }
                .animation(generationPhaseAnimation, value: generationCompletionDisplayState)
                .animation(generationPhaseAnimation, value: shouldShowPrimaryGenerateAction)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    var mockAIActionControl: some View {
        if !viewModel.isGenerating && !viewModel.isSelectingCards {
            CreateDeckCapsuleButton(
                action: {
                    isTitleFocused = false
                    exitDraftSelectionModeForExternalAction()
                    viewModel.startMockAIGeneration()
                },
                isEnabled: canStartLocalGeneration,
                accessibilityLabel: localized("Run mock AI generation")
            ) {
                HStack(spacing: UIConstants.Spacing.small) {
                    Image(systemName: "bolt.badge.clock")
                        .font(.system(size: 14, weight: .bold))
                    Text(localized("Mock AI"))
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)
                }
                .foregroundStyle(.blue)
            }
        }
    }

    @ViewBuilder
    var generateActionControl: some View {
        GenerateMoreAIButton(
            action: {
                presentAIGenerationSourcePicker()
            },
            isEnabled: canStartLocalGeneration,
            label: localized("Generate more"),
            accessibilityLabel: localized("Generate cards with AI")
        )
    }

    @ViewBuilder
    var topAIGenerationControls: some View {
        HStack(spacing: UIConstants.Spacing.small) {
            Button {
                if viewModel.hasPausedAIGeneration {
                    Task {
                        await viewModel.resumePausedAIGeneration()
                    }
                } else {
                    viewModel.pauseAIGeneration()
                }
            } label: {
                ChromeSoftCircleSymbol(
                    systemName: viewModel.hasPausedAIGeneration ? "play.fill" : "pause.fill",
                    size: UIConstants.Size.actionButton,
                    tint: aiToolbarTint
                )
            }
            .buttonStyle(.plain)
            .aiGenerationBorderBeam(
                accent: aiToolbarTint,
                cornerRadius: UIConstants.Size.actionButton / 2,
                beamBlur: 8,
                lineWidth: 1.45,
                duration: 2.2,
                isEnabled: viewModel.isGenerating || viewModel.hasPausedAIGeneration
            )
            .animation(generationPhaseAnimation, value: generationMotionKey)
            .accessibilityLabel(
                viewModel.hasPausedAIGeneration
                    ? localized("Resume AI generation")
                    : localized("Pause AI generation")
            )

            Button {
                viewModel.requestAIGenerationCancel()
            } label: {
                ChromeSoftCircleSymbol(
                    systemName: "xmark",
                    size: UIConstants.Size.actionButton
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(localized("Cancel AI generation"))
        }
    }

    var generationHeaderStatusControl: some View {
        let holdsAlmostReadyStatus = generationCompletionDisplayState == .holdingAlmostReady
        let statusTitle: String = {
            if holdsAlmostReadyStatus {
                return localized("Almost ready")
            }
            return viewModel.aiGenerationDisplayPhase.map(localizedGenerationDisplayPhase) ?? localized("Almost ready")
        }()
        let generatedCount = holdsAlmostReadyStatus ? completionStatusGeneratedCount : viewModel.aiGeneratedCardCount
        let targetCount = holdsAlmostReadyStatus ? completionStatusTargetCount : viewModel.aiTargetCardCount
        let tint = holdsAlmostReadyStatus ? themeManager.successPrimary : aiToolbarTint

        return HStack(spacing: UIConstants.Spacing.small) {
            AnimatedGenerationStatusTitle(
                title: statusTitle,
                animation: generationPhaseAnimation,
                tint: nil
            )
            .font(.system(size: 20, weight: .heavy))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)

            ProgressActivityDots(color: tint)
                .frame(minWidth: 28)
                .animation(generationPhaseAnimation, value: generationMotionKey)

            if targetCount > 0 {
                Text("\(generatedCount)/\(targetCount)")
                    .font(.system(size: 15, weight: .bold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: UIConstants.Animation.standard), value: generatedCount)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(aiToolbarStatusText ?? statusTitle)
        .animation(generationPhaseAnimation, value: generationMotionKey)
        .animation(generationPhaseAnimation, value: generationCompletionDisplayState)
    }

    var shouldShowGenerationProgressStatus: Bool {
        viewModel.aiGenerationDisplayPhase != nil
            || generationCompletionDisplayState == .holdingAlmostReady
    }

    var addCardButton: some View {
        Menu {
            addCardTypeButtons
        } label: {
            ChromeSoftCircleSymbol(
                systemName: "plus",
                size: UIConstants.Size.actionButton,
                tint: themeManager.roleColor(.buttonDangerForeground)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(localized("Choose card type"))
    }

    func floatingGenerateAction(bottomInset: CGFloat) -> some View {
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

    func moreMenuContents(
        prepareSelectionVisual: @escaping () -> Void = {},
        finishMenuInteraction: @escaping () -> Void = {}
    ) -> UIMenu {
        var children: [UIMenuElement] = [
            SelectionModeMenuElement.action(
                title: viewModel.isSelectingCards ? localized("Done Selecting") : localized("Select Cards"),
                systemImage: viewModel.isSelectingCards ? "checkmark" : "checkmark.circle",
                isEnabled: viewModel.isSelectingCards || (!viewModel.isGenerating && !viewModel.draftCards.isEmpty)
            ) {
                if !viewModel.isSelectingCards {
                    prepareSelectionVisual()
                } else {
                    finishMenuInteraction()
                }
                isTitleFocused = false
                withBottomChromeAnimation {
                    if viewModel.isSelectingCards {
                        viewModel.exitCardSelectionMode()
                    } else {
                        viewModel.enterCardSelectionMode()
                    }
                }
            },
        ]

        if viewModel.isEditingExistingDeck {
            children.append(
                SelectionModeMenuElement.action(
                    title: localized("Undo Changes"),
                    systemImage: "arrow.uturn.backward",
                    isEnabled: viewModel.canUndoChanges
                ) {
                    finishMenuInteraction()
                    isTitleFocused = false
                    withAnimation(.easeInOut(duration: UIConstants.Animation.standard)) {
                        viewModel.revertToInitialState()
                    }
                }
            )

            children.append(
                SelectionModeMenuElement.action(
                    title: localized("Delete Deck"),
                    systemImage: "trash",
                    isEnabled: viewModel.canDeleteDeck,
                    isDestructive: true
                ) {
                    finishMenuInteraction()
                    isTitleFocused = false
                    showDeleteDeckConfirmation = true
                }
            )
        }

        children.append(locationMenu(finishMenuInteraction: finishMenuInteraction))
        children.append(editorSortMenu(finishMenuInteraction: finishMenuInteraction))
        return UIMenu(children: children)
    }

    private func locationMenu(finishMenuInteraction: @escaping () -> Void) -> UIMenu {
        var children: [UIMenuElement] = [
            SelectionModeMenuElement.action(
                title: localized("Library"),
                systemImage: viewModel.selectedFolder == nil ? "checkmark" : "tray.full",
                state: viewModel.selectedFolder == nil ? .on : .off
            ) {
                finishMenuInteraction()
                isTitleFocused = false
                exitDraftSelectionModeForExternalAction()
                viewModel.selectedFolder = nil
            },
        ]

        if !folders.isEmpty {
            children.append(contentsOf: folders.map { folder in
                let isSelected = viewModel.selectedFolder?.id == folder.id
                return SelectionModeMenuElement.action(
                    title: folder.title,
                    systemImage: isSelected ? "checkmark" : "folder",
                    state: isSelected ? .on : .off
                ) {
                    finishMenuInteraction()
                    isTitleFocused = false
                    exitDraftSelectionModeForExternalAction()
                    viewModel.selectedFolder = folder
                }
            })
        }

        return UIMenu(
            title: localizedFormat("Location: %@", destinationTitle),
            image: UIImage(systemName: "folder"),
            options: [],
            children: children
        )
    }

    private func editorSortMenu(finishMenuInteraction: @escaping () -> Void) -> UIMenu {
        UIMenu(
            title: localized("Sort By"),
            image: UIImage(systemName: "arrow.up.arrow.down"),
            options: [],
            children: CreateDeckSortOrder.allCases.map { sortOrder in
                SelectionModeMenuElement.action(
                    title: sortOrder.localizedTitle(locale: locale),
                    systemImage: appPreferences.createDeckSortOrder == sortOrder ? "checkmark" : "arrow.up.arrow.down",
                    isEnabled: viewModel.draftCards.count >= 2,
                    state: appPreferences.createDeckSortOrder == sortOrder ? .on : .off
                ) {
                    finishMenuInteraction()
                    appPreferences.createDeckSortOrder = sortOrder
                }
            }
        )
    }

    var addCardTypeButtons: some View {
        Group {
            Button {
                openCardEditor(for: .flashcard)
            } label: {
                CardTypeMenuLabel(
                    kind: .flashcard,
                    title: localized("Flashcard")
                )
            }

            Button {
                openCardEditor(for: .quiz)
            } label: {
                CardTypeMenuLabel(
                    kind: .quiz,
                    title: localized("Quiz")
                )
            }
        }
    }

    var moreActionsButton: some View {
        SelectionModeMenuButton(
            isSelecting: viewModel.isSelectingCards,
            menuAccessibilityLabel: localized("More actions"),
            doneAccessibilityLabel: localized("Done selecting draft cards"),
            onDone: {
                isTitleFocused = false
                withBottomChromeAnimation {
                    viewModel.exitCardSelectionMode()
                }
            }
        ) { prepareSelectionVisual, finishMenuInteraction in
            moreMenuContents(
                prepareSelectionVisual: prepareSelectionVisual,
                finishMenuInteraction: finishMenuInteraction
            )
        }
    }
}

struct CreateDeckHeaderStatChip: View {
    let symbol: String
    let text: String
    var tint: Color = .secondary
    var rotation: Angle = .zero

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .rotationEffect(rotation)

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

struct CreateDeckChromeButton<Label: View>: View {
    let action: () -> Void
    var isEnabled: Bool = true
    var chrome: QuizFlashButtonChrome = .surface
    let accessibilityLabel: String
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            CreateDeckChromeCircleSurface(content: label)
        }
        .quizFlashButtonStyle(chrome, shape: .circle, size: UIConstants.Size.actionButton)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct CreateDeckChromeCircleSurface<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(width: UIConstants.Size.actionButton, height: UIConstants.Size.actionButton)
    }
}

struct CreateDeckCapsuleButton<Label: View>: View {
    let action: () -> Void
    var isEnabled: Bool = true
    var chrome: QuizFlashButtonChrome = .surface
    let accessibilityLabel: String
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            CreateDeckCapsuleContainer(content: label)
        }
        .quizFlashButtonStyle(chrome, shape: .capsule, size: UIConstants.Size.capsuleHeight)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct CreateDeckCapsuleContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, UIConstants.Spacing.standard)
            .frame(minWidth: UIConstants.Size.capsuleHeight)
            .frame(height: UIConstants.Size.capsuleHeight)
    }
}

struct GenerateMoreAIButton: View {
    let action: () -> Void
    var isEnabled: Bool = true
    let label: String
    let accessibilityLabel: String

    var body: some View {
        Button(action: action) {
            GenerateMoreAIControlSurface(label: label)
        }
        .buttonStyle(GenerateMoreAIButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct GenerateMoreAIControlSurface: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager

    let label: String

    var body: some View {
        HStack(spacing: UIConstants.Spacing.small) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .bold))

            Text(label)
                .font(.system(size: 15, weight: .bold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .foregroundStyle(themeManager.accentColor.color)
        .padding(.horizontal, UIConstants.Spacing.standard)
        .frame(height: UIConstants.Size.capsuleHeight)
        .background {
            Capsule(style: .continuous)
                .fill(themeManager.roleColor(.buttonSurfaceFill))
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(borderColor, lineWidth: borderLineWidth)
        }
        .shadow(color: .black.opacity(0.30), radius: 10, x: 0, y: 5)
        .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1)
        .contentShape(Capsule(style: .continuous))
    }

    private var borderColor: Color {
        AppBorderRenderer.color(
            for: .control,
            preferences: appPreferences.borderDesign,
            colorScheme: colorScheme
        )
    }

    private var borderLineWidth: CGFloat {
        AppBorderRenderer.lineWidth(
            for: .control,
            preferences: appPreferences.borderDesign
        )
    }
}

private struct CompletionGenerateMoreControl: View {
    @Environment(ThemeManager.self) private var themeManager

    let showsGenerateMore: Bool
    let isVisible: Bool
    let isEnabled: Bool
    let doneLabel: String
    let generateMoreLabel: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button {
            guard showsGenerateMore, isEnabled else { return }
            action()
        } label: {
            ZStack(alignment: .leading) {
                generateMoreSurface
                    .opacity(showsGenerateMore ? 1 : 0)
                    .scaleEffect(showsGenerateMore ? 1 : 0.985, anchor: .leading)
                    .animation(generateMoreRevealAnimation, value: showsGenerateMore)

                Text(doneLabel)
                    .font(.system(size: 20, weight: .heavy))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(themeManager.successPrimary)
                    .opacity(showsGenerateMore ? 0 : 1)
                    .scaleEffect(showsGenerateMore ? 0.985 : 1, anchor: .leading)
                    .animation(doneDismissAnimation, value: showsGenerateMore)
            }
            .frame(height: UIConstants.Size.capsuleHeight)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(GenerateMoreAIButtonStyle())
        .disabled(!showsGenerateMore || !isEnabled)
        .opacity(isVisible ? (isEnabled || !showsGenerateMore ? 1 : 0.55) : 0)
        .scaleEffect(isVisible ? 1 : 0.985, anchor: showsGenerateMore ? .trailing : .leading)
        .allowsHitTesting(isVisible && showsGenerateMore && isEnabled)
        .animation(.easeInOut(duration: UIConstants.Animation.standard), value: isVisible)
        .accessibilityHidden(!isVisible)
        .accessibilityLabel(showsGenerateMore ? accessibilityLabel : doneLabel)
    }

    private var generateMoreSurface: some View {
        GenerateMoreAIControlSurface(label: generateMoreLabel)
    }

    private var generateMoreRevealAnimation: Animation {
        if showsGenerateMore {
            return .easeOut(duration: 0.24).delay(0.18)
        }
        return .easeOut(duration: UIConstants.Animation.instant)
    }

    private var doneDismissAnimation: Animation {
        if showsGenerateMore {
            return .easeOut(duration: 0.14)
        }
        return .easeOut(duration: UIConstants.Animation.standard)
    }
}

private struct GenerateMoreAIButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.9 : 1)
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(.timingCurve(0.24, 0.84, 0.30, 1.0, duration: 0.16), value: configuration.isPressed)
    }
}

struct CreateDeckChromeButtonLabel: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: UIConstants.Size.actionIcon, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: UIConstants.Size.actionButton, height: UIConstants.Size.actionButton)
    }
}

struct CreateDeckCollapsedTitlePill: View {
    let title: String
    let maxWidth: CGFloat
    let isVisible: Bool
    let fallbackTitle: String

    var body: some View {
        CollapsibleTitlePill(
            title: .verbatim(title),
            maxWidth: maxWidth,
            isVisible: isVisible,
            fallbackTitle: fallbackTitle
        )
    }
}

private struct AnimatedGenerationStatusTitle: View {
    let title: String
    let animation: Animation
    var tint: Color? = nil

    var body: some View {
        ZStack(alignment: .leading) {
            Group {
                if let tint {
                    Text(title)
                        .foregroundStyle(tint)
                } else {
                    AIShimmeringStatusText(title)
                }
            }
            .id(title)
            .transition(
                .asymmetric(
                    insertion: .opacity
                        .combined(with: .offset(x: 0, y: 7))
                        .combined(with: .scale(scale: 0.985, anchor: .leading)),
                    removal: .opacity
                        .combined(with: .offset(x: 0, y: -7))
                        .combined(with: .scale(scale: 1.01, anchor: .leading))
                )
            )
        }
        .animation(animation, value: title)
    }
}
