//
//  LibraryViewModel+SearchCache.swift
//  QuizFlash
//
//  Search cache lifecycle for the Library view model.
//

import SwiftData

// MARK: - Search Cache

extension LibraryViewModel {

    /// Rebuilds the search payload cache only if the deck dataset has materially
    /// changed since the last build.
    ///
    /// This is the primary entry point for cache management. Views should call
    /// this method rather than `buildSearchCache(decks:)` directly, so that
    /// repeated `onAppear` calls (caused by tab switches or navigation) are
    /// free when the underlying data has not changed.
    ///
    /// By storing `cachedDeckIDs` on the ViewModel rather than as `@State` on
    /// the View, the deduplication check survives across all view instances that
    /// share this ViewModel (e.g. the root Library tab reusing the environment
    /// injected instance across tab switches).
    func rebuildCacheIfNeeded(decks: [DeckModel], container: ModelContainer) {
        let newIDs = Set(decks.map { $0.id })
        guard newIDs != cachedDeckIDs else { return }
        cachedDeckIDs = newIDs
        buildSearchCache(decks: decks, container: container)
    }

    /// Builds the search payload cache on a background thread.
    /// Safe to call as often as needed — any in-flight build is cancelled
    /// first, so rapid calls (e.g. deck add/delete) don't stack up.
    func buildSearchCache(decks: [DeckModel], container: ModelContainer) {
        cacheTask?.cancel()

        // Snapshot only lightweight metadata on the main context.
        let deckInfos = decks.map {
            (
                id: $0.persistentModelID,
                title: $0.title,
                colorHex: $0.colorHex,
                cardCount: $0.cardCount,
                editedAt: $0.editedAt
            )
        }

        cacheTask = Task { [weak self] in
            // Keep the cache rebuild off the main actor so tab switches stay smooth.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self, !Task.isCancelled else { return }
                if self.sharedSearchActor == nil {
                    self.sharedSearchActor = LibrarySearchActor(modelContainer: container)
                }
            }

            guard !Task.isCancelled, let self else { return }
            let actor: LibrarySearchActor? = await MainActor.run { self.sharedSearchActor }
            guard let actor else { return }

            let payloads = await actor.buildPayloads(for: deckInfos)

            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.cachedSearchPayloads = payloads
            }
        }
    }
}
