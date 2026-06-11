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

    /// Pre-computed activity summary for the current local day in this deck.
    let todayActivity: DeckTodayActivitySummary

    /// Pre-computed grouped review history for the current deck.
    let activityHistory: DeckActivityHistorySummary
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
            return CardDataSnapshot(
                gridCards: [],
                stats: .empty,
                todayActivity: .placeholder(),
                activityHistory: .placeholder()
            )
        }

        let now        = Date()
        let todayStart = Calendar.current.startOfDay(for: now)
        var gridCards  = [GridCardInfo]()
        var accum      = StatsAccumulator()
        var activityAccum = DeckTodayActivityAccumulator(referenceDate: now)
        var historyAccum = DeckActivityHistoryAccumulator(referenceDate: now)

        // Important iOS 17 rule:
        // Avoid predicates that walk optional relationships such as
        // `$0.deck?.persistentModelID == deckID`. They are known to behave
        // pathologically on iOS 17, including runaway memory growth and empty
        // result sets for otherwise valid decks. Once the deck is resolved in
        // this same context, reading `deck.cards` is the stable path.
        let cards = resolvedCards(for: deck, deckID: deckID)
            .map(CardSortEntry.init(card:))
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned {
                    return lhs.isPinned && !rhs.isPinned
                }
                if lhs.cardNumber != rhs.cardNumber {
                    return lhs.cardNumber < rhs.cardNumber
                }
                return lhs.createdAt < rhs.createdAt
            }

        for entry in cards {
            autoreleasepool {
                let card = entry.card
                let frontText = card.frontText
                let backText = card.backText
                let activityTitle = deckActivityTitle(frontText: frontText, backText: backText)
                gridCards.append(GridCardInfo(
                    id:                   card.persistentModelID,
                    kind:                 card.kind,
                    creationSource:       card.creationSource,
                    cardNumber:           entry.cardNumber,
                    interval:             card.interval,
                    reviewHistoryIsEmpty: card.reviewHistory.isEmpty,
                    isPinned:             entry.isPinned,
                    frontText:            frontText,
                    backText:             backText,
                    frontPreviewText:     lightweightPreviewText(from: frontText),
                    backPreviewText:      lightweightPreviewText(from: backText),
                    searchDocumentText:   card.searchDocumentText,
                    createdAt:            card.createdAt,
                    editedAt:             card.editedAt
                ))
                accum.accumulate(card: card, now: now, todayStart: todayStart)
                activityAccum.accumulate(
                    cardID: card.persistentModelID,
                    title: activityTitle,
                    reviewHistory: card.reviewHistory,
                    todayStart: todayStart
                )
                historyAccum.accumulate(
                    cardID: card.persistentModelID,
                    title: activityTitle,
                    reviewHistory: card.reviewHistory
                )
            }
        }

        // Flush heavy CardModel objects from RAM immediately after projecting
        // them into lightweight GridCardInfo structs.
        flushContext()

        return CardDataSnapshot(
            gridCards: gridCards,
            stats:     accum.build(count: gridCards.count),
            todayActivity: activityAccum.build(),
            activityHistory: historyAccum.build()
        )
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

    /// Produces a stable lightweight title for deck-activity cards without
    /// invoking richer preview sanitizers on the hot snapshot path.
    private func deckActivityTitle(frontText: String, backText: String) -> String {
        let frontPreview = lightweightPreviewText(from: frontText)
        if !frontPreview.isEmpty {
            return frontPreview
        }

        let backPreview = lightweightPreviewText(from: backText)
        if !backPreview.isEmpty {
            return backPreview
        }

        return "Untitled card"
    }

    private struct CardSortEntry {
        let card: CardModel
        let isPinned: Bool
        let cardNumber: Int
        let createdAt: Date

        init(card: CardModel) {
            self.card = card
            self.isPinned = card.isPinned
            self.cardNumber = card.cardNumber
            self.createdAt = card.createdAt
        }
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
        let previewContent = card.cardContent

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
            hasFrontSketch: frontZone.map { containsMedia($0, contentType: .sketch) } ?? false,
            previewContent: previewContent
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
        let history = card.reviewHistory
        for event in history {
            totalReviews += 1
            totalXP += event.xpAwarded
            if event.difficultyRaw >= ReviewDifficulty.good.rawValue {
                correctReviews += 1
            }
            if event.timestamp >= todayStart {
                todayReviewed += 1
            }
        }
        if card.dueDate <= now { dueCards += 1 }
        masterySum += Self.masteryScore(for: card)
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

/// Accumulates lightweight card-review activity for the current local day.
private struct DeckTodayActivityAccumulator {
    let referenceDate: Date
    var uniqueCardsReviewed = 0
    var rawReviewCount = 0
    var landedCount = 0
    var retryCount = 0
    var cards: [DeckTodayReviewedCardSummary] = []

    nonisolated mutating func accumulate(
        cardID: PersistentIdentifier,
        title: String,
        reviewHistory: [ReviewEvent],
        todayStart: Date
    ) {
        var reviewCount = 0
        var lastEvent: ReviewEvent?

        for event in reviewHistory where event.timestamp >= todayStart {
            reviewCount += 1
            if let currentLast = lastEvent {
                if event.timestamp >= currentLast.timestamp {
                    lastEvent = event
                }
            } else {
                lastEvent = event
            }
        }

        guard let lastEvent else { return }

        uniqueCardsReviewed += 1
        rawReviewCount += reviewCount

        if lastEvent.difficulty == .again {
            retryCount += 1
        } else {
            landedCount += 1
        }

        cards.append(
            DeckTodayReviewedCardSummary(
                id: cardID,
                title: title,
                finalDifficulty: lastEvent.difficulty,
                reviewCount: reviewCount,
                lastReviewedAt: lastEvent.timestamp
            )
        )
    }

    nonisolated func build() -> DeckTodayActivitySummary {
        guard uniqueCardsReviewed > 0 else {
            return .placeholder(referenceDate: referenceDate)
        }

        let locale = AppPreferences.persistedResolvedLocale

        let sortedCards = cards.sorted { lhs, rhs in
            if lhs.lastReviewedAt != rhs.lastReviewedAt {
                return lhs.lastReviewedAt > rhs.lastReviewedAt
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        let rawReviewLabel = AppLocalization.numbered(
            rawReviewCount,
            singular: "%d pass",
            plural: "%d passes",
            locale: locale
        )
        let uniqueLabel = AppLocalization.numbered(
            uniqueCardsReviewed,
            singular: "%d card",
            plural: "%d cards",
            locale: locale
        )
        let retryDetail: String
        if retryCount == 0 {
            retryDetail = AppLocalization.string("Clean finish so far.", locale: locale)
        } else if retryCount == 1 {
            retryDetail = AppLocalization.string("1 still needs another pass.", locale: locale)
        } else {
            let format = AppLocalization.string("%d still need another pass.", locale: locale)
            retryDetail = String(format: format, locale: locale, retryCount)
        }
        let detailFormat = AppLocalization.string("%@ folded into %@. %@", locale: locale)
        let headline = AppLocalization.numbered(
            uniqueCardsReviewed,
            singular: "%d card moved today",
            plural: "%d cards moved today",
            locale: locale
        )

        return DeckTodayActivitySummary(
            activityDate: referenceDate,
            activityLabel: AppLocalization.string("Today", locale: locale),
            uniqueCardsReviewed: uniqueCardsReviewed,
            rawReviewCount: rawReviewCount,
            landedCount: landedCount,
            retryCount: retryCount,
            headline: headline,
            detailLine: String(format: detailFormat, locale: locale, rawReviewLabel, uniqueLabel, retryDetail),
            cards: sortedCards
        )
    }
}

/// Accumulates lightweight deck-review activity grouped by local day.
private struct DeckActivityHistoryAccumulator {
    let referenceDate: Date
    let calendar = Calendar.current
    var dayBuckets: [Date: DeckActivityHistoryDayAccumulator] = [:]

    nonisolated mutating func accumulate(
        cardID: PersistentIdentifier,
        title: String,
        reviewHistory: [ReviewEvent]
    ) {
        guard !reviewHistory.isEmpty else { return }

        var cardDayBuckets: [Date: DeckActivityHistoryCardAccumulator] = [:]

        for event in reviewHistory {
            let dayStart = calendar.startOfDay(for: event.timestamp)
            var bucket = cardDayBuckets[dayStart] ?? DeckActivityHistoryCardAccumulator()
            bucket.record(event: event)
            cardDayBuckets[dayStart] = bucket
        }

        for (dayStart, cardBucket) in cardDayBuckets {
            var dayBucket = dayBuckets[dayStart] ?? DeckActivityHistoryDayAccumulator(activityDate: dayStart)
            dayBucket.append(
                cardID: cardID,
                title: title,
                cardBucket: cardBucket
            )
            dayBuckets[dayStart] = dayBucket
        }
    }

    nonisolated func build() -> DeckActivityHistorySummary {
        let sortedDays = dayBuckets.values
            .sorted { lhs, rhs in lhs.activityDate > rhs.activityDate }
            .map { $0.build(referenceDate: referenceDate, calendar: calendar) }

        return DeckActivityHistorySummary(
            totalActiveDays: sortedDays.count,
            totalRawReviewCount: sortedDays.reduce(into: 0) { partial, day in
                partial += day.rawReviewCount
            },
            daySummaries: sortedDays
        )
    }
}

private struct DeckActivityHistoryCardAccumulator {
    var reviewCount = 0
    var finalDifficulty: ReviewDifficulty = .again
    var lastReviewedAt: Date = .distantPast

    nonisolated init() {}

    nonisolated mutating func record(event: ReviewEvent) {
        reviewCount += 1
        if event.timestamp >= lastReviewedAt {
            lastReviewedAt = event.timestamp
            finalDifficulty = event.difficulty
        }
    }
}

private struct DeckActivityHistoryDayAccumulator {
    let activityDate: Date
    var uniqueCardsReviewed = 0
    var rawReviewCount = 0
    var landedCount = 0
    var retryCount = 0
    var cards: [DeckTodayReviewedCardSummary] = []

    nonisolated mutating func append(
        cardID: PersistentIdentifier,
        title: String,
        cardBucket: DeckActivityHistoryCardAccumulator
    ) {
        uniqueCardsReviewed += 1
        rawReviewCount += cardBucket.reviewCount

        if cardBucket.finalDifficulty == .again {
            retryCount += 1
        } else {
            landedCount += 1
        }

        cards.append(
            DeckTodayReviewedCardSummary(
                id: cardID,
                title: title,
                finalDifficulty: cardBucket.finalDifficulty,
                reviewCount: cardBucket.reviewCount,
                lastReviewedAt: cardBucket.lastReviewedAt
            )
        )
    }

    nonisolated func build(referenceDate: Date, calendar: Calendar) -> DeckActivityDaySummary {
        let sortedCards = cards.sorted { lhs, rhs in
            if lhs.lastReviewedAt != rhs.lastReviewedAt {
                return lhs.lastReviewedAt > rhs.lastReviewedAt
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        return DeckActivityDaySummary(
            id: activityDate,
            activityDate: activityDate,
            activityLabel: Self.activityLabel(
                for: activityDate,
                referenceDate: referenceDate,
                calendar: calendar
            ),
            uniqueCardsReviewed: uniqueCardsReviewed,
            rawReviewCount: rawReviewCount,
            landedCount: landedCount,
            retryCount: retryCount,
            cards: sortedCards
        )
    }

    private nonisolated static func activityLabel(
        for date: Date,
        referenceDate: Date,
        calendar: Calendar
    ) -> String {
        let locale = AppPreferences.persistedResolvedLocale

        if calendar.isDate(date, inSameDayAs: referenceDate) {
            return AppLocalization.string("Today", locale: locale)
        }

        if let yesterday = calendar.date(byAdding: .day, value: -1, to: referenceDate),
            calendar.isDate(date, inSameDayAs: yesterday) {
            return AppLocalization.string("Yesterday", locale: locale)
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        formatter.locale = locale
        formatter.calendar = calendar
        return formatter.string(from: date)
    }
}
