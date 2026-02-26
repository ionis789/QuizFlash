//
//  DeckViewModel.swift
//  QuizFlash
//

import SwiftUI
import SwiftData

@Observable
@MainActor
final class DeckViewModel {

    // MARK: - Search State
    var searchQuery: String? = nil

    // MARK: - Scroll State (Isolated for Performance)
    var collapseProgress: CGFloat = 0

    // MARK: - Selection State
    var isSelecting = false
    var selectedCards: Set<PersistentIdentifier> = []
    var showDeleteConfirmation = false

    // MARK: - Sorting
    var sortOrder: SortOrder = .newest

    // MARK: - Cached Data
    // Caching this prevents aggressive UI diffing during scroll events
    private(set) var cachedGroupedCards: [DeckCardGridView.CardSection] = []

    // MARK: - Export State
    var isExporting = false
    var exportedURL: URL?
    var showShareSheet = false
    var showExportError = false
    var exportErrorMessage = ""

    // MARK: - Initialization
    init(searchQuery: String? = nil) {
        self.searchQuery = searchQuery
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
    func deleteSingleCard(_ card: CardModel, from deck: DeckModel, context: ModelContext) {
        context.delete(card)
        deck.cards.removeAll { $0.id == card.id }
        deck.editedAt = Date()
        selectedCards.remove(card.id)
        updateGroupedCards(for: deck) // Update cache
    }

    func deleteSelectedCards(from deck: DeckModel, context: ModelContext) {
        for card in deck.cards where selectedCards.contains(card.id) {
            context.delete(card)
            deck.cards.removeAll { $0.id == card.id }
        }
        selectedCards.removeAll()
        isSelecting = false
        deck.editedAt = Date()
        updateGroupedCards(for: deck) // Update cache
    }

    // MARK: - Export Logic
    func exportDeck(_ deck: DeckModel) {
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

    // MARK: - Deep Text Extraction Helper
    private func extractAllText(from zone: ZoneModel) -> String {
        if zone.isLeaf { return zone.contentType == .text ? zone.text : "" }
        return (zone.children ?? []).map { extractAllText(from: $0) }.joined(separator: " ")
    }

    // MARK: - Grouping & Filtering Logic (Acum populează cache-ul)
    func updateGroupedCards(for deck: DeckModel) {
        var filteredCards = deck.cards

        // 1. In-memory Tokenized Filtering
        if let query = searchQuery, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let tokens = query.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            if !tokens.isEmpty {
                let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

                filteredCards = filteredCards.filter { card in
                    let fullText = extractAllText(from: card.frontZone) + " \n " + extractAllText(from: card.backZone)
                    return tokens.allSatisfy { token in
                        fullText.range(of: token, options: options) != nil
                    }
                }
            }
        }

        // 2. Sorting
        let sortedAll = filteredCards.sorted { c1, c2 in
            switch sortOrder {
            case .newest: return c1.createdAt > c2.createdAt
            case .oldest: return c1.createdAt < c2.createdAt
            case .lastEdited: return c1.editedAt > c2.editedAt
            case .alphabetical:
                return c1.frontText.localizedCaseInsensitiveCompare(c2.frontText) == .orderedAscending
            }
        }

        if sortOrder == .alphabetical {
            if sortedAll.isEmpty {
                self.cachedGroupedCards = []
                return
            }
            self.cachedGroupedCards = [
                DeckCardGridView.CardSection(id: "all", title: "All Cards", cards: sortedAll, dateForSorting: nil)
            ]
            return
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

        self.cachedGroupedCards = sections.sorted { s1, s2 in
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
