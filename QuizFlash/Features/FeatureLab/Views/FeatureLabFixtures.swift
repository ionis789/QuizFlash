//
//  FeatureLabFixtures.swift
//  QuizFlash
//
//  Shared in-memory fixtures used by internal labs and UI catalogs.
//

import Foundation
import SwiftData

enum FeatureLabFixtures {
    struct Runtime {
        let libraryDeckRow: LibraryDeckRowSnapshot
        let deckGridSections: [DeckCardGridView.CardSection]
        let recentDeck: DeckModel
        let folder: FolderModel
        let draftCard: DraftCard
        let flashCardsPlayModeSimulationDeckTitle: String
        let flashCardsPlayModeSimulationCards: [PlayableCard]
        let progress: DeckProgressStats
        let stats: DeckStats
        let todayActivity: DeckTodayActivitySummary
    }

    static let shared: Runtime = {
        let libraryDeck = DeckModel(title: "Operating Systems Crash Course", colorHex: "#FF6B4A")
        libraryDeck.cardCount = 32
        libraryDeck.lastOpenedAt = .now.addingTimeInterval(-60 * 35)
        libraryDeck.editedAt = .now.addingTimeInterval(-60 * 11)

        let flashcard = CardModel(
            frontZone: .text("Define idempotency in REST APIs."),
            backZone: .text("The same repeated request leaves server state unchanged after the first success."),
            cardNumber: 1,
            isPinned: true,
            creationSource: .manual
        )
        flashcard.interval = 21
        flashcard.consecutiveCorrectAnswers = 4

        let quizCard = CardModel(
            content: .quiz(
                QuizCardContent(
                    questionZone: .text("Which data structure usually provides O(1) average lookup?"),
                    choices: [
                        QuizChoiceDraft(contentZone: .text("Hash table"), isCorrect: true),
                        QuizChoiceDraft(contentZone: .text("Linked list"), isCorrect: false),
                        QuizChoiceDraft(contentZone: .text("Binary heap"), isCorrect: false)
                    ],
                    explanationZone: .text("Hashing trades ordered traversal for very fast direct access on average."),
                    allowsMultipleCorrect: false
                )
            ),
            cardNumber: 2,
            isPinned: false,
            creationSource: .ai
        )
        quizCard.interval = 3
        quizCard.consecutiveCorrectAnswers = 1

        let writeSource = ZoneModel.text("HTTP status 429 means too many ____.")
        let writeCard = CardModel(
            content: .write(
                WriteCardContent(
                    sourceZone: writeSource,
                    blankSelection: .init(
                        zoneID: writeSource.id,
                        utf16Range: 27..<35,
                        omittedText: "requests"
                    )
                )
            ),
            cardNumber: 3,
            isPinned: false,
            creationSource: .manual
        )
        writeCard.interval = 0

        let matchCard = CardModel(
            content: .match(
                MatchCardContent(
                    prompt: "TCP handshake",
                    answer: "SYN, SYN-ACK, ACK"
                )
            ),
            cardNumber: 4,
            isPinned: false,
            creationSource: .manual
        )
        matchCard.interval = 8
        matchCard.consecutiveCorrectAnswers = 2

        let recentDeck = DeckModel(title: "Discrete Math Sprint", colorHex: "#FF6B4A")
        recentDeck.cardCount = 48
        recentDeck.lastOpenedAt = .now.addingTimeInterval(-60 * 42)
        recentDeck.editedAt = .now.addingTimeInterval(-60 * 18)

        let folder = FolderModel(title: "Semester Finals", colorHex: "#F5A623")
        folder.deckCount = 6

        let draftCard = DraftCard(
            cardNumber: 12,
            content: .quiz(
                QuizCardContent(
                    questionZone: .text("Which protocol upgrades an HTTP connection into a persistent full-duplex channel?"),
                    choices: [
                        QuizChoiceDraft(contentZone: .text("WebSocket"), isCorrect: true),
                        QuizChoiceDraft(contentZone: .text("SMTP"), isCorrect: false),
                        QuizChoiceDraft(contentZone: .text("FTP"), isCorrect: false)
                    ],
                    explanationZone: .text("WebSocket starts with HTTP and upgrades the same TCP connection for two-way messaging."),
                    allowsMultipleCorrect: false
                )
            ),
            isPinned: true,
            creationSource: .manual,
            createdAt: .now.addingTimeInterval(-60 * 60 * 26),
            editedAt: .now.addingTimeInterval(-60 * 13)
        )

        let simulationDeckTitle = "Probabilistic Analysis of Algorithms"
        let simulationCardOne = CardModel(
            frontZone: makeSimulationFrontZone(
                title: "What does the indicator variable $X_i$ represent?",
                detail: "Connect the hiring-process intuition with the compact mathematical notation."
            ),
            backZone: makeSimulationBackZone(
                summary: "$X_i = 1$ if candidate $i$ is hired and $0$ otherwise.",
                insight: "This turns the total number of hires into $X = \\sum_i X_i$, which makes $\\mathbb{E}[X]$ easy to analyze."
            ),
            cardNumber: 1,
            isPinned: false,
            creationSource: .manual
        )
        simulationCardOne.interval = 6

        let simulationCardTwo = CardModel(
            frontZone: makeSimulationFrontZone(
                title: "Why can a fast flick commit before distance reaches 100%?",
                detail: "Think about predicted travel, velocity alignment, and the real dismiss distance."
            ),
            backZone: makeSimulationBackZone(
                summary: "Because the commit engine validates a genuine flick lane, not just raw projection alone.",
                insight: "Velocity, direction alignment, minimum travel, and projected reach must all agree with the same dismiss threshold."
            ),
            cardNumber: 2,
            isPinned: false,
            creationSource: .manual
        )
        simulationCardTwo.interval = 12

        let simulationCardThree = CardModel(
            frontZone: makeSimulationFrontZone(
                title: "What should the swipe object animation communicate?",
                detail: "Focus on intent confirmation, clean travel toward the edge, and a readable handoff into card dismiss."
            ),
            backZone: makeSimulationBackZone(
                summary: "It should feel attached to the gesture first, then confidently peel away once dismiss is certain.",
                insight: "Readable motion needs a short engage phase, a visible glide, and a fade that starts after movement is already legible."
            ),
            cardNumber: 3,
            isPinned: true,
            creationSource: .manual
        )
        simulationCardThree.interval = 18

        let flashCardsPlayModeSimulationCards = [
            simulationCardOne,
            simulationCardTwo,
            simulationCardThree,
        ].map { card in
            PlayableCard(
                id: card.persistentModelID,
                cardNumber: card.cardNumber,
                frontZone: card.frontZone,
                backZone: card.backZone,
                interval: card.interval
            )
        }

        let libraryDeckRow = LibraryDeckRowSnapshot(
            id: libraryDeck.persistentModelID,
            title: libraryDeck.title,
            colorHex: libraryDeck.colorHex,
            createdAt: libraryDeck.createdAt,
            editedAt: libraryDeck.editedAt,
            lastOpenedAt: libraryDeck.lastOpenedAt,
            cardCount: libraryDeck.cardCount,
            folderTitle: nil
        )

        let pinnedCard = makeGridCardInfo(flashcard, reviewHistoryIsEmpty: false)
        let gridCards = [
            makeGridCardInfo(quizCard, reviewHistoryIsEmpty: false),
            makeGridCardInfo(writeCard, reviewHistoryIsEmpty: true),
            makeGridCardInfo(matchCard, reviewHistoryIsEmpty: false)
        ]

        let deckGridSections = [
            DeckCardGridView.CardSection(
                id: "pinned",
                title: "Pinned",
                cards: [pinnedCard]
            ),
            DeckCardGridView.CardSection(
                id: "recent",
                title: "Recent",
                cards: gridCards
            )
        ]

        let progress = DeckProgressStats(
            newCards: 8,
            learningCards: 15,
            masteredCards: 25,
            total: 48
        )

        let stats = DeckStats(
            totalCards: 48,
            dueCards: 9,
            totalReviews: 187,
            accuracy: 91,
            totalXPEarned: 1240,
            deckMastery: 0.68,
            todayReviewed: 22
        )

        let todayActivity = DeckTodayActivitySummary(
            activityDate: .now,
            activityLabel: "Today",
            uniqueCardsReviewed: 4,
            rawReviewCount: 7,
            landedCount: 3,
            retryCount: 1,
            headline: "4 cards moved today",
            detailLine: "7 passes folded into 4 cards. 1 still needs another pass.",
            cards: [
                DeckTodayReviewedCardSummary(
                    id: flashcard.persistentModelID,
                    title: "Define idempotency in REST APIs.",
                    finalDifficulty: .good,
                    reviewCount: 2,
                    lastReviewedAt: .now.addingTimeInterval(-60 * 3)
                ),
                DeckTodayReviewedCardSummary(
                    id: quizCard.persistentModelID,
                    title: "Which data structure usually provides O(1) average lookup?",
                    finalDifficulty: .again,
                    reviewCount: 1,
                    lastReviewedAt: .now.addingTimeInterval(-60 * 11)
                ),
                DeckTodayReviewedCardSummary(
                    id: writeCard.persistentModelID,
                    title: "HTTP status 429 means too many ____.",
                    finalDifficulty: .hard,
                    reviewCount: 3,
                    lastReviewedAt: .now.addingTimeInterval(-60 * 18)
                ),
                DeckTodayReviewedCardSummary(
                    id: matchCard.persistentModelID,
                    title: "TCP handshake",
                    finalDifficulty: .easy,
                    reviewCount: 1,
                    lastReviewedAt: .now.addingTimeInterval(-60 * 27)
                )
            ]
        )

        return Runtime(
            libraryDeckRow: libraryDeckRow,
            deckGridSections: deckGridSections,
            recentDeck: recentDeck,
            folder: folder,
            draftCard: draftCard,
            flashCardsPlayModeSimulationDeckTitle: simulationDeckTitle,
            flashCardsPlayModeSimulationCards: flashCardsPlayModeSimulationCards,
            progress: progress,
            stats: stats,
            todayActivity: todayActivity
        )
    }()

    private static func makeGridCardInfo(
        _ card: CardModel,
        reviewHistoryIsEmpty: Bool
    ) -> GridCardInfo {
        GridCardInfo(
            id: card.persistentModelID,
            kind: card.kind,
            creationSource: card.creationSource,
            conversionMetadata: card.conversionMetadata,
            cardNumber: card.cardNumber,
            interval: card.interval,
            reviewHistoryIsEmpty: reviewHistoryIsEmpty,
            isPinned: card.isPinned,
            frontText: card.frontText,
            backText: card.backText,
            frontPreviewText: card.frontText,
            backPreviewText: card.backText,
            searchDocumentText: "\(card.frontText) \(card.backText)",
            createdAt: card.createdAt,
            editedAt: card.editedAt
        )
    }

    private static func makeSimulationFrontZone(title: String, detail: String) -> ZoneModel {
        var eyebrow = ZoneModel.text("SWIPE LAB")
        eyebrow.textStyle = .caption
        eyebrow.fontFamily = .rounded
        eyebrow.textColor = .orange
        eyebrow.isBold = true

        var headline = ZoneModel.text(title)
        headline.textStyle = .headline
        headline.fontFamily = .rounded
        headline.isBold = true

        var body = ZoneModel.text(detail)
        body.textStyle = .body
        body.fontFamily = .rounded

        return .container(direction: .vertical, children: [eyebrow, headline, body])
    }

    private static func makeSimulationBackZone(summary: String, insight: String) -> ZoneModel {
        var eyebrow = ZoneModel.text("ANSWER")
        eyebrow.textStyle = .caption
        eyebrow.fontFamily = .rounded
        eyebrow.textColor = .green
        eyebrow.isBold = true

        var summaryZone = ZoneModel.text(summary)
        summaryZone.textStyle = .headline
        summaryZone.fontFamily = .rounded
        summaryZone.isBold = true

        var insightZone = ZoneModel.text(insight)
        insightZone.textStyle = .body
        insightZone.fontFamily = .rounded

        return .container(direction: .vertical, children: [eyebrow, summaryZone, insightZone])
    }
}
