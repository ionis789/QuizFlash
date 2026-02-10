//
//  DeckView.swift
//  QuizFlash
//
//  Created by Ion Socol on 08.01.2026.
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

    // Sorting
    @State private var sortOrder: SortOrder = .newest

    var body: some View {
        ZStack(alignment: .bottom) {
            // Main
            VStack(spacing: 0) {
                // Header Info
                DeckHeaderView(deck: deck, onEdit: { isPresentingEdit = true })

                VStack(spacing: 16) {
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
                        }
                    )

                    ScrollView {
                        DeckCardGridView(
                            cards: groupedCards,
                            isSelecting: isSelecting,
                            selectedCards: selectedCards,
                            onToggleSelection: toggleSelection,
                            onTapCard: handleCardTap,
                            onLongPressCard: requestSingleDelete
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
        .sheet(isPresented: $isAddingCard) {
            AddCardSheetView { front, back in
                let newCard = CardModel(frontText: front, backText: back)
                deck.cards.append(newCard)
                deck.editedAt = Date()
            }
        }
        .sheet(isPresented: $isPresentingEdit) {
            NavigationStack {
                CreateView(deckToEdit: deck)
            }
        }
        .fullScreenCover(isPresented: $isPlayingQuiz) {
            NavigationStack {
                DefaultModePlay(deck: deck)
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
            return sortOrder == .oldest ? d1 < d2 : d1 > d2
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
