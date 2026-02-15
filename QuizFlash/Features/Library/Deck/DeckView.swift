//
//  DeckView.swift
//  QuizFlash
//
//  Created by Ion Socol on 08.01.2026.
//
//  Deck view with card grid and play modes.
//

import SwiftUI
import SwiftData

struct DeckView: View {
    @Environment(\.modelContext) var context
    @Bindable var deck: DeckModel

    // MARK: - State
    @State private var isAddingCard = false
    @State private var isPresentingEdit = false
    @State private var isPlayingQuiz = false

    // Selection State
    @State private var isSelecting = false
    @State private var selectedCards: Set<PersistentIdentifier> = []
    @State private var showDeleteConfirmation = false

    // Card Preview/Edit State
    @State private var previewedCard: CardModel? = nil
    @State private var editingCard: CardModel? = nil

    // Sorting
    @State private var sortOrder: SortOrder = .newest

    // Export State
    @State private var isExporting = false
    @State private var exportedURL: URL?
    @State private var showShareSheet = false
    @State private var showExportError = false
    @State private var exportErrorMessage = ""

    var body: some View {
        ZStack(alignment: .bottom) {
            // Main
            VStack(spacing: 0) {
                // Header Info
                DeckHeaderView(deck: deck, onEdit: { isPresentingEdit = true })

                VStack(spacing: 16) {
                    // Deck Stats Section
                    if let deckStats = aggregateDeckStats(deck: deck) {
                        DeckStatsView(stats: deckStats)
                    }
                    // Play Modes
                    DeckPlayModesView(deck: deck, onPlay: { isPlayingQuiz = true })

                    // Toolbar
                    DeckSectionToolbar(
                        deck: deck,
                        isSelecting: isSelecting,
                        sortOrder: $sortOrder,
                        onAdd: { isAddingCard = true },
                        onStartSelection: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                isSelecting = true
                            }
                        },
                        onExport: { exportDeck() }
                    )

                    ScrollView {
                        DeckCardGridView(
                            cards: groupedCards,
                            isSelecting: isSelecting,
                            selectedCards: selectedCards,
                            onToggleSelection: toggleSelection,
                            onTapCard: { card in
                                if isSelecting {
                                    toggleSelection(card)
                                } else {
                                    previewedCard = card
                                }
                            },
                            onLongPressCard: { card in
                                if isSelecting {
                                    toggleSelection(card)
                                } else {
                                    editingCard = card
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
                if isSelecting {
                    exitSelectionMode()
                }
            }

            // Bottom Selection Bar
            if isSelecting {
                DeckSelectionBottomBar(
                    selectedCount: selectedCards.count,
                    onDone: exitSelectionMode,
                    onDelete: { showDeleteConfirmation = true }
                )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 20)
                    .zIndex(10)
            }
        }
            .navigationTitle(deck.title)
            .navigationBarTitleDisplayMode(.inline)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isSelecting)

        // MARK: - Dialogs & Sheets
        .confirmationDialog(
            "Delete \(selectedCards.count) card\(selectedCards.count == 1 ? "" : "s")?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteSelectedCards()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This action cannot be undone.")
        }
        // Add new card
        .fullScreenCover(isPresented: $isAddingCard) {
            AddCardSheetView { frontZone, backZone in
                let newCard = CardModel(
                    frontZone: frontZone,
                    backZone: backZone
                )
                deck.cards.append(newCard)
                deck.editedAt = Date()
            }
        }
            .fullScreenCover(isPresented: $isPresentingEdit) {
            NavigationStack {
                CreateView(deckToEdit: deck)
            }
        }
            .fullScreenCover(isPresented: $isPlayingQuiz) {
            NavigationStack {
                DefaultModePlay(deck: deck)
            }
        }
        // Export share sheet
        .sheet(isPresented: $showShareSheet) {
            if let url = exportedURL {
                ShareSheet(items: [url])
            }
        }
            .alert("Export Error", isPresented: $showExportError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(exportErrorMessage)
        }
        // Export loading overlay
        .overlay {
            if isExporting {
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
        .fullScreenCover(item: $previewedCard) { card in
            CardPreviewScreen(card: card)
        }
        // Card Edit Full Screen
        .fullScreenCover(item: $editingCard) { card in
            NavigationStack {
                AddCardSheetView(
                    frontZone: card.frontZone,
                    backZone: card.backZone
                ) { frontZone, backZone in
                    // Update card
                    card.frontZone = frontZone
                    card.backZone = backZone
                    card.editedAt = Date()
                    editingCard = nil
                }
            }
        }
    }
}

// MARK: - Logic & Extensions
extension DeckView {

    private func handleCardTap(_ card: CardModel) {
        if isSelecting {
            toggleSelection(card)
        }
    }

    private func toggleSelection(_ card: CardModel) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            if selectedCards.contains(card.id) {
                selectedCards.remove(card.id)
            } else {
                selectedCards.insert(card.id)
            }
        }
    }

    private func exitSelectionMode() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            isSelecting = false
            selectedCards.removeAll()
        }
    }

    private func requestSingleDelete(_ card: CardModel) {
        // Context menu action. Ignore in multi-select mode.
        guard !isSelecting else { return }
        deleteSingleCard(card)
    }

    private func deleteSingleCard(_ card: CardModel) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            context.delete(card)
            deck.cards.removeAll { $0.id == card.id }
            deck.editedAt = Date()
            selectedCards.remove(card.id)
        }
    }

    private func deleteSelectedCards() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            for card in deck.cards where selectedCards.contains(card.id) {
                context.delete(card)
                deck.cards.removeAll { $0.id == card.id }
            }
            selectedCards.removeAll()
            isSelecting = false
            deck.editedAt = Date()
        }
    }

    // MARK: - Export
    private func exportDeck() {
        isExporting = true

        Task {
            do {
                let url = try await DeckSharingManager.shared.exportDeck(deck)
                await MainActor.run {
                    isExporting = false
                    exportedURL = url
                    showShareSheet = true
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    exportErrorMessage = error.localizedDescription
                    showExportError = true
                }
            }
        }
    }

    // Grouping Logic
    var groupedCards: [DeckCardGridView.CardSection] {
        let sortedAll = deck.cards.sorted { c1, c2 in
            switch sortOrder {
            case .newest: return c1.createdAt > c2.createdAt
            case .oldest: return c1.createdAt < c2.createdAt
            case .lastEdited: return c1.editedAt > c2.editedAt
            case .alphabetical:
                return c1.frontText.localizedCaseInsensitiveCompare(c2.frontText) == .orderedAscending
            }
        }

        if sortOrder == .alphabetical {
            if sortedAll.isEmpty { return [] }
            return [
                DeckCardGridView.CardSection(
                    id: "all",
                    title: "All Cards",
                    cards: sortedAll,
                    dateForSorting: nil
                )
            ]
        }

        let calendar = Calendar.current
        let groups = Dictionary(grouping: sortedAll) { card -> Date in
            let dateToCheck = sortOrder == .lastEdited ? card.editedAt : card.createdAt
            return calendar.startOfDay(for: dateToCheck)
        }

        let sections = groups.map { (startOfDay, cardsInGroup) -> DeckCardGridView.CardSection in
            let title = getSectionTitle(for: startOfDay, calendar: calendar)
            return DeckCardGridView.CardSection(id: title, title: title, cards: cardsInGroup, dateForSorting: startOfDay)
        }

        return sections.sorted { s1, s2 in
            guard let d1 = s1.dateForSorting, let d2 = s2.dateForSorting else { return false }
            return sortOrder == .oldest ? d1 < d2: d1 > d2
        }
    }

    private func getSectionTitle(for date: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let now = Date()
        if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            let weekdayFormatter = DateFormatter(); weekdayFormatter.dateFormat = "EEEE"
            return "This Week - " + weekdayFormatter.string(from: date)
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .month) {
            let dayFormatter = DateFormatter(); dayFormatter.dateFormat = "MMMM d"
            return dayFormatter.string(from: date)
        }
        let fullFormatter = DateFormatter(); fullFormatter.dateFormat = "MMMM yyyy"
        return fullFormatter.string(from: date)
    }
}

// MARK: - Card Preview Screen pentru binding corect la isFlipped
private struct CardPreviewScreen: View {
    let card: CardModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        let front = ZoneCardContent(rootZone: card.frontZone)
        let back = ZoneCardContent(rootZone: card.backZone)
        VStack(spacing: 0) {
            ZStack {
                ZonePreviewSheet(front: front, back: back)
            }
                .overlay(alignment: .bottom) {
                if let stats = card.stats {
                    CardStatsView(stats: stats)
                }
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

// MARK: - Card Stats View (UI modern)
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
                        StatIconItem(icon: "percent", value: stats.totalAttempts > 0 ? String(format: "%d%%", Int(Double(stats.correctCount) / Double(stats.totalAttempts) * 100)) : "-", label: "Accuracy", color: .accentColor)
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
