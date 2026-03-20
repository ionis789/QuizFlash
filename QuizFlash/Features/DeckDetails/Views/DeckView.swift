//
//  DeckView.swift
//  QuizFlash
//
//  Deck detail screen showing the card grid, stats, and play-mode entry points.
//  Business logic is fully delegated to `DeckViewModel`.
//
//  ## iOS 17 Retain Cycle Wrapper
//  `DeckView` is a thin wrapper that lazily creates `DeckViewModel` on appear,
//  preventing the retain cycle that arises when a `@Observable` ViewModel is
//  strongly captured by its own SwiftUI View during `NavigationStack` push.
//  The actual UI lives in `DeckContentView`.

import SwiftUI
import SwiftData
import UIKit

private let kDeckScrollSpace = "DeckViewScrollSpace"
private let kDeckChromeSpace = "DeckViewChromeSpace"

struct DeckContentView: View {
    @Environment(\.modelContext) var context
    @Environment(NavigationManager.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Bindable var deck: DeckModel
    let searchQuery: String?
    let ownerTab: AppTabBar

    // The back-button label frozen at push time via DeckNavigationValue.
    // Never read from router state — immune to cross-tab mutation.
    let backLabel: String

    @State private var isPresentingEdit = false
    @State private var selectedPlayMode: DeckPlayModeDestination? = nil
    @State private var selectedPlayModeSettings: DeckPlayModeDestination? = nil
    @State private var previewedCard: CardModel? = nil
    @State private var cardEditorDestination: CardEditorDestination? = nil
    @State private var showConversionSheet = false
    @State private var unavailablePlayMode: DeckPlayModeDestination? = nil
    @State private var showAddCardTypeDialog = false
    @State private var pendingDeleteCardID: PersistentIdentifier? = nil
    @State private var activeActionMenuCardID: PersistentIdentifier? = nil
    @State private var playModeRecentUsageSnapshot: [DeckPlayModeDestination: Date] = [:]
    @Bindable var viewModel: DeckViewModel
    @State private var hasLoadedInitialSnapshot = false
    @State private var navigationBarHeight: CGFloat =
        UIConstants.Layout.deckNavigationTopPadding
        + UIConstants.Size.capsuleHeight
        + UIConstants.Spacing.small
    @State private var navigationBarBottomY: CGFloat = 0

    /// Scroll-driven progress — updated by DeckScrollMonitor via KVO, never by SwiftUI state.
    @State private var scrollState = DeckScrollState()

    private var isSuspended: Bool {
        router.activeTab != ownerTab
    }

    /// Reserved top spacing that keeps the hero content below the floating chrome.
    private var topContentInset: CGFloat {
        navigationBarHeight + UIConstants.Layout.deckHeroChromeClearance
    }

    /// Bottom scroll clearance reserved for floating chrome without creating a large dead zone.
    private var bottomContentInset: CGFloat {
        let baseInset = UIConstants.Spacing.small
        guard viewModel.isSelecting else { return baseInset }
        return UIConstants.Size.selectionToolbarBarHeight
            + UIConstants.Layout.bottomChromeBottomPadding
            + UIConstants.Spacing.standard
    }

    /// Formats deck creation date and card count for display under the deck title.
    ///
    /// Uses a static `DateFormatter` to avoid allocating a new formatter on every render pass.
    private var subtitleText: String {
        let count = deck.cardCount
        return "\(Self.subtitleDateFormatter.string(from: deck.createdAt))  •  \(count) card\(count == 1 ? "" : "s")"
    }

    /// Static date formatter for `subtitleText`. Allocated once for the app session.
    private static let subtitleDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
    private let actionMenuTopClearance: CGFloat = 10
    private let actionMenuBottomClearance: CGFloat = 10
    private var activeActionMenuCard: GridCardInfo? {
        guard let id = activeActionMenuCardID else { return nil }
        for section in viewModel.cachedGroupedCards {
            if let card = section.cards.first(where: { $0.id == id }) {
                return card
            }
        }
        return nil
    }

    // MARK: - Body

    var body: some View {
        deckContent
            /// Hides the native system navigation bar.
            /// This stabilizes `safeAreaInsets` and prevents layout invalidation during scroll physics (rubber-banding).
            .toolbar(.hidden, for: .navigationBar)
            .customTabBarVisibility(viewModel.isSelecting ? .hidden : .implicit)
            .onAppear {
                guard !hasLoadedInitialSnapshot, !isSuspended else { return }
                hasLoadedInitialSnapshot = true
                refreshPlayModeRecentUsageSnapshot()
                viewModel.configureGroupingMode(from: deck.cardGroupingMode)
                viewModel.requestSnapshotLoad(
                    deckID: deck.persistentModelID,
                    container: context.container
                )
            }
            .onDisappear {
                guard !isPresentingEdit,
                      selectedPlayMode == nil,
                      selectedPlayModeSettings == nil,
                      previewedCard == nil,
                      cardEditorDestination == nil,
                      !showConversionSheet else { return }
                viewModel.tearDown()
                ImageCache.shared.clearCache()
            }
            .onChange(of: deck.cardCount) {
                guard !isSuspended else { return }
                viewModel.requestSnapshotLoad(
                    deckID: deck.persistentModelID,
                    container: context.container
                )
            }
            .onChange(of: viewModel.sortOrder) {
                guard !isSuspended else { return }
                viewModel.requestSnapshotLoad(
                    deckID: deck.persistentModelID,
                    container: context.container
                )
            }
            .onChange(of: viewModel.searchQuery) {
                guard !isSuspended else { return }
                viewModel.requestSnapshotLoad(
                    deckID: deck.persistentModelID,
                    container: context.container
                )
            }
            .onChange(of: selectedPlayMode) { old, new in
                if let completedMode = old, new == nil {
                    recordCompletedPlayModeSession(completedMode)
                    deck.lastOpenedAt = Date()
                    try? context.save()
                    guard !isSuspended else { return }
                    viewModel.requestSnapshotLoad(
                        deckID: deck.persistentModelID,
                        container: context.container
                    )
                }
            }
            .onChange(of: isSuspended) { _, suspended in
                if suspended {
                    viewModel.suspendHeavyWork()
                    CardPreviewCache.shared.flush()
                } else {
                    viewModel.configureGroupingMode(from: deck.cardGroupingMode)
                    viewModel.requestSnapshotLoad(
                        deckID: deck.persistentModelID,
                        container: context.container
                    )
                }
            }
            .onChange(of: showConversionSheet) { _, isPresented in
                if !isPresented {
                    viewModel.dismissConversionSheet()
                }
            }
            .alert(
                "Delete \(viewModel.selectedCards.count) card\(viewModel.selectedCards.count == 1 ? "" : "s")?",
                isPresented: $viewModel.showDeleteConfirmation
            ) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    withBottomChromeAnimation {
                        viewModel.deleteSelectedCards(from: deck, context: context)
                    }
                }
            } message: { Text("This action cannot be undone.") }
            .alert(
                "Delete this card?",
                isPresented: Binding(
                    get: { pendingDeleteCardID != nil },
                    set: { if !$0 { pendingDeleteCardID = nil } }
                )
            ) {
                Button("Cancel", role: .cancel) {
                    pendingDeleteCardID = nil
                }
                Button("Delete", role: .destructive) {
                    guard let id = pendingDeleteCardID else { return }
                    pendingDeleteCardID = nil
                    viewModel.deleteCard(withID: id, from: deck, context: context)
                }
            } message: {
                Text("This action cannot be undone.")
            }
            .sheet(isPresented: $viewModel.showShareSheet) {
                if let url = viewModel.exportedURL { ShareSheet(items: [url]) }
            }
            .alert("Export Error", isPresented: $viewModel.showExportError) {
                Button("OK", role: .cancel) { }
            } message: { Text(viewModel.exportErrorMessage) }
            .confirmationDialog("Choose Card Type", isPresented: $showAddCardTypeDialog, titleVisibility: .visible) {
                Button("Flashcard") { presentCardEditor(for: .flashcard) }
                Button("Quiz") { presentCardEditor(for: .quiz) }
                Button("Write") { presentCardEditor(for: .write) }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Pick the type of card you want to add to this deck.")
            }
            .overlay { exportingOverlay }
    }

    // MARK: - Body Fragments

    private var deckContent: some View {
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
            .overlayPreferenceValue(DeckGridCardBoundsPreferenceKey.self) { preferences in
                actionMenuOverlay(preferences: preferences)
            }
            .swipeBack(
                enabled: !viewModel.showShareSheet
                    && !isPresentingEdit
                    && selectedPlayMode == nil
                    && selectedPlayModeSettings == nil
                    && previewedCard == nil
                    && cardEditorDestination == nil
                    && !showConversionSheet
                    && unavailablePlayMode == nil
                    && activeActionMenuCardID == nil
            ) { dismiss() }
            .animation(.bottomChromeSpring, value: viewModel.isSelecting)
            .environment(scrollState)
            .overlay { unavailablePlayModeOverlay }
    }

    // MARK: Navigation Bar

    private var measuredNavigationBar: some View {
        unifiedNavigationBar
            .background {
                Color.clear
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { newHeight in
                        if abs(navigationBarHeight - newHeight) > 0.5 {
                            navigationBarHeight = newHeight
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.frame(in: .named(kDeckChromeSpace)).maxY
                    } action: { newBottom in
                        if abs(navigationBarBottomY - newBottom) > 0.5 {
                            navigationBarBottomY = newBottom
                        }
                    }
            }
    }

    private var unifiedNavigationBar: some View {
        DeckCustomNavigationBar(
            deck: deck,
            stats: viewModel.currentStats,
            backLabel: backLabel,
            searchQuery: searchQuery,
            isSelecting: viewModel.isSelecting,
            sortOrder: $viewModel.sortOrder,
            groupingMode: Binding(
                get: { viewModel.groupingMode },
                set: { newValue in
                    viewModel.updateGroupingMode(newValue, for: deck, context: context)
                }
            ),
            onBack: { dismiss() },
            onAdd: { showAddCardTypeDialog = true },
            onStartSelection: {
                withBottomChromeAnimation {
                    viewModel.enterSelectionMode()
                }
            },
            onConvert: { presentDeckConversion() },
            onExport: { viewModel.exportDeck(deck) }
        )
    }

    private var mainContentWithCovers: some View {
        mainContent
            .fullScreenSheet(
                ignoresSafeArea: true,
                isPresented: $isPresentingEdit,
                backgroundReceivesDragProgress: true
            ) { safeArea in
                CreateDeckView(deckToEdit: deck, safeAreaInsets: safeArea)
            } background: {
                CreateDeckSheetBackground()
            }
            .fullScreenSheet(
                ignoresSafeArea: true,
                item: $selectedPlayMode,
                backgroundReceivesDragProgress: true
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
                ignoresSafeArea: true,
                item: $selectedPlayModeSettings
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
                ignoresSafeArea: true,
                isPresented: $showConversionSheet,
                backgroundReceivesDragProgress: true
            ) { safeArea in
                DeckCardConversionSheetView(
                    viewModel: viewModel,
                    deck: deck,
                    safeAreaInsets: safeArea,
                    onDismiss: {
                        viewModel.dismissConversionSheet()
                    },
                    onOpenDestinationDeck: { destinationDeckID in
                        openConvertedDeck(destinationDeckID)
                    }
                )
            } background: {
                CardPreviewModeBackground()
            }
            .fullScreenSheet(
                ignoresSafeArea: true,
                item: $previewedCard,
                backgroundReceivesDragProgress: true,
                dragDismissActivationHeight: 180
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
    private var exportingOverlay: some View {
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

    private var mainContent: some View {
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
                                    isPresentingEdit = true
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

                        DeckMasteryRing(
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
                            summary: viewModel.readinessSummary,
                            onOpenRecommendedConversion: handleReadinessConversion(_:)
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
                            onOpenRecommendedConversion: { mode in
                                handlePlayModeRecommendedConversion(mode)
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
                    onDeleteCard: handleDeleteCard(_:),
                    onPresentActionMenu: presentActionMenu(for:),
                    onDismissActionMenu: dismissActiveActionMenu
                )
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background {
                Color(.systemGroupedBackground)

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
        .background(Color(.systemGroupedBackground))

        return scrollView
    }

    private func handleEditCard(_ gridCard: GridCardInfo) {
        dismissActiveActionMenu()
        if let model = context.model(for: gridCard.id) as? CardModel {
            presentCardEditor(for: model)
        }
    }

    private func handleTogglePinned(_ gridCard: GridCardInfo) {
        dismissActiveActionMenu()
        viewModel.togglePinnedState(for: gridCard.id, in: deck, context: context)
    }

    private func handleConvertCard(_ gridCard: GridCardInfo) {
        dismissActiveActionMenu()
        viewModel.presentSingleCardConversion(for: gridCard.id, in: deck)
        showConversionSheet = viewModel.conversionRequest != nil
    }

    private func handleReadinessConversion(_ targetKind: CardKind) {
        dismissActiveActionMenu()
        viewModel.presentReadinessConversion(for: targetKind, in: deck)
        showConversionSheet = viewModel.conversionRequest != nil
    }

    private func handlePreviewRecommendedConversion(
        for card: CardModel,
        targetKind: CardKind
    ) {
        previewedCard = nil
        viewModel.presentSingleCardConversion(
            for: card.persistentModelID,
            in: deck,
            preferredTargetKind: targetKind
        )
        Task { @MainActor in
            await Task.yield()
            showConversionSheet = viewModel.conversionRequest != nil
        }
    }

    private func handlePlayModeRecommendedConversion(_ mode: DeckPlayModeDestination) {
        dismissActiveActionMenu()

        switch mode {
        case .match:
            if viewModel.readinessSummary.recommendedConversions.contains(where: { $0.targetKind == .match }) {
                viewModel.presentReadinessConversion(for: .match, in: deck)
            } else {
                viewModel.presentDeckConversion(for: deck, preferredTargetKind: .match)
            }
        case .flashcards, .quiz, .learn, .write:
            return
        }

        showConversionSheet = viewModel.conversionRequest != nil
    }

    private func openPlayMode(_ mode: DeckPlayModeDestination) {
        dismissUnavailablePlayMode()
        selectedPlayMode = mode
    }

    private func presentUnavailablePlayMode(_ mode: DeckPlayModeDestination) {
        dismissActiveActionMenu()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            unavailablePlayMode = mode
        }
    }

    private func dismissUnavailablePlayMode() {
        guard unavailablePlayMode != nil else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.92)) {
            unavailablePlayMode = nil
        }
    }

    private func convertUnavailablePlayMode(_ mode: DeckPlayModeDestination) {
        dismissUnavailablePlayMode()
        guard let targetKind = mode.unavailableConversionTargetKind else { return }
        viewModel.presentDeckConversion(for: deck, preferredTargetKind: targetKind)
        showConversionSheet = viewModel.conversionRequest != nil
    }

    private func recordCompletedPlayModeSession(_ mode: DeckPlayModeDestination) {
        let settings = DeckPlayModeSettingsStore.resolve(for: deck, in: context)
        settings.markRecentlyUsed(mode)
    }

    private func refreshPlayModeRecentUsageSnapshot() {
        let settings = deck.playModeSettings
        playModeRecentUsageSnapshot = DeckPlayModeDestination.allCases.reduce(into: [:]) { result, mode in
            if let date = settings?.recentUsageDate(for: mode) {
                result[mode] = date
            }
        }
    }

    private func openConvertedDeck(_ destinationDeckID: PersistentIdentifier) {
        showConversionSheet = false
        viewModel.dismissConversionSheet()
        router.activeTab = ownerTab
        router.append(
            DeckNavigationValue(
                deckID: destinationDeckID,
                backLabel: deck.title
            )
        )
    }

    private func handleDeleteCard(_ gridCard: GridCardInfo) {
        dismissActiveActionMenu()
        pendingDeleteCardID = gridCard.id
    }

    private func presentCardEditor(for kind: CardKind) {
        showAddCardTypeDialog = false
        cardEditorDestination = .create(kind: kind)
    }

    private func presentCardEditor(for card: CardModel) {
        cardEditorDestination = .edit(DraftCard.from(card))
    }

    private func handleCardEditorSave(destination: CardEditorDestination, content: DraftCardContent) {
        switch destination {
        case .create, .createFromDraft:
            viewModel.addCard(content: content, to: deck, context: context)
        case .edit(let draftCard):
            guard let cardID = draftCard.originalCardID,
                  let card = context.model(for: cardID) as? CardModel else {
                cardEditorDestination = nil
                return
            }

            if card.cardContent != content {
                card.cardContent = content
                card.editedAt = Date()
                deck.editedAt = Date()
                try? context.save()
                viewModel.requestSnapshotLoad(
                    deckID: deck.persistentModelID,
                    container: context.container
                )
            }
        }

        cardEditorDestination = nil
    }

    private func presentDeckConversion() {
        dismissActiveActionMenu()
        viewModel.presentDeckConversion(for: deck)
        showConversionSheet = viewModel.conversionRequest != nil
    }

    private func presentSelectionConversion() {
        dismissActiveActionMenu()
        viewModel.presentSelectionConversion(for: deck)
        showConversionSheet = viewModel.conversionRequest != nil
    }

    private func presentActionMenu(for id: PersistentIdentifier) {
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.prepare()
        generator.impactOccurred(intensity: 0.9)
        withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
            activeActionMenuCardID = id
        }
    }

    private func dismissActiveActionMenu() {
        guard activeActionMenuCardID != nil else { return }
        withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
            activeActionMenuCardID = nil
        }
    }

    @ViewBuilder
    private func actionMenuOverlay(
        preferences: [PersistentIdentifier: Anchor<CGRect>]
    ) -> some View {
        GeometryReader { proxy in
            if let card = activeActionMenuCard,
               let anchor = preferences[card.id],
               !viewModel.isSelecting,
               !isSuspended {
                let rect = proxy[anchor]
                let menuWidth = DeckGridCardMetrics.headerMenuWidth
                let menuHeight = DeckGridCardMetrics.headerMenuHeight
                let floatingGap = DeckGridCardMetrics.headerMenuFloatingGap
                let horizontalClearance = DeckGridCardMetrics.headerMenuHorizontalClearance
                let topLimit = navigationBarBottomY + actionMenuTopClearance
                let bottomLimit = proxy.size.height - actionMenuBottomClearance
                let preferredX = rect.minX + DeckGridCardMetrics.sideInset
                let clampedX = min(
                    max(preferredX, horizontalClearance),
                    max(horizontalClearance, proxy.size.width - horizontalClearance - menuWidth)
                )
                let topY = rect.minY - menuHeight - floatingGap
                let bottomY = rect.maxY + floatingGap
                let topSpace = rect.minY - topLimit - floatingGap
                let bottomSpace = bottomLimit - rect.maxY - floatingGap
                let placement: ActionMenuPlacement =
                    (topSpace >= menuHeight || topSpace >= bottomSpace) ? .top : .bottom
                let clampedY = placement == .top
                    ? max(topLimit, topY)
                    : min(bottomY, max(topLimit, bottomLimit - menuHeight))
                let transitionAnchor = UnitPoint(
                    x: clampedX > preferredX ? 1 : 0,
                    y: placement == .top ? 1 : 0
                )

                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissActiveActionMenu()
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { _ in
                                dismissActiveActionMenu()
                            }
                    )
                    .zIndex(199)

                DeckGridHeaderActionMenu(
                    isPinned: card.isPinned,
                    accent: ThemeManager.shared.accentColor.color,
                    onTogglePinned: {
                        dismissActiveActionMenu()
                        handleTogglePinned(card)
                    },
                    onEdit: {
                        dismissActiveActionMenu()
                        handleEditCard(card)
                    },
                    onConvert: {
                        dismissActiveActionMenu()
                        handleConvertCard(card)
                    },
                    onDelete: {
                        dismissActiveActionMenu()
                        handleDeleteCard(card)
                    }
                )
                .offset(
                    x: clampedX,
                    y: clampedY
                )
                .transition(
                    .asymmetric(
                        insertion: .opacity
                            .combined(
                                with: .scale(
                                    scale: 0.84,
                                    anchor: transitionAnchor
                                )
                            ),
                        removal: .opacity
                            .combined(
                                with: .scale(
                                    scale: 0.94,
                                    anchor: transitionAnchor
                                )
                            )
                    )
                )
                .zIndex(200)
            }
        }
    }

    @ViewBuilder
    private var unavailablePlayModeOverlay: some View {
        if let unavailablePlayMode {
            let prompt = unavailablePlayMode.unavailablePrompt(in: viewModel.playModeAvailability)

            ZStack(alignment: .bottom) {
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissUnavailablePlayMode()
                    }
                    .transition(.opacity)

                PlayModeUnavailableCard(
                    mode: unavailablePlayMode,
                    prompt: prompt,
                    tintColor: unavailablePlayMode.tintColor(
                        deckColor: Color(hex: deck.colorHex) ?? ThemeManager.shared.accentColor.color,
                        accentColor: ThemeManager.shared.accentColor.color
                    ),
                    onConvert: prompt.actionTitle == nil
                        ? nil
                        : { convertUnavailablePlayMode(unavailablePlayMode) },
                    onDismiss: dismissUnavailablePlayMode
                )
                .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
                .padding(
                    .bottom,
                    UIConstants.Size.bottomChromeBarHeight
                        + UIConstants.Layout.bottomChromeBottomPadding
                        + UIConstants.Spacing.medium
                )
                .transition(
                    .opacity
                        .combined(with: .scale(scale: 0.94, anchor: .bottom))
                )
            }
            .zIndex(260)
        }
    }

    private enum ActionMenuPlacement {
        case top
        case bottom
    }

    private struct PlayModeUnavailableCard: View {
        let mode: DeckPlayModeDestination
        let prompt: PlayModeUnavailablePrompt
        let tintColor: Color
        let onConvert: (() -> Void)?
        let onDismiss: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
                HStack(alignment: .center, spacing: UIConstants.Spacing.medium) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(tintColor.opacity(0.16))
                        .frame(width: 54, height: 54)
                        .overlay {
                            Image(systemName: mode.systemImage)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(tintColor)
                        }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(prompt.title)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(prompt.detail)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: UIConstants.Spacing.small) {
                    Button("Not now", action: onDismiss)
                        .buttonStyle(.plain)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: UIConstants.Size.capsuleHeight)
                        .background(Color.white.opacity(0.05), in: Capsule())

                    if let onConvert, let actionTitle = prompt.actionTitle {
                        Button(actionTitle, action: onConvert)
                            .buttonStyle(.plain)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(tintColor)
                            .frame(maxWidth: .infinity)
                            .frame(height: UIConstants.Size.capsuleHeight)
                            .background(tintColor.opacity(0.12), in: Capsule())
                    }
                }
            }
            .padding(UIConstants.Spacing.large)
            .widgetStyle(cornerRadius: 30)
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
            }
        }
    }

    private struct DeckCardPreviewSheetView: View {
        let card: CardModel
        let safeAreaInsets: UIEdgeInsets
        let onOpenRecommendedConversion: (CardKind) -> Void

        @Environment(\.horizontalSizeClass) private var horizontalSizeClass

        @State private var showStats = false
        @Namespace private var statsTransition

        private var isCompact: Bool { horizontalSizeClass == .compact }

        var body: some View {
            GeometryReader { geo in
                let resolvedSafeBottomInset = max(safeAreaInsets.bottom, geo.safeAreaInsets.bottom)
                let horizontalInset = isCompact
                    ? UIConstants.Layout.compactScreenEdgeInset
                    : UIConstants.Layout.screenEdgeInset
                let panelWidth = min(
                    max(280, geo.size.width * (UIConstants.isPad ? 0.34 : 0.7)),
                    UIConstants.isPad ? 420 : 336
                )

                ZStack {
                    CardPreviewModeView(
                        content: card.cardContent,
                        safeAreaInsets: safeAreaInsets,
                        showsLeadingAccessory: true,
                        leadingAccessory: AnyView(statsButton),
                        onOpenRecommendedConversion: onOpenRecommendedConversion
                    )

                    if showStats {
                        Color.black.opacity(0.16)
                            .ignoresSafeArea()
                            .onTapGesture { closeStats() }
                        statsSurface(width: panelWidth)
                            .padding(.trailing, horizontalInset)
                            .padding(.bottom, resolvedSafeBottomInset + UIConstants.Spacing.large)
                    }
                }
                .animation(.spring(response: 0.38, dampingFraction: 0.86), value: showStats)
            }
        }

        private var statsButton: some View {
            Button {
                if showStats {
                    closeStats()
                } else {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                        showStats = true
                    }
                }
            } label: {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: UIConstants.Size.actionIcon, weight: .bold))
                    .foregroundStyle(showStats ? .primary : .secondary)
            }
            .buttonStyle(.plain)
        }

        @ViewBuilder
        private func statsSurface(width: CGFloat) -> some View {
            CardStatsView(card: card, onClose: closeStats)
                .frame(width: width)
                .matchedGeometryEffect(id: "preview.stats.surface", in: statsTransition, anchor: .bottomTrailing)
                .transition(.identity)
                .zIndex(2)
        }

        private func closeStats() {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                showStats = false
            }
        }
    }

    private struct CardStatsView: View {
        let card: CardModel
        let onClose: () -> Void

        var totalReviews: Int { card.reviewHistory.count }
        var correctReviews: Int { card.reviewHistory.filter { $0.difficultyRaw >= ReviewDifficulty.good.rawValue }.count }
        var accuracy: Int {
            guard totalReviews > 0 else { return 0 }
            return Int((Double(correctReviews) / Double(totalReviews)) * 100)
        }
        var totalXPEarned: Int { card.reviewHistory.reduce(0) { $0 + $1.xpAwarded } }
        private static let dueDateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.setLocalizedDateFormatFromTemplate("d MMM")
            return formatter
        }()

        var body: some View {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 40, height: 4)
                    .accessibilityHidden(true)
                    .frame(maxWidth: .infinity)

                HStack(alignment: .top, spacing: UIConstants.Spacing.standard) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Spaced Repetition Stats")
                            .font(.system(size: 20, weight: .black, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("Live card memory and schedule snapshot")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.primary)
                            .frame(width: 42, height: 42)
                            .glassButton(shape: .circle)
                    }
                    .buttonStyle(.plain)
                }

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                    spacing: 12
                ) {
                    StatMetricTile(icon: "arrow.2.squarepath", value: "\(totalReviews)", label: "Reviews", color: .blue)
                    StatMetricTile(icon: "target", value: "\(accuracy)%", label: "Accuracy", color: .green)
                    StatMetricTile(icon: "sparkles", value: "\(totalXPEarned)", label: "XP", color: .yellow)
                    StatMetricTile(icon: "brain.head.profile", value: String(format: "%.1f", card.easeFactor), label: "Ease", color: .purple)
                    StatMetricTile(icon: "calendar.badge.clock", value: "\(card.interval)d", label: "Interval", color: .orange)
                    StatMetricTile(icon: "clock", value: dateString(card.dueDate), label: "Due", color: card.dueDate <= Date() ? .red : .primary)
                }
            }
            .padding(20)
            .widgetStyle(cornerRadius: 30)
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
        }

        private func dateString(_ date: Date) -> String {
            Self.dueDateFormatter.string(from: date)
        }
    }

    private struct StatMetricTile: View {
        let icon: String
        let value: String
        let label: String
        var color: Color = .primary

        var body: some View {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(color)
                    .frame(width: 24, height: 24)
                Text(value)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(label.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }
}


// MARK: - iOS 17 Retain Cycle Wrapper

struct DeckView: View {
    let deck: DeckModel
    let searchQuery: String?
    let backLabel: String
    let ownerTab: AppTabBar

    @State private var viewModel: DeckViewModel? = nil

    init(deck: DeckModel, searchQuery: String? = nil, backLabel: String, ownerTab: AppTabBar) {
        self.deck = deck
        self.searchQuery = searchQuery
        self.backLabel = backLabel
        self.ownerTab = ownerTab
    }

    var body: some View {
        Group {
            if let vm = viewModel {
                DeckContentView(
                    deck: deck,
                    searchQuery: searchQuery,
                    ownerTab: ownerTab,
                    backLabel: backLabel,
                    viewModel: vm
                )
            } else {
                Color(.systemGroupedBackground)
                    .onAppear {
                        if self.viewModel == nil {
                            self.viewModel = DeckViewModel(searchQuery: searchQuery)
                        }
                    }
            }
        }
    }
}
