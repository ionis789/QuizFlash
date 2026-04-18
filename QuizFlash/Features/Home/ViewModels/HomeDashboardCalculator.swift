// HomeDashboardCalculator.swift
// QuizFlash
//
// Derived Home dashboard and calendar calculations extracted from HomeViewModel.

import Foundation
import SwiftData

private struct HomeDailyReviewAggregate {
    let uniqueCardCount: Int
    let rawReviewCount: Int
    let xpEarned: Int
    let correctCardCount: Int
    let retryCardCount: Int
    let deckSummaries: [HomeWeeklyDeckActivitySummary]

    static let empty = HomeDailyReviewAggregate(
        uniqueCardCount: 0,
        rawReviewCount: 0,
        xpEarned: 0,
        correctCardCount: 0,
        retryCardCount: 0,
        deckSummaries: []
    )
}

extension HomeViewModel {
    /// Produces the short narrative lines shown above the Home exam-goal cards.
    ///
    /// The narrative intentionally stays short and action-oriented rather than
    /// motivational. It uses current goal pressure plus recent activity logs.
    func buildDashboardNarrative(
        upcomingExamSummaries: [HomeExamGoalSummary],
        userProfile: UserProfile?,
        referenceDate: Date = Date()
    ) -> HomeDashboardNarrative? {
        let summaries = Array(upcomingExamSummaries.prefix(6))
        guard !summaries.isEmpty else { return nil }

        let riskGoal = summaries.max { lhs, rhs in
            riskScore(for: lhs) < riskScore(for: rhs)
        }
        let closestWinGoal = summaries.max { lhs, rhs in
            lhs.readinessFraction < rhs.readinessFraction
        }
        let recentStudyDays = recentStudyDayCount(referenceDate: referenceDate)

        let riskLine: String?
        if let riskGoal, let weakestDeck = riskGoal.weakestDeck {
            riskLine = "Risk deck: \(weakestDeck.title) for \(riskGoal.title) has \(weakestDeck.remainingCards) cards still needing work."
        } else {
            riskLine = nil
        }

        let closestWinLine: String?
        if let closestWinGoal {
            closestWinLine = "Closest win: \(closestWinGoal.title) is at \(Int((closestWinGoal.readinessFraction * 100).rounded()))% readiness."
        } else {
            closestWinLine = nil
        }

        let nextBestActionLine: String?
        if let riskGoal, let weakestDeck = riskGoal.weakestDeck {
            let streakText: String
            if let userProfile, userProfile.currentStreak > 0 {
                streakText = " Keep the \(userProfile.currentStreak)-day streak alive."
            } else {
                streakText = ""
            }

            nextBestActionLine = "Next best action: review \(max(riskGoal.dailyPaceNeeded, 1)) cards/day in \(weakestDeck.title). \(recentStudyDays)/7 recent study days.\(streakText)"
        } else {
            nextBestActionLine = nil
        }

        return HomeDashboardNarrative(
            riskDeckLine: riskLine,
            closestWinLine: closestWinLine,
            nextBestActionLine: nextBestActionLine
        )
    }

    /// Refreshes dashboard payloads that stay stable while only the selected day changes.
    func refreshDashboardStaticSnapshot(
        examGoals: [ExamGoalModel],
        userProfile: UserProfile?,
        referenceDate: Date = Date()
    ) {
        let signature = buildDashboardStaticSignature(
            userProfile: userProfile,
            referenceDate: referenceDate
        )
        guard dashboardStaticSignature != signature else { return }
        dashboardStaticSignature = signature

        let upcomingExamSummaries = upcomingExamGoalSummaries(
            from: examGoals,
            referenceDate: referenceDate
        )

        dashboardStaticSnapshot = HomeDashboardStaticSnapshot(
            upcomingExamSummaries: upcomingExamSummaries,
            examPressure: buildExamPressureSummary(from: upcomingExamSummaries),
            examNarrative: buildDashboardNarrative(
                upcomingExamSummaries: upcomingExamSummaries,
                userProfile: userProfile,
                referenceDate: referenceDate
            )
        )
    }

    /// Builds the lightweight greeting widget summary shown at the top of Home.
    ///
    /// The greeting prefers the most recent deck, then falls back to the highest-priority
    /// deck-health candidate, and finally uses today's dashboard context when no deck
    /// destination is available.
    func workspaceOnboardingState(
        allDeckCount: Int,
        folderCount: Int
    ) -> HomeWorkspaceOnboardingState {
        if allDeckCount == 0 {
            return .needsDeck
        }

        if folderCount == 0 && allDeckCount > 1 {
            return .needsFolders
        }

        return .ready
    }

    /// Builds the custom iPad companion summary that mirrors the sticky calendar behaviour.
    func todayFocusSummary(
        userProfile: UserProfile?,
        recentDecks: [DeckModel],
        allDeckCount: Int,
        folderCount: Int,
        referenceDate: Date = Date()
    ) -> HomeTodayFocusHeaderSummary {
        let overview = dashboardSnapshot.selectedDayOverview
        let workspaceState = workspaceOnboardingState(
            allDeckCount: allDeckCount,
            folderCount: folderCount
        )
        let greetingTitle = Self.greetingPhase(for: referenceDate).title

        if workspaceState == .needsDeck {
            return HomeTodayFocusHeaderSummary(
                introTitle: greetingTitle,
                introSubtitle: "Create your first deck to begin.",
                eyebrow: "Start",
                title: "No deck yet",
                detail: "Create a deck to start studying from Home.",
                compactTitle: "No deck yet",
                compactDetail: "Create Deck",
                colorHex: "",
                primaryPill: "",
                secondaryPill: nil,
                progressFraction: 0,
                progressValueText: "New",
                progressLabel: "Start",
                ctaTitle: "Create Deck",
                action: .switchTab(.create)
            )
        }

        if let recentDeck = recentDecks.first {
            let deckTitle = recentDeck.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedTitle = deckTitle.isEmpty ? "Untitled Deck" : deckTitle
            let matchingHealth = deckHealthSummaries.first { $0.id == recentDeck.persistentModelID }
            let remainingCards = max(overview.remainingCardsToGoal, 0)
            let detail: String

            if overview.didReachGoal {
                detail = "Today's goal is closed."
            } else if let lastOpenedAt = recentDeck.lastOpenedAt {
                detail = "Last opened \(Self.relativeTimeLabel(for: lastOpenedAt, referenceDate: referenceDate))."
            } else if let matchingHealth {
                let deckPressure = matchingHealth.dueCards + matchingHealth.newCards
                if deckPressure > 0 {
                    detail = "\(min(deckPressure, max(remainingCards, 1))) cards are ready."
                } else {
                    detail = "\(remainingCards) cards are still open today."
                }
            } else {
                detail = "\(remainingCards) cards are still open today."
            }

            return HomeTodayFocusHeaderSummary(
                introTitle: greetingTitle,
                introSubtitle: "Continue where you left off.",
                eyebrow: overview.didReachGoal ? "Today clear" : "Today goal",
                title: resolvedTitle,
                detail: detail,
                compactTitle: resolvedTitle,
                compactDetail: "Resume Deck",
                colorHex: recentDeck.colorHex,
                primaryPill: "",
                secondaryPill: nil,
                progressFraction: overview.goalCompletionFraction,
                progressValueText: overview.didReachGoal ? "Done" : "\(remainingCards)",
                progressLabel: overview.didReachGoal ? "Today" : "To goal",
                ctaTitle: "Resume Deck",
                action: .openDeck(recentDeck.persistentModelID)
            )
        }

        if let focusDeck = deckHealthSummaries.first {
            let remainingCards = max(overview.remainingCardsToGoal, 0)
            let focusTitle = focusDeck.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Focus deck"
                : focusDeck.title

            return HomeTodayFocusHeaderSummary(
                introTitle: greetingTitle,
                introSubtitle: overview.cardsReviewed == 0
                    ? "Start today's goal from this deck."
                    : "Continue where you left off.",
                eyebrow: overview.didReachGoal ? "Today clear" : "Today goal",
                title: focusTitle,
                detail: overview.cardsReviewed == 0
                    ? "Open this deck to start today's goal."
                    : "\(remainingCards) cards are still open today.",
                compactTitle: focusTitle,
                compactDetail: "Open Deck",
                colorHex: focusDeck.colorHex,
                primaryPill: "",
                secondaryPill: nil,
                progressFraction: overview.goalCompletionFraction,
                progressValueText: overview.didReachGoal ? "Done" : "\(remainingCards)",
                progressLabel: overview.didReachGoal ? "Today" : "To goal",
                ctaTitle: "Open Focus Deck",
                action: .openDeck(focusDeck.id)
            )
        }

        let totalXP = max(userProfile?.totalXP ?? 0, 0)
        let secondaryPill = totalXP > 0 ? "\(totalXP) XP" : nil

        return HomeTodayFocusHeaderSummary(
            introTitle: greetingTitle,
            introSubtitle: overview.didReachGoal
                ? "Today is already closed."
                : "Pick a deck and continue.",
            eyebrow: overview.didReachGoal ? "Today clear" : "Today goal",
            title: Self.greetingPhase(for: referenceDate) == .night ? "Pick a deck for tonight" : "Pick a deck for today",
            detail: overview.didReachGoal
                ? "Today's goal is already closed."
                : "\(overview.remainingCardsToGoal) cards are still open today.",
            compactTitle: overview.didReachGoal ? "Today is clear" : "Pick a deck",
            compactDetail: "Open Home",
            colorHex: "",
            primaryPill: overview.didReachGoal ? "Goal closed" : "\(overview.remainingCardsToGoal) left",
            secondaryPill: secondaryPill,
            progressFraction: overview.goalCompletionFraction,
            progressValueText: overview.didReachGoal ? "Done" : "\(overview.remainingCardsToGoal)",
            progressLabel: overview.didReachGoal ? "Today" : "To goal",
            ctaTitle: nil,
            action: nil
        )
    }

    func greetingSummary(
        userProfile: UserProfile?,
        recentDecks: [DeckModel],
        allDeckCount: Int,
        folderCount: Int,
        referenceDate: Date = Date()
    ) -> HomeGreetingSummary {
        let greetingTitle = Self.greetingPhase(for: referenceDate).title
        let overview = dashboardSnapshot.selectedDayOverview
        let workspaceState = workspaceOnboardingState(
            allDeckCount: allDeckCount,
            folderCount: folderCount
        )

        if workspaceState == .needsDeck {
            return HomeGreetingSummary(
                title: greetingTitle,
                subtitle: "Build your study space",
                contextTitle: "Create your first deck",
                contextLine: "Add one deck and Home will start surfacing progress, momentum and recall cues here.",
                colorHex: "",
                primaryPill: folderCount == 0
                    ? "New workspace"
                    : "\(folderCount) folder\(folderCount == 1 ? "" : "s") ready",
                secondaryPill: nil,
                progressFraction: 0,
                progressValueText: "New",
                progressLabel: "Setup",
                ctaTitle: "Open Create",
                action: .switchTab(.create)
            )
        }

        if let recentDeck = recentDecks.first {
            let deckTitle = recentDeck.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedTitle = deckTitle.isEmpty ? "Untitled Deck" : deckTitle
            let matchingHealth = deckHealthSummaries.first { $0.id == recentDeck.persistentModelID }
            let contextLine: String
            let progressFraction: Double
            let progressValueText: String
            let progressLabel: String

            if let matchingHealth {
                let remainingCards = matchingHealth.dueCards + matchingHealth.newCards
                contextLine = remainingCards == 0
                    ? "This deck looks stable right now. A short pass keeps recall warm."
                    : "\(remainingCards) cards still need attention in this deck."
                progressFraction = matchingHealth.masteryFraction
                progressValueText = "\(Int((matchingHealth.masteryFraction * 100).rounded()))%"
                progressLabel = "Mastery"
            } else if overview.didReachGoal {
                contextLine = "Today's target is already clear. A short review keeps the streak moving."
                progressFraction = overview.goalCompletionFraction
                progressValueText = "Done"
                progressLabel = "Today"
            } else {
                contextLine = "This deck is the cleanest way back into a focused pass without hunting around the library."
                progressFraction = overview.goalCompletionFraction
                progressValueText = "\(overview.remainingCardsToGoal)"
                progressLabel = "To goal"
            }

            return HomeGreetingSummary(
                title: greetingTitle,
                subtitle: "Continue where you left off",
                contextTitle: resolvedTitle,
                contextLine: contextLine,
                colorHex: recentDeck.colorHex,
                primaryPill: "\(recentDeck.cardCount) cards",
                secondaryPill: recentDeck.lastOpenedAt.map {
                    "Opened \(Self.relativeTimeLabel(for: $0, referenceDate: referenceDate))"
                },
                progressFraction: progressFraction,
                progressValueText: progressValueText,
                progressLabel: progressLabel,
                ctaTitle: "Resume Deck",
                action: .openDeck(recentDeck.persistentModelID)
            )
        }

        if let focusDeck = deckHealthSummaries.first {
            return HomeGreetingSummary(
                title: greetingTitle,
                subtitle: "Pick up the deck that needs attention",
                contextTitle: focusDeck.title,
                contextLine: focusDeck.actionLine,
                colorHex: focusDeck.colorHex,
                primaryPill: "\(focusDeck.totalCards) cards",
                secondaryPill: focusDeck.lastOpenedLabel.map { "Opened \($0)" },
                progressFraction: focusDeck.masteryFraction,
                progressValueText: "\(Int((focusDeck.masteryFraction * 100).rounded()))%",
                progressLabel: "Mastery",
                ctaTitle: "Open Focus Deck",
                action: .openDeck(focusDeck.id)
            )
        }

        if workspaceState == .needsFolders {
            return HomeGreetingSummary(
                title: greetingTitle,
                subtitle: "Bring structure to your study space",
                contextTitle: "Group your decks into folders",
                contextLine: "Folders stay closer to the top of Home and make larger libraries easier to scan on both iPhone and iPad.",
                colorHex: "",
                primaryPill: "\(allDeckCount) decks",
                secondaryPill: nil,
                progressFraction: overview.goalCompletionFraction,
                progressValueText: overview.didReachGoal ? "Done" : "\(overview.remainingCardsToGoal)",
                progressLabel: overview.didReachGoal ? "Today" : "To goal",
                ctaTitle: "Create Folder",
                action: .createFolder
            )
        }

        let totalXP = max(userProfile?.totalXP ?? 0, 0)
        let streakCount = max(userProfile?.currentStreak ?? 0, 0)
        let secondaryPill = streakCount > 0 ? "\(streakCount)-day streak" : nil

        return HomeGreetingSummary(
            title: greetingTitle,
            subtitle: "Start a focused study pass",
            contextTitle: overview.headline,
            contextLine: dashboardSnapshot.selectedDayInsight.recommendationLine,
            colorHex: "",
            primaryPill: "\(totalXP) XP",
            secondaryPill: secondaryPill,
            progressFraction: overview.goalCompletionFraction,
            progressValueText: overview.didReachGoal ? "Done" : "\(overview.remainingCardsToGoal)",
            progressLabel: overview.didReachGoal ? "Today" : "To goal",
            ctaTitle: nil,
            action: nil
        )
    }

    // MARK: - Private

    /// Medium date formatter reused by Home exam-goal cards.
    static let mediumDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    /// Weekday-aware label reused by the selected-day Home summary.
    static let selectedDayLabelFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, d MMM"
        return formatter
    }()

    /// Compact weekday formatter used by the Home weekly momentum strip.
    static let shortWeekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEEE"
        return formatter
    }()

    func buildSelectedDayOverview(
        for selectedDate: Date,
        userProfile: UserProfile?,
        cards: [CardModel]
    ) -> HomeSelectedDayOverviewSummary {
        let selectedDateKey = Self.dateKeyFormatter.string(from: selectedDate)
        let cacheKey = [
            selectedDateKey,
            profileSignature(for: userProfile),
            "\(logsCacheRevision)"
        ].joined(separator: "||")

        if let cached = selectedDayOverviewCache[cacheKey] {
            return cached
        }

        let log = getFastLog(for: selectedDate)
        let reviewAggregate = buildDailyReviewAggregate(
            for: selectedDate,
            cards: cards
        )
        let cardsReviewed = reviewAggregate.uniqueCardCount
        let dailyGoal = max(log?.dailyGoal ?? 50, 1)
        let xpEarnedToday = reviewAggregate.xpEarned
        let newCardsLearned = log?.newCardsLearned ?? 0
        let goalCompletionFraction = min(Double(cardsReviewed) / Double(dailyGoal), 1.0)
        let remainingCardsToGoal = max(dailyGoal - cardsReviewed, 0)
        let selectedDateLabel = Self.labelForSelectedDay(selectedDate)

        let headline: String
        let detailLine: String
        if cardsReviewed >= dailyGoal {
            headline = "Goal reached"
            detailLine = "You completed \(cardsReviewed) unique cards on \(selectedDateLabel.lowercased())."
        } else if cardsReviewed > 0 {
            headline = "\(remainingCardsToGoal) cards to target"
            if reviewAggregate.rawReviewCount > cardsReviewed {
                detailLine = "You already covered \(cardsReviewed) unique cards across \(reviewAggregate.rawReviewCount) review passes."
            } else {
                detailLine = "You already covered \(cardsReviewed) unique cards and earned \(xpEarnedToday) XP."
            }
        } else {
            headline = "Fresh study window"
            detailLine = "No study logged for \(selectedDateLabel.lowercased()) yet."
        }

        let summary = HomeSelectedDayOverviewSummary(
            selectedDate: selectedDate,
            selectedDateLabel: selectedDateLabel,
            cardsReviewed: cardsReviewed,
            rawReviewCount: reviewAggregate.rawReviewCount,
            dailyGoal: dailyGoal,
            goalCompletionFraction: goalCompletionFraction,
            remainingCardsToGoal: remainingCardsToGoal,
            xpEarnedToday: xpEarnedToday,
            newCardsLearned: newCardsLearned,
            correctCardCount: reviewAggregate.correctCardCount,
            retryCardCount: reviewAggregate.retryCardCount,
            streakCount: userProfile?.currentStreak ?? 0,
            totalXP: userProfile?.totalXP ?? 0,
            level: userProfile?.level ?? 1,
            headline: headline,
            detailLine: detailLine
        )
        selectedDayOverviewCache[cacheKey] = summary
        return summary
    }

    func buildWeeklyMomentumSummary(
        selectedDate: Date,
        cards: [CardModel]
    ) -> HomeWeeklyMomentumSummary {
        let calendar = AppPreferences.shared.resolvedCalendar
        let startOfSelectedDay = calendar.startOfDay(for: selectedDate)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: startOfSelectedDay)?.start
            ?? startOfSelectedDay
        let weekKey = Self.dateKeyFormatter.string(from: weekStart)
        let cacheKey = [
            weekKey,
            "\(logsCacheRevision)"
        ].joined(separator: "||")

        if let cached = weeklyMomentumCache[cacheKey] {
            return cached
        }

        let daySummaries: [HomeWeeklyDaySummary] = (0..<7).compactMap { index in
            guard let day = calendar.date(byAdding: .day, value: index, to: weekStart) else { return nil }
            let dayKey = Self.dateKeyFormatter.string(from: day)
            let log = logsCache[dayKey]
            let reviewAggregate = buildDailyReviewAggregate(
                for: day,
                cards: cards
            )
            let cardsReviewed = reviewAggregate.uniqueCardCount
            let xpEarned = reviewAggregate.xpEarned
            let goal = max(log?.dailyGoal ?? 50, 1)
            let intensityFraction = min(Double(cardsReviewed) / Double(goal), 1.0)

            return HomeWeeklyDaySummary(
                id: dayKey,
                date: day,
                shortWeekday: Self.shortWeekdayFormatter.string(from: day),
                cardsReviewed: cardsReviewed,
                rawReviewCount: reviewAggregate.rawReviewCount,
                xpEarned: xpEarned,
                goal: goal,
                correctCardCount: reviewAggregate.correctCardCount,
                retryCardCount: reviewAggregate.retryCardCount,
                intensityFraction: intensityFraction,
                didStudy: cardsReviewed > 0 || xpEarned > 0,
                didReachGoal: cardsReviewed >= goal,
                isSelectedDay: calendar.isDate(day, inSameDayAs: startOfSelectedDay)
            )
        }

        let totalCardsReviewed = daySummaries.map(\.cardsReviewed).reduce(0, +)
        let totalXPEarned = daySummaries.map(\.xpEarned).reduce(0, +)
        let activeDays = daySummaries.filter(\.didStudy).count
        let goalHitDays = daySummaries.filter(\.didReachGoal).count
        let averageCardsPerActiveDay = activeDays > 0 ? Int(round(Double(totalCardsReviewed) / Double(activeDays))) : 0
        let averageXPPerActiveDay = activeDays > 0 ? Int(round(Double(totalXPEarned) / Double(activeDays))) : 0
        let consistencyFraction = Double(activeDays) / 7.0
        let bestDay = daySummaries.max { lhs, rhs in
            if lhs.cardsReviewed != rhs.cardsReviewed { return lhs.cardsReviewed < rhs.cardsReviewed }
            return lhs.xpEarned < rhs.xpEarned
        }

        let headline: String
        let detailLine: String
        if activeDays == 0 {
            headline = "No activity yet"
            detailLine = "Your weekly trend will appear as soon as you study."
        } else if goalHitDays > 0 {
            headline = "\(goalHitDays)/7 goal days"
            detailLine = "Average pace is \(averageCardsPerActiveDay) cards on active study days."
        } else {
            headline = "\(activeDays)/7 active days"
            detailLine = "You averaged \(averageCardsPerActiveDay) cards and \(averageXPPerActiveDay) XP when active."
        }

        let summary = HomeWeeklyMomentumSummary(
            totalCardsReviewed: totalCardsReviewed,
            totalXPEarned: totalXPEarned,
            activeDays: activeDays,
            goalHitDays: goalHitDays,
            averageCardsPerActiveDay: averageCardsPerActiveDay,
            averageXPPerActiveDay: averageXPPerActiveDay,
            consistencyFraction: consistencyFraction,
            bestDayLabel: bestDay.map { Self.selectedDayLabelFormatter.string(from: $0.date) },
            headline: headline,
            detailLine: detailLine,
            daySummaries: daySummaries
        )
        weeklyMomentumCache[cacheKey] = summary
        return summary
    }

    fileprivate func buildDailyReviewAggregate(
        for date: Date,
        cards: [CardModel]
    ) -> HomeDailyReviewAggregate {
        let calendar = AppPreferences.shared.resolvedCalendar
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return .empty
        }

        var reviewedCards: [HomeWeeklyReviewedCardSummary] = []
        reviewedCards.reserveCapacity(16)

        var rawReviewCount = 0
        var xpEarned = 0

        for card in cards {
            guard !card.reviewHistory.isEmpty else { continue }

            let dayEvents = card.reviewHistory
                .filter { $0.timestamp >= dayStart && $0.timestamp < dayEnd }

            guard !dayEvents.isEmpty else { continue }

            rawReviewCount += dayEvents.count
            xpEarned += dayEvents.reduce(0) { $0 + $1.xpAwarded }

            guard let finalEvent = dayEvents.max(by: { $0.timestamp < $1.timestamp }) else { continue }

            let deckTitle = normalizedDeckTitle(for: card)
            let cardTitle = normalizedCardTitle(for: card)
            let deckColorHex = card.deck?.colorHex ?? "#70707A"
            let deckID = card.deck?.persistentModelID
            let stableID = "\(Self.dateKeyFormatter.string(from: dayStart))-\(card.persistentModelID.hashValue)"

            reviewedCards.append(
                HomeWeeklyReviewedCardSummary(
                    id: stableID,
                    cardID: card.persistentModelID,
                    deckID: deckID,
                    deckTitle: deckTitle,
                    deckColorHex: deckColorHex,
                    title: cardTitle,
                    finalDifficulty: finalEvent.difficulty,
                    reviewCount: dayEvents.count,
                    lastReviewedAt: finalEvent.timestamp
                )
            )
        }

        let correctCardCount = reviewedCards.filter(\.wasCorrectAtEndOfDay).count
        let retryCardCount = max(reviewedCards.count - correctCardCount, 0)

        let groupedCards = Dictionary(grouping: reviewedCards, by: { reviewedCard in
            "\(reviewedCard.deckID?.hashValue ?? 0)|\(reviewedCard.deckTitle)|\(reviewedCard.deckColorHex)"
        })

        let deckSummaries: [HomeWeeklyDeckActivitySummary] = groupedCards.compactMap { entry in
            let cards = entry.value
            guard let first = cards.first else { return nil }
            let sortedCards = cards.sorted { lhs, rhs in
                if lhs.wasCorrectAtEndOfDay != rhs.wasCorrectAtEndOfDay {
                    return !lhs.wasCorrectAtEndOfDay && rhs.wasCorrectAtEndOfDay
                }
                return lhs.lastReviewedAt > rhs.lastReviewedAt
            }
            let deckCorrect = sortedCards.filter(\.wasCorrectAtEndOfDay).count
            return HomeWeeklyDeckActivitySummary(
                id: "\(Self.dateKeyFormatter.string(from: dayStart))-\(first.deckID?.hashValue ?? first.deckTitle.hashValue)",
                deckID: first.deckID,
                title: first.deckTitle,
                colorHex: first.deckColorHex,
                uniqueCardCount: sortedCards.count,
                correctCardCount: deckCorrect,
                retryCardCount: max(sortedCards.count - deckCorrect, 0),
                cards: sortedCards
            )
        }
        .sorted { lhs, rhs in
            if lhs.retryCardCount != rhs.retryCardCount {
                return lhs.retryCardCount > rhs.retryCardCount
            }
            if lhs.uniqueCardCount != rhs.uniqueCardCount {
                return lhs.uniqueCardCount > rhs.uniqueCardCount
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        return HomeDailyReviewAggregate(
            uniqueCardCount: reviewedCards.count,
            rawReviewCount: rawReviewCount,
            xpEarned: xpEarned,
            correctCardCount: correctCardCount,
            retryCardCount: retryCardCount,
            deckSummaries: deckSummaries
        )
    }

    func buildSelectedDayInsightSummary(
        selectedDate: Date,
        selectedDayOverview: HomeSelectedDayOverviewSummary,
        selectedDayExamSummaries: [HomeExamGoalSummary],
        upcomingExamSummaries: [HomeExamGoalSummary],
        weeklyMomentum: HomeWeeklyMomentumSummary
    ) -> HomeSelectedDayInsightSummary {
        let cacheKey = [
            Self.dateKeyFormatter.string(from: selectedDate),
            selectedDayOverview.headline,
            selectedDayOverview.detailLine,
            "\(selectedDayOverview.cardsReviewed)",
            "\(selectedDayOverview.remainingCardsToGoal)",
            "\(weeklyMomentum.averageCardsPerActiveDay)",
            selectedDayExamSummaries.map(\.id.hashValue).map(String.init).joined(separator: "~"),
            upcomingExamSummaries.map(\.id.hashValue).map(String.init).joined(separator: "~")
        ].joined(separator: "||")

        if let cached = selectedDayInsightCache[cacheKey] {
            return cached
        }

        let averageCardsPerActiveDay = weeklyMomentum.averageCardsPerActiveDay
        let cardsReviewed = selectedDayOverview.cardsReviewed

        let paceLine: String
        if averageCardsPerActiveDay == 0 && cardsReviewed == 0 {
            paceLine = "No recent study baseline yet."
        } else if averageCardsPerActiveDay == 0 {
            paceLine = "This day sets your first study pace."
        } else {
            let delta = cardsReviewed - averageCardsPerActiveDay
            if delta == 0 {
                paceLine = "Exactly on your 7-day average pace."
            } else if delta > 0 {
                paceLine = "\(delta) cards above your 7-day average."
            } else {
                paceLine = "\(-delta) cards below your 7-day average."
            }
        }

        let examContextLine: String
        if !selectedDayExamSummaries.isEmpty {
            examContextLine = selectedDayExamSummaries.count == 1
                ? "One exam goal lands on this day."
                : "\(selectedDayExamSummaries.count) exam goals land on this day."
        } else if let nextGoal = upcomingExamSummaries.first {
            examContextLine = "Nearest pressure point: \(nextGoal.title) is \(nextGoal.countdownLabel.lowercased())."
        } else {
            examContextLine = "No exam goals are pressuring this day."
        }

        let headline: String
        let detailLine: String
        if !selectedDayExamSummaries.isEmpty {
            headline = selectedDayExamSummaries.count == 1 ? "This day carries an exam target" : "This day is a study checkpoint"
            detailLine = selectedDayExamSummaries.first?.summaryLine ?? "Use this date to consolidate your strongest recall."
        } else if selectedDayOverview.didReachGoal {
            headline = "This day is already in good shape"
            detailLine = "You cleared the target and can use any extra time for due-card cleanup."
        } else if cardsReviewed > 0 {
            headline = "This day still has room to improve"
            detailLine = "You are \(selectedDayOverview.remainingCardsToGoal) cards away from the target."
        } else {
            headline = "This day is still open"
            detailLine = "No study has landed here yet, so it can absorb focused catch-up work."
        }

        let recommendationLine: String
        if let selectedGoal = selectedDayExamSummaries.first, let weakestDeck = selectedGoal.weakestDeck {
            recommendationLine = "Best next move: rehearse \(weakestDeck.title) and protect \(selectedGoal.countdownLabel.lowercased())."
        } else if let pressure = upcomingExamSummaries.first, let weakestDeck = pressure.weakestDeck {
            let suggestedCards = max(pressure.dailyPaceNeeded, selectedDayOverview.remainingCardsToGoal > 0 ? min(selectedDayOverview.remainingCardsToGoal, pressure.dailyPaceNeeded) : pressure.dailyPaceNeeded)
            recommendationLine = "Best next move: put \(suggestedCards) reviews into \(weakestDeck.title) to reduce upcoming pressure."
        } else if selectedDayOverview.didReachGoal {
            recommendationLine = "Best next move: keep the streak warm with a short due-card pass."
        } else {
            recommendationLine = "Best next move: finish the remaining \(selectedDayOverview.remainingCardsToGoal) cards and lock the day."
        }

        let summary = HomeSelectedDayInsightSummary(
            headline: headline,
            detailLine: detailLine,
            recommendationLine: recommendationLine,
            paceLine: paceLine,
            examContextLine: examContextLine,
            xpEarned: selectedDayOverview.xpEarnedToday,
            newCardsLearned: selectedDayOverview.newCardsLearned,
            selectedDayExamCount: selectedDayExamSummaries.count
        )
        selectedDayInsightCache[cacheKey] = summary
        return summary
    }

    func buildExamPressureSummary(
        from upcomingExamSummaries: [HomeExamGoalSummary]
    ) -> HomeExamPressureSummary? {
        guard let topRiskGoal = upcomingExamSummaries.max(by: { riskScore(for: $0) < riskScore(for: $1) }) else {
            return nil
        }

        let headline: String
        if topRiskGoal.belowTargetDeckCount > 0 || topRiskGoal.overdueCount > 0 {
            headline = "Needs attention now"
        } else if topRiskGoal.readinessFraction >= 0.75 {
            headline = "On track"
        } else {
            headline = "Steady pressure"
        }

        let actionLine: String
        if let weakestDeck = topRiskGoal.weakestDeck {
            if topRiskGoal.dailyPaceNeeded > 0 {
                actionLine = "Focus \(topRiskGoal.dailyPaceNeeded) reviews/day in \(weakestDeck.title) to lift readiness."
            } else {
                actionLine = "Use \(weakestDeck.title) for quick reinforcement before the deadline."
            }
        } else if topRiskGoal.dailyPaceNeeded > 0 {
            actionLine = "Keep a pace of \(topRiskGoal.dailyPaceNeeded) reviews/day until the goal is stable."
        } else {
            actionLine = "Maintain light recall sessions to protect readiness."
        }

        return HomeExamPressureSummary(
            goalID: topRiskGoal.id,
            goalTitle: topRiskGoal.title,
            countdownLabel: topRiskGoal.countdownLabel,
            readinessFraction: topRiskGoal.readinessFraction,
            headline: headline,
            detailLine: topRiskGoal.summaryLine,
            actionLine: actionLine,
            overdueCards: topRiskGoal.overdueCount,
            dailyPaceNeeded: topRiskGoal.dailyPaceNeeded,
            belowTargetDeckCount: topRiskGoal.belowTargetDeckCount,
            weakestDeckTitle: topRiskGoal.weakestDeck?.title,
            weakestDeckReadinessFraction: topRiskGoal.weakestDeck?.readinessFraction
        )
    }

    func activeExamGoalDeckCounts(
        from examGoals: [ExamGoalModel],
        referenceDate: Date
    ) -> [PersistentIdentifier: Int] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: referenceDate)

        var counts: [PersistentIdentifier: Int] = [:]
        for goal in examGoals where goal.status == .active && calendar.startOfDay(for: goal.date) >= today {
            for deck in goal.linkedDecks {
                counts[deck.persistentModelID, default: 0] += 1
            }
        }
        return counts
    }

    func prioritizedDeckHealthCandidates(
        from decks: [DeckModel],
        recentDeckIDs: Set<PersistentIdentifier>,
        goalCounts: [PersistentIdentifier: Int]
    ) -> [DeckModel] {
        decks
            .filter { $0.cardCount > 0 }
            .sorted { lhs, rhs in
                let lhsGoalCount = goalCounts[lhs.persistentModelID] ?? 0
                let rhsGoalCount = goalCounts[rhs.persistentModelID] ?? 0
                if lhsGoalCount != rhsGoalCount { return lhsGoalCount > rhsGoalCount }

                let lhsRecent = recentDeckIDs.contains(lhs.persistentModelID)
                let rhsRecent = recentDeckIDs.contains(rhs.persistentModelID)
                if lhsRecent != rhsRecent { return lhsRecent && !rhsRecent }

                if lhs.cardCount != rhs.cardCount { return lhs.cardCount > rhs.cardCount }
                return (lhs.lastOpenedAt ?? .distantPast) > (rhs.lastOpenedAt ?? .distantPast)
            }
            .prefix(8)
            .map { $0 }
    }

    func buildDeckHealthSummary(
        for deck: DeckModel,
        report: LearnModeReport,
        linkedGoalCount: Int,
        isRecentlyOpened: Bool,
        referenceDate: Date
    ) -> HomeDeckHealthSummary {
        let masteryFraction = report.totalCards > 0
            ? Double(report.stableCards) / Double(report.totalCards)
            : 0

        let headline: String
        if linkedGoalCount > 0 && report.dueCards > 0 {
            headline = "Exam-linked and under pressure"
        } else if report.dueCards > 0 {
            headline = "\(report.dueCards) due right now"
        } else if report.newCards > 0 {
            headline = "\(report.newCards) new cards waiting"
        } else if report.stableCards == report.totalCards {
            headline = "Healthy deck"
        } else {
            headline = "Mostly stable, with room to tune"
        }

        let detailLine: String
        if linkedGoalCount > 0 {
            detailLine = "Supports \(linkedGoalCount) active exam goal\(linkedGoalCount == 1 ? "" : "s"). Accuracy is \(report.reviewAccuracy)%."
        } else if report.reviewedCards == 0 {
            detailLine = "No reviews logged yet across \(report.totalCards) cards."
        } else {
            detailLine = "\(report.stableCards) stable, \(report.buildingCards) building, \(report.dueCards) due. Accuracy is \(report.reviewAccuracy)%."
        }

        let primaryInsight = report.focusCards.first ?? report.newMaterialCards.first ?? report.stableHighlights.first
        let actionLine = primaryInsight?.recommendation
            ?? (report.dueCards > 0
                ? "Start with due cards before adding anything new."
                : report.newCards > 0
                    ? "Introduce a few new cards and build first-pass familiarity."
                    : "Use a short review pass to keep the deck warm.")

        return HomeDeckHealthSummary(
            id: deck.persistentModelID,
            title: deck.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Deck" : deck.title,
            colorHex: deck.colorHex,
            totalCards: report.totalCards,
            dueCards: report.dueCards,
            newCards: report.newCards,
            buildingCards: report.buildingCards,
            stableCards: report.stableCards,
            reviewAccuracy: report.reviewAccuracy,
            masteryFraction: masteryFraction,
            linkedGoalCount: linkedGoalCount,
            isRecentlyOpened: isRecentlyOpened,
            lastOpenedLabel: deck.lastOpenedAt.map {
                Self.relativeTimeLabel(for: $0, referenceDate: referenceDate)
            },
            headline: headline,
            detailLine: detailLine,
            actionLine: actionLine,
            focusPrompt: primaryInsight?.promptPreview
        )
    }

    func deckHealthRiskScore(for summary: HomeDeckHealthSummary) -> Double {
        guard summary.totalCards > 0 else { return 0 }

        let duePressure = min(Double(summary.dueCards) / Double(summary.totalCards), 1.0) * 0.45
        let newPressure = min(Double(summary.newCards) / Double(summary.totalCards), 1.0) * 0.12
        let buildingPressure = min(Double(summary.buildingCards) / Double(summary.totalCards), 1.0) * 0.18
        let accuracyPressure = (1.0 - (Double(summary.reviewAccuracy) / 100.0)) * 0.18
        let examPressure = min(Double(summary.linkedGoalCount) * 0.18, 0.36)
        let recentBoost = summary.isRecentlyOpened ? 0.05 : 0

        return duePressure + newPressure + buildingPressure + accuracyPressure + examPressure + recentBoost
    }

    func buildCalendarDayInsight(
        key: String,
        date: Date,
        log: DailyActivityLog?,
        goals: [ExamGoalModel],
        streakDates: Set<String>
    ) -> HomeCalendarDayInsight {
        let cardsReviewed = log?.cardsReviewed ?? 0
        let xpEarned = log?.xpEarnedToday ?? 0
        let dailyGoal = max(log?.dailyGoal ?? 50, 1)
        let didStudy = cardsReviewed > 0 || xpEarned > 0
        let activityFraction = didStudy
            ? max(min(Double(cardsReviewed) / Double(dailyGoal), 1.0), xpEarned > 0 ? 0.22 : 0.12)
            : 0
        let activeGoals = goals.filter { $0.status != .archived }
        let hasGoalNote = activeGoals.contains { !$0.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        return HomeCalendarDayInsight(
            date: date,
            dateString: key,
            cardsReviewed: cardsReviewed,
            xpEarned: xpEarned,
            dailyGoal: dailyGoal,
            activityFraction: activityFraction,
            didStudy: didStudy,
            isPerfectDay: log?.isPerfectDay ?? false,
            isStreakDay: streakDates.contains(key),
            hasExamGoal: !activeGoals.isEmpty,
            hasGoalNote: hasGoalNote,
            examGoalCount: activeGoals.count
        )
    }

    func buildDashboardSnapshotSignature(
        selectedDate: Date,
        userProfile: UserProfile?,
        analyticsRevision: Int,
        deckRevision: Int
    ) -> String {
        let selectedDateKey = Self.dateKeyFormatter.string(from: selectedDate)
        return [
            selectedDateKey,
            profileSignature(for: userProfile),
            "\(analyticsRevision)",
            "\(deckRevision)",
            "\(examGoalsCacheRevision)"
        ].joined(separator: "||")
    }

    func buildDashboardStaticSignature(
        userProfile: UserProfile?,
        referenceDate: Date
    ) -> String {
        [
            Self.dateKeyFormatter.string(from: referenceDate),
            profileSignature(for: userProfile),
            "\(logsCacheRevision)",
            "\(examGoalsCacheRevision)",
            "\(activeExamGoalDeckRevisionFingerprint())"
        ].joined(separator: "||")
    }

    func buildCalendarInsightsSignature(
        userProfile: UserProfile?,
        referenceDate: Date
    ) -> String {
        [
            Self.dateKeyFormatter.string(from: referenceDate),
            profileSignature(for: userProfile),
            "\(logsCacheRevision)",
            "\(examGoalsCacheRevision)"
        ].joined(separator: "||")
    }

    func buildDeckHealthSignature(
        decks: [DeckModel],
        recentDecks: [DeckModel],
        examGoals: [ExamGoalModel],
        referenceDate: Date
    ) -> String {
        let deckSignature = decks
            .map {
                [
                    "\($0.persistentModelID.hashValue)",
                    $0.title,
                    $0.colorHex,
                    "\($0.cardCount)",
                    "\($0.editedAt.timeIntervalSince1970)",
                    "\($0.lastOpenedAt?.timeIntervalSince1970 ?? 0)"
                ].joined(separator: "|")
            }
            .sorted()
            .joined(separator: "~")

        let recentSignature = recentDecks
            .map { "\($0.persistentModelID.hashValue)" }
            .joined(separator: "~")

        return [
            Self.dateKeyFormatter.string(from: referenceDate),
            deckSignature,
            recentSignature,
            "\(examGoalsCacheRevision)"
        ].joined(separator: "||")
    }

    func buildActiveStreakDateKeys(
        userProfile: UserProfile?,
        referenceDate: Date
    ) -> Set<String> {
        guard
            let userProfile,
            userProfile.currentStreak > 0,
            let lastActiveDate = userProfile.lastActiveDate
        else { return [] }

        let calendar = Calendar.current
        let normalizedReference = calendar.startOfDay(for: referenceDate)
        let normalizedLastActive = calendar.startOfDay(for: lastActiveDate)

        guard normalizedLastActive <= normalizedReference else { return [] }

        let streakLength = max(userProfile.currentStreak, 0)
        return Set((0..<streakLength).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: normalizedLastActive) else {
                return nil
            }
            return Self.dateKeyFormatter.string(from: date)
        })
    }

    func recentStudyDayCount(referenceDate: Date) -> Int {
        let calendar = Calendar.current
        let normalizedReference = calendar.startOfDay(for: referenceDate)
        let cacheKey = [
            Self.dateKeyFormatter.string(from: normalizedReference),
            "\(logsCacheRevision)"
        ].joined(separator: "||")

        if let cached = recentStudyDayCountCache[cacheKey] {
            return cached
        }

        let count = (0..<7).reduce(into: 0) { count, offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: normalizedReference) else {
                return
            }
            let key = Self.dateKeyFormatter.string(from: day)
            guard let log = logsCache[key], log.cardsReviewed > 0 else { return }
            count += 1
        }
        recentStudyDayCountCache[cacheKey] = count
        return count
    }

    func normalizedCardTitle(for card: CardModel) -> String {
        let preferred = card.frontText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !preferred.isEmpty { return preferred }

        let fallback = card.backText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fallback.isEmpty { return fallback }

        return "Untitled Card"
    }

    func normalizedDeckTitle(for card: CardModel) -> String {
        let title = card.deck?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? "Untitled Deck" : title
    }

    func profileSignature(for userProfile: UserProfile?) -> String {
        userProfile.map {
            [
                "\($0.totalXP)",
                "\($0.currentStreak)",
                "\($0.longestStreak)",
                "\($0.lastActiveDate?.timeIntervalSince1970 ?? 0)"
            ].joined(separator: "|")
        } ?? "no-profile"
    }

    static func labelForSelectedDay(_ date: Date, referenceDate: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: referenceDate),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: referenceDate),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "Tomorrow"
        }
        return selectedDayLabelFormatter.string(from: date)
    }

    static func greetingPhase(for referenceDate: Date) -> HomeGreetingPhase {
        let hour = Calendar.current.component(.hour, from: referenceDate)
        switch hour {
        case 5..<12:
            return .morning
        case 12..<17:
            return .afternoon
        case 17..<22:
            return .evening
        default:
            return .night
        }
    }

    func buildExamGoalSummary(
        for goal: ExamGoalModel,
        referenceDate: Date
    ) -> HomeExamGoalSummary {
        let cacheKey = goalSummaryCacheKey(for: goal, referenceDate: referenceDate)
        if let cached = examGoalSummaryCache[cacheKey] {
            return cached
        }

        let calendar = Calendar.current
        let startOfReferenceDay = calendar.startOfDay(for: referenceDate)
        let startOfGoalDay = calendar.startOfDay(for: goal.date)
        let daysRemaining = max(calendar.dateComponents([.day], from: startOfReferenceDay, to: startOfGoalDay).day ?? 0, 0)
        let deckSummaries = goal.linkedDecks.map { buildDeckSummary(for: $0, now: referenceDate) }
        let readinessFraction = deckSummaries.isEmpty
            ? 0
            : deckSummaries.map(\.readinessFraction).reduce(0, +) / Double(deckSummaries.count)
        let overdueCount = deckSummaries.map(\.dueCards).reduce(0, +)
        let remainingCards = deckSummaries.map(\.remainingCards).reduce(0, +)
        let dailyPaceNeeded = remainingCards == 0 ? 0 : Int(ceil(Double(remainingCards) / Double(max(daysRemaining, 1))))
        let perDeckTarget = max(1, Int(ceil(Double(goal.targetWorkload) / Double(max(deckSummaries.count, 1)))))
        let belowTargetDeckCount = deckSummaries.filter {
            $0.remainingCards > perDeckTarget || $0.readinessFraction < readinessThreshold(daysRemaining: daysRemaining)
        }.count
        let weakestDeck = deckSummaries.min { lhs, rhs in
            if lhs.readinessFraction != rhs.readinessFraction {
                return lhs.readinessFraction < rhs.readinessFraction
            }
            return lhs.remainingCards > rhs.remainingCards
        }

        let summaryLine: String
        if daysRemaining == 0 {
            summaryLine = belowTargetDeckCount > 0
                ? "Exam day is here and \(belowTargetDeckCount) linked deck\(belowTargetDeckCount == 1 ? "" : "s") still need attention."
                : "Exam day is here. Focus on calm recall and quick due-card passes."
        } else if belowTargetDeckCount > 0 {
            summaryLine = "Exam in \(daysRemaining) day\(daysRemaining == 1 ? "" : "s") and \(belowTargetDeckCount) linked deck\(belowTargetDeckCount == 1 ? "" : "s") are below target."
        } else if dailyPaceNeeded > 0 {
            summaryLine = "On track if you keep roughly \(dailyPaceNeeded) review\(dailyPaceNeeded == 1 ? "" : "s") per day."
        } else {
            summaryLine = "Linked decks look healthy for this goal right now."
        }

        let summary = HomeExamGoalSummary(
            id: goal.persistentModelID,
            title: goal.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Goal" : goal.title,
            note: goal.note,
            date: goal.date,
            status: goal.status,
            countdownLabel: Self.countdownLabel(for: goal.date, referenceDate: referenceDate),
            dateLabel: Self.mediumDateLabel(for: goal.date),
            targetWorkload: goal.targetWorkload,
            linkedDeckCount: deckSummaries.count,
            readinessFraction: readinessFraction,
            overdueCount: overdueCount,
            dailyPaceNeeded: dailyPaceNeeded,
            belowTargetDeckCount: belowTargetDeckCount,
            weakestDeck: weakestDeck,
            summaryLine: summaryLine,
            deckSummaries: deckSummaries
        )
        examGoalSummaryCache[cacheKey] = summary
        return summary
    }

    func buildDeckSummary(for deck: DeckModel, now: Date) -> HomeExamDeckSummary {
        let cacheKey = deckSummaryCacheKey(for: deck, referenceDate: now)
        if let cached = examDeckSummaryCache[cacheKey] {
            return cached
        }

        let cards = deck.cards
        let totalCards = max(deck.cardCount, cards.count)
        var reviewedCards = 0
        var dueCards = 0
        var newCards = 0
        var stableCards = 0
        var successfulReviews = 0
        var reviewEventCount = 0

        for card in cards {
            let history = card.reviewHistory

            if history.isEmpty {
                newCards += 1
            } else {
                reviewedCards += 1
            }

            if card.dueDate <= now {
                dueCards += 1
            }

            if card.interval >= 14 {
                stableCards += 1
            }

            reviewEventCount += history.count
            for event in history where event.difficultyRaw >= ReviewDifficulty.good.rawValue {
                successfulReviews += 1
            }
        }

        let accuracyFraction = reviewEventCount == 0
            ? 0
            : Double(successfulReviews) / Double(reviewEventCount)
        let coverageFraction = totalCards > 0
            ? Double(reviewedCards) / Double(totalCards)
            : 0
        let stabilityFraction = totalCards > 0
            ? Double(stableCards) / Double(totalCards)
            : 0
        let duePenalty = totalCards > 0
            ? Double(dueCards) / Double(totalCards)
            : 0
        let readinessFraction = min(
            1,
            max(
                0,
                (coverageFraction * 0.45)
                + (accuracyFraction * 0.35)
                + (stabilityFraction * 0.25)
                - (duePenalty * 0.20)
            )
        )

        let summary = HomeExamDeckSummary(
            id: deck.persistentModelID,
            title: deck.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Deck" : deck.title,
            colorHex: deck.colorHex,
            totalCards: totalCards,
            reviewedCards: reviewedCards,
            dueCards: dueCards,
            newCards: newCards,
            accuracyFraction: accuracyFraction,
            readinessFraction: readinessFraction
        )
        examDeckSummaryCache[cacheKey] = summary
        return summary
    }

    func readinessThreshold(daysRemaining: Int) -> Double {
        switch daysRemaining {
        case 0...3:
            return 0.78
        case 4...7:
            return 0.68
        default:
            return 0.58
        }
    }

    func riskScore(for summary: HomeExamGoalSummary) -> Double {
        let readinessPressure = 1 - summary.readinessFraction
        let workloadPressure = Double(summary.belowTargetDeckCount) * 0.25
        let overduePressure = summary.overdueCount > 0 ? min(Double(summary.overdueCount) / 40.0, 0.4) : 0
        return readinessPressure + workloadPressure + overduePressure
    }

    func activeExamGoalDeckRevisionFingerprint() -> Int {
        var aggregate = 17
        for goal in examGoalsCache.values.flatMap({ $0 }) where goal.status != .archived {
            aggregate ^= goalSummaryRevisionFingerprint(for: goal)
        }
        return aggregate
    }

    func goalSummaryCacheKey(for goal: ExamGoalModel, referenceDate: Date) -> String {
        [
            "\(goal.persistentModelID.hashValue)",
            Self.dateKeyFormatter.string(from: referenceDate),
            "\(goalSummaryRevisionFingerprint(for: goal))"
        ].joined(separator: "||")
    }

    func goalSummaryRevisionFingerprint(for goal: ExamGoalModel) -> Int {
        var deckAggregate = goal.linkedDecks.count &* 131
        for deck in goal.linkedDecks {
            deckAggregate ^= deckSummaryRevisionFingerprint(for: deck)
        }

        var hasher = Hasher()
        hasher.combine(goal.persistentModelID.hashValue)
        hasher.combine(goal.title)
        hasher.combine(goal.note)
        hasher.combine(goal.statusRaw)
        hasher.combine(Self.dateKeyFormatter.string(from: goal.date))
        hasher.combine(goal.targetWorkload)
        hasher.combine(deckAggregate)
        return hasher.finalize()
    }

    func deckSummaryCacheKey(for deck: DeckModel, referenceDate: Date) -> String {
        [
            "\(deck.persistentModelID.hashValue)",
            Self.dateKeyFormatter.string(from: referenceDate),
            "\(deckSummaryRevisionFingerprint(for: deck))"
        ].joined(separator: "||")
    }

    func deckSummaryRevisionFingerprint(for deck: DeckModel) -> Int {
        var hasher = Hasher()
        hasher.combine(deck.persistentModelID.hashValue)
        hasher.combine(deck.title)
        hasher.combine(deck.colorHex)
        hasher.combine(deck.cardCount)
        hasher.combine(deck.editedAt.timeIntervalSince1970.bitPattern)
        return hasher.finalize()
    }
}
