//
//  DeckScreenContent.swift
//  QuizFlash
//
//  Extracted content layout for the deck screen.
//

import SwiftUI
import SwiftData
import UIKit

extension DeckContentView {
    var deckContent: some View {
        ZStack(alignment: .bottom) {
            mainContentWithTopEdgeShadow
            if viewModel.isSelecting {
                BottomChromeContainer(
                    kind: .selection,
                    bottomPadding: BottomChromeInsets.persistent
                ) {
                    DeckSelectionBottomBar(
                        selectedCount: viewModel.selectedCards.count,
                        isSelectAllEnabled: !viewModel.areAllVisibleCardsSelected,
                        onSelectAll: {
                            withAnimation(.selectionToolbarSpring) {
                                viewModel.selectAllVisibleCards()
                            }
                        },
                        onDelete: { viewModel.showDeleteConfirmation = true }
                    )
                }
                .transition(.bottomChrome)
                .zIndex(10)
            }
        }
        .coordinateSpace(name: kDeckChromeSpace)
        .overlay(alignment: .top) {
            if shouldShowDeckNavigationBar {
                measuredNavigationBar
            }
        }
        .animation(.bottomChromeSpring, value: viewModel.isSelecting)
        .environment(scrollState)
        .swipeBack(
            enabled: !viewModel.showShareSheet
                && selectedPlayMode == nil
                && selectedPlayModeSettings == nil
                && previewedCard == nil
                && deckEditorPresentation == nil
                && cardEditorDestination == nil
        ) { dismiss() }
        .fullScreenSheet(
            item: $selectedPlayMode,
            configuration: .sheet(
                heightMode: .fullScreen,
                dragActivationArea: .fixed(0),
                backgroundReceivesDragProgress: true,
                showsBackdropBlur: true,
                showsDefaultTopProgressiveBlur: false,
                hidesTabBar: false,
                coversTabBar: true
            )
        ) { mode, safeArea in
            if mode == .flashcards,
               let preparedFlashcardsPlayModeViewModel {
                DefaultModePlay(
                    deck: deck,
                    safeAreaInsets: safeArea,
                    viewModel: preparedFlashcardsPlayModeViewModel
                )
            } else {
                mode.playSheetView(
                    for: deck,
                    safeAreaInsets: safeArea,
                    availability: viewModel.playModeAvailability
                )
            }
        } background: {
            PlayModeFullScreenSheetBackground()
        }
        .fullScreenSheet(
            item: $selectedPlayModeSettings,
            configuration: .chrome(
                heightMode: playModeSettingsSheetHeightMode,
                backgroundReceivesDragProgress: false,
                showsBackdropBlur: true
            )
        ) { mode, safeArea in
            mode.settingsSheetView(
                for: deck,
                safeAreaInsets: safeArea,
                availability: viewModel.playModeAvailability,
                onContentHeightChange: updatePlayModeSettingsSheetHeight
            )
        } background: {
            if let mode = selectedPlayModeSettings {
                PlayModeSettingsBackground(deck: deck, mode: mode)
            } else {
                CardPreviewModeBackground()
            }
        }
        .fullScreenSheet(
            item: $previewedCard,
            configuration: .sheet(
                heightMode: .fullScreen,
                showsDefaultTopProgressiveBlur: false
            )
        ) { card, safeArea in
            CardPreviewSheetView(
                content: card.cardContent,
                safeAreaInsets: safeArea,
                contentAlignment: resolvedFlashcardSettings.contentAlignment,
                textSize: resolvedFlashcardSettings.textSize,
                showsEditButton: true,
                onEdit: {
                    presentCardEditor(for: card)
                }
            )
        } background: {
            CardPreviewModeBackground()
        }
        .fullScreenSheet(
            item: $viewModel.activitySheetPresentation,
            configuration: .sheet(
                heightMode: .custom(0.75),
                showsCloseButton: true
            )
        ) { _, safeArea in
            DeckActivityDetailSheetView(
                summary: viewModel.activityHistorySummary,
                deckTint: Color(hex: deck.colorHex) ?? themeManager.roleColor(.buttonPrimaryFill),
                safeAreaInsets: safeArea
            )
        } background: {
            DeckActivitySheetBackground()
        }
        .fullScreenSheet(
            item: $deckEditorPresentation,
            configuration: .chrome(
                heightMode: .fullScreen,
                backgroundReceivesDragProgress: false,
                showsBackdropBlur: true,
                hidesTabBar: true,
                coversTabBar: true
            )
        ) { presentation, safeArea in
            if let editingDeck = context.safeModel(for: presentation.id, as: DeckModel.self) {
                DeckWorkspaceView(
                    deckToEdit: editingDeck,
                    sheetSafeAreaInsets: safeArea
                ) {
                    deckEditorPresentation = nil
                    viewModel.requestSnapshotLoad(
                        deckID: deck.persistentModelID,
                        container: context.container
                    )
                }
            }
        } background: {
            DeckActivitySheetBackground()
        }
        .fullScreenCover(item: $cardEditorDestination) { destination in
            CardEditorView(
                destination: destination,
                searchQuery: viewModel.searchQuery,
                textSizeOverride: resolvedEditorTextSize(for: destination.kind)
            ) { content in
                handleCardEditorSave(destination: destination, content: content)
            }
        }
    }

    // MARK: Navigation Bar

    var shouldShowDeckNavigationBar: Bool {
        cardEditorDestination == nil
    }

    var playModeSettingsSheetHeightMode: FullScreenSheetHeightMode {
        let fallbackHeight: CGFloat
        switch selectedPlayModeSettings {
        case .quiz:
            fallbackHeight = 510
        case .flashcards:
            let settings = deck.playModeSettings?.flashcardSettings ?? FlashcardModeSettings()
            fallbackHeight = settings.tapAnimationStyle == .staticSwap ? 650 : 600
        case nil:
            fallbackHeight = 510
        }

        return .adaptiveAbsolute(
            playModeSettingsMeasuredSheetHeight > 0 ? playModeSettingsMeasuredSheetHeight : fallbackHeight,
            maxFraction: 0.96
        )
    }

    func updatePlayModeSettingsSheetHeight(_ height: CGFloat) {
        let roundedHeight = ceil(height)
        guard roundedHeight > 0,
              abs(playModeSettingsMeasuredSheetHeight - roundedHeight) > 0.5 else {
            return
        }

        withAnimation(.easeInOut(duration: 0.18)) {
            playModeSettingsMeasuredSheetHeight = roundedHeight
        }
    }

    private var resolvedFlashcardSettings: FlashcardModeSettings {
        var settings = deck.playModeSettings?.flashcardSettings ?? FlashcardModeSettings()
        if deck.playModeSettings == nil {
            settings.textSize = appPreferences.defaultTextSize
        }
        return settings
    }

    private func resolvedEditorTextSize(for kind: CardKind) -> FlashcardTextSize {
        switch kind {
        case .flashcard:
            return resolvedFlashcardSettings.textSize
        case .quiz:
            if let settings = deck.playModeSettings?.quizSettings {
                return settings.textSize
            }
            return appPreferences.defaultTextSize
        }
    }

    var measuredNavigationBar: some View {
        unifiedNavigationBar
    }

    var unifiedNavigationBar: some View {
        DeckCustomNavigationBar(
            deck: deck,
            stats: viewModel.currentStats,
            backLabel: backLabel,
            searchQuery: searchQuery,
            isSelecting: viewModel.isSelecting,
            selectedCount: viewModel.selectedCards.count,
            selectedCardsAreAllPinned: viewModel.areSelectedCardsAllPinned,
            coordinateSpaceName: kDeckChromeSpace,
            sortOrder: $viewModel.sortOrder,
            groupingMode: Binding(
                get: { viewModel.groupingMode },
                set: { newValue in
                    viewModel.updateGroupingMode(newValue, for: deck, context: context)
                }
            ),
            onBack: {
                exitSelectionModeForExternalAction()
                dismiss()
            },
            onAdd: {
                exitSelectionModeForExternalAction()
                showAddCardTypeDialog = true
            },
            onSetSelectedPinnedState: { isPinned in
                viewModel.setSelectedCardsPinned(
                    isPinned,
                    in: deck,
                    context: context
                )
                withBottomChromeAnimation {
                    viewModel.exitSelectionMode()
                }
            },
            onStartSelection: {
                withBottomChromeAnimation {
                    viewModel.enterSelectionMode()
                }
            },
            onDoneSelection: {
                withBottomChromeAnimation {
                    viewModel.exitSelectionMode()
                }
            },
            onExport: {
                exitSelectionModeForExternalAction()
                viewModel.exportDeck(deck)
            },
            onHeightChange: { newHeight in
                if abs(navigationBarHeight - newHeight) > 0.5 {
                    navigationBarHeight = newHeight
                }
            },
            onBottomChange: { newBottom in
                if abs(navigationBarBottomY - newBottom) > 0.5 {
                    navigationBarBottomY = newBottom
                }
            }
        )
    }

    var structuralTopEdgeShadowHeight: CGFloat {
        if navigationBarBottomY > 0 {
            return navigationBarBottomY
        }
        return UIConstants.Layout.topEdgeShadowHeight
    }

    var mainContentWithTopEdgeShadow: some View {
        mainContent
            .screenTopEdgeShadow(
                topHeight: structuralTopEdgeShadowHeight,
                topRevealProgress: scrollState.pillVisible ? 1 : 0,
                debugScreenID: "deck.details",
                style: .progressiveBlur()
            )
    }

    @ViewBuilder
    var exportingOverlay: some View {
        if viewModel.isExporting {
            ZStack {
                Color.black.opacity(0.3).ignoresSafeArea()
                VStack(spacing: 16) {
                    ProgressActivityDots()
                        .scaleEffect(1.5)
                    Text(localized("Exporting...")).font(.headline)
                }
                    .padding(32)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    var mainContent: some View {
        GeometryReader { geometry in
            let layout = DeckDetailAdaptiveLayoutContext(containerWidth: geometry.size.width)

            ScrollView {
                VStack(spacing: 0) {
                    ScrollPositionRestorer(
                        getOffset: { viewModel.savedScrollOffset },
                        onOffsetChange: { offset in
                            viewModel.savedScrollOffset = offset
                        }
                    )
                    .frame(width: 0, height: 0)

                    if let query = searchQuery, !query.isEmpty {
                        HStack {
                            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                                .foregroundStyle(Color.accentColor)
                            (
                                Text(localized("Filtered by"))
                                + Text(verbatim: " \"\(query)\"")
                            )
                            .font(.subheadline)
                            Spacer()
                        }
                        .padding(.horizontal, UIConstants.Layout.compactScreenEdgeInset)
                        .padding(.vertical, 12)
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.horizontal, layout.sectionHorizontalInset)
                        .padding(.top, 12)
                        .frame(maxWidth: layout.contentWidth, alignment: .leading)
                        .frame(maxWidth: .infinity)
                    }

                    VStack(spacing: 16) {
                        Button {
                            exitSelectionModeForExternalAction()
                            deckEditorPresentation = DeckEditorSheetPresentation(id: deck.persistentModelID)
                        } label: {
                            HStack(alignment: .top, spacing: 16) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(deck.title)
                                        .font(.system(size: layout.heroTitleFontSize, weight: .heavy))
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.7)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    Text(subtitleText)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .textCase(.uppercase)
                                }

                                Spacer(minLength: 0)

                                DeckHeroEditIndicator(
                                    tint: themeManager.roleColor(.buttonDangerForeground)
                                )
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(localized("Opens deck edit mode"))
                        .background {
                            Color.clear
                                .onGeometryChange(for: CGFloat.self) { proxy in
                                    proxy.frame(in: .named(kDeckChromeSpace)).maxY
                                } action: { maxY in
                                    let revealLine =
                                        navigationBarBottomY
                                        - UIConstants.Layout.deckHeroPillRevealClearance
                                    let isCollapsed = maxY < revealLine
                                    if scrollState.pillVisible != isCollapsed {
                                        scrollState.pillVisible = isCollapsed
                                    }
                                }
                        }
                        .padding(.horizontal, layout.heroHorizontalInset)

                        if searchQuery == nil || searchQuery?.isEmpty == true {
                            DeckProgressView(
                                stats: viewModel.currentStats,
                                deckTint: Color(hex: deck.colorHex) ?? themeManager.roleColor(.buttonPrimaryFill),
                                horizontalInset: layout.sectionHorizontalInset
                            )
                            DeckPlayModesView(
                                deck: deck,
                                availability: viewModel.playModeAvailability,
                                recentUsageSnapshot: playModeRecentUsageSnapshot,
                                horizontalInset: layout.sectionHorizontalInset,
                                onOpenMode: { mode in
                                    openPlayMode(mode)
                                },
                                onOpenSettings: { mode in
                                    selectedPlayModeSettings = mode
                                }
                            )
                            .padding(.top, 16)
                        }
                    }
                    .frame(maxWidth: layout.contentWidth, alignment: .topLeading)
                    .frame(maxWidth: .infinity)

                    DeckCardGridView(
                        cards: viewModel.cachedGroupedCards,
                        isSelecting: viewModel.isSelecting,
                        selectedCards: viewModel.selectedCards,
                        isSuspended: isSuspended,
                        columnCount: layout.gridColumnCount,
                        horizontalInset: layout.gridHorizontalInset,
                        onToggleSelection: { gridCard in
                            withAnimation(.spring(response: 0.18, dampingFraction: 0.88)) {
                                viewModel.toggleSelection(for: gridCard.id)
                            }
                        },
                        onTapCard: { gridCard in
                            if viewModel.isSelecting {
                                withAnimation(.spring(response: 0.18, dampingFraction: 0.88)) {
                                    viewModel.toggleSelection(for: gridCard.id)
                                }
                            } else if searchQuery != nil {
                                if let model = context.model(for: gridCard.id) as? CardModel {
                                    presentCardEditor(for: model)
                                }
                            } else {
                                if let model = context.model(for: gridCard.id) as? CardModel { previewedCard = model }
                            }
                        },
                        onEditCard: handleEditCard(_:),
                        onTogglePinned: handleTogglePinned(_:),
                        onDeleteCard: handleDeleteCard(_:)
                    )
                    .padding(.top, searchQuery == nil || searchQuery?.isEmpty == true ? 28 : 4)
                    .frame(maxWidth: layout.contentWidth, alignment: .topLeading)
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .tabBarAutoHideOnScroll(enabled: !viewModel.isSelecting)
                .background {
                    themeManager.groupedScreenBackground
                }
            }
            .coordinateSpace(name: kDeckScrollSpace)
            .scrollIndicators(.hidden)
            .gesture(
                TapGesture().onEnded {
                    guard viewModel.isSelecting else { return }
                    withBottomChromeAnimation {
                        viewModel.exitSelectionMode()
                    }
                }
            )
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: topContentInset)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: bottomContentInset)
            }
            .background(themeManager.groupedScreenBackground)
        }
    }
}

private struct DeckDetailAdaptiveLayoutContext: Equatable {
    private static let widthThresholds = AdaptiveLayoutWidthThresholds(
        medium: 520,
        wide: 860
    )
    private static let maxReadableContentWidth: CGFloat = 860

    let containerWidth: CGFloat
    let contentWidth: CGFloat
    let widthClass: ContainerWidthClass

    init(containerWidth: CGFloat) {
        self.containerWidth = containerWidth

        let modeContext = AdaptiveLayoutContext(
            containerWidth: containerWidth,
            horizontalInset: UIConstants.Spacing.large,
            thresholds: Self.widthThresholds
        )
        widthClass = modeContext.widthClass

        let contentContext = AdaptiveLayoutContext(
            containerWidth: containerWidth,
            horizontalInset: 0,
            thresholds: Self.widthThresholds,
            maxContentWidth: widthClass == .wide ? Self.maxReadableContentWidth : nil
        )
        contentWidth = contentContext.contentWidth
    }

    var heroTitleFontSize: CGFloat {
        switch widthClass {
        case .narrow:
            return 42
        case .medium:
            return 40
        case .wide:
            return 38
        }
    }

    var heroHorizontalInset: CGFloat {
        switch widthClass {
        case .narrow:
            return UIConstants.Layout.heroScreenEdgeInset
        case .medium:
            return UIConstants.Spacing.extraLarge
        case .wide:
            return UIConstants.Spacing.large
        }
    }

    var sectionHorizontalInset: CGFloat {
        switch widthClass {
        case .narrow:
            return UIConstants.Layout.screenEdgeInset
        case .medium, .wide:
            return UIConstants.Spacing.large
        }
    }

    var gridHorizontalInset: CGFloat {
        switch widthClass {
        case .narrow:
            return UIConstants.Layout.cardListEdgeInset
        case .medium, .wide:
            return UIConstants.Spacing.large
        }
    }

    var gridColumnCount: Int {
        let availableGridWidth = max(contentWidth - (gridHorizontalInset * 2), 0)
        if availableGridWidth >= 760 {
            return 3
        }
        return 2
    }
}

private struct DeckHeroEditIndicator: View {
    let tint: Color

    var body: some View {
        Image(systemName: "square.and.pencil")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: 24, height: 24)
            .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
            .offset(x: -2, y: 8)
            .accessibilityHidden(true)
    }
}

private struct PlayModeFullScreenSheetBackground: View {
    var body: some View {
        Color.black
    }
}
