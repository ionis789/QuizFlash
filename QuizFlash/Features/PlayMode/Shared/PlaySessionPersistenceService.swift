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

        for review in reviews {
            guard let card = fetchCard(id: review.cardID, in: bgContext) else {
                continue
            }

            let reviewEvent = ReviewEvent(
                timeSpent: review.timeSpent,
                difficulty: review.difficulty,
                xpAwarded: review.xpAwarded
            )
            card.reviewHistory.append(reviewEvent)
            applySpacedRepetition(review.difficulty, to: card)

            savedReviewCount += 1
            totalXP += review.xpAwarded
        }

        guard savedReviewCount > 0 else { return }

        updateDailyActivityLog(
            reviewCount: savedReviewCount,
            totalXP: totalXP,
            in: bgContext
        )
        updateUserProfile(totalXP: totalXP, in: bgContext)

        do {
            try bgContext.save()
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
        in context: ModelContext
    ) {
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

    // MARK: - Formatters

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
