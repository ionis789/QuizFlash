//
//  PlayModeCardRepository.swift
//  QuizFlash
//
//  Background repository producing mode-specific playable payloads.
//

import Foundation
import SwiftData

// MARK: - Play Mode Availability

/// Lightweight deck-level counts used to decide whether a play mode has compatible cards.
struct PlayModeCardAvailability: Equatable, Sendable {
    let totalCards: Int
    let flashcardCards: Int
    let quizCards: Int

    /// Empty placeholder used before any deck snapshot has been loaded.
    nonisolated static let empty = PlayModeCardAvailability(
        totalCards: 0,
        flashcardCards: 0,
        quizCards: 0
    )
}

// MARK: - Flashcards Payload

/// A lightweight flashcard payload used by the swipe-based play mode.
struct PlayableCard: Identifiable, Equatable, Sendable {
    let id: PersistentIdentifier
    let cardNumber: Int
    let frontZone: ZoneModel
    let backZone: ZoneModel
    let interval: Int
}

/// Partial flashcard load used to paint the first play-mode card before the
/// entire deck has been decoded.
struct PlayableCardLoadBatch: Equatable, Sendable {
    let cards: [PlayableCard]
    let totalCount: Int
    let loadedAll: Bool
}

// MARK: - Quiz Payload

/// A lightweight quiz payload sourced only from persisted quiz cards.
struct QuizPlayableCard: Identifiable, Equatable, Sendable {
    let id: PersistentIdentifier
    let cardNumber: Int
    let interval: Int
    let questionZone: ZoneModel
    let choices: [QuizChoiceDraft]
    let explanationZone: ZoneModel?
    let allowsMultipleCorrect: Bool
}

// MARK: - Deck Health Payload

/// Lightweight deck-level snapshot used by Home deck-health summaries.
struct DeckHealthReport: Equatable, Sendable {
    let totalCards: Int
    let reviewedCards: Int
    let newCards: Int
    let dueCards: Int
    let buildingCards: Int
    let stableCards: Int
    let reviewAccuracy: Int
    let flashcardCards: Int
    let quizCards: Int
    let focusCards: [DeckHealthCardInsight]
    let newMaterialCards: [DeckHealthCardInsight]
    let stableHighlights: [DeckHealthCardInsight]
    let coverageGroups: [DeckHealthCoverageGroup]

    /// Empty placeholder used before the first repository load completes.
    nonisolated static let empty = DeckHealthReport(
        totalCards: 0,
        reviewedCards: 0,
        newCards: 0,
        dueCards: 0,
        buildingCards: 0,
        stableCards: 0,
        reviewAccuracy: 0,
        flashcardCards: 0,
        quizCards: 0,
        focusCards: [],
        newMaterialCards: [],
        stableHighlights: [],
        coverageGroups: []
    )
}

/// One lightweight card-level insight used by deck-health ranking.
struct DeckHealthCardInsight: Identifiable, Equatable, Sendable {
    let id: PersistentIdentifier
    let kind: CardKind
    let cardNumber: Int
    let promptPreview: String
    let answerPreview: String
    let statusSummary: String
    let recommendation: String
}

/// One grouped coverage block used by deck-health analysis.
struct DeckHealthCoverageGroup: Identifiable, Equatable, Sendable {
    let id: String
    let kind: CardKind
    let title: String
    let detail: String
    let cardCount: Int
    let samplePrompts: [String]
}

// MARK: - Play Mode Card Repository

/// Background repository that projects one deck into play-mode-specific value payloads.
///
/// This keeps kind filtering and heavy card-content decoding off the main actor while
/// giving each future play mode a stable input contract.
actor PlayModeCardRepository {

    // MARK: - Private State

    private let container: ModelContainer
    private var activeContext: ModelContext

    // MARK: - Init

    init(container: ModelContainer) {
        self.container = container
        let context = ModelContext(container)
        context.autosaveEnabled = false
        self.activeContext = context
    }

    // MARK: - Availability

    /// Counts how many cards in a deck are compatible with each persisted play mode.
    func fetchAvailability(deckID: PersistentIdentifier) -> PlayModeCardAvailability {
        guard let deck = activeContext.model(for: deckID) as? DeckModel else {
            return .empty
        }

        let cards = sortedCards(resolvedCards(for: deck, deckID: deckID))
        var flashcardCards = 0
        var quizCards = 0

        for card in cards {
            switch card.kind {
            case .flashcard:
                flashcardCards += 1
            case .quiz:
                quizCards += 1
            }
        }

        flushContext()

        return PlayModeCardAvailability(
            totalCards: cards.count,
            flashcardCards: flashcardCards,
            quizCards: quizCards
        )
    }

    // MARK: - Flashcards

    /// Loads one flashcard payload by identifier.
    func loadPlayableCard(for cardID: PersistentIdentifier) -> PlayableCard? {
        guard let card = activeContext.model(for: cardID) as? CardModel else { return nil }
        defer { flushContext() }

        guard case .flashcard(let content) = card.cardContent else { return nil }
        return PlayableCard(
            id: card.persistentModelID,
            cardNumber: card.cardNumber,
            frontZone: content.frontZone,
            backZone: content.backZone,
            interval: card.interval
        )
    }

    /// Loads flashcard payloads for a deck, excluding quiz cards entirely.
    func loadPlayableCards(for deckID: PersistentIdentifier) -> [PlayableCard] {
        guard let deck = activeContext.model(for: deckID) as? DeckModel else { return [] }

        let cards = sortedCards(resolvedCards(for: deck, deckID: deckID))
        var results: [PlayableCard] = []

        for card in cards {
            autoreleasepool {
                guard case .flashcard(let content) = card.cardContent else { return }

                results.append(
                    PlayableCard(
                        id: card.persistentModelID,
                        cardNumber: card.cardNumber,
                        frontZone: content.frontZone,
                        backZone: content.backZone,
                        interval: card.interval
                    )
                )
                card.clearZoneCache()
            }
        }

        flushContext()
        return results
    }

    /// Loads a small ordered batch of flashcards without decoding the whole deck.
    ///
    /// This is used by Flashcards play mode so the first card can render as soon
    /// as a handful of payloads are ready, while the rest of the deck continues
    /// loading in the background.
    func loadPlayableCardBatch(
        for deckID: PersistentIdentifier,
        order: FlashcardSessionOrder,
        limit: Int? = nil,
        excludingIDs: Set<PersistentIdentifier> = []
    ) -> PlayableCardLoadBatch {
        guard let deck = activeContext.model(for: deckID) as? DeckModel else {
            return PlayableCardLoadBatch(cards: [], totalCount: 0, loadedAll: true)
        }

        let orderedCards = orderedFlashcards(
            resolvedCards(for: deck, deckID: deckID),
            order: order
        )
        let excludedIDKeys = Set(excludingIDs.map(persistentIdentifierKey))
        let remainingCards = orderedCards.filter {
            !excludedIDKeys.contains(persistentIdentifierKey($0.persistentModelID))
        }
        let cardsToDecode: ArraySlice<CardModel>
        if let limit {
            cardsToDecode = remainingCards.prefix(limit)
        } else {
            cardsToDecode = remainingCards[...]
        }

        var results: [PlayableCard] = []
        results.reserveCapacity(cardsToDecode.count)

        for card in cardsToDecode {
            autoreleasepool {
                guard case .flashcard(let content) = card.cardContent else { return }

                results.append(
                    PlayableCard(
                        id: card.persistentModelID,
                        cardNumber: card.cardNumber,
                        frontZone: content.frontZone,
                        backZone: content.backZone,
                        interval: card.interval
                    )
                )
                card.clearZoneCache()
            }
        }

        let loadedAll = results.count >= remainingCards.count
        let batch = PlayableCardLoadBatch(
            cards: results,
            totalCount: orderedCards.count,
            loadedAll: loadedAll
        )

        flushContext()
        return batch
    }

    // MARK: - Quiz

    /// Loads validated quiz payloads for a deck and records explicit invalid-content buckets.
    func loadValidatedQuizCards(for deckID: PersistentIdentifier) -> ValidatedPlayModeLoadResult<QuizPlayableCard> {
        guard let deck = activeContext.model(for: deckID) as? DeckModel else {
            return ValidatedPlayModeLoadResult(cards: [], diagnostics: .empty)
        }

        let cards = sortedCards(resolvedCards(for: deck, deckID: deckID))
        var results: [QuizPlayableCard] = []
        var invalidReasons: [PlayModeValidationReason: Int] = [:]
        var compatibleCount = 0

        for card in cards {
            autoreleasepool {
                guard case .quiz(let content) = card.cardContent else { return }
                compatibleCount += 1

                guard content.questionZone.hasContent else {
                    Self.increment(.missingQuestion, in: &invalidReasons)
                    card.clearZoneCache()
                    return
                }

                let nonEmptyChoices = content.choices.filter { $0.contentZone.hasContent }
                guard nonEmptyChoices.count >= 2 else {
                    Self.increment(.insufficientChoices, in: &invalidReasons)
                    card.clearZoneCache()
                    return
                }

                let correctChoices = nonEmptyChoices.filter(\.isCorrect)
                guard !correctChoices.isEmpty else {
                    Self.increment(.missingCorrectChoice, in: &invalidReasons)
                    card.clearZoneCache()
                    return
                }

                guard content.allowsMultipleCorrect || correctChoices.count == 1 else {
                    Self.increment(.multipleCorrectChoicesDisallowed, in: &invalidReasons)
                    card.clearZoneCache()
                    return
                }

                results.append(
                    QuizPlayableCard(
                        id: card.persistentModelID,
                        cardNumber: card.cardNumber,
                        interval: card.interval,
                        questionZone: content.questionZone,
                        choices: nonEmptyChoices,
                        explanationZone: content.explanationZone?.hasContent == true ? content.explanationZone : nil,
                        allowsMultipleCorrect: content.allowsMultipleCorrect
                    )
                )
                card.clearZoneCache()
            }
        }

        let diagnostics = PlayModeValidationDiagnostics(
            compatibleCount: compatibleCount,
            playableCount: results.count,
            invalidReasonCounts: invalidReasons
        )

        flushContext()
        return ValidatedPlayModeLoadResult(cards: results, diagnostics: diagnostics)
    }

    // MARK: - Deck Health

    /// Builds a deck-health report from cached mixed-card previews and review history.
    func loadDeckHealthReport(for deckID: PersistentIdentifier) -> DeckHealthReport {
        guard let deck = activeContext.model(for: deckID) as? DeckModel else {
            return .empty
        }

        let cards = sortedCards(resolvedCards(for: deck, deckID: deckID))
        let now = Date()

        var reviewedCards = 0
        var newCards = 0
        var dueCards = 0
        var buildingCards = 0
        var stableCards = 0
        var flashcardCards = 0
        var quizCards = 0
        var totalReviews = 0
        var successfulReviews = 0

        var focusCandidates: [(score: Double, insight: DeckHealthCardInsight)] = []
        var newMaterialCards: [DeckHealthCardInsight] = []
        var stableHighlights: [(score: Double, insight: DeckHealthCardInsight)] = []
        var coverageBuckets: [CardKind: [String]] = [:]

        for card in cards {
            autoreleasepool {
                switch card.kind {
                case .flashcard:
                    flashcardCards += 1
                case .quiz:
                    quizCards += 1
                }

                let history = card.reviewHistory.sorted { $0.timestamp > $1.timestamp }
                let reviewCount = history.count
                let correctReviews = history.filter { $0.difficultyRaw >= ReviewDifficulty.good.rawValue }.count
                let accuracy = reviewCount > 0
                    ? Int((Double(correctReviews) / Double(reviewCount)) * 100)
                    : 0
                let promptPreview = Self.normalizedPreview(card.frontText)
                let answerPreview = Self.normalizedPreview(card.backText)

                totalReviews += reviewCount
                successfulReviews += correctReviews
                coverageBuckets[card.kind, default: []].append(promptPreview)

                if history.isEmpty {
                    newCards += 1
                    newMaterialCards.append(
                        DeckHealthCardInsight(
                            id: card.persistentModelID,
                            kind: card.kind,
                            cardNumber: card.cardNumber,
                            promptPreview: promptPreview,
                            answerPreview: answerPreview,
                            statusSummary: "New \(Self.kindLabel(for: card.kind))",
                            recommendation: "Read this once, then move it into active recall."
                        )
                    )
                    return
                }

                reviewedCards += 1

                if card.dueDate <= now {
                    dueCards += 1
                } else if card.interval >= 7 {
                    stableCards += 1
                } else {
                    buildingCards += 1
                }

                let insight = DeckHealthCardInsight(
                    id: card.persistentModelID,
                    kind: card.kind,
                    cardNumber: card.cardNumber,
                    promptPreview: promptPreview,
                    answerPreview: answerPreview,
                    statusSummary: Self.reviewStatusSummary(
                        kind: card.kind,
                        reviewCount: reviewCount,
                        accuracy: accuracy,
                        interval: card.interval
                    ),
                    recommendation: Self.recommendation(
                        for: card,
                        history: history,
                        now: now,
                        accuracy: accuracy
                    )
                )

                let focusScore = Self.focusScore(for: card, history: history, now: now, accuracy: accuracy)
                if focusScore > 0 {
                    focusCandidates.append((score: focusScore, insight: insight))
                }

                let stableScore = Self.stableScore(for: card, history: history, accuracy: accuracy)
                if stableScore > 0 {
                    stableHighlights.append((score: stableScore, insight: insight))
                }
            }
        }

        flushContext()

        let reviewAccuracy = totalReviews > 0
            ? Int((Double(successfulReviews) / Double(totalReviews)) * 100)
            : 0

        return DeckHealthReport(
            totalCards: cards.count,
            reviewedCards: reviewedCards,
            newCards: newCards,
            dueCards: dueCards,
            buildingCards: buildingCards,
            stableCards: stableCards,
            reviewAccuracy: reviewAccuracy,
            flashcardCards: flashcardCards,
            quizCards: quizCards,
            focusCards: focusCandidates
                .sorted { lhs, rhs in
                    if lhs.score != rhs.score { return lhs.score > rhs.score }
                    return lhs.insight.cardNumber < rhs.insight.cardNumber
                }
                .prefix(4)
                .map(\.insight),
            newMaterialCards: Array(newMaterialCards.prefix(4)),
            stableHighlights: stableHighlights
                .sorted { lhs, rhs in
                    if lhs.score != rhs.score { return lhs.score > rhs.score }
                    return lhs.insight.cardNumber < rhs.insight.cardNumber
                }
                .prefix(4)
                .map(\.insight),
            coverageGroups: Self.coverageGroups(
                flashcardCards: flashcardCards,
                quizCards: quizCards,
                coverageBuckets: coverageBuckets
            )
        )
    }

    // MARK: - Lifecycle

    /// Replaces the actor's context so retained card graphs are released promptly.
    func tearDown() {
        flushContext()
    }

    // MARK: - Helpers

    private func flushContext() {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        activeContext = context
    }

    private func resolvedCards(for deck: DeckModel, deckID: PersistentIdentifier) -> [CardModel] {
        let directCards = deck.cards
        if !directCards.isEmpty || deck.cardCount == 0 {
            return directCards
        }

        let descriptor = FetchDescriptor<CardModel>()
        guard let allCards = try? activeContext.fetch(descriptor) else {
            return directCards
        }

        return allCards.filter { $0.deck?.persistentModelID == deckID }
    }

    private func persistentIdentifierKey(_ id: PersistentIdentifier) -> String {
        String(describing: id)
    }

    private func sortedCards(_ cards: [CardModel]) -> [CardModel] {
        cards.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }
            if lhs.cardNumber != rhs.cardNumber {
                return lhs.cardNumber < rhs.cardNumber
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private func orderedFlashcards(
        _ cards: [CardModel],
        order: FlashcardSessionOrder
    ) -> [CardModel] {
        let flashcards = cards.filter { $0.kind == .flashcard }

        switch order {
        case .studyPriority:
            return flashcards.sorted { lhs, rhs in
                if lhs.interval == 0 && rhs.interval != 0 { return true }
                if lhs.interval != 0 && rhs.interval == 0 { return false }
                if lhs.interval != rhs.interval { return lhs.interval < rhs.interval }
                return lhs.cardNumber < rhs.cardNumber
            }
        case .newestFirst:
            return flashcards.sorted { lhs, rhs in
                if lhs.cardNumber != rhs.cardNumber {
                    return lhs.cardNumber > rhs.cardNumber
                }
                return lhs.interval < rhs.interval
            }
        case .oldestFirst:
            return flashcards.sorted { lhs, rhs in
                if lhs.cardNumber != rhs.cardNumber {
                    return lhs.cardNumber < rhs.cardNumber
                }
                return lhs.interval < rhs.interval
            }
        case .shuffled:
            return flashcards.shuffled()
        }
    }

    private static func normalizedPreview(_ text: String, fallback: String = "Untitled") -> String {
        let trimmed = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty, trimmed.caseInsensitiveCompare("empty") != .orderedSame else {
            return fallback
        }

        return String(trimmed.prefix(140))
    }

    private static func validatedPreviewText(for zone: ZoneModel) -> String? {
        let preview = zone.previewText(maxLength: 140)
        return validatedPreviewText(for: preview)
    }

    private static func validatedPreviewText(for text: String) -> String? {
        let preview = String(text.prefix(140))
        let trimmed = preview
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty, trimmed.caseInsensitiveCompare("empty") != .orderedSame else {
            return nil
        }

        return trimmed
    }

    private static func increment(
        _ reason: PlayModeValidationReason,
        in counts: inout [PlayModeValidationReason: Int]
    ) {
        counts[reason, default: 0] += 1
    }

    private static func kindLabel(for kind: CardKind) -> String {
        switch kind {
        case .flashcard:
            return "flashcard"
        case .quiz:
            return "quiz"
        }
    }

    private static func reviewStatusSummary(
        kind: CardKind,
        reviewCount: Int,
        accuracy: Int,
        interval: Int
    ) -> String {
        let kindSummary: String
        switch kind {
        case .flashcard:
            kindSummary = "Flashcard"
        case .quiz:
            kindSummary = "Quiz"
        }

        return "\(kindSummary) · \(reviewCount) reviews · \(accuracy)% correct · \(interval)d interval"
    }

    private static func recommendation(
        for card: CardModel,
        history: [ReviewEvent],
        now: Date,
        accuracy: Int
    ) -> String {
        let overdueDays = max(0, Int(now.timeIntervalSince(card.dueDate) / 86_400))
        if overdueDays > 0 {
            return overdueDays == 1
                ? "Due now. Revisit this before moving on."
                : "Overdue by \(overdueDays) days. Put it early in the session."
        }

        if let lastDifficulty = history.first?.difficulty {
            switch lastDifficulty {
            case .again:
                return "Last review failed. Rebuild this one from the prompt."
            case .hard:
                return "Recent recall was shaky. Keep it in the short loop."
            case .good, .easy:
                break
            }
        }

        if accuracy < 70 {
            return "Accuracy is still uneven. Pair it with a slower explanation pass."
        }

        if card.interval >= 14 {
            return "Retention looks stable. Skim it after the weaker material."
        }

        return "Keep this in the active rotation until the interval stretches."
    }

    private static func focusScore(
        for card: CardModel,
        history: [ReviewEvent],
        now: Date,
        accuracy: Int
    ) -> Double {
        guard !history.isEmpty else { return 0 }

        let overdueDays = max(0, now.timeIntervalSince(card.dueDate) / 86_400)
        let lastDifficultyPenalty: Double
        switch history.first?.difficulty ?? .good {
        case .again:
            lastDifficultyPenalty = 1.7
        case .hard:
            lastDifficultyPenalty = 1.1
        case .good:
            lastDifficultyPenalty = 0.2
        case .easy:
            lastDifficultyPenalty = 0.0
        }

        let intervalPenalty: Double
        switch card.interval {
        case ...1:
            intervalPenalty = 0.9
        case 2...4:
            intervalPenalty = 0.45
        default:
            intervalPenalty = 0.0
        }

        let accuracyPenalty = max(0, (75.0 - Double(accuracy)) / 25.0)
        return overdueDays + lastDifficultyPenalty + intervalPenalty + accuracyPenalty
    }

    private static func stableScore(
        for card: CardModel,
        history: [ReviewEvent],
        accuracy: Int
    ) -> Double {
        guard !history.isEmpty else { return 0 }
        guard accuracy >= 80 else { return 0 }
        guard card.interval >= 7 else { return 0 }

        return Double(card.interval) + (Double(accuracy) / 100.0)
    }

    private static func coverageGroups(
        flashcardCards: Int,
        quizCards: Int,
        coverageBuckets: [CardKind: [String]]
    ) -> [DeckHealthCoverageGroup] {
        CardKind.allCases.compactMap { kind in
            let cardCount: Int
            let title: String
            let detail: String

            switch kind {
            case .flashcard:
                cardCount = flashcardCards
                title = "Core Concepts"
                detail = "Fast prompt-and-answer anchors for scanning definitions and facts."
            case .quiz:
                cardCount = quizCards
                title = "Knowledge Checks"
                detail = "Multiple-choice checkpoints that pressure test recognition and comparison."
            }

            guard cardCount > 0 else { return nil }

            let prompts = Array((coverageBuckets[kind] ?? []).prefix(3))
            return DeckHealthCoverageGroup(
                id: kind.rawValue,
                kind: kind,
                title: title,
                detail: detail,
                cardCount: cardCount,
                samplePrompts: prompts
            )
        }
    }
}
