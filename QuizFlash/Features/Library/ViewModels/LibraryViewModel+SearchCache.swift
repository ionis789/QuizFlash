//
//  LibraryViewModel+SearchCache.swift
//  QuizFlash
//
//  Search cache lifecycle for the Library view model.
//

import Foundation
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
        let signature = Self.searchCacheFingerprint(for: decks)
        guard signature != searchCacheSignature || cachedSearchPayloads.isEmpty else { return }
        guard pendingSearchCacheSignature != signature else { return }

        pendingSearchCacheSignature = signature
        cachedDeckIDs = Set(decks.map(\.persistentModelID))
        buildSearchCache(decks: decks, container: container, signature: signature)
    }

    /// Builds the search payload cache on a background thread.
    /// Safe to call as often as needed — any in-flight build is cancelled
    /// first, so rapid calls (e.g. deck add/delete) don't stack up.
    func buildSearchCache(decks: [DeckModel], container: ModelContainer, signature: Int) {
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
            guard !Task.isCancelled else {
                await MainActor.run {
                    if self?.pendingSearchCacheSignature == signature {
                        self?.pendingSearchCacheSignature = nil
                    }
                }
                return
            }

            await MainActor.run {
                guard let self, !Task.isCancelled else { return }
                if self.sharedSearchActor == nil {
                    self.sharedSearchActor = LibrarySearchActor(modelContainer: container)
                }
            }

            guard !Task.isCancelled, let self else { return }
            let actor: LibrarySearchActor? = await MainActor.run { self.sharedSearchActor }
            guard let actor else {
                await MainActor.run {
                    if self.pendingSearchCacheSignature == signature {
                        self.pendingSearchCacheSignature = nil
                    }
                }
                return
            }

            let payloads = await actor.buildPayloads(for: deckInfos)

            guard !Task.isCancelled else {
                await MainActor.run {
                    if self.pendingSearchCacheSignature == signature {
                        self.pendingSearchCacheSignature = nil
                    }
                }
                return
            }
            await MainActor.run {
                self.cachedSearchPayloads = payloads
                self.searchCacheSignature = signature
                self.pendingSearchCacheSignature = nil

                if self.isSearching,
                   !self.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.debounceSearchInput(self.searchText)
                }
            }
        }
    }

    static func searchCacheFingerprint(for decks: [DeckModel]) -> Int {
        var aggregate = decks.count &* 1_000_241
        for deck in decks {
            var hasher = Hasher()
            hasher.combine(deck.persistentModelID.hashValue)
            hasher.combine(deck.cardCount)
            hasher.combine(deck.editedAt.timeIntervalSinceReferenceDate.bitPattern)
            aggregate ^= hasher.finalize()
        }
        return aggregate
    }
}
