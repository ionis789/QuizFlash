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
            mainContentWithCovers
            if viewModel.isSelecting {
                BottomChromeContainer(
                    kind: .selection,
                    bottomPadding: BottomChromeInsets.persistent
                ) {
                    DeckSelectionBottomBar(
                        selectedCount: viewModel.selectedCards.count,
                        onDone: {
                            withBottomChromeAnimation {
                                viewModel.exitSelectionMode()
                            }
                        },
                        onClearSelection: {
                            withAnimation(.selectionToolbarSpring) {
                                viewModel.clearSelection()
                            }
                        },
                        onConvert: {
                            presentSelectionConversion()
                        },
                        onDelete: { viewModel.showDeleteConfirmation = true }
                    )
                }
                    .transition(.bottomChrome)
                    .zIndex(10)
            }
        }
            .coordinateSpace(name: kDeckChromeSpace)
            .overlay(alignment: .top) { measuredNavigationBar }
            .swipeBack(
                enabled: !viewModel.showShareSheet
                    && selectedPlayMode == nil
                    && selectedPlayModeSettings == nil
                    && previewedCard == nil
                    && cardEditorDestination == nil
                    && unavailablePlayMode == nil
            ) { dismiss() }
            .animation(.bottomChromeSpring, value: viewModel.isSelecting)
            .environment(scrollState)
            .overlay { unavailablePlayModeOverlay }
    }

    // MARK: Navigation Bar

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
            onStartSelection: {
                withBottomChromeAnimation {
                    viewModel.enterSelectionMode()
                }
            },
            onConvert: { presentDeckConversion() },
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

    var mainContentWithCovers: some View {
        mainContent
            .fullScreenSheet(
                item: $selectedPlayMode,
                configuration: .chrome(backgroundReceivesDragProgress: true)
            ) { mode, safeArea in
                mode.playSheetView(
                    for: deck,
                    safeAreaInsets: safeArea,
                    availability: viewModel.playModeAvailability
                )
            } background: {
                CardPreviewModeBackground()
            }
            .fullScreenSheet(
                item: $selectedPlayModeSettings,
                configuration: .chrome(backgroundReceivesDragProgress: false)
            ) { mode, safeArea in
                mode.settingsSheetView(
                    for: deck,
                    safeAreaInsets: safeArea,
                    availability: viewModel.playModeAvailability
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
                configuration: .sheet(dragActivationArea: .fixed(180))
            ) { card, safeArea in
                DeckCardPreviewSheetView(
                    card: card,
                    safeAreaInsets: safeArea,
                    onOpenRecommendedConversion: { targetKind in
                        handlePreviewRecommendedConversion(for: card, targetKind: targetKind)
                    }
                )
            } background: {
                CardPreviewModeBackground()
            }
            .fullScreenCover(item: $cardEditorDestination) { destination in
                CardEditorView(
                    destination: destination,
                    searchQuery: viewModel.searchQuery
                ) { content in
                    handleCardEditorSave(destination: destination, content: content)
                }
            }
    }

    @ViewBuilder
    var exportingOverlay: some View {
        if viewModel.isExporting {
            ZStack {
                Color.black.opacity(0.3).ignoresSafeArea()
                VStack(spacing: 16) {
                    ProgressView().scaleEffect(1.5)
                    Text("Exporting...").font(.headline)
                }
                    .padding(32)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    var mainContent: some View {
        let scrollView = ScrollView {
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
                        Text("Filtered by \"**\(query)**\"")
                            .font(.subheadline)
                        Spacer()
                    }
                    .padding(.horizontal, UIConstants.Layout.compactScreenEdgeInset)
                    .padding(.vertical, 12)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
                    .padding(.top, 12)
                }

                VStack(spacing: 16) {
                    HStack(alignment: .center, spacing: 20) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .center, spacing: 12) {
                                Text(deck.title)
                                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.7)

                                Button {
                                    exitSelectionModeForExternalAction()
                                    router.showDeckWorkspace(for: deck.persistentModelID)
                                } label: {
                                    let deckColor = Color(hex: deck.colorHex) ?? .blue
                                    Label("Edit", systemImage: "square.and.pencil")
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundStyle(deckColor.opacity(0.96))
                                        .padding(.horizontal, 12)
                                        .frame(height: UIConstants.Size.heroInlineActionHeight)
                                        .background(.ultraThinMaterial, in: Capsule())
                                        .overlay {
                                            Capsule()
                                                .fill(deckColor.opacity(0.12))
                                        }
                                        .overlay {
                                            Capsule()
                                                .stroke(Color.white.opacity(0.10), lineWidth: 0.75)
                                        }
                                }
                                .buttonStyle(.plain)
                            }

                            Text(subtitleText)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                        }
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

                        Spacer(minLength: 0)

                        MasteryProgressRing(
                            mastery: viewModel.currentStats.deckMastery,
                            deckColor: Color(hex: deck.colorHex) ?? .blue
                        )
                    }
                    .padding(.horizontal, UIConstants.Layout.heroScreenEdgeInset)

                    if searchQuery == nil || searchQuery?.isEmpty == true {
                        DeckProgressView(
                            progress: viewModel.progressStats,
                            stats: viewModel.currentStats,
                            deckCardCount: deck.cardCount
                        )
                        DeckReadinessDiagnosticsView(
                            summary: viewModel.readinessSummary
                        )
                        DeckPlayModesView(
                            deck: deck,
                            availability: viewModel.playModeAvailability,
                            recentUsageSnapshot: playModeRecentUsageSnapshot,
                            onOpenMode: { mode in
                                openPlayMode(mode)
                            },
                            onOpenSettings: { mode in
                                selectedPlayModeSettings = mode
                            },
                            onRequestUnavailableMode: { mode in
                                presentUnavailablePlayMode(mode)
                            }
                        )
                        .padding(.top, 16)
                    }
                }

                DeckCardGridView(
                    cards: viewModel.cachedGroupedCards,
                    isSelecting: viewModel.isSelecting,
                    selectedCards: viewModel.selectedCards,
                    isSuspended: isSuspended,
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
                    onConvertCard: handleConvertCard(_:),
                    onTogglePinned: handleTogglePinned(_:),
                    onDeleteCard: handleDeleteCard(_:)
                )
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .tabBarAutoHideOnScroll(enabled: !viewModel.isSelecting)
            .background {
                themeManager.groupedScreenBackground

                if viewModel.isSelecting {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withBottomChromeAnimation {
                                viewModel.exitSelectionMode()
                            }
                        }
                }
            }
        }
        .coordinateSpace(name: kDeckScrollSpace)
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: topContentInset)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: bottomContentInset)
        }
        .background(themeManager.groupedScreenBackground)

        return scrollView
    }
}
