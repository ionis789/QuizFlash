//
//  ReviewModels.swift
//  QuizFlash
//
//  Domain models for the Spaced-Repetition System (SRS) review pipeline.
//  `ReviewDifficulty` is the user-facing rating scale; `ReviewEvent` is
//  the immutable audit record stored for every swipe.
//

import Foundation
import SwiftData

// MARK: - ReviewDifficulty

/// The rating a user assigns to a card after reviewing it.
///
/// Raw values map to SM-2 algorithm grades and are persisted in `ReviewEvent`.
enum ReviewDifficulty: Int, Codable {
    /// The user could not recall the answer — resets the interval to 1 day.
    case again = 0
    /// The user recalled the answer with significant effort.
    case hard  = 1
    /// The user recalled the answer correctly with acceptable effort.
    case good  = 2
    /// The user recalled the answer effortlessly — maximum interval increase.
    case easy  = 3
}

// MARK: - ReviewEvent

/// An immutable record of a single card review, appended to `CardModel.reviewHistory`
/// after every swipe.
///
/// Storing `difficultyRaw` (the enum's `Int` backing) instead of a string keeps
/// the schema migration surface small and preserves full `Codable` round-tripping.
@Model
class ReviewEvent {

    // MARK: - Stored Properties

    /// Timestamp of the moment the user swiped the card.
    var timestamp: Date = Date()

    /// Duration in seconds the card was visible before the user made a decision.
    var timeSpent: TimeInterval

    /// Raw integer value of the `ReviewDifficulty` enum case.
    ///
    /// Stored as an `Int` so that adding enum cases in the future does not
    /// require a SwiftData schema migration.
    var difficultyRaw: Int

    /// XP awarded for this review (base XP ± speed bonus).
    var xpAwarded: Int

    /// Stable Firestore document ID for cloud sync. Nil until the review event is uploaded.
    var cloudID: String?

    /// Firebase Auth UID that owns the cloud copy of this review event.
    var ownerUID: String?

    /// Last successful cloud sync timestamp.
    var lastSyncedAt: Date?

    /// Inverse relationship back to the card that was reviewed.
    var card: CardModel?

    // MARK: - Computed Properties

    /// Type-safe accessor for the review difficulty.
    ///
    /// Falls back to `.good` if a stored raw value does not match any known case
    /// (forward-compatibility guard for future enum additions).
    var difficulty: ReviewDifficulty {
        get { ReviewDifficulty(rawValue: difficultyRaw) ?? .good }
        set { difficultyRaw = newValue.rawValue }
    }

    // MARK: - Init

    /// Creates a new `ReviewEvent` with the current timestamp.
    ///
    /// - Parameters:
    ///   - timeSpent: Seconds the card was on screen before the swipe.
    ///   - difficulty: The user's self-assessed difficulty rating.
    ///   - xpAwarded: XP credited to the user for this review.
    init(timeSpent: TimeInterval, difficulty: ReviewDifficulty, xpAwarded: Int) {
        self.timeSpent     = timeSpent
        self.difficultyRaw = difficulty.rawValue
        self.xpAwarded     = xpAwarded
        self.timestamp     = Date()
    }
}
