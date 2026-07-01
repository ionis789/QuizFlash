//
//  PlaySessionPersistenceService.swift
//  QuizFlash
//
//  Shared detached persistence path for interactive play-mode review writes.
//

import Foundation
import OSLog
import SwiftData

// MARK: - PlaySessionReviewWrite

/// One detached review write emitted by a play-mode session.
struct PlaySessionReviewWrite: Sendable {
    let cardID: PersistentIdentifier
    let difficulty: ReviewDifficulty
    let timeSpent: TimeInterval
    let xpAwarded: Int
}

// MARK: - PlaySessionPersistenceService

/// Persists review events, SRS mutations, and gamification counters on a detached background context.
actor PlaySessionPersistenceService {

    private struct DeckAggregateCacheKey: Hashable {
        let dayKey: String
        let deckID: PersistentIdentifier?
    }

    private struct CardAggregateCacheKey: Hashable {
        let dayKey: String
        let cardID: PersistentIdentifier
    }

    private struct CloudDeckSyncKey: Hashable {
        let ownerUID: String
        let deckID: String
    }

    private struct HomeAnalyticsMutationCache {
        var dayAggregates: [String: HomeDailyStudyAggregate] = [:]
        var deckAggregates: [DeckAggregateCacheKey: HomeDailyDeckAggregate] = [:]
        var cardAggregates: [CardAggregateCacheKey: HomeDailyCardAggregate] = [:]
    }

    // MARK: - Dependencies

    private let container: ModelContainer
    private let logger = Logger(subsystem: "QuizFlash", category: "PlaySessionPersistence")

    // MARK: - Init

    init(container: ModelContainer) {
        self.container = container
    }

    // MARK: - Public

    /// Persists one or more review writes on an isolated background context.
    /// - Parameter reviews: The detached review writes that should be committed.
    func persistReviews(_ reviews: [PlaySessionReviewWrite]) async {
        guard !reviews.isEmpty else { return }

        let bgContext = ModelContext(container)
        bgContext.autosaveEnabled = false

        var savedReviewCount = 0
        var totalXP = 0
        var newCardsLearnedCount = 0
        var analyticsCache = HomeAnalyticsMutationCache()
        var affectedCloudDecks = Set<CloudDeckSyncKey>()

        for review in reviews {
            guard let card = fetchCard(id: review.cardID, in: bgContext) else {
                continue
            }

            let wasNewCard = card.reviewHistory.isEmpty
            let deck = card.deck
            let reviewEvent = ReviewEvent(
                timeSpent: review.timeSpent,
                difficulty: review.difficulty,
                xpAwarded: review.xpAwarded
            )
            reviewEvent.ownerUID = deck?.ownerUID ?? card.ownerUID
            reviewEvent.cloudID = UUID().uuidString
            card.reviewHistory.append(reviewEvent)
            applySpacedRepetition(review.difficulty, to: card)
            card.editedAt = reviewEvent.timestamp
            deck?.editedAt = reviewEvent.timestamp
            updateHomeAnalytics(
                for: reviewEvent,
                card: card,
                wasNewCard: wasNewCard,
                in: bgContext,
                cache: &analyticsCache
            )

            if let ownerUID = deck?.ownerUID ?? card.ownerUID,
               let deckID = deck?.cloudID {
                affectedCloudDecks.insert(CloudDeckSyncKey(ownerUID: ownerUID, deckID: deckID))
            }

            savedReviewCount += 1
            totalXP += review.xpAwarded
            if wasNewCard {
                newCardsLearnedCount += 1
            }
        }

        guard savedReviewCount > 0 else { return }

        let dailyLog = updateDailyActivityLog(
            reviewCount: savedReviewCount,
            totalXP: totalXP,
            newCardsLearned: newCardsLearnedCount,
            in: bgContext
        )
        updateHomeAnalyticsDailyGoal(
            for: dailyLog,
            in: bgContext,
            cache: &analyticsCache
        )
        updateUserProfile(totalXP: totalXP, in: bgContext)

        do {
            try bgContext.save()
            let decksToSync = affectedCloudDecks
            await MainActor.run {
                for key in decksToSync {
                    CloudSyncCoordinator.shared.enqueueUpsert(ownerUID: key.ownerUID, deckID: key.deckID)
                }
            }
        } catch {
            logger.error("Detached session save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Helpers

    private func applySpacedRepetition(_ difficulty: ReviewDifficulty, to card: CardModel) {
        if difficulty == .again {
            card.consecutiveCorrectAnswers = 0
            card.interval = 1
            card.easeFactor = max(1.3, card.easeFactor - 0.2)
        } else {
            card.consecutiveCorrectAnswers += 1

            switch card.consecutiveCorrectAnswers {
            case 1:
                card.interval = 1
            case 2:
                card.interval = 6
            default:
                card.interval = Int(round(Double(card.interval) * card.easeFactor))
            }
        }

        card.dueDate = Calendar.current.date(
            byAdding: .day,
            value: card.interval,
            to: Date()
        ) ?? Date()
    }

    private func fetchCard(
        id: PersistentIdentifier,
        in context: ModelContext
    ) -> CardModel? {
        let descriptor = FetchDescriptor<CardModel>(
            predicate: #Predicate { $0.persistentModelID == id }
        )
        return (try? context.fetch(descriptor))?.first
    }

    private func updateDailyActivityLog(
        reviewCount: Int,
        totalXP: Int,
        newCardsLearned: Int,
        in context: ModelContext
    ) -> DailyActivityLog {
        let todayString = Self.dayFormatter.string(from: Date())
        let descriptor = FetchDescriptor<DailyActivityLog>(
            predicate: #Predicate { $0.dateString == todayString }
        )

        let log: DailyActivityLog
        if let existing = (try? context.fetch(descriptor))?.first {
            log = existing
        } else {
            log = DailyActivityLog(date: Date())
            context.insert(log)
        }

        log.cardsReviewed += reviewCount
        log.xpEarnedToday += totalXP
        log.newCardsLearned += newCardsLearned
        return log
    }

    private func updateUserProfile(totalXP: Int, in context: ModelContext) {
        let descriptor = FetchDescriptor<UserProfile>()

        let profile: UserProfile
        if let existing = (try? context.fetch(descriptor))?.first {
            profile = existing
        } else {
            profile = UserProfile()
            context.insert(profile)
        }

        profile.totalXP += totalXP
        profile.lastActiveDate = Date()
    }

    private func updateHomeAnalytics(
        for reviewEvent: ReviewEvent,
        card: CardModel,
        wasNewCard: Bool,
        in context: ModelContext,
        cache: inout HomeAnalyticsMutationCache
    ) {
        let dayDate = HomeAnalyticsDayKey.normalizedDay(for: reviewEvent.timestamp)
        let dayKey = HomeAnalyticsDayKey.make(from: dayDate)
        let deck = card.deck
        let deckCacheKey = DeckAggregateCacheKey(
            dayKey: dayKey,
            deckID: deck?.persistentModelID
        )
        let cardCacheKey = CardAggregateCacheKey(
            dayKey: dayKey,
            cardID: card.persistentModelID
        )
        let deckIdentifier = deck?.cloudID ?? encode(deck?.persistentModelID)
        let cardIdentifier = card.cloudID ?? encode(card.persistentModelID)
        let deckAggregate = fetchOrCreateDailyDeckAggregate(
            dayDate: dayDate,
            dayKey: dayKey,
            deckCacheKey: deckCacheKey,
            deckIdentifier: deckIdentifier,
            deck: deck,
            in: context,
            cache: &cache
        )
        let existingCardAggregate = fetchDailyCardAggregate(
            cardCacheKey: cardCacheKey,
            aggregateKey: "\(dayKey)|\(cardIdentifier)",
            in: context,
            cache: &cache
        )
        let finalWasCorrect = reviewEvent.difficulty != .again

        let dayAggregate = fetchOrCreateDailyStudyAggregate(
            dayDate: dayDate,
            dayKey: dayKey,
            in: context,
            cache: &cache
        )
        dayAggregate.rawReviewCount += 1
        dayAggregate.xpEarned += reviewEvent.xpAwarded
        if wasNewCard {
            dayAggregate.newCardsLearned += 1
        }

        if let existingCardAggregate {
            let previousWasCorrect = existingCardAggregate.finalDifficulty != .again
            if previousWasCorrect != finalWasCorrect {
                if finalWasCorrect {
                    dayAggregate.landedCount += 1
                    dayAggregate.retryCount = max(dayAggregate.retryCount - 1, 0)
                    deckAggregate.landedCount += 1
                    deckAggregate.retryCount = max(deckAggregate.retryCount - 1, 0)
                } else {
                    dayAggregate.retryCount += 1
                    dayAggregate.landedCount = max(dayAggregate.landedCount - 1, 0)
                    deckAggregate.retryCount += 1
                    deckAggregate.landedCount = max(deckAggregate.landedCount - 1, 0)
                }
            }

            existingCardAggregate.deck = deck
            existingCardAggregate.deckIdentifier = deckIdentifier
            existingCardAggregate.deckAggregateKey = deckAggregate.aggregateKey
            existingCardAggregate.deckTitleSnapshot = normalizedDeckTitle(for: deck)
            existingCardAggregate.deckColorHexSnapshot = normalizedDeckColorHex(for: deck)
            existingCardAggregate.cardTitleSnapshot = normalizedCardTitle(for: card)
            existingCardAggregate.finalDifficulty = reviewEvent.difficulty
            existingCardAggregate.repeatCount += 1
            existingCardAggregate.lastReviewedAt = reviewEvent.timestamp
            return
        }

        dayAggregate.uniqueCardCount += 1
        deckAggregate.uniqueCardCount += 1
        if finalWasCorrect {
            dayAggregate.landedCount += 1
            deckAggregate.landedCount += 1
        } else {
            dayAggregate.retryCount += 1
            deckAggregate.retryCount += 1
        }

        let cardAggregate = HomeDailyCardAggregate(
            dayDate: dayDate,
            cardIdentifier: cardIdentifier,
            deckIdentifier: deckIdentifier,
            card: card,
            deck: deck,
            deckTitleSnapshot: normalizedDeckTitle(for: deck),
            deckColorHexSnapshot: normalizedDeckColorHex(for: deck),
            cardTitleSnapshot: normalizedCardTitle(for: card),
            finalDifficulty: reviewEvent.difficulty,
            repeatCount: 1,
            lastReviewedAt: reviewEvent.timestamp
        )
        context.insert(cardAggregate)
        cache.cardAggregates[cardCacheKey] = cardAggregate
    }

    private func updateHomeAnalyticsDailyGoal(
        for dailyLog: DailyActivityLog,
        in context: ModelContext,
        cache: inout HomeAnalyticsMutationCache
    ) {
        let dayKey = dailyLog.dateString
        guard let aggregate = fetchDailyStudyAggregate(
            dayKey: dayKey,
            in: context,
            cache: &cache
        ) else {
            return
        }
        aggregate.dailyGoal = max(dailyLog.dailyGoal, 1)
    }

    private func fetchOrCreateDailyStudyAggregate(
        dayDate: Date,
        dayKey: String,
        in context: ModelContext,
        cache: inout HomeAnalyticsMutationCache
    ) -> HomeDailyStudyAggregate {
        if let existing = fetchDailyStudyAggregate(
            dayKey: dayKey,
            in: context,
            cache: &cache
        ) {
            return existing
        }

        let aggregate = HomeDailyStudyAggregate(dayDate: dayDate)
        context.insert(aggregate)
        cache.dayAggregates[dayKey] = aggregate
        return aggregate
    }

    private func fetchDailyStudyAggregate(
        dayKey: String,
        in context: ModelContext,
        cache: inout HomeAnalyticsMutationCache
    ) -> HomeDailyStudyAggregate? {
        if let cached = cache.dayAggregates[dayKey] {
            return cached
        }

        let descriptor = FetchDescriptor<HomeDailyStudyAggregate>(
            predicate: #Predicate { $0.dayKey == dayKey }
        )
        let aggregate = (try? context.fetch(descriptor))?.first
        if let aggregate {
            cache.dayAggregates[dayKey] = aggregate
        }
        return aggregate
    }

    private func fetchOrCreateDailyDeckAggregate(
        dayDate: Date,
        dayKey: String,
        deckCacheKey: DeckAggregateCacheKey,
        deckIdentifier: String,
        deck: DeckModel?,
        in context: ModelContext,
        cache: inout HomeAnalyticsMutationCache
    ) -> HomeDailyDeckAggregate {
        let aggregateKey = "\(dayKey)|\(deckIdentifier)"
        if let existing = fetchDailyDeckAggregate(
            deckCacheKey: deckCacheKey,
            aggregateKey: aggregateKey,
            in: context,
            cache: &cache
        ) {
            existing.deck = deck
            existing.deckTitleSnapshot = normalizedDeckTitle(for: deck)
            existing.deckColorHexSnapshot = normalizedDeckColorHex(for: deck)
            return existing
        }

        let aggregate = HomeDailyDeckAggregate(
            dayDate: dayDate,
            deckIdentifier: deckIdentifier,
            deck: deck,
            deckTitleSnapshot: normalizedDeckTitle(for: deck),
            deckColorHexSnapshot: normalizedDeckColorHex(for: deck)
        )
        context.insert(aggregate)
        cache.deckAggregates[deckCacheKey] = aggregate
        return aggregate
    }

    private func fetchDailyDeckAggregate(
        deckCacheKey: DeckAggregateCacheKey,
        aggregateKey: String,
        in context: ModelContext,
        cache: inout HomeAnalyticsMutationCache
    ) -> HomeDailyDeckAggregate? {
        if let cached = cache.deckAggregates[deckCacheKey] {
            return cached
        }

        let descriptor = FetchDescriptor<HomeDailyDeckAggregate>(
            predicate: #Predicate { $0.aggregateKey == aggregateKey }
        )
        let aggregate = (try? context.fetch(descriptor))?.first
        if let aggregate {
            cache.deckAggregates[deckCacheKey] = aggregate
        }
        return aggregate
    }

    private func fetchDailyCardAggregate(
        cardCacheKey: CardAggregateCacheKey,
        aggregateKey: String,
        in context: ModelContext,
        cache: inout HomeAnalyticsMutationCache
    ) -> HomeDailyCardAggregate? {
        if let cached = cache.cardAggregates[cardCacheKey] {
            return cached
        }

        let descriptor = FetchDescriptor<HomeDailyCardAggregate>(
            predicate: #Predicate { $0.aggregateKey == aggregateKey }
        )
        let aggregate = (try? context.fetch(descriptor))?.first
        if let aggregate {
            cache.cardAggregates[cardCacheKey] = aggregate
        }
        return aggregate
    }

    private func encode(_ id: PersistentIdentifier?) -> String {
        guard let id else { return "unassigned" }
        return HomeAnalyticsIdentifierCodec.encode(id)
    }

    private func normalizedDeckTitle(for deck: DeckModel?) -> String {
        let trimmed = deck?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Untitled Deck" : trimmed
    }

    private func normalizedDeckColorHex(for deck: DeckModel?) -> String {
        let color = deck?.colorHex.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return color.isEmpty ? "#70707A" : color
    }

    private func normalizedCardTitle(for card: CardModel?) -> String {
        let primary = card?.frontText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !primary.isEmpty {
            return primary
        }

        let fallback = card?.backText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return fallback.isEmpty ? "Untitled Card" : fallback
    }

    // MARK: - Formatters

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
