//
//  DeckView.swift
//  QuizFlash
//
//  Key fix: Replaced UIViewRepresentable ScrollOffsetReader with the native
//  iOS 17 `onScrollGeometryChange` modifier. This eliminates the UIKit bridge
//  entirely, runs on the scroll thread (not the main queue), and never triggers
//  a full view-tree re-evaluation.
//

import SwiftUI
import SwiftData

// MARK: - Collapse distance constant (shared with DeckHeroView if needed)
private let kHeroCollapseDistance: CGFloat = 200

struct DeckView: View {
    @Environment(\.modelContext) var context
    @Environment(NavigationManager.self) private var router
    @Bindable var deck: DeckModel
    let searchQuery: String?

    @State private var isAddingCard = false
    @State private var isPresentingEdit = false
    @State private var isPlayingQuiz = false
    @State private var previewedCard: CardModel? = nil
    @State private var editingCard: CardModel? = nil

    @State private var viewModel: DeckViewModel

    // ── Gamification data (read-only, written by DefaultModePlayViewModel) ──
    @Query private var activityLogs: [DailyActivityLog]
    @Query private var userProfiles: [UserProfile]
    private var userProfile: UserProfile? { userProfiles.first }

    init(deck: DeckModel, searchQuery: String? = nil) {
        self.deck = deck
        self.searchQuery = searchQuery
        _viewModel = State(initialValue: DeckViewModel(searchQuery: searchQuery))
    }

    // MARK: - Body
    var body: some View {
        ZStack(alignment: .bottom) {

            mainContent
                .fullScreenCover(isPresented: $isAddingCard) {
                CreateCardView(searchQuery: nil) { frontZone, backZone in
                    let newCard = CardModel(frontZone: frontZone, backZone: backZone)
                    deck.cards.append(newCard)
                    deck.editedAt = Date()
                    viewModel.updateGroupedCards(for: deck)
                }
            }
                .fullScreenCover(isPresented: $isPresentingEdit) {
                NavigationStack {
                    CreateDeckView(deckToEdit: deck, isTabBarHidden: .constant(true))
                }
            }
                .fullScreenCover(isPresented: $isPlayingQuiz, onDismiss: {
                deck.lastOpenedAt = Date()
                try? context.save()
                cachedStats = aggregateDeckStats(deck: deck, activityLogs: activityLogs)
            }) {
                NavigationStack {
                    DefaultModePlay(deck: deck)
                }
            }
                .fullScreenCover(item: $previewedCard) { card in
                CardPreviewScreen(card: card)
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
                            viewModel.updateGroupedCards(for: deck)
                        }
                        editingCard = nil
                    }
                }
            }

            // ── Bottom Selection Bar ───────────────────────────────────────
            if viewModel.isSelecting {
                DeckSelectionBottomBar(
                    selectedCount: viewModel.selectedCards.count,
                    onDone: viewModel.exitSelectionMode,
                    onDelete: { viewModel.showDeleteConfirmation = true }
                )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 20)
                    .zIndex(10)
            }
        }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.isSelecting)
            .onAppear {
            MathWebViewPool.shared.prewarm()
        }
        // MARK: - Dialogs & Sheets
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
        } message: {
            Text("This action cannot be undone.")
        }
            .sheet(isPresented: $viewModel.showShareSheet) {
            if let url = viewModel.exportedURL {
                ShareSheet(items: [url])
            }
        }
            .alert("Export Error", isPresented: $viewModel.showExportError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.exportErrorMessage)
        }
            .overlay {
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
    }

    // ── Memoized stats ───────────────────────────────────────────────────
    @State private var cachedStats: DeckStats?

    private var stats: DeckStats {
        cachedStats ?? aggregateDeckStats(deck: deck, activityLogs: activityLogs)
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {

                if searchQuery == nil {
                    DeckHeroView(
                        deck: deck,
                        stats: stats,
                        onEdit: { isPresentingEdit = true }
                    )
                        .zIndex(-1)
                }

                // ── Active Search Banner ─────────────────────────────────
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
                    if searchQuery == nil || searchQuery?.isEmpty == true {
                        DeckPlayModesView(deck: deck, onPlay: { isPlayingQuiz = true })
                            .padding(.top, 16)

                        DeckProgressView(
                            deck: deck,
                            stats: stats
                        )
                    }

                    DeckSectionToolbar(
                        deck: deck,
                        isSelecting: viewModel.isSelecting,
                        sortOrder: $viewModel.sortOrder,
                        onAdd: { isAddingCard = true },
                        onStartSelection: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                viewModel.isSelecting = true
                            }
                        },
                        onExport: { viewModel.exportDeck(deck) }
                    )

                    DeckCardGridView(
                        cards: viewModel.cachedGroupedCards,
                        isSelecting: viewModel.isSelecting,
                        selectedCards: viewModel.selectedCards,
                        onToggleSelection: viewModel.toggleSelection,
                        onTapCard: { card in
                            if viewModel.isSelecting {
                                viewModel.toggleSelection(for: card)
                            } else if searchQuery != nil {
                                editingCard = card
                            } else {
                                previewedCard = card
                            }
                        },
                        onLongPressCard: { card in
                            if viewModel.isSelecting {
                                viewModel.toggleSelection(for: card)
                            } else {
                                editingCard = card
                            }
                        },
                        onDeleteCard: { card in
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                viewModel.deleteSingleCard(card, from: deck, context: context)
                            }
                        }
                    )
                        .padding(.top, 4)
                        .padding(.bottom, 120)
                }
                    .contentShape(Rectangle())
                    .onTapGesture {
                    if viewModel.isSelecting { viewModel.exitSelectionMode() }
                }
            }
            // ─────────────────────────────────────────────────────────────
            // iOS 17 NATIVE SCROLL TRACKING — replaces ScrollOffsetReader.
            //
            // Why this is better:
            // • Runs on the scroll compositor thread, not the main queue.
            // • The `transform` closure is called per frame; the `action`
            //   closure is called only when the transformed value changes.
            // • Zero UIKit bridge overhead, zero Binding retention issues.
            // • Does NOT invalidate DeckView's body — only the action closure
            //   runs, which writes to the @Observable ViewModel.
            //   DeckView itself never reads collapseProgress, so only
            //   DeckTopBarView (the sole reader) re-renders.
            //
            // The `if #available` block provides an iOS 16 fallback via the
            // fixed ScrollOffsetReader below (closure-based, not Binding-based).
            // ─────────────────────────────────────────────────────────────
            .modifier(ScrollCollapseTracker(
                distance: kHeroCollapseDistance,
                disabled: searchQuery != nil,
                onProgress: { p in
                    if abs(viewModel.collapseProgress - p) > 0.005 {
                        viewModel.collapseProgress = p
                    }
                }
            ))
        }
            .coordinateSpace(name: "deckScroll")
            .safeAreaInset(edge: .top) {
            DeckTopBarView(
                deck: deck,
                stats: stats,
                viewModel: viewModel,
                searchQuery: searchQuery,
                onBack: { router.path.removeLast() },
                onEdit: { isPresentingEdit = true }
            )
        }
            .scrollIndicators(.hidden)
            .background(Color(uiColor: .systemGroupedBackground))
            .onAppear {
            cachedStats = aggregateDeckStats(deck: deck, activityLogs: activityLogs)
            viewModel.updateGroupedCards(for: deck)
        }
            .onChange(of: deck.cards.count) {
            cachedStats = aggregateDeckStats(deck: deck, activityLogs: activityLogs)
            viewModel.updateGroupedCards(for: deck)
        }
            .onChange(of: activityLogs.count) {
            cachedStats = aggregateDeckStats(deck: deck, activityLogs: activityLogs)
        }
            .onChange(of: viewModel.sortOrder) { _, _ in
            viewModel.updateGroupedCards(for: deck)
        }
            .onChange(of: viewModel.searchQuery) { _, _ in
            viewModel.updateGroupedCards(for: deck)
        }
    }

    // MARK: - Additional Subviews (unchanged)
    private struct CardPreviewScreen: View {
        let card: CardModel
        @State private var showStats: Bool = false
        @Environment(\.dismiss) var dismiss

        var body: some View {
            let front = ZoneCardContent(rootZone: card.frontZone)
            let back = ZoneCardContent(rootZone: card.backZone)

            ZStack {
                CardPreviewModeView(front: front, back: back)
            }
                .overlay(alignment: .bottom) {
                if showStats {
                    CardStatsView(card: card)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
                .overlay(alignment: .bottomTrailing) {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { showStats.toggle() }
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
                Text("Spaced Repetition Stats")
                    .font(.headline.bold())

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
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }

    private struct StatIconItem: View {
        let icon: String
        let value: String
        let label: String
        var color: Color = .primary

        var body: some View {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                Text(value)
                    .font(.headline.bold())
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private struct DeckStatsView: View {
        let stats: DeckStats

        var body: some View {
            HStack(spacing: 20) {
                StatIconItem(icon: "rectangle.stack.fill", value: "\(stats.totalCards)", label: "Cards", color: .blue)
                StatIconItem(icon: "exclamationmark.circle.fill", value: "\(stats.dueCards)", label: "Due Now", color: stats.dueCards > 0 ? .red : .gray)
                StatIconItem(icon: "target", value: "\(stats.accuracy)%", label: "Accuracy", color: .green)
                StatIconItem(icon: "star.fill", value: "\(stats.totalXPEarned)", label: "XP", color: .yellow)
            }
                .padding(.vertical, 8)
        }
    }
}

// MARK: - ScrollCollapseTracker ViewModifier
//
// Single entry point that picks the right implementation based on OS version.
// Keep this in DeckView.swift so the constant `kHeroCollapseDistance` is shared.

private struct ScrollCollapseTracker: ViewModifier {
    let distance: CGFloat
    let disabled: Bool
    let onProgress: @MainActor (CGFloat) -> Void

    func body(content: Content) -> some View {
        if disabled {
            // Search mode: hero is always collapsed, no tracking needed.
            content
        } else if #available(iOS 18, *) {
            content
                // `onScrollGeometryChange` fires on the render server, not the
                // main thread, so it cannot cause a main-queue callback storm.
                // The `transform` closure extracts a single CGFloat; the
                // `action` closure is called ONLY when that value changes,
                // which eliminates redundant SwiftUI state writes.
                .onScrollGeometryChange(for: CGFloat.self) { geo in
                    geo.contentOffset.y + geo.contentInsets.top
                } action: { _, newOffset in
                    let p = min(max(newOffset / distance, 0), 1.0)
                    if abs(p - 0) > 0.005 || p == 0 {
                        onProgress(p)
                    }
                }
        } else {
            // iOS 17 fallback: use the fixed @MainActor closure-based ScrollOffsetReader.
            content
                .background(
                    ScrollOffsetReader(
                        collapseDistance: distance,
                        onProgress: onProgress
                    )
                        .allowsHitTesting(false)
                )
        }
    }
}

// MARK: - DeckStats (unchanged)

struct DeckStats {
    let totalCards: Int
    let dueCards: Int
    let totalReviews: Int
    let accuracy: Int
    let totalXPEarned: Int
    let deckMastery: Double
    let todayReviewed: Int
}

private func cardMasteryScore(_ card: CardModel) -> Double {
    guard !card.reviewHistory.isEmpty else { return 0.0 }
    let interval = card.interval
    let baseScore: Double
    switch interval {
    case 0: baseScore = 0.10
    case 1: baseScore = 0.15
    case 2...3: baseScore = 0.25
    case 4...6: baseScore = 0.40
    case 7...10: baseScore = 0.58
    case 11...14: baseScore = 0.70
    case 15...20: baseScore = 0.82
    default:
        let easeNorm = (card.easeFactor - 1.3) / (2.5 - 1.3)
        baseScore = 0.90 + easeNorm * 0.10
    }
    return min(baseScore, 1.0)
}

func aggregateDeckStats(deck: DeckModel, activityLogs: [DailyActivityLog] = []) -> DeckStats {
    let cards = deck.cards
    var totalReviews = 0
    var correctReviews = 0
    var totalXP = 0
    var dueCards = 0
    var masterySum = 0.0
    let now = Date()
    let todayStart = Calendar.current.startOfDay(for: now)

    for card in cards {
        totalReviews += card.reviewHistory.count
        correctReviews += card.reviewHistory.filter { $0.difficultyRaw >= ReviewDifficulty.good.rawValue }.count
        totalXP += card.reviewHistory.reduce(0) { $0 + $1.xpAwarded }
        if card.dueDate <= now { dueCards += 1 }
        masterySum += cardMasteryScore(card)
    }

    let accuracy = totalReviews > 0 ? Int((Double(correctReviews) / Double(totalReviews)) * 100) : 0
    let deckMastery = cards.isEmpty ? 0.0 : masterySum / Double(cards.count)

    let todayReviewed = cards.reduce(0) { count, card in
        count + card.reviewHistory.filter { $0.timestamp >= todayStart }.count
    }

    return DeckStats(
        totalCards: cards.count,
        dueCards: dueCards,
        totalReviews: totalReviews,
        accuracy: accuracy,
        totalXPEarned: totalXP,
        deckMastery: deckMastery,
        todayReviewed: todayReviewed
    )
}
