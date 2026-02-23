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

    @State private var viewModel: DeckViewModel

    init(deck: DeckModel, searchQuery: String? = nil) {
        self.deck = deck
        self.searchQuery = searchQuery
        _viewModel = State(initialValue: DeckViewModel(searchQuery: searchQuery))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Main
            VStack(spacing: 0) {
                // Header Info
                DeckHeaderView(deck: deck, onEdit: { isPresentingEdit = true })
                
                // MARK: - Active Search Banner
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
                    if let deckStats = aggregateDeckStats(deck: deck), searchQuery == nil {
                        DeckStatsView(stats: deckStats)
                    }
                    
                    if searchQuery == nil {
                        DeckPlayModesView(deck: deck, onPlay: { isPlayingQuiz = true })
                    }

                    // Toolbar
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

                    ScrollView {
                        DeckCardGridView(
                            cards: viewModel.groupedCards(for: deck),
                            isSelecting: viewModel.isSelecting,
                            selectedCards: viewModel.selectedCards,
                            onToggleSelection: viewModel.toggleSelection,
                            onTapCard: { card in
                                if viewModel.isSelecting {
                                    viewModel.toggleSelection(for: card)
                                } else if searchQuery != nil {
                                    // Bypasses Preview Mode directly into Edit/Highlight Mode
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
                        .scrollIndicators(.hidden)
                        .padding(.top, 4)
                        .padding(.bottom, 100)
                    }
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .contentShape(Rectangle())
            .onTapGesture {
                if viewModel.isSelecting {
                    viewModel.exitSelectionMode()
                }
            }

            // Bottom Selection Bar
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
        .navigationTitle(searchQuery != nil ? "Search Results" : deck.title)
        .navigationBarTitleDisplayMode(.inline)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.isSelecting)

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
                CreateDeckView(deckToEdit: deck)
            }
        }
        .fullScreenCover(isPresented: $isPlayingQuiz) {
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
                // Pass Search Query downwards to render Highlight overlays
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
}

// MARK: - Additional Subviews (Unchanged for brevity, assumed identically implemented in codebase)
private struct CardPreviewScreen: View {
    let card: CardModel
    @State private var showStats: Bool = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        let front = ZoneCardContent(rootZone: card.frontZone)
        let back = ZoneCardContent(rootZone: card.backZone)
        ZStack { CardPreviewModeView(front: front, back: back) }
        .overlay(alignment: .bottom) {
            if let stats = card.stats, showStats {
                CardStatsView(stats: stats).transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { showStats.toggle() }
            } label: {
                Image(systemName: "info.circle").font(.title3.bold()).padding().foregroundStyle(.primary)
            }
        }
    }
    
    static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private struct CardStatsView: View {
    let stats: CardStats
    var body: some View { /* Pre-existing code */ EmptyView() }
}
private struct StatIconItem: View {
    let icon: String; let value: String; let label: String; var color: Color = .primary
    var body: some View { /* Pre-existing code */ EmptyView() }
}
private struct DeckStats { /* Pre-existing code */
    let total: Int; let correct: Int; let wrong: Int; let accuracy: Int; let maxStreak: Int; let lastActivity: Date?
}
private func aggregateDeckStats(deck: DeckModel) -> DeckStats? { /* Pre-existing code */ return nil }
private struct DeckStatsView: View {
    let stats: DeckStats
    var body: some View { /* Pre-existing code */ EmptyView() }
}
