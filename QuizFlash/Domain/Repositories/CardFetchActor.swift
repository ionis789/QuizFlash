//
//  CardFetchActor.swift
//  QuizFlash
//
//  A background actor responsible for fetching card data and generating
//  thumbnails in isolation from the main-thread ModelContext.
//  This file must remain free of SwiftUI and UIKit imports —
//  it is a pure data-layer repository.
//

import Foundation
import SwiftData
import UIKit

// MARK: - DeckStats

/// A lightweight, sendable value type summarising the review statistics for a single deck.
///
/// `DeckStats` is computed on the background actor and then transferred to the
/// main actor for display, so it must conform to `Sendable`.
struct DeckStats: Sendable {

    // MARK: - Properties

    /// The total number of cards in the deck.
    let totalCards: Int

    /// The number of cards whose `dueDate` is on or before the current time.
    let dueCards: Int

    /// The cumulative number of review events recorded across all cards.
    let totalReviews: Int

    /// The review accuracy as an integer percentage (0–100).
    let accuracy: Int

    /// The total XP earned from all review events in the deck.
    let totalXPEarned: Int

    /// The average mastery score across all cards, from `0.0` (none) to `1.0` (mastered).
    let deckMastery: Double

    /// The number of review events recorded today (since midnight local time).
    let todayReviewed: Int

    // MARK: - Factory

    /// A zeroed-out `DeckStats` value representing a deck with no data.
    nonisolated static let empty = DeckStats(
        totalCards: 0, dueCards: 0, totalReviews: 0,
        accuracy: 0, totalXPEarned: 0, deckMastery: 0.0, todayReviewed: 0
    )
}

// MARK: - CardDataSnapshot

/// A sendable snapshot pairing a list of lightweight card summaries with aggregated deck statistics.
///
/// Produced by ``CardFetchActor/fetchSnapshot(deckID:)`` and transferred
/// to the main actor for rendering the deck grid.
struct CardDataSnapshot: Sendable {

    // MARK: - Properties

    /// Lightweight representations of each card, safe to pass across actor boundaries.
    let gridCards: [GridCardInfo]

    /// Aggregated statistics for the deck at the time the snapshot was taken.
    let stats: DeckStats
}

/// A sendable conversion-ready projection of a persisted card.
struct CardConversionSourceSnapshot: Sendable {
    let id: PersistentIdentifier
    let kind: CardKind
    let content: DraftCardContent
}

// MARK: - CardFetchActor

/// A Swift actor that performs all card-related data fetches on a dedicated background context.
///
/// Using a dedicated `ModelContext` on the actor isolates reads from the main-thread
/// context, preventing UI jank and avoiding the iOS 17 `ModelContext` row-cache trap
/// where faulted relationship arrays permanently retain large model graphs in memory.
///
/// ## Memory Management
///
/// After each fetch, ``flushContext()`` replaces the active `ModelContext` with a fresh
/// instance, immediately deallocating any `CardModel` objects (and their `Data` blobs)
/// that were loaded into the previous context's row cache.
actor CardFetchActor {

    // MARK: - Private State

    /// The shared `ModelContainer` used to create fresh `ModelContext` instances.
    ///
    /// Retaining the container (not the context) is the correct pattern: the container
    /// is shared and cheap, while each context owns its own in-memory row cache.
    private let container: ModelContainer

    /// The current background `ModelContext` used for fetching.
    ///
    /// Replaced by ``flushContext()`` after every operation to free the row cache.
    private var activeContext: ModelContext

    // MARK: - Initialization

    /// Creates a new `CardFetchActor` backed by the given `ModelContainer`.
    ///
    /// A fresh `ModelContext` with auto-save disabled is created immediately.
    /// Auto-save is disabled because this actor performs read-only fetches
    /// and must never accidentally persist partial state to the store.
    ///
    /// - Parameter container: The shared `ModelContainer` for the app's schema.
    init(container: ModelContainer) {
        self.container = container
        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false
        self.activeContext = ctx
    }

    // MARK: - Context Management

    /// Replaces the active `ModelContext` with a new, empty one, immediately freeing RAM.
    ///
    /// SwiftData does not expose a `reset()` method on `ModelContext`. The only reliable
    /// way to evict large objects (e.g. card `Data` blobs of several MB) from the
    /// iOS 17 row cache is to discard the context object entirely and allocate a fresh one.
    /// The old context — and all models it retains — is deallocated as soon as ARC
    /// releases the last reference.
    private func flushContext() {
        let freshContext = ModelContext(container)
        freshContext.autosaveEnabled = false
        self.activeContext = freshContext
    }

    // MARK: - Card Snapshot

    /// Fetches a lightweight snapshot of all cards in the specified deck.
    ///
    /// This method:
    /// 1. Resolves the parent `DeckModel` inside the actor's own `ModelContext`.
    /// 2. Reads the `deck.cards` relationship from that same context.
    /// 2. Projects each card into a ``GridCardInfo`` value type.
    /// 3. Accumulates deck statistics via ``StatsAccumulator``.
    /// 4. Flushes the context immediately after projection to reclaim memory.
    ///
    /// - Parameter deckID: The `PersistentIdentifier` of the target deck.
    /// - Returns: A ``CardDataSnapshot`` containing grid-display data and statistics.
    func fetchSnapshot(deckID: PersistentIdentifier) -> CardDataSnapshot {
        guard let deck = activeContext.model(for: deckID) as? DeckModel else {
            return CardDataSnapshot(gridCards: [], stats: .empty)
        }

        let now        = Date()
        let todayStart = Calendar.current.startOfDay(for: now)
        var gridCards  = [GridCardInfo]()
        var accum      = StatsAccumulator()

        // Important iOS 17 rule:
        // Avoid predicates that walk optional relationships such as
        // `$0.deck?.persistentModelID == deckID`. They are known to behave
        // pathologically on iOS 17, including runaway memory growth and empty
        // result sets for otherwise valid decks. Once the deck is resolved in
        // this same context, reading `deck.cards` is the stable path.
        let deckCards = resolvedCards(for: deck, deckID: deckID)
        let cards = deckCards.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }
            if lhs.cardNumber != rhs.cardNumber {
                return lhs.cardNumber < rhs.cardNumber
            }
            return lhs.createdAt < rhs.createdAt
        }

        for card in cards {
            autoreleasepool {
                let frontText = card.frontText
                let backText = card.backText
                gridCards.append(GridCardInfo(
                    id:                   card.persistentModelID,
                    kind:                 card.kind,
                    creationSource:       card.creationSource,
                    conversionMetadata:   card.conversionMetadata,
                    cardNumber:           card.cardNumber,
                    interval:             card.interval,
                    reviewHistoryIsEmpty: card.reviewHistory.isEmpty,
                    isPinned:             card.isPinned,
                    frontText:            frontText,
                    backText:             backText,
                    frontPreviewText:     lightweightPreviewText(from: frontText),
                    backPreviewText:      lightweightPreviewText(from: backText),
                    searchDocumentText:   card.searchDocumentText,
                    createdAt:            card.createdAt,
                    editedAt:             card.editedAt
                ))
                accum.accumulate(card: card, now: now, todayStart: todayStart)
            }
        }

        // Flush heavy CardModel objects from RAM immediately after projecting
        // them into lightweight GridCardInfo structs.
        flushContext()

        return CardDataSnapshot(
            gridCards: gridCards,
            stats:     accum.build(count: gridCards.count)
        )
    }

    /// Fetches full heterogeneous card payloads for a conversion run without
    /// exposing live `CardModel` instances to the main actor.
    func fetchConversionSources(
        deckID: PersistentIdentifier,
        cardIDs: [PersistentIdentifier]? = nil
    ) -> [CardConversionSourceSnapshot] {
        guard let deck = activeContext.model(for: deckID) as? DeckModel else {
            return []
        }

        let deckCards = resolvedCards(for: deck, deckID: deckID)
        let filteredCards: [CardModel]
        if let cardIDs, !cardIDs.isEmpty {
            let allowedIDs = Set(cardIDs)
            filteredCards = deckCards.filter { allowedIDs.contains($0.persistentModelID) }
        } else {
            filteredCards = deckCards
        }

        let orderedCards = filteredCards.sorted { lhs, rhs in
            if lhs.cardNumber != rhs.cardNumber {
                return lhs.cardNumber < rhs.cardNumber
            }
            return lhs.createdAt < rhs.createdAt
        }

        let projected = orderedCards.map { card in
            CardConversionSourceSnapshot(
                id: card.persistentModelID,
                kind: card.kind,
                content: card.cardContent
            )
        }

        flushContext()
        return projected
    }

    /// Resolves cards for the deck using the direct relationship first, then
    /// falls back to a whole-store scan when SwiftData returns an empty
    /// relationship for a deck that still reports a non-zero denormalized
    /// `cardCount`. This guards pathological iOS 17 cases without using an
    /// optional-relationship predicate on a hot path.
    private func resolvedCards(for deck: DeckModel, deckID: PersistentIdentifier) -> [CardModel] {
        let directCards = deck.cards
        if !directCards.isEmpty || deck.cardCount == 0 {
            return directCards
        }

        let descriptor = FetchDescriptor<CardModel>()
        guard let allCards = try? activeContext.fetch(descriptor) else {
            return directCards
        }

        return allCards.filter { card in
            card.deck?.persistentModelID == deckID
        }
    }

    /// Produces a very cheap deck-grid preview string. This intentionally avoids
    /// the richer math sanitizer path, because some AI-generated LaTeX-heavy
    /// cards can trigger pathological memory spikes during snapshot loading on
    /// iOS 17.
    private func lightweightPreviewText(from text: String) -> String {
        let normalizedLineBreaks = text.replacingOccurrences(of: "\r\n", with: "\n")
        let collapsedWhitespace = normalizedLineBreaks
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if collapsedWhitespace.caseInsensitiveCompare("empty") == .orderedSame {
            return ""
        }

        return String(collapsedWhitespace.prefix(200))
    }

    // MARK: - Thumbnail Generation

    /// Generates a compressed thumbnail payload for the card identified by `id`.
    ///
    /// This method reads the raw zone data blobs, flushes the context to free memory,
    /// and then decodes and downsamples the first image or sketch found in the zone tree.
    /// Flushing before decoding ensures that the heavy `Data` blobs stored in the
    /// `ModelContext` row cache are released before the CPU-intensive decode step begins.
    ///
    /// - Parameter id: The `PersistentIdentifier` of the target `CardModel`.
    /// - Returns: A ``CardPreviewPayload`` containing the thumbnail and media presence flags,
    ///   or `nil` if the card cannot be found in the store.
    func generateThumbnail(for id: PersistentIdentifier) -> CardPreviewPayload? {
        guard let card = activeContext.model(for: id) as? CardModel else { return nil }

        let frontData = card.frontZoneData
        let backData  = card.backZoneData

        // Flush the database from RAM before the CPU-intensive image decode step.
        flushContext()

        let frontZone = frontData.flatMap { ZoneModel.decode(from: $0) }
        let backZone  = backData.flatMap  { ZoneModel.decode(from: $0) }

        let rawImageData = frontZone.flatMap { getFirstImageData(from: $0) }
                        ?? backZone.flatMap  { getFirstImageData(from: $0) }

        let thumbData = rawImageData.flatMap { raw -> Data? in
            let maxPx: CGFloat = 88 * 3
            return downsample(data: raw, maxDimension: maxPx)
                .flatMap { $0.jpegData(compressionQuality: 0.6) }
        }

        return CardPreviewPayload(
            thumbnailData:  thumbData,
            hasFrontImage:  frontZone.map { containsMedia($0, contentType: .image)  } ?? false,
            hasFrontSketch: frontZone.map { containsMedia($0, contentType: .sketch) } ?? false
        )
    }

    // MARK: - Lifecycle

    /// Performs cleanup when the actor is no longer needed.
    ///
    /// Replaces the active context with a fresh one so that any models
    /// still retained in the row cache are deallocated before the actor itself
    /// is released by ARC.
    func tearDown() {
        flushContext()
    }
}

// MARK: - StatsAccumulator

/// A mutable value type that accumulates per-card review statistics
/// during a single pass over a card collection.
///
/// Designed for use inside ``CardFetchActor`` only. Not thread-safe.
private struct StatsAccumulator {

    // MARK: - Accumulation State

    /// Running total of review events across all processed cards.
    var totalReviews   = 0

    /// Running total of review events rated `.good` or better.
    var correctReviews = 0

    /// Running total of XP awarded across all review events.
    var totalXP        = 0

    /// Running count of cards whose `dueDate` is on or before the current time.
    var dueCards       = 0

    /// Running sum of per-card mastery scores; divided by card count to produce the average.
    var masterySum     = 0.0

    /// Running count of review events that occurred today (since midnight local time).
    var todayReviewed  = 0

    nonisolated init() {}

    // MARK: - Mutation

    /// Incorporates the statistics of a single card into the accumulator.
    ///
    /// - Parameters:
    ///   - card: The `CardModel` to process.
    ///   - now: The reference timestamp for due-date comparison.
    ///   - todayStart: Midnight in the user's local time zone, used for today's review count.
    nonisolated mutating func accumulate(card: CardModel, now: Date, todayStart: Date) {
        let history     = card.reviewHistory
        totalReviews   += history.count
        correctReviews += history.filter { $0.difficultyRaw >= ReviewDifficulty.good.rawValue }.count
        totalXP        += history.reduce(0) { $0 + $1.xpAwarded }
        if card.dueDate <= now { dueCards += 1 }
        todayReviewed  += history.filter { $0.timestamp >= todayStart }.count
        masterySum     += Self.masteryScore(for: card)
    }

    // MARK: - Build

    /// Produces a finalised ``DeckStats`` value from the accumulated data.
    ///
    /// - Parameter count: The total number of cards processed (used as the denominator
    ///   for mastery averaging).
    /// - Returns: A populated ``DeckStats`` snapshot.
    nonisolated func build(count: Int) -> DeckStats {
        DeckStats(
            totalCards:    count,
            dueCards:      dueCards,
            totalReviews:  totalReviews,
            accuracy:      totalReviews > 0
                ? Int(Double(correctReviews) / Double(totalReviews) * 100) : 0,
            totalXPEarned: totalXP,
            deckMastery:   count > 0 ? masterySum / Double(count) : 0.0,
            todayReviewed: todayReviewed
        )
    }

    // MARK: - Mastery Scoring

    /// Calculates a normalised mastery score for a single card based on its SRS interval
    /// and ease factor.
    ///
    /// Cards with no review history return `0.0`. Cards with a long interval and a high
    /// ease factor approach `1.0`. The scale is intentionally non-linear to reward
    /// sustained retention over raw review volume.
    ///
    /// - Parameter card: The `CardModel` to score.
    /// - Returns: A `Double` in the range `[0.0, 1.0]`.
    nonisolated static func masteryScore(for card: CardModel) -> Double {
        guard !card.reviewHistory.isEmpty else { return 0.0 }
        switch card.interval {
        case 0:       return 0.10
        case 1:       return 0.15
        case 2...3:   return 0.25
        case 4...6:   return 0.40
        case 7...10:  return 0.58
        case 11...14: return 0.70
        case 15...20: return 0.82
        default:
            let easeNorm = (card.easeFactor - 1.3) / (2.5 - 1.3)
            return min(0.90 + easeNorm * 0.10, 1.0)
        }
    }
}
