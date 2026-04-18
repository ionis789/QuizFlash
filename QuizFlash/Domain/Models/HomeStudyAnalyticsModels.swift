//
//  HomeStudyAnalyticsModels.swift
//  QuizFlash
//
//  Persisted Home-specific analytics aggregates keyed by study day.
//

import Foundation
import SwiftData

// MARK: - Home Analytics Day Key

/// Shared day-key helpers used by Home analytics aggregates and background rebuilds.
nonisolated enum HomeAnalyticsDayKey {
    static func normalizedDay(
        for date: Date,
        calendar: Calendar = .current
    ) -> Date {
        calendar.startOfDay(for: date)
    }

    static func make(
        from date: Date,
        calendar: Calendar = .current
    ) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: normalizedDay(for: date, calendar: calendar))
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}

// MARK: - Home Analytics Identifier Codec

/// Encodes `PersistentIdentifier` values into stable string keys for aggregate rows.
nonisolated enum HomeAnalyticsIdentifierCodec {
    static func encode(_ id: PersistentIdentifier) -> String {
        guard
            let data = try? JSONEncoder().encode(id),
            let string = String(data: data, encoding: .utf8)
        else {
            return String(describing: id)
        }
        return string
    }
}

// MARK: - Home Daily Study Aggregate

/// Day-level Home analytics used by the weekly chart and hero summary.
@Model
final class HomeDailyStudyAggregate {
    @Attribute(.unique) var dayKey: String
    var dayDate: Date
    var uniqueCardCount: Int
    var rawReviewCount: Int
    var landedCount: Int
    var retryCount: Int
    var xpEarned: Int
    var newCardsLearned: Int
    var dailyGoal: Int

    init(
        dayDate: Date,
        uniqueCardCount: Int = 0,
        rawReviewCount: Int = 0,
        landedCount: Int = 0,
        retryCount: Int = 0,
        xpEarned: Int = 0,
        newCardsLearned: Int = 0,
        dailyGoal: Int = 50
    ) {
        let normalizedDay = HomeAnalyticsDayKey.normalizedDay(for: dayDate)
        self.dayKey = HomeAnalyticsDayKey.make(from: normalizedDay)
        self.dayDate = normalizedDay
        self.uniqueCardCount = uniqueCardCount
        self.rawReviewCount = rawReviewCount
        self.landedCount = landedCount
        self.retryCount = retryCount
        self.xpEarned = xpEarned
        self.newCardsLearned = newCardsLearned
        self.dailyGoal = dailyGoal
    }
}

// MARK: - Home Daily Deck Aggregate

/// Selected-day deck breakdown snapshot used by the Home detail card.
@Model
final class HomeDailyDeckAggregate {
    @Attribute(.unique) var aggregateKey: String
    var dayKey: String
    var dayDate: Date
    var deckIdentifier: String
    var deckTitleSnapshot: String
    var deckColorHexSnapshot: String
    var uniqueCardCount: Int
    var landedCount: Int
    var retryCount: Int

    @Relationship(deleteRule: .nullify) var deck: DeckModel?

    init(
        dayDate: Date,
        deckIdentifier: String,
        deck: DeckModel?,
        deckTitleSnapshot: String,
        deckColorHexSnapshot: String,
        uniqueCardCount: Int = 0,
        landedCount: Int = 0,
        retryCount: Int = 0
    ) {
        let normalizedDay = HomeAnalyticsDayKey.normalizedDay(for: dayDate)
        let dayKey = HomeAnalyticsDayKey.make(from: normalizedDay)
        self.aggregateKey = "\(dayKey)|\(deckIdentifier)"
        self.dayKey = dayKey
        self.dayDate = normalizedDay
        self.deckIdentifier = deckIdentifier
        self.deck = deck
        self.deckTitleSnapshot = deckTitleSnapshot
        self.deckColorHexSnapshot = deckColorHexSnapshot
        self.uniqueCardCount = uniqueCardCount
        self.landedCount = landedCount
        self.retryCount = retryCount
    }
}

// MARK: - Home Daily Card Aggregate

/// Lightweight selected-day card history row used inside the Home breakdown viewport.
@Model
final class HomeDailyCardAggregate {
    @Attribute(.unique) var aggregateKey: String
    var dayKey: String
    var dayDate: Date
    var cardIdentifier: String
    var deckIdentifier: String
    var deckAggregateKey: String
    var deckTitleSnapshot: String
    var deckColorHexSnapshot: String
    var cardTitleSnapshot: String
    var finalDifficultyRaw: Int
    var repeatCount: Int
    var lastReviewedAt: Date

    @Relationship(deleteRule: .nullify) var card: CardModel?
    @Relationship(deleteRule: .nullify) var deck: DeckModel?

    var finalDifficulty: ReviewDifficulty {
        get { ReviewDifficulty(rawValue: finalDifficultyRaw) ?? .good }
        set { finalDifficultyRaw = newValue.rawValue }
    }

    init(
        dayDate: Date,
        cardIdentifier: String,
        deckIdentifier: String,
        card: CardModel?,
        deck: DeckModel?,
        deckTitleSnapshot: String,
        deckColorHexSnapshot: String,
        cardTitleSnapshot: String,
        finalDifficulty: ReviewDifficulty,
        repeatCount: Int,
        lastReviewedAt: Date
    ) {
        let normalizedDay = HomeAnalyticsDayKey.normalizedDay(for: dayDate)
        let dayKey = HomeAnalyticsDayKey.make(from: normalizedDay)
        self.aggregateKey = "\(dayKey)|\(cardIdentifier)"
        self.dayKey = dayKey
        self.dayDate = normalizedDay
        self.cardIdentifier = cardIdentifier
        self.deckIdentifier = deckIdentifier
        self.deckAggregateKey = "\(dayKey)|\(deckIdentifier)"
        self.card = card
        self.deck = deck
        self.deckTitleSnapshot = deckTitleSnapshot
        self.deckColorHexSnapshot = deckColorHexSnapshot
        self.cardTitleSnapshot = cardTitleSnapshot
        self.finalDifficultyRaw = finalDifficulty.rawValue
        self.repeatCount = repeatCount
        self.lastReviewedAt = lastReviewedAt
    }
}
