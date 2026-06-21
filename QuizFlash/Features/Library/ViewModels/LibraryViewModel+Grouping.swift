//
//  LibraryViewModel+Grouping.swift
//  QuizFlash
//
//  Deck grouping cache management for the Library view model.
//

import Foundation

// MARK: - Grouping

extension LibraryViewModel {

    /// Computes and caches grouped decks on a background thread.
    func updateGroupedDecks(from snapshot: [DeckModel]) {
        groupingTask?.cancel()
        cachedDeckCount = snapshot.count

        guard !snapshot.isEmpty else {
            cachedGroupedDecks = []
            return
        }

        let localSortOrder = sortOrder
        let deckSnapshots = LibraryGrouping.makeDeckSnapshots(from: snapshot)
        let localLocale = AppPreferences.shared.resolvedLocale
        var localCalendar = AppPreferences.shared.resolvedCalendar
        localCalendar.locale = localLocale

        if cachedGroupedDecks.isEmpty {
            cachedGroupedDecks = LibraryGrouping.sections(
                decks: deckSnapshots,
                sortOrder: localSortOrder,
                locale: localLocale,
                calendar: localCalendar
            )
            return
        }

        groupingTask = Task { [weak self, deckSnapshots, localSortOrder, localLocale, localCalendar] in
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled, let self else { return }

            let sections = await Task.detached(priority: .userInitiated) {
                LibraryGrouping.sections(
                    decks: deckSnapshots,
                    sortOrder: localSortOrder,
                    locale: localLocale,
                    calendar: localCalendar
                )
            }.value
            guard !Task.isCancelled else { return }

            await MainActor.run {
                if !self.areSectionsStructurallyIdentical(old: self.cachedGroupedDecks, new: sections) {
                    self.cachedGroupedDecks = sections
                }
            }
        }
    }
}

// MARK: - Grouping Helpers

private extension LibraryViewModel {

    func areSectionsStructurallyIdentical(old: [DeckSection], new: [DeckSection]) -> Bool {
        guard old.count == new.count else { return false }
        for i in 0..<old.count {
            if old[i].title != new[i].title { return false }
            if old[i].decks != new[i].decks { return false }
        }
        return true
    }
}
