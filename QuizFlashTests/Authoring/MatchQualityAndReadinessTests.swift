//
//  MatchQualityAndReadinessTests.swift
//  QuizFlashTests
//
//  Covers shared Match compactness rules and readiness visibility boundaries.
//

import XCTest
import SwiftData
@testable import QuizFlash

@MainActor
final class MatchQualityAndReadinessTests: XCTestCase {
    func testMatchQualityPolicyNormalizesWhitespaceAndRejectsVerbosePairs() {
        let compact = MatchCardQualityPolicy.evaluate(
            prompt: "  BFS  ",
            answer: "Breadth-first search"
        )
        XCTAssertTrue(compact.isCompact)
        XCTAssertEqual(compact.prompt, "BFS")
        XCTAssertEqual(compact.answer, "Breadth-first search")

        let verbose = MatchCardQualityPolicy.evaluate(
            prompt: "Describe in detail how the adjacency matrix of a directed graph is interpreted in algorithm design",
            answer: "It is a square matrix where the entry on row i and column j becomes one when an arc exists from node i to node j, otherwise zero, and it is useful because it makes dense-graph lookups straightforward."
        )
        XCTAssertFalse(verbose.isCompact)
    }

    func testFlashcardDraftsNoLongerSurfaceUserVisibleMatchReadiness() {
        let diagnostics = CardReadinessDiagnostics.diagnostics(
            for: TestMutationFactory.flashcard(
                front: "Binary tree",
                back: "Hierarchical structure with two children"
            )
        )

        XCTAssertTrue(diagnostics.isEmpty)
    }

    func testDedicatedMatchDraftsUseSharedCompactnessPolicy() {
        let compactSummary = CardReadinessDiagnostics.summary(
            for: [
                TestMutationFactory.match(prompt: "DFS", answer: "Depth-first search")
            ]
        )
        XCTAssertEqual(compactSummary.matchReadyCount, 1)
        XCTAssertEqual(compactSummary.matchWeakCount, 0)

        let weakSummary = CardReadinessDiagnostics.summary(
            for: [
                TestMutationFactory.match(
                    prompt: "Explain how the adjacency matrix representation behaves for dense directed graphs",
                    answer: "It stores every possible ordered pair and marks whether an arc exists, which makes access constant time but uses much more memory for sparse graphs."
                )
            ]
        )
        XCTAssertEqual(weakSummary.matchReadyCount, 0)
        XCTAssertEqual(weakSummary.matchWeakCount, 1)
    }

    func testDeckSurfaceSummaryHidesMatchReadinessButKeepsWriteWarnings() throws {
        let context = try TestModelContainerFactory.makeContext()
        let deck = DeckModel(title: "Algorithms", colorHex: "#112233")
        let matchCard = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.match(
                prompt: "Explain how the adjacency matrix representation behaves for dense directed graphs",
                answer: "It stores every possible ordered pair and marks whether an arc exists, which makes access constant time but uses much more memory for sparse graphs."
            ),
            cardNumber: 1
        )
        let writeCard = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.write(
                prompt: "The running time is O(n^2).",
                answer: "O(n^2)"
            ),
            cardNumber: 2
        )

        context.insert(deck)
        context.insert(matchCard)
        context.insert(writeCard)
        deck.cards = [matchCard, writeCard]
        deck.cardCount = 2
        try context.save()

        let cards = [
            makeGridCardInfo(
                from: matchCard,
                frontText: "Explain how the adjacency matrix representation behaves for dense directed graphs",
                backText: "It stores every possible ordered pair and marks whether an arc exists, which makes access constant time but uses much more memory for sparse graphs."
            ),
            makeGridCardInfo(
                from: writeCard,
                frontText: "The running time is O(n^2).",
                backText: "O(n^2)"
            )
        ]

        let summary = CardReadinessDiagnostics.deckSurfaceSummary(for: cards)
        XCTAssertEqual(summary.matchReadyCount, 0)
        XCTAssertEqual(summary.matchWeakCount, 0)
        XCTAssertEqual(summary.writeMathHeavyCount, 1)
    }

    private func makeGridCardInfo(
        from card: CardModel,
        frontText: String,
        backText: String
    ) -> GridCardInfo {
        GridCardInfo(
            id: card.persistentModelID,
            kind: card.cardContent.kind,
            creationSource: card.creationSource,
            conversionMetadata: card.conversionMetadata,
            cardNumber: card.cardNumber,
            interval: card.interval,
            reviewHistoryIsEmpty: card.reviewHistory.isEmpty,
            isPinned: card.isPinned,
            frontText: frontText,
            backText: backText,
            frontPreviewText: frontText,
            backPreviewText: backText,
            searchDocumentText: "\(frontText) \(backText)",
            createdAt: card.createdAt,
            editedAt: card.editedAt
        )
    }
}
