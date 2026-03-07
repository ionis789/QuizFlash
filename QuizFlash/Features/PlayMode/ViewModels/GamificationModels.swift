//
//  GamificationModels.swift
//  QuizFlash
//
//  SwiftData models that power the app's gamification layer:
//  XP accumulation, level progression, streaks, and the daily activity
//  heatmap that feeds the Statistics screen.
//

import Foundation
import SwiftData

// MARK: - UserProfile

/// Stores the player's global gamification state: total XP, current streak,
/// longest streak, and the last date the app was actively used.
///
/// Level is derived dynamically from `totalXP` so no migration is required
/// when the levelling formula changes.
@Model
class UserProfile {

    // MARK: - Stored Properties

    /// Cumulative XP earned across all study sessions.
    var totalXP: Int = 0

    /// Number of consecutive calendar days the user has studied.
    var currentStreak: Int = 0

    /// All-time longest streak the user has achieved.
    var longestStreak: Int = 0

    /// The most recent date on which the user completed at least one swipe.
    var lastActiveDate: Date?

    // MARK: - Computed Properties

    /// Current level, calculated as one level per 500 XP (level 1 at 0 XP).
    ///
    /// The formula is intentionally linear to keep it predictable. It can be
    /// swapped for an exponential curve (RPG-style) without a data migration
    /// because `level` is not stored.
    var level: Int {
        (totalXP / 500) + 1
    }

    // MARK: - Init

    init(
        totalXP: Int = 0,
        currentStreak: Int = 0,
        longestStreak: Int = 0,
        lastActiveDate: Date? = nil
    ) {
        self.totalXP       = totalXP
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.lastActiveDate = lastActiveDate
    }
}

// MARK: - DailyActivityLog

/// A per-day record of study activity, used to render the calendar heatmap
/// on the Statistics screen.
///
/// Keyed by a `"yyyy-MM-dd"` string so that heatmap queries can use an exact
/// predicate match rather than a date-range scan, which is significantly faster
/// for large history tables.
@Model
class DailyActivityLog {

    // MARK: - Stored Properties

    /// Date key in `"yyyy-MM-dd"` format. Marked unique to prevent duplicate entries.
    @Attribute(.unique) var dateString: String

    /// The actual `Date` value for the day this log represents.
    var date: Date

    /// Number of flashcard reviews completed on this day.
    var cardsReviewed: Int = 0

    /// Number of cards encountered for the first time (new cards) on this day.
    var newCardsLearned: Int = 0

    /// Total XP earned during this calendar day.
    var xpEarnedToday: Int = 0

    /// The daily review target set by the user. Configurable via Settings.
    var dailyGoal: Int = 50

    // MARK: - Computed Properties

    /// `true` when the user reached or exceeded their daily review goal.
    ///
    /// A perfect day is displayed with a fully-saturated tile in the heatmap.
    var isPerfectDay: Bool {
        cardsReviewed >= dailyGoal
    }

    // MARK: - Init

    /// Creates a new log entry for the given date.
    ///
    /// - Parameters:
    ///   - date: The calendar day this log represents. Defaults to today.
    ///   - dailyGoal: The review target for the day. Defaults to 50 cards.
    init(date: Date = Date(), dailyGoal: Int = 50) {
        self.date      = date
        self.dailyGoal = dailyGoal
        // Build the unique string key once at insertion time.
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        self.dateString = formatter.string(from: date)
    }
}
