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
        let locale = Self.homeLocale
        let workspaceState = workspaceOnboardingState(
            allDeckCount: allDeckCount,
            folderCount: folderCount
        )
        let greetingTitle = Self.greetingPhase(for: referenceDate).title
        let localized: (String.LocalizationValue) -> String = { value in
            AppLocalization.string(value, locale: locale)
        }
        let localizedFormat: (String.LocalizationValue, [CVarArg]) -> String = { value, arguments in
            let format = AppLocalization.string(value, locale: locale)
            return String(format: format, locale: locale, arguments: arguments)
        }

        if workspaceState == .needsDeck {
            return HomeTodayFocusHeaderSummary(
                introTitle: greetingTitle,
                introSubtitle: localized("Create your first deck to begin."),
                eyebrow: localized("Start"),
                title: localized("No deck yet"),
                detail: localized("Create a deck to start studying from Home."),
                compactTitle: localized("No deck yet"),
                compactDetail: localized("Create Deck"),
                colorHex: "",
                primaryPill: "",
                secondaryPill: nil,
                progressFraction: 0,
                progressValueText: localized("New"),
                progressLabel: localized("Start"),
                ctaTitle: localized("Create Deck"),
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
                detail = localized("Today's goal is closed.")
            } else if let lastOpenedAt = recentDeck.lastOpenedAt {
                detail = String.localizedStringWithFormat(
                    localized("Last opened %@."),
                    Self.relativeTimeLabel(for: lastOpenedAt, referenceDate: referenceDate)
                )
            } else if let matchingHealth {
                let deckPressure = matchingHealth.dueCards + matchingHealth.newCards
                if deckPressure > 0 {
                    detail = localizedFormat(
                        "%d cards are ready.",
                        [min(deckPressure, max(remainingCards, 1))]
                    )
                } else {
                    detail = localizedFormat("%d cards are still open today.", [remainingCards])
                }
            } else {
                detail = localizedFormat("%d cards are still open today.", [remainingCards])
            }

            return HomeTodayFocusHeaderSummary(
                introTitle: greetingTitle,
                introSubtitle: localized("Continue where you left off."),
                eyebrow: overview.didReachGoal ? localized("Today clear") : localized("Today goal"),
                title: resolvedTitle,
                detail: detail,
                compactTitle: resolvedTitle,
                compactDetail: localized("Resume Deck"),
                colorHex: recentDeck.colorHex,
                primaryPill: "",
                secondaryPill: nil,
                progressFraction: overview.goalCompletionFraction,
                progressValueText: overview.didReachGoal ? localized("Done") : "\(remainingCards)",
                progressLabel: overview.didReachGoal ? localized("Today") : localized("To goal"),
                ctaTitle: localized("Resume Deck"),
                action: .openDeck(recentDeck.persistentModelID)
            )
        }

        if let focusDeck = deckHealthSummaries.first {
            let remainingCards = max(overview.remainingCardsToGoal, 0)
            let focusTitle = focusDeck.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? localized("Focus deck")
                : focusDeck.title

            return HomeTodayFocusHeaderSummary(
                introTitle: greetingTitle,
                introSubtitle: overview.cardsReviewed == 0
                    ? localized("Start today's goal from this deck.")
                    : localized("Continue where you left off."),
                eyebrow: overview.didReachGoal ? localized("Today clear") : localized("Today goal"),
                title: focusTitle,
                detail: overview.cardsReviewed == 0
                    ? localized("Open this deck to start today's goal.")
                    : localizedFormat("%d cards are still open today.", [remainingCards]),
                compactTitle: focusTitle,
                compactDetail: localized("Open Deck"),
                colorHex: focusDeck.colorHex,
                primaryPill: "",
                secondaryPill: nil,
                progressFraction: overview.goalCompletionFraction,
                progressValueText: overview.didReachGoal ? localized("Done") : "\(remainingCards)",
                progressLabel: overview.didReachGoal ? localized("Today") : localized("To goal"),
                ctaTitle: localized("Open Focus Deck"),
                action: .openDeck(focusDeck.id)
            )
        }

        let totalXP = max(userProfile?.totalXP ?? 0, 0)
        let secondaryPill = totalXP > 0 ? "\(totalXP) XP" : nil

        return HomeTodayFocusHeaderSummary(
            introTitle: greetingTitle,
            introSubtitle: overview.didReachGoal
                ? localized("Today is already closed.")
                : localized("Pick a deck and continue."),
            eyebrow: overview.didReachGoal ? localized("Today clear") : localized("Today goal"),
            title: Self.greetingPhase(for: referenceDate) == .night
                ? localized("Pick a deck for tonight")
                : localized("Pick a deck for today"),
            detail: overview.didReachGoal
                ? localized("Today's goal is already closed.")
                : localizedFormat("%d cards are still open today.", [overview.remainingCardsToGoal]),
            compactTitle: overview.didReachGoal ? localized("Today is clear") : localized("Pick a deck"),
            compactDetail: localized("Open Home"),
            colorHex: "",
            primaryPill: overview.didReachGoal
                ? localized("Goal closed")
                : localizedFormat("%d left", [overview.remainingCardsToGoal]),
            secondaryPill: secondaryPill,
            progressFraction: overview.goalCompletionFraction,
            progressValueText: overview.didReachGoal ? localized("Done") : "\(overview.remainingCardsToGoal)",
            progressLabel: overview.didReachGoal ? localized("Today") : localized("To goal"),
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

    private static var homeLocale: Locale {
        AppPreferences.shared.resolvedLocale
    }

    private static var homeCalendar: Calendar {
        AppPreferences.shared.resolvedCalendar
    }

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
        weeklyMomentum: HomeWeeklyMomentumSummary
    ) -> HomeSelectedDayInsightSummary {
        let cacheKey = [
            Self.dateKeyFormatter.string(from: selectedDate),
            selectedDayOverview.headline,
            selectedDayOverview.detailLine,
            "\(selectedDayOverview.cardsReviewed)",
            "\(selectedDayOverview.remainingCardsToGoal)",
            "\(weeklyMomentum.averageCardsPerActiveDay)"
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

        let headline: String
        let detailLine: String
        if selectedDayOverview.didReachGoal {
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
        if selectedDayOverview.didReachGoal {
            recommendationLine = "Best next move: keep the streak warm with a short due-card pass."
        } else if let focusDeck = deckHealthSummaries.first {
            recommendationLine = "Best next move: open \(focusDeck.title) and work through the cards already waiting there."
        } else {
            recommendationLine = "Best next move: finish the remaining \(selectedDayOverview.remainingCardsToGoal) cards and lock the day."
        }

        let summary = HomeSelectedDayInsightSummary(
            headline: headline,
            detailLine: detailLine,
            recommendationLine: recommendationLine,
            paceLine: paceLine,
            xpEarned: selectedDayOverview.xpEarnedToday,
            newCardsLearned: selectedDayOverview.newCardsLearned
        )
        selectedDayInsightCache[cacheKey] = summary
        return summary
    }

    func prioritizedDeckHealthCandidates(
        from decks: [DeckModel],
        recentDeckIDs: Set<PersistentIdentifier>
    ) -> [DeckModel] {
        decks
            .filter { $0.cardCount > 0 }
            .sorted { lhs, rhs in
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
        report: DeckHealthReport,
        isRecentlyOpened: Bool,
        referenceDate: Date
    ) -> HomeDeckHealthSummary {
        let masteryFraction = report.totalCards > 0
            ? Double(report.stableCards) / Double(report.totalCards)
            : 0

        let headline: String
        if report.dueCards > 0 {
            headline = "\(report.dueCards) due right now"
        } else if report.newCards > 0 {
            headline = "\(report.newCards) new cards waiting"
        } else if report.stableCards == report.totalCards {
            headline = "Healthy deck"
        } else {
            headline = "Mostly stable, with room to tune"
        }

        let detailLine: String
        if report.reviewedCards == 0 {
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
        let recentBoost = summary.isRecentlyOpened ? 0.05 : 0

        return duePressure + newPressure + buildingPressure + accuracyPressure + recentBoost
    }

    func buildCalendarDayInsight(
        key: String,
        date: Date,
        log: DailyActivityLog?,
        streakDates: Set<String>
    ) -> HomeCalendarDayInsight {
        let cardsReviewed = log?.cardsReviewed ?? 0
        let xpEarned = log?.xpEarnedToday ?? 0
        let dailyGoal = max(log?.dailyGoal ?? 50, 1)
        let didStudy = cardsReviewed > 0 || xpEarned > 0
        let activityFraction = didStudy
            ? max(min(Double(cardsReviewed) / Double(dailyGoal), 1.0), xpEarned > 0 ? 0.22 : 0.12)
            : 0

        return HomeCalendarDayInsight(
            date: date,
            dateString: key,
            cardsReviewed: cardsReviewed,
            xpEarned: xpEarned,
            dailyGoal: dailyGoal,
            activityFraction: activityFraction,
            didStudy: didStudy,
            isPerfectDay: log?.isPerfectDay ?? false,
            isStreakDay: streakDates.contains(key)
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
            "\(deckRevision)"
        ].joined(separator: "||")
    }

    func buildCalendarInsightsSignature(
        userProfile: UserProfile?,
        referenceDate: Date
    ) -> String {
        [
            Self.dateKeyFormatter.string(from: referenceDate),
            profileSignature(for: userProfile),
            "\(logsCacheRevision)"
        ].joined(separator: "||")
    }

    func buildDeckHealthSignature(
        decks: [DeckModel],
        recentDecks: [DeckModel],
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
            recentSignature
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
        let locale = homeLocale
        let calendar = homeCalendar
        if calendar.isDateInToday(date) {
            return AppLocalization.string("Today", locale: locale)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: referenceDate),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return AppLocalization.string("Yesterday", locale: locale)
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: referenceDate),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return AppLocalization.string("Tomorrow", locale: locale)
        }
        selectedDayLabelFormatter.locale = locale
        selectedDayLabelFormatter.calendar = calendar
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
