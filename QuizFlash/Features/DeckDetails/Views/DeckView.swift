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

/// Threshold scroll distance before the compact navigation pill fades in.
private let kHeroCollapseDistance: CGFloat = 10

struct DeckContentView: View {
    @Environment(\.modelContext) var context

    @Environment(NavigationManager.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Bindable var deck: DeckModel
    let searchQuery: String?

    // The back-button label frozen at push time via DeckNavigationValue.
    // Never read from router state — immune to cross-tab mutation.
    let backLabel: String

    @State private var isAddingCard = false
    @State private var isPresentingEdit = false
    @State private var isPlayingQuiz = false
    @State private var previewedCard: CardModel? = nil
    @State private var editingCard: CardModel? = nil
    @Bindable var viewModel: DeckViewModel
    @State private var isMenuExpanded: Bool = false
    @State private var menuPosition: CGRect = .zero
    @State private var menuTracker = MenuPositionTracker()

    /// Scroll-driven progress — updated by DeckScrollMonitor via KVO, never by SwiftUI state.
    @State private var scrollState = DeckScrollState()

    /// View-level safe-area bottom inset.
    @State private var viewSafeBottom: CGFloat = 0

    /// Physical screen safe-area bottom inset.
    @State private var physicalSafeBottom: CGFloat = 0

    /// Extra height that TabView adds to the safe area for its native UITabBar.
    private var tabBarOffset: CGFloat {
        max(0, viewSafeBottom - physicalSafeBottom)
    }

    @Query private var userProfiles: [UserProfile]
    private var userProfile: UserProfile? { userProfiles.first }

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

    // MARK: - Body

    var body: some View {
        deckContent
        /// Hides the native system navigation bar.
        /// This stabilizes `safeAreaInsets` and prevents layout invalidation during scroll physics (rubber-banding).
        .toolbar(.hidden, for: .navigationBar)
            .customTabBarVisibility(viewModel.isSelecting ? .hidden : .implicit)
            .onAppear {
            Task {
                await viewModel.loadSnapshot(
                    deckID: deck.persistentModelID,
                    container: context.container
                )
            }
        }
            .onDisappear {
            viewModel.tearDown()
            ImageCache.shared.clearCache()
            MathWebViewPool.shared.flush()
        }
            .onChange(of: isPlayingQuiz) { old, new in
            if old == true && new == false { viewModel.savedScrollOffset = 1 }
        }
            .onChange(of: isPresentingEdit) { old, new in
            if old == true && new == false { viewModel.savedScrollOffset = 1 }
        }
            .onChange(of: deck.cardCount) {
            Task {
                await viewModel.loadSnapshot(deckID: deck.persistentModelID, container: context.container)
                viewModel.savedScrollOffset = 1
            }
        }
            .onChange(of: viewModel.sortOrder) {
            Task { await viewModel.loadSnapshot(deckID: deck.persistentModelID, container: context.container) }
        }
            .onChange(of: viewModel.searchQuery) {
            Task { await viewModel.loadSnapshot(deckID: deck.persistentModelID, container: context.container) }
        }
            .alert(
            "Delete \(viewModel.selectedCards.count) card\(viewModel.selectedCards.count == 1 ? "" : "s")?",
            isPresented: $viewModel.showDeleteConfirmation
        ) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    viewModel.deleteSelectedCards(from: deck, context: context)
                }
            }
        } message: { Text("This action cannot be undone.") }
            .sheet(isPresented: $viewModel.showShareSheet) {
            if let url = viewModel.exportedURL { ShareSheet(items: [url]) }
        }
            .alert("Export Error", isPresented: $viewModel.showExportError) {
            Button("OK", role: .cancel) { }
        } message: { Text(viewModel.exportErrorMessage) }
            .overlay { exportingOverlay }
    }

    // MARK: - Body Fragments

    private var deckContent: some View {
        ZStack(alignment: .bottom) {
            mainContentWithCovers
            if viewModel.isSelecting {
                DeckSelectionBottomBar(
                    selectedCount: viewModel.selectedCards.count,
                    onDone: viewModel.exitSelectionMode,
                    onDelete: { viewModel.showDeleteConfirmation = true }
                )
                    .padding(.bottom, -tabBarOffset)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(10)
            }
        }
            .overlay(alignment: .top) { unifiedNavigationBar }
            .overlay(alignment: .topLeading) { menuOverlay }
            .swipeBack { dismiss() }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.isSelecting)
            .environment(scrollState)
            .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                    viewSafeBottom = geo.safeAreaInsets.bottom
                    physicalSafeBottom = UIApplication.shared
                        .connectedScenes
                        .compactMap { $0 as? UIWindowScene }
                        .first?.windows
                        .first(where: { $0.isKeyWindow })?
                        .safeAreaInsets.bottom ?? 0
                }
                    .onChange(of: geo.safeAreaInsets.bottom) { _, v in
                    viewSafeBottom = v
                    physicalSafeBottom = UIApplication.shared
                        .connectedScenes
                        .compactMap { $0 as? UIWindowScene }
                        .first?.windows
                        .first(where: { $0.isKeyWindow })?
                        .safeAreaInsets.bottom ?? 0
                }
            }
        }
    }

    // MARK: Navigation Bar

    private var unifiedNavigationBar: some View {
        DeckCustomNavigationBar(
            deck: deck,
            stats: viewModel.currentStats,
            backLabel: backLabel,
            searchQuery: searchQuery,
            isSelecting: viewModel.isSelecting,
            isMenuExpanded: $isMenuExpanded,
            menuPosition: $menuPosition,
            menuTracker: menuTracker,
            onBack: { dismiss() },
            onAdd: { isAddingCard = true },
            onStartSelection: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    viewModel.isSelecting = true
                }
            },
            onExport: { viewModel.exportDeck(deck) }
        )
    }

    private var actionButtonsOverlay: some View {
        DeckActionOverlay(
            deck: deck,
            isSelecting: viewModel.isSelecting,
            isMenuExpanded: $isMenuExpanded,
            menuPosition: $menuPosition,
            menuTracker: menuTracker,
            onAdd: { isAddingCard = true },
            onStartSelection: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    viewModel.isSelecting = true
                }
            },
            onExport: { viewModel.exportDeck(deck) }
        )
    }

    private var mainContentWithCovers: some View {
        mainContent
            .fullScreenCover(isPresented: $isAddingCard) {
            CreateCardView(searchQuery: nil) { frontZone, backZone in
                deck.lastAssignedCardNumber += 1
                let newCard = CardModel(
                    frontZone: frontZone,
                    backZone: backZone,
                    cardNumber: deck.lastAssignedCardNumber
                )
                newCard.deck = deck
                context.insert(newCard)
                deck.cardCount += 1
                try? context.save()
                deck.editedAt = Date()
            }
        }
            .fullScreenCover(isPresented: $isPresentingEdit) {
            NavigationStack { CreateDeckView(deckToEdit: deck) }
        }
            .fullScreenCover(isPresented: $isPlayingQuiz, onDismiss: {
            deck.lastOpenedAt = Date()
            try? context.save()
            Task { await viewModel.loadSnapshot(deckID: deck.persistentModelID, container: context.container) }
        }) {
            NavigationStack { DefaultModePlay(deck: deck) }
        }
            .fullScreenSheet(
                ignoresSafeArea: true,
                item: $previewedCard,
                dragDismissActivationHeight: 180
            ) { card, safeArea in
                DeckCardPreviewSheetView(card: card, safeAreaInsets: safeArea)
            } background: {
                CardPreviewModeBackground()
            }
            .fullScreenCover(item: $editingCard) { card in
            NavigationStack {
                CreateCardView(
                    frontZone: card.frontZone,
                    backZone: card.backZone,
                    searchQuery: viewModel.searchQuery
                ) { frontZone, backZone in
                    if card.frontZone != frontZone || card.backZone != backZone {
                        card.frontZone = frontZone
                        card.backZone = backZone
                        card.editedAt = Date()
                        deck.editedAt = Date()
                        try? context.save()
                        Task { await viewModel.loadSnapshot(deckID: deck.persistentModelID, container: context.container) }
                    }
                    editingCard = nil
                }
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
        /// Wraps the scrollable content in a `GeometryReader` for synchronous layout calculation.
        /// Combined with the hidden native toolbar, this guarantees a stable environment from frame zero.
        GeometryReader { outer in
            let safeTop = outer.safeAreaInsets.top == 0 ? 47.0 : outer.safeAreaInsets.top

            ScrollView {
                VStack(spacing: 0) {

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
                                        Image(systemName: "pencil")
                                            .font(.system(size: UIConstants.Size.actionIcon, weight: .bold))
                                            .foregroundStyle(.secondary.opacity(0.8))
                                            .frame(width: UIConstants.Size.actionButton, height: UIConstants.Size.actionButton)
                                            .glassButton(shape: .circle)
                                    }
                                        .buttonStyle(.plain)
                                }

                                Text(subtitleText)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                            }

                            Spacer(minLength: 0)

                            DeckMasteryRing(
                                mastery: viewModel.currentStats.deckMastery,
                                deckColor: Color(hex: deck.colorHex) ?? .blue,
                                size: 76,
                                strokeWidth: 9
                            )
                        }
                            .padding(.horizontal, UIConstants.Layout.heroScreenEdgeInset)
                        /// Compensates for the safe area space removed by `.toolbar(.hidden, for: .navigationBar)`.
                        .padding(.top, UIConstants.Layout.deckHeroTopPadding)

                        Color.clear
                            .frame(height: 1)
                            .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.frame(in: .global).minY
                        } action: { minY in
                            let isAbove = minY < safeTop
                            if scrollState.pillVisible != isAbove {
                                scrollState.pillVisible = isAbove
                            }
                        }

                        if searchQuery == nil || searchQuery?.isEmpty == true {
                            DeckProgressView(
                                progress: viewModel.progressStats,
                                stats: viewModel.currentStats,
                                deckCardCount: deck.cardCount
                            )
                            DeckPlayModesView(deck: deck, onPlay: { isPlayingQuiz = true })
                                .padding(.top, 16)
                        }

                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                            Section {
                                Color.clear.frame(height: 4)
                                DeckCardGridView(
                                    cards: viewModel.cachedGroupedCards,
                                    isSelecting: viewModel.isSelecting,
                                    selectedCards: viewModel.selectedCards,
                                    onToggleSelection: { gridCard in viewModel.toggleSelection(for: gridCard.id) },
                                    onTapCard: { gridCard in
                                        if viewModel.isSelecting {
                                            viewModel.toggleSelection(for: gridCard.id)
                                        } else if searchQuery != nil {
                                            if let model = context.model(for: gridCard.id) as? CardModel { editingCard = model }
                                        } else {
                                            if let model = context.model(for: gridCard.id) as? CardModel { previewedCard = model }
                                        }
                                    },
                                    onLongPressCard: { gridCard in
                                        if viewModel.isSelecting {
                                            viewModel.toggleSelection(for: gridCard.id)
                                        } else {
                                            if let model = context.model(for: gridCard.id) as? CardModel { editingCard = model }
                                        }
                                    },
                                    onDeleteCard: { gridCard in
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                            viewModel.deleteSingleCard(id: gridCard.id, from: deck, context: context)
                                        }
                                    }
                                )
                                Color.clear.frame(height: 120)
                            }
                        }

                    }
                        .contentShape(Rectangle())
                        .onTapGesture {
                        if viewModel.isSelecting { viewModel.exitSelectionMode() }
                    }
                        .frame(minHeight: outer.size.height)
                }
            }
                .scrollIndicators(.hidden)
                .scrollDisabled(isMenuExpanded)
                .background(Color(.systemGroupedBackground))
        }
    }

    // MARK: - Menu Overlay


    @ViewBuilder
    private var menuOverlay: some View {
        GeometryReader { proxy in
            let screenHeight = proxy.size.height
            let spaceBelow = screenHeight - menuPosition.maxY
            let placeAbove = spaceBelow < 340

            ZStack(alignment: placeAbove ? .bottomTrailing : .topTrailing) {
                Rectangle()
                    .foregroundStyle(.clear)
                    .contentShape(.rect)
                    .onTapGesture {
                    withAnimation(.snappy(duration: 0.3, extraBounce: 0)) {
                        isMenuExpanded = false
                    }
                }
                    .allowsHitTesting(isMenuExpanded)

                if isMenuExpanded {
                    VisionOSStyleView(cornerRadius: 24) {
                        DeckMenuControls(
                            deck: deck,
                            isSelecting: viewModel.isSelecting,
                            sortOrder: $viewModel.sortOrder,
                            isExpanded: $isMenuExpanded,
                            onStartSelection: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    viewModel.isSelecting = true
                                }
                            },
                            onExport: { viewModel.exportDeck(deck) }
                        )
                            .frame(width: 240)
                    }
                        .transition(.blurReplace)
                        .padding(placeAbove ? .bottom : .top, placeAbove ? (screenHeight - menuPosition.minY + 12) : (menuPosition.maxY + 12))
                        .padding(.trailing, proxy.size.width - menuPosition.maxX)
                }
            }
        }
            .ignoresSafeArea()
    }

    // MARK: - Subviews

    private struct DeckCardPreviewSheetView: View {
        let card: CardModel
        let safeAreaInsets: UIEdgeInsets

        @Environment(\.dismiss) private var dismiss
        @Environment(\.fullScreenSheetDismiss) private var fullScreenSheetDismiss
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
        @Environment(\.colorScheme) private var colorScheme

        @State private var isFlipped = false
        @State private var topChromeHeight: CGFloat = 0
        @State private var showStats = false
        @Namespace private var statsTransition

        private var isCompact: Bool { horizontalSizeClass == .compact }
        private var accent: Color { ThemeManager.shared.accentColor.color }
        private var chromeButtonHeight: CGFloat {
            UIConstants.Size.capsuleHeight
        }
        private var leadingChromeWidth: CGFloat {
            isCompact ? 160 : 188
        }

        var body: some View {
            GeometryReader { geo in
                let isLandscape = geo.size.width > geo.size.height
                let resolvedSafeTopInset = max(safeAreaInsets.top, geo.safeAreaInsets.top)
                let resolvedSafeBottomInset = max(safeAreaInsets.bottom, geo.safeAreaInsets.bottom)
                let horizontalInset = isCompact
                    ? UIConstants.Layout.compactScreenEdgeInset
                    : UIConstants.Layout.screenEdgeInset
                let cardHorizontalInset = isCompact
                    ? UIConstants.Spacing.standard
                    : (isLandscape ? geo.size.width * 0.15 : 40)
                let cardTopInset = topChromeHeight + UIConstants.Spacing.medium
                let cardBottomInset = max(resolvedSafeBottomInset, UIConstants.Spacing.standard)
                let availableCardHeight = max(
                    UIConstants.Size.cardMinHeight,
                    geo.size.height - cardTopInset - cardBottomInset
                )
                let panelWidth = min(
                    max(280, geo.size.width * (UIConstants.isPad ? 0.34 : 0.7)),
                    UIConstants.isPad ? 420 : 336
                )

                ZStack {
                    if fullScreenSheetDismiss == nil {
                        CardPreviewModeBackground()
                            .ignoresSafeArea()
                    }

                    FlipCard(
                        frontZone: card.frontZone,
                        backZone: card.backZone,
                        isFlipped: $isFlipped
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: availableCardHeight)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.interactiveSpring(response: 0.45, dampingFraction: 0.85)) {
                            isFlipped.toggle()
                        }
                    }
                    .padding(.top, cardTopInset)
                    .padding(.horizontal, cardHorizontalInset)
                    .padding(.bottom, cardBottomInset)

                    if showStats {
                        Color.black.opacity(0.16)
                            .ignoresSafeArea()
                            .onTapGesture { closeStats() }
                    }
                }
                .overlay(alignment: .top) {
                    previewChrome(
                        safeTopInset: resolvedSafeTopInset,
                        horizontalInset: horizontalInset
                    )
                }
                .overlay(alignment: .bottomTrailing) {
                    if showStats {
                        statsSurface(width: panelWidth)
                            .padding(.trailing, horizontalInset)
                            .padding(.bottom, resolvedSafeBottomInset + UIConstants.Spacing.large)
                    }
                }
                .fullScreenSheetDragActivationHeight(cardTopInset)
                .animation(.spring(response: 0.38, dampingFraction: 0.86), value: showStats)
            }
        }

        private func previewChrome(safeTopInset: CGFloat, horizontalInset: CGFloat) -> some View {
            VStack(spacing: UIConstants.Spacing.small) {
                Capsule()
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.2 : 0.35))
                    .frame(width: 56, height: 5)
                    .accessibilityHidden(true)

                ZStack {
                    VStack(spacing: 2) {
                        Text("Preview Mode")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        faceLabel
                    }

                    HStack {
                        statsButton
                            .frame(width: leadingChromeWidth, alignment: .leading)

                        Spacer(minLength: 0)

                        doneButton
                            .frame(width: chromeButtonHeight, alignment: .trailing)
                    }
                }
                .frame(height: chromeButtonHeight)
            }
            .padding(.top, safeTopInset + UIConstants.Spacing.tiny)
            .padding(.horizontal, horizontalInset)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { newHeight in
                if abs(topChromeHeight - newHeight) > 0.5 {
                    topChromeHeight = newHeight
                }
            }
        }

        private var faceLabel: some View {
            Text(isFlipped ? "ANSWER" : "QUESTION")
                .font(.system(size: UIConstants.Size.navigationChromeLabel, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
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

        private var doneButton: some View {
            Button(action: closePreview) {
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(accent)
                    .frame(width: chromeButtonHeight, height: chromeButtonHeight)
                    .glassButton(shape: .circle)
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

        private func closePreview() {
            if let fullScreenSheetDismiss {
                fullScreenSheetDismiss()
            } else {
                dismiss()
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

    @State private var viewModel: DeckViewModel? = nil

    init(deck: DeckModel, searchQuery: String? = nil, backLabel: String) {
        self.deck = deck
        self.searchQuery = searchQuery
        self.backLabel = backLabel
    }

    var body: some View {
        Group {
            if let vm = viewModel {
                DeckContentView(deck: deck, searchQuery: searchQuery, backLabel: backLabel, viewModel: vm)
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
