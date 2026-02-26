//
//  DeckView.swift
//  QuizFlash
//

import SwiftUI
import SwiftData

struct DeckView: View {
    @Environment(\.modelContext) var context
    @Bindable var deck: DeckModel
    let searchQuery: String?

    @State private var isAddingCard = false
    @State private var isPresentingEdit = false
    @State private var isPlayingQuiz = false
    @State private var previewedCard: CardModel? = nil
    @State private var editingCard: CardModel? = nil

    // ── Scroll collapse state ─────────────────────────────────────────────
    @State private var isHeroCollapsed: Bool = false

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
        // ── Navigation bar: pill when collapsed, plain title when expanded ──
        .navigationBarTitleDisplayMode(.inline)
            .toolbar {
            ToolbarItem(placement: .principal) {
                navBarPrincipal
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
            .fullScreenCover(isPresented: $isAddingCard) {
            CreateCardView(searchQuery: nil) { frontZone, backZone in
                let newCard = CardModel(frontZone: frontZone, backZone: backZone)
                deck.cards.append(newCard)
                deck.editedAt = Date()
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
        }) {
            NavigationStack {
                DefaultModePlay(deck: deck)
            }
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
                    }
                    editingCard = nil
                }
            }
        }
    }

    // MARK: - Computed Stats (cached for both hero and mini header)

    private var computedStats: DeckStats { aggregateDeckStats(deck: deck, activityLogs: activityLogs) }

    // MARK: - Navigation Bar Principal
    // NOTE: ToolbarItem ignores .transition() — SwiftUI does not animate conditional
    // content swaps inside toolbar. Correct pattern: single ZStack with opacity/scale.

    private var navBarPrincipal: some View {
        let showPill = isHeroCollapsed && searchQuery == nil

        return ZStack {
            // Plain title — visible when hero is expanded
            Text(searchQuery != nil ? "Search Results" : deck.title)
                .font(.headline.weight(.semibold))
                .opacity(showPill ? 0 : 1)
                .scaleEffect(showPill ? 0.85 : 1)

            // Compact pill — visible when hero is scrolled away
            NavBarDeckPill(deck: deck, stats: computedStats)
                .opacity(showPill ? 1 : 0)
                .scaleEffect(showPill ? 1 : 0.80)
        }
            .animation(.spring(response: 0.38, dampingFraction: 0.65), value: showPill)
    }

    // MARK: - Main Content (single ScrollView — enables scroll-collapse)

    private var mainContent: some View {
        ScrollView(showsIndicators: false) {
            // ── Scroll offset tracker (zero height, invisible) ──────────────
            GeometryReader { geo in
                Color.clear.preference(
                    key: DeckScrollOffsetKey.self,
                    value: geo.frame(in: .named("deckScroll")).minY
                )
            }
                .frame(height: 0)

            VStack(spacing: 0) {
                // ── Expanded hero ─────────────────────────────────────────
                if searchQuery == nil {
                    DeckHeroView(
                        deck: deck,
                        stats: computedStats,
                        isCompact: false,
                        onEdit: { isPresentingEdit = true }
                    )
                    // When collapsed: fade out + slight scale down, but KEEP layout space
                    // so the scroll position is stable and content doesn't jump.
                    // The negative offset nudges it off-screen without layout reflow.
                    .opacity(isHeroCollapsed ? 0 : 1)
                        .scaleEffect(isHeroCollapsed ? 0.94 : 1, anchor: .top)
                        .offset(y: isHeroCollapsed ? -12 : 0)
                        .animation(.spring(response: 0.42, dampingFraction: 0.65), value: isHeroCollapsed)
                }

                // ── Active Search Banner ──────────────────────────────────
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
                        // Play modes
                        DeckPlayModesView(deck: deck, onPlay: { isPlayingQuiz = true })
                            .padding(.top, 16)

                        // Habit tracker
                        LearningHabitView(
                            activityLogs: activityLogs,
                            userProfile: userProfile,

                        )
                    }

                    // ── Toolbar ───────────────────────────────────────────
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

                    // ── Card Grid ─────────────────────────────────────────
                    DeckCardGridView(
                        cards: viewModel.groupedCards(for: deck),
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
                        .padding(.bottom, 120) // extra bottom padding for tab bar
                }
                    .contentShape(Rectangle())
                    .onTapGesture {
                    if viewModel.isSelecting { viewModel.exitSelectionMode() }
                }
            }
        }
            .coordinateSpace(name: "deckScroll")
            .onPreferenceChange(DeckScrollOffsetKey.self) { offset in
            // Hero collapse threshold: collapse once hero (~220pt) scrolls out
            let shouldCollapse = offset < -180
            if shouldCollapse != isHeroCollapsed {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.62)) {
                    isHeroCollapsed = shouldCollapse
                }
            }
        }
            .background(Color(uiColor: .systemGroupedBackground))
    }

    // MARK: - Additional Subviews (Actualizate pentru Gamification & SRS)
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

// MARK: - NavBarDeckPill (shown in toolbar when hero is scrolled away)

private struct NavBarDeckPill: View {
    let deck: DeckModel
    let stats: DeckStats

    private var deckColor: Color { Color(hex: deck.colorHex) ?? .blue }
    private var masteryCol: Color { masteryColor(stats.deckMastery) }
    private var masteryInt: Int { Int(stats.deckMastery * 100) }

    var body: some View {
        HStack(spacing: 8) {
            // Deck icon
            ZStack {
                Circle()
                    .fill(deckColor.opacity(0.25))
                    .frame(width: 26, height: 26)
                Image(systemName: deck.icon.isEmpty ? "sparkles.rectangle.stack.fill" : deck.icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(deckColor)
            }

            // Title + mastery
            VStack(alignment: .leading, spacing: 0) {
                Text(deck.title)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                Text("\(masteryInt)% mastered")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            // Mastery arc
            ZStack {
                Circle()
                    .trim(from: 0, to: 1)
                    .stroke(masteryCol.opacity(0.20), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 22, height: 22)
                    .rotationEffect(.degrees(-90))
                Circle()
                    .trim(from: 0, to: stats.deckMastery)
                    .stroke(masteryCol, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 22, height: 22)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.7, dampingFraction: 0.8), value: stats.deckMastery)
            }

            // Due badge (only when relevant)
            if stats.dueCards > 0 {
                Text("\(stats.dueCards)")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.red, in: Capsule())
            }
        }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
            Capsule()
                .stroke(deckColor.opacity(0.30), lineWidth: 1)
        )
    }
}

// MARK: - DeckStats (top-level — shared between DeckView & DeckHeroView)

struct DeckStats {
    let totalCards: Int
    let dueCards: Int
    let totalReviews: Int
    let accuracy: Int
    let totalXPEarned: Int
    let deckMastery: Double // 0.0–1.0 based on SRS intervals
    let todayReviewed: Int // Cards reviewed today in this deck
}

// MARK: - Card Mastery Score (SRS-based algorithm)
// A card is "mastered" when the SM-2 algorithm has extended its interval to 21+ days.
// This means the user has proven consistent recall over weeks, not just days.
//
// Scale:
//   No reviews         → 0%   (Never seen)
//   interval 1         → 15%  (Seen once, still fragile)
//   interval 2-6       → 20-50% (Active learning phase)
//   interval 7-14      → 55-75% (Consolidating)
//   interval 15-20     → 78-89% (Almost mastered)
//   interval 21+       → 90-100% (Mastered — ease factor influences top end)

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
    default: // 21+ days
        // Ease factor ranges 1.3–2.5; normalise to 0–1 and blend into top range
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

    // Today's reviews: count ReviewEvents timestamped today across all cards in this deck
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

// MARK: - Scroll Offset PreferenceKey

private struct DeckScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
