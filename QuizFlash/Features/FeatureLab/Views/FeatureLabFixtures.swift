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
        let progress: DeckProgressStats
        let stats: DeckStats
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

        return Runtime(
            libraryDeckRow: libraryDeckRow,
            deckGridSections: deckGridSections,
            recentDeck: recentDeck,
            folder: folder,
            draftCard: draftCard,
            progress: progress,
            stats: stats
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
}
