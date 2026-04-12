//
//  DeckWorkspaceChrome.swift
//  QuizFlash
//

import SwiftUI
import SwiftData

// MARK: - Subviews
extension DeckWorkspaceView {

    // MARK: 1. Header Chrome
    func heroHeader(topPadding: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: isShowingWorkspaceConvert ? UIConstants.Spacing.medium : UIConstants.Spacing.large) {
            if isShowingWorkspaceConvert {
                workspaceConvertHero
            } else {
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, UIConstants.Layout.heroScreenEdgeInset)
        .padding(.top, topPadding)
        .padding(.bottom, UIConstants.Spacing.extraLarge)
    }

    @ViewBuilder
    func navigationChrome(
        containerWidth _: CGFloat,
        safeTopInset _: CGFloat
    ) -> some View {
        let horizontalInset = UIConstants.Layout.compactScreenEdgeInset

        navigationBarContent(horizontalInset: horizontalInset, appliesTopNavigationChrome: true)
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
            if isShowingWorkspaceConvert {
                EmptyView()
            } else {
                CreateDeckCollapsedTitlePill(
                    title: collapsedDeckTitle,
                    maxWidth: maxTitleWidth,
                    isVisible: shouldShowCollapsedTitle
                )
            }
        } trailing: {
            if isShowingWorkspaceConvert {
                headerConvertActionControl
            } else {
                HStack(spacing: UIConstants.Spacing.small) {
                    addCardButton
                    moreActionsButton
                }
            }
        }
    }

    @ViewBuilder
    private var workspaceLeadingControl: some View {
        if isShowingWorkspaceConvert {
            cancelConversionButton
        } else if viewModel.isEditingExistingDeck && !viewModel.hasUnsavedChanges {
            dismissWorkspaceButton
        } else {
            doneButton
        }
    }

    private var workspaceConvertHero: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
            Text("Convert Cards")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)

            Text("Choose one source type, convert into another, and save the result with minimal setup.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var headerConvertActionControl: some View {
        let request = aiWorkspaceCoordinator.conversionSeed?.request
        let canStart = request?.canStart ?? false

        CreateDeckCapsuleButton(
            action: startWorkspaceConversion,
            isEnabled: canStart,
            accessibilityLabel: "Start conversion"
        ) {
            HStack(spacing: UIConstants.Spacing.small) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 13, weight: .bold, design: .rounded))

                Text("Convert")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .lineLimit(1)

                if let request {
                    Text("\(request.sourceCount)")
                        .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                        .padding(.horizontal, 7)
                        .frame(height: 22)
                        .background(Color.white.opacity(0.16), in: Capsule())
                }
            }
            .foregroundStyle(.orange)
        }
    }

    private var cancelConversionButton: some View {
        CreateDeckChromeButton(
            action: {
                isTitleFocused = false
                aiWorkspaceCoordinator.dismissConversionConfiguration()
            },
            accessibilityLabel: "Cancel conversion"
        ) {
            CreateDeckChromeButtonLabel(symbol: "xmark", tint: accent)
        }
    }

    private var dismissWorkspaceButton: some View {
        CreateDeckChromeButton(
            action: {
                isTitleFocused = false
                requestDismiss()
            },
            accessibilityLabel: "Cancel editing deck"
        ) {
            CreateDeckChromeButtonLabel(symbol: "xmark", tint: .primary)
        }
    }

    var headerMetadataRow: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            HStack(alignment: .center, spacing: UIConstants.Spacing.medium) {
                destinationMetadataControl
                .layoutPriority(1)

                Spacer(minLength: 0)

                HStack(spacing: UIConstants.Spacing.small) {
                    mockAIActionControl
                    generateActionControl
                }
                .opacity(shouldShowInlineHeaderActions ? 1 : 0)
                .allowsHitTesting(shouldShowInlineHeaderActions)
                .accessibilityHidden(!shouldShowInlineHeaderActions)
            }

            if !viewModel.draftCards.isEmpty {
                headerStatsStrip
            }
        }
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

    var shouldShowInlineHeaderActions: Bool {
        !isShowingWorkspaceConvert
            && !hasUnifiedAISession
            && !viewModel.isSelectingCards
            && !shouldShowFloatingGenerate
    }

    var destinationMetadataControl: some View {
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

    var headerStatsStrip: some View {
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

    var doneButton: some View {
        CreateDeckChromeButton(
            action: handleSave,
            isEnabled: canSave,
            accessibilityLabel: "Save deck"
        ) {
            CreateDeckChromeButtonLabel(symbol: "checkmark", tint: canSave ? accent : .secondary)
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
    var generateActionControl: some View {
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

    var addCardButton: some View {
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

    var moreMenuContents: some View {
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

    var addCardTypeButtons: some View {
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

    var moreActionsButton: some View {
        Menu(content: { moreMenuContents }) {
            CreateDeckChromeCircleSurface {
                CreateDeckChromeButtonLabel(symbol: "ellipsis", tint: accent)
            }
        }
            .buttonStyle(.plain)
            .accessibilityLabel("More actions")
    }
}

struct CreateDeckHeaderStatChip: View {
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

struct CreateDeckChromeButton<Label: View>: View {
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

struct CreateDeckCapsuleContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, UIConstants.Spacing.standard)
            .frame(minWidth: UIConstants.Size.capsuleHeight)
            .frame(height: UIConstants.Size.capsuleHeight)
    }
}

struct CreateDeckAIStatusIndicator: View {
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

struct CreateDeckChromeButtonLabel: View {
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

struct CreateDeckCollapsedTitlePill: View {
    let title: String
    let maxWidth: CGFloat
    let isVisible: Bool

    var body: some View {
        CollapsibleTitlePill(
            title: title,
            maxWidth: maxWidth,
            isVisible: isVisible,
            fallbackTitle: "Untitled Deck"
        )
    }
}
