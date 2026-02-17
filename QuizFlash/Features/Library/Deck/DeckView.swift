//
//  DeckView.swift
//  QuizFlash
//
//  Refactored by Senior iOS Architect
//

import SwiftUI
import SwiftData

struct DeckView: View {
    @Environment(\.modelContext) private var context
    @Bindable var deck: DeckModel

    @State private var viewModel: DeckViewModel

    init(deck: DeckModel) {
        self.deck = deck
        _viewModel = State(initialValue: DeckViewModel(deck: deck))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Main
            VStack(spacing: 0) {
                // Header Info
                DeckHeaderView(deck: deck, onEdit: { viewModel.isPresentingEdit = true })

                VStack(spacing: 16) {
                    // Deck Stats Section
                    if let deckStats = aggregateDeckStats(deck: deck) {
                        DeckStatsView(stats: deckStats)
                    }
                    // Play Modes
                    DeckPlayModesView(deck: deck, onPlay: { viewModel.isPlayingQuiz = true })

                    // Toolbar
                    DeckSectionToolbar(
                        deck: deck,
                        isSelecting: viewModel.isSelecting,
                        sortOrder: $viewModel.sortOrder,
                        onAdd: { viewModel.isAddingCard = true },
                        onStartSelection: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                viewModel.isSelecting = true
                            }
                        },
                        onExport: { viewModel.exportDeck() }
                    )

                    ScrollView {
                        DeckCardGridView(
                            cards: viewModel.groupedCards(),
                            isSelecting: viewModel.isSelecting,
                            selectedCards: viewModel.selectedCards,
                            onToggleSelection: viewModel.toggleSelection,
                            onTapCard: { card in
                                if viewModel.isSelecting {
                                    viewModel.toggleSelection(for: card)
                                } else {
                                    viewModel.previewedCard = card
                                }
                            },
                            onLongPressCard: { card in
                                if viewModel.isSelecting {
                                    viewModel.toggleSelection(for: card)
                                } else {
                                    viewModel.editingCard = card
                                }
                            },
                            onDeleteCard: { card in
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    viewModel.deleteSingleCard(card, context: context)
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
        .navigationTitle(deck.title)
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
                    viewModel.deleteSelectedCards(context: context)
                }
            }
        } message: {
            Text("This action cannot be undone.")
        }
        
        // Add new card
        .fullScreenCover(isPresented: $viewModel.isAddingCard) {
            AddCardSheetView { frontZone, backZone in
                viewModel.addNewCard(frontZone: frontZone, backZone: backZone)
            }
        }
        
        // Edit Deck Info
        .fullScreenCover(isPresented: $viewModel.isPresentingEdit) {
            NavigationStack {
                CreateView(deckToEdit: deck)
            }
        }
        
        // Play Quiz Mode
        .fullScreenCover(isPresented: $viewModel.isPlayingQuiz) {
            NavigationStack {
                DefaultModePlay(deck: deck)
            }
        }
        
        // Export share sheet
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
        
        // Export loading overlay
        .overlay {
            if viewModel.isExporting {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()

                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Exporting...")
                            .font(.headline)
                    }
                    .padding(32)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        
        // Card Preview Full Screen
        .fullScreenCover(item: $viewModel.previewedCard) { card in
            CardPreviewScreen(card: card)
        }
        
        // Card Edit Full Screen
        .fullScreenCover(item: $viewModel.editingCard) { card in
            NavigationStack {
                AddCardSheetView(
                    frontZone: card.frontZone,
                    backZone: card.backZone
                ) { frontZone, backZone in
                    viewModel.saveEditedCard(original: card, newFront: frontZone, newBack: backZone)
                    viewModel.editingCard = nil
                }
            }
        }
    }
}

// MARK: - Card Preview Screen
private struct CardPreviewScreen: View {
    let card: CardModel
    @State private var showStats: Bool = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        let front = ZoneCardContent(rootZone: card.frontZone)
        let back = ZoneCardContent(rootZone: card.backZone)
        ZStack {
            ZonePreviewSheet(front: front, back: back)
        }
        .overlay(alignment: .bottom) {
            if let stats = card.stats, showStats {
                CardStatsView(stats: stats)
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
    
    static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Card Stats View
private struct CardStatsView: View {
    let stats: CardStats
    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    VStack(spacing: 12) {
                        HStack(spacing: 24) {
                            StatIconItem(icon: "checkmark.circle.fill", value: "\(stats.correctCount)", label: "Correct", color: .green)
                            StatIconItem(icon: "xmark.circle.fill", value: "\(stats.wrongCount)", label: "Wrong", color: .red)
                            StatIconItem(icon: "sum", value: "\(stats.totalAttempts)", label: "Total", color: .blue)
                            StatIconItem(
                                icon: "percent",
                                value: stats.totalAttempts > 0 ? String(format: "%d%%", Int(Double(stats.correctCount) / Double(stats.totalAttempts) * 100)) : "-",
                                label: "Accuracy",
                                color: .accentColor
                            )
                        }
                        .padding(.top, 18)
                        
                        HStack(spacing: 24) {
                            StatIconItem(icon: "flame.fill", value: "\(stats.streak)", label: "Streak", color: .orange)
                            if let last = stats.lastAttemptDate {
                                VStack(spacing: 2) {
                                    Label("Last Attempt", systemImage: "clock")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(CardPreviewScreen.dateString(last))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.primary)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.bottom, 12)
                    }
                    .padding(.horizontal, 18)
                )
                .frame(maxWidth: 480)
                .frame(height: 120)
                .padding(.top, 12)
                .padding(.bottom, 18)
                .padding(.horizontal, 24)
        }
    }
}

private struct StatIconItem: View {
    let icon: String
    let value: String
    let label: String
    var color: Color = .primary
    
    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                Text(value)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(color)
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Deck Stats Model & View
private struct DeckStats {
    let total: Int
    let correct: Int
    let wrong: Int
    let accuracy: Int // percent
    let maxStreak: Int
    let lastActivity: Date?
}

private func aggregateDeckStats(deck: DeckModel) -> DeckStats? {
    let allStats = deck.cards.compactMap { $0.stats }
    guard !allStats.isEmpty else { return nil }
    let total = allStats.reduce(0) { $0 + $1.totalAttempts }
    let correct = allStats.reduce(0) { $0 + $1.correctCount }
    let wrong = allStats.reduce(0) { $0 + $1.wrongCount }
    let accuracy = total > 0 ? Int(Double(correct) / Double(total) * 100) : 0
    let maxStreak = allStats.map { $0.streak }.max() ?? 0
    let lastActivity = allStats.compactMap { $0.lastAttemptDate }.max()
    return DeckStats(total: total, correct: correct, wrong: wrong, accuracy: accuracy, maxStreak: maxStreak, lastActivity: lastActivity)
}

private struct DeckStatsView: View {
    let stats: DeckStats
    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    VStack(spacing: 12) {
                        HStack(spacing: 24) {
                            StatIconItem(icon: "checkmark.circle.fill", value: "\(stats.correct)", label: "Correct", color: .green)
                            StatIconItem(icon: "xmark.circle.fill", value: "\(stats.wrong)", label: "Wrong", color: .red)
                            StatIconItem(icon: "sum", value: "\(stats.total)", label: "Total", color: .blue)
                            StatIconItem(icon: "percent", value: "\(stats.accuracy)%", label: "Accuracy", color: .accentColor)
                        }
                        .padding(.top, 18)
                        
                        HStack(spacing: 24) {
                            StatIconItem(icon: "flame.fill", value: "\(stats.maxStreak)", label: "Max Streak", color: .orange)
                            if let last = stats.lastActivity {
                                VStack(spacing: 2) {
                                    Label("Last Activity", systemImage: "clock")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(CardPreviewScreen.dateString(last))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.primary)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.bottom, 12)
                    }
                    .padding(.horizontal, 18)
                )
                .frame(maxWidth: 600)
                .frame(height: 120)
                .padding(.top, 12)
                .padding(.bottom, 18)
                .padding(.horizontal, 24)
        }
    }
}
