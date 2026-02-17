//
//  DeckViewModel.swift
//  QuizFlash
//
//  Refactored by Senior iOS Architect
//

import SwiftUI
import SwiftData

@Observable
@MainActor
final class DeckViewModel {
    
    // MARK: - Core Data
    var deck: DeckModel
    
    // MARK: - Presentation & Navigation State
    var isAddingCard = false
    var isPresentingEdit = false
    var isPlayingQuiz = false
    var previewedCard: CardModel? = nil
    var editingCard: CardModel? = nil
    
    // MARK: - Selection State
    var isSelecting = false
    var selectedCards: Set<PersistentIdentifier> = []
    var showDeleteConfirmation = false
    
    // MARK: - Sorting
    var sortOrder: SortOrder = .newest
    
    // MARK: - Export State
    var isExporting = false
    var exportedURL: URL?
    var showShareSheet = false
    var showExportError = false
    var exportErrorMessage = ""

    // MARK: - Initialization
    init(deck: DeckModel) {
        self.deck = deck
    }

    // MARK: - Card Operations
    func addNewCard(frontZone: ZoneModel, backZone: ZoneModel) {
        let newCard = CardModel(
            frontZone: frontZone,
            backZone: backZone
        )
        deck.cards.append(newCard)
        deck.editedAt = Date()
    }
    
    func saveEditedCard(original: CardModel, newFront: ZoneModel, newBack: ZoneModel) {
        // Business logic strictly contained in the ViewModel
        if original.frontZone != newFront || original.backZone != newBack {
            original.frontZone = newFront
            original.backZone = newBack
            original.editedAt = Date()
            deck.editedAt = Date()
        }
    }

    // MARK: - Selection Actions
    func toggleSelection(for card: CardModel) {
        if selectedCards.contains(card.id) {
            selectedCards.remove(card.id)
        } else {
            selectedCards.insert(card.id)
        }
    }

    func exitSelectionMode() {
        isSelecting = false
        selectedCards.removeAll()
    }

    // MARK: - Deletion Logic
    func deleteSingleCard(_ card: CardModel, context: ModelContext) {
        context.delete(card)
        deck.cards.removeAll { $0.id == card.id }
        deck.editedAt = Date()
        selectedCards.remove(card.id)
    }

    func deleteSelectedCards(context: ModelContext) {
        for card in deck.cards where selectedCards.contains(card.id) {
            context.delete(card)
            deck.cards.removeAll { $0.id == card.id }
        }
        selectedCards.removeAll()
        isSelecting = false
        deck.editedAt = Date()
    }

    // MARK: - Export Logic
    func exportDeck() {
        isExporting = true
        
        Task {
            do {
                let url = try await DeckSharingManager.shared.exportDeck(deck)
                self.isExporting = false
                self.exportedURL = url
                self.showShareSheet = true
            } catch {
                self.isExporting = false
                self.exportErrorMessage = error.localizedDescription
                self.showExportError = true
            }
        }
    }
    
    // MARK: - Grouping Logic
    func groupedCards() -> [DeckCardGridView.CardSection] {
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
