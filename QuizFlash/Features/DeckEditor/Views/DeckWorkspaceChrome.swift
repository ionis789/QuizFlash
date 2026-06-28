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
        if hasActiveGenerationRuntime && !isTitleFocused {
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
            HStack(alignment: .center, spacing: UIConstants.Spacing.medium) {
                if shouldShowGenerationHeaderStatus {
                    if showsGenerationCompletionCheckmark {
                        generationCompletionStatusControl
                    } else {
                        generationHeaderStatusControl
                    }
                } else {
                    Spacer(minLength: 0)

                    if shouldShowMockAIHeaderAction {
                        mockAIActionControl
                    }

                    if !viewModel.draftCards.isEmpty {
                        headerGenerateActionControl
                    }
                }
            }
            .frame(minHeight: UIConstants.Size.capsuleHeight)
            .transition(
                .asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .leading)),
                    removal: .opacity.combined(with: .scale(scale: 0.94, anchor: .leading))
                )
            )
            .animation(.easeInOut(duration: UIConstants.Animation.standard), value: shouldShowGenerationHeaderStatus)
            .animation(generationPhaseAnimation, value: showsGenerationCompletionCheckmark)
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
        viewModel.aiGenerationDisplayPhase != nil || showsGenerationCompletionCheckmark
    }

    var shouldShowMockAIHeaderAction: Bool {
        developmentPreferences.deckWorkspaceMockAIEnabled
            && !hasUnifiedAISession
            && !viewModel.isSelectingCards
            && !shouldShowFloatingGenerate
    }

    var shouldShowPrimaryGenerateAction: Bool {
        !hasUnifiedAISession
            && !shouldShowFloatingGenerate
    }

    var shouldShowTopAIGenerationControls: Bool {
        viewModel.aiGenerationDisplayPhase != nil
    }

    var heroTitleReservedHeight: CGFloat {
        guard hasActiveGenerationRuntime else { return 0 }
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
    var headerGenerateActionControl: some View {
        primaryGenerateActionControl
    }

    @ViewBuilder
    var primaryGenerateActionControl: some View {
        if shouldShowPrimaryGenerateAction {
            CreateDeckCapsuleButton(
                action: {
                    presentAIGenerationSourcePicker()
                },
                isEnabled: canStartLocalGeneration,
                chrome: .surface,
                accessibilityLabel: localized("Generate cards with AI")
            ) {
                Text(localized("Generate more"))
                    .font(.system(size: 15, weight: .heavy))
                    .lineLimit(1)
                    .foregroundStyle(themeManager.roleColor(.buttonDangerForeground))
            }
        }
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
        CreateDeckCapsuleButton(
            action: {
                presentAIGenerationSourcePicker()
            },
            isEnabled: canStartLocalGeneration,
            chrome: .surface,
            accessibilityLabel: localized("Generate cards with AI")
        ) {
            Text(localized("Generate more"))
                .font(.system(size: 14, weight: .bold))
                .lineLimit(1)
                .foregroundStyle(themeManager.roleColor(.buttonDangerForeground))
        }
    }

    @ViewBuilder
    var topAIGenerationControls: some View {
        HStack(spacing: UIConstants.Spacing.small) {
            Button {
                if viewModel.hasPausedAIGeneration {
                    viewModel.resumePausedAIGeneration()
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
        let statusTitle = viewModel.aiGenerationDisplayPhase
            .map(localizedGenerationDisplayPhase) ?? localized("Generating cards")

        return HStack(spacing: UIConstants.Spacing.small) {
            AnimatedGenerationStatusTitle(
                title: statusTitle,
                animation: generationPhaseAnimation
            )
                .font(.system(size: 20, weight: .heavy))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            ProgressActivityDots(color: aiToolbarTint)
                .frame(minWidth: 28)
                .animation(generationPhaseAnimation, value: generationMotionKey)

            if viewModel.aiTargetCardCount > 0 {
                Text("\(viewModel.aiGeneratedCardCount)/\(viewModel.aiTargetCardCount)")
                    .font(.system(size: 15, weight: .bold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: UIConstants.Animation.standard), value: viewModel.aiGeneratedCardCount)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(aiToolbarStatusText ?? statusTitle)
        .animation(generationPhaseAnimation, value: generationMotionKey)
    }

    var generationCompletionStatusControl: some View {
        HStack(spacing: UIConstants.Spacing.small) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 25, weight: .heavy))
                .foregroundStyle(themeManager.successPrimary)
                .symbolEffect(.bounce, value: showsGenerationCompletionCheckmark)
        }
        .frame(maxWidth: .infinity, minHeight: UIConstants.Size.capsuleHeight, alignment: .leading)
        .accessibilityLabel(localized("Done"))
        .transition(
            .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.72, anchor: .leading)),
                removal: .opacity.combined(with: .scale(scale: 1.08, anchor: .leading))
            )
        )
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
                Label(localized("Flashcard"), systemImage: "rectangle.on.rectangle.angled")
            }

            Button {
                openCardEditor(for: .quiz)
            } label: {
                Label(localized("Quiz"), systemImage: "questionmark.square.dashed")
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

    var body: some View {
        ZStack(alignment: .leading) {
            AIShimmeringStatusText(title)
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
