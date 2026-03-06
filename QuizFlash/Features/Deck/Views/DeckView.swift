//
//  DeckView.swift
//  QuizFlash
//

import SwiftUI
import SwiftData

private let kHeroCollapseDistance: CGFloat = 10

struct DeckContentView: View {
    @Environment(\.modelContext) var context

    @Environment(NavigationManager.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Bindable var deck: DeckModel
    let searchQuery: String?

    @State private var isAddingCard = false
    @State private var isPresentingEdit = false
    @State private var isPlayingQuiz = false
    @State private var previewedCard: CardModel? = nil
    @State private var editingCard: CardModel? = nil
    @Bindable var viewModel: DeckViewModel
    @State private var isMenuExpanded: Bool = false
    @State private var menuPosition: CGRect = .zero
    @State private var menuTracker = MenuPositionTracker()
    /// Scroll-driven progress — updated by DeckScrollMonitor via KVO, never by SwiftUI state
    @State private var scrollState = DeckScrollState()

    /// View-level safe-area bottom (from SwiftUI GeometryReader inside the ZStack).
    /// Inside TabView this includes UITabBar.height (~49 pt) on top of the physical
    /// home-indicator inset, even when the tab bar is hidden via NativeTabBarConfigurator.
    @State private var viewSafeBottom: CGFloat = 0

    /// Physical screen safe-area bottom read directly from UIWindow.
    /// Always equals only the home-indicator inset (~34 pt) — never inflated by the tab bar.
    @State private var physicalSafeBottom: CGFloat = 0

    /// Extra height that TabView adds to the safe area for its native UITabBar.
    /// When the tab bar is hidden (selection mode), this offset remains until the async
    /// safe-area recalculation completes. Applying -tabBarOffset as bottom padding on
    /// DeckSelectionBottomBar moves it down to the correct physical position immediately.
    private var tabBarOffset: CGFloat {
        max(0, viewSafeBottom - physicalSafeBottom)
    }

    @Query private var userProfiles: [UserProfile]
    private var userProfile: UserProfile? { userProfiles.first }

    private var subtitleText: String {
        let f = DateFormatter()
        f.dateStyle = .medium; f.timeStyle = .none
        return "\(f.string(from: deck.createdAt))  •  \(deck.cardCount) cards"
    }

    // MARK: - Body

    var body: some View {
        deckContent
        // Hide the floating tab bar only while selection mode is active,
        // so it does not overlap DeckSelectionBottomBar.
        // In normal browsing the tab bar remains visible.
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

    /// Top-level ZStack with selection bar, menu overlay, and navigation chrome.
    /// Separated from `body` so the type-checker handles each expression independently.
    private var deckContent: some View {
        ZStack(alignment: .bottom) {
            mainContentWithCovers
            if viewModel.isSelecting {
                DeckSelectionBottomBar(
                    selectedCount: viewModel.selectedCards.count,
                    onDone: viewModel.exitSelectionMode,
                    onDelete: { viewModel.showDeleteConfirmation = true }
                )
                // TabView inflates the ZStack safe-area bottom by UITabBar.height
                // even while the bar is hidden. tabBarOffset = that extra inset.
                // Negative padding shifts the bar down to sit above the home indicator,
                // not above the phantom tab bar space.
                .padding(.bottom, -tabBarOffset)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        // A single unified overlay for the top navigation items
        .overlay(alignment: .top) { unifiedNavigationBar }
            .overlay(alignment: .topLeading) { menuOverlay } // Dropdown menu remains separate Z-layer
        .swipeBack { dismiss() }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.isSelecting)
            .environment(scrollState)
            .background {
            // Capture safe-area insets for tabBarOffset computation.
            // GeometryReader inside .background reads the ZStack's coordinate space,
            // which includes the TabView-injected UITabBar inset in .bottom.
            // UIWindow is queried separately for the physical-only inset.
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
            backLabel: router.deckBackLabel,
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


    // MARK: - Back Button

    private var backButtonOverlay: some View {
        Button { dismiss() } label: {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                Text(router.deckBackLabel)
                    .font(.system(size: 13, weight: .semibold))
            }
                .foregroundStyle(ThemeManager.shared.accentColor.color)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(height: 50)
                .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay {
                    // glow dark foarte subtil pentru adâncime
                    Capsule()
                        .fill(Color.white.opacity(0.35))
                        .blur(radius: 10)
                        .mask(
                        Capsule()
                            .stroke(lineWidth: 4)
                    )
                        .blendMode(.overlay)
                }
            }

        }
            .buttonStyle(.plain)
            .padding(.leading, 16)
            .padding(.top, 8)
    }

    // MARK: - Action Buttons Overlay

    /// Top-trailing overlay providing the add (+) and menu (ellipsis) buttons.
    /// Symmetric counterpart to backButtonOverlay — same capsule style, same
    /// vertical alignment, positioned at the trailing edge instead of leading.
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

    /// `mainContent` plus all fullScreenCover presentations.
    /// Extracted so the type-checker does not have to process all five covers inside `body`.
    private var mainContentWithCovers: some View {
        mainContent
            .fullScreenCover(isPresented: $isAddingCard) {
            CreateCardView(searchQuery: nil) { frontZone, backZone in
                let newCard = CardModel(frontZone: frontZone, backZone: backZone)
                newCard.deck = deck
                context.insert(newCard)
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
            .fullScreenCover(item: $previewedCard) { CardPreviewScreen(card: $0) }
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
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color.accentColor.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                    }

                    VStack(spacing: 16) {

                        // MARK: - Premium Header Section
                        // Replace the existing header HStack inside DeckView's mainContent with this:

                        HStack(alignment: .center, spacing: 20) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .center, spacing: 12) {
                                    Text(deck.title)
                                    // Using a larger, heavier font for that premium modern iOS feel
                                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.7)

                                    // Edit affordance promoted to a subtle, yet tap-friendly circular button
                                    Button {
                                        isPresentingEdit = true
                                    } label: {
                                        Image(systemName: "pencil")
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundStyle(.secondary.opacity(0.8))
                                            .padding(10)
                                            .background(.ultraThinMaterial, in: Circle())
                                    }
                                        .buttonStyle(.plain)
                                }

                                Text(subtitleText)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase) // Uppercase for modern subtitling (like the reference app)
                            }

                            Spacer(minLength: 0)

                            // Slightly larger mastery ring to balance the bigger typography
                            DeckMasteryRing(
                                mastery: viewModel.currentStats.deckMastery,
                                deckColor: Color(hex: deck.colorHex) ?? .blue,
                                size: 76,
                                strokeWidth: 9
                            )
                        }
                            .padding(.horizontal, 24) // Increased horizontal padding for a spacious look
                        .padding(.top, 100) // Adjusted top padding to breathe under the navigation chrome

                        // Invisible anchor — when this crosses safeAreaTop, pill appears
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
                            DeckProgressView(deck: deck, stats: viewModel.currentStats, cards: viewModel.allCardInfos)
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
                            } header: {
                                // Simplified to label-only. Action buttons (+, ellipsis)
                                // are now rendered via the topTrailing overlay so they
                                // remain accessible regardless of scroll position.
                                DeckSectionToolbar(
                                    deck: deck,
                                    pillVisible: scrollState.pillVisible
                                )
                                    .background(Color(uiColor: .systemGroupedBackground))
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
                .background(Color(uiColor: .systemGroupedBackground))
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

    private struct CardPreviewScreen: View {
        let card: CardModel
        @State private var showStats = false
        @Environment(\.dismiss) var dismiss

        var body: some View {
            ZStack {
                CardPreviewModeView(
                    front: ZoneCardContent(rootZone: card.frontZone),
                    back: ZoneCardContent(rootZone: card.backZone)
                )
            }
                .overlay(alignment: .bottom) {
                if showStats {
                    CardStatsView(card: card)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
                .overlay(alignment: .bottomTrailing) {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showStats.toggle()
                    }
                } label: {
                    Image(systemName: "info.circle")
                        .font(.title3.bold())
                        .padding()
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    private struct CardStatsView: View {
        let card: CardModel
        var totalReviews: Int { card.reviewHistory.count }
        var correctReviews: Int { card.reviewHistory.filter { $0.difficultyRaw >= ReviewDifficulty.good.rawValue }.count }
        var accuracy: Int {
            guard totalReviews > 0 else { return 0 }
            return Int((Double(correctReviews) / Double(totalReviews)) * 100)
        }
        var totalXPEarned: Int { card.reviewHistory.reduce(0) { $0 + $1.xpAwarded } }

        var body: some View {
            VStack(spacing: 16) {
                Text("Spaced Repetition Stats").font(.headline.bold())
                HStack(spacing: 24) {
                    StatIconItem(icon: "arrow.2.squarepath", value: "\(totalReviews)", label: "Reviews", color: .blue)
                    StatIconItem(icon: "target", value: "\(accuracy)%", label: "Accuracy", color: .green)
                    StatIconItem(icon: "sparkles", value: "\(totalXPEarned)", label: "XP", color: .yellow)
                }
                Divider()
                HStack(spacing: 24) {
                    StatIconItem(icon: "brain.head.profile", value: String(format: "%.1f", card.easeFactor), label: "Ease", color: .purple)
                    StatIconItem(icon: "calendar.badge.clock", value: "\(card.interval)d", label: "Interval", color: .orange)
                    StatIconItem(icon: "clock", value: dateString(card.dueDate), label: "Due", color: card.dueDate <= Date() ? .red : .primary)
                }
            }
                .padding(20)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
                .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
                .padding()
        }

        private func dateString(_ date: Date) -> String {
            let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .none
            return f.string(from: date)
        }
    }

    private struct StatIconItem: View {
        let icon: String; let value: String; let label: String
        var color: Color = .primary
        var body: some View {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.title2).foregroundStyle(color)
                Text(value).font(.headline.bold())
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}


// MARK: - iOS 17 Retain Cycle Wrapper

struct DeckView: View {
    let deck: DeckModel
    let searchQuery: String?

    @State private var viewModel: DeckViewModel? = nil

    init(deck: DeckModel, searchQuery: String? = nil) {
        self.deck = deck
        self.searchQuery = searchQuery
    }

    var body: some View {
        Group {
            if let vm = viewModel {
                DeckContentView(deck: deck, searchQuery: searchQuery, viewModel: vm)
            } else {
                Color(uiColor: .systemGroupedBackground)
                    .onAppear {
                    if self.viewModel == nil {
                        self.viewModel = DeckViewModel(searchQuery: searchQuery)
                    }
                }
            }
        }
    }
}
