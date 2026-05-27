//
//  LibraryViewModelSearchTests.swift
//  QuizFlashTests
//
//  Covers the rendered search snapshot behavior used by Library and Folder lists.
//

import XCTest
import SwiftData
@testable import QuizFlash

@MainActor
final class LibraryViewModelSearchTests: XCTestCase {
    func testSearchKeepsPreviousRenderedSnapshotUntilNewResultsFinish() async {
        let context = try! TestModelContainerFactory.makeContext()
        let alphaDeck = DeckModel(title: "Alpha Deck", colorHex: "#FF9500")
        let betaDeck = DeckModel(title: "Beta Deck", colorHex: "#0A84FF")
        let alphaCard = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.flashcard(front: "alpha prompt", back: "answer"),
            cardNumber: 1
        )
        let betaCard = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.flashcard(front: "beta prompt", back: "answer"),
            cardNumber: 1
        )
        context.insert(alphaDeck)
        context.insert(betaDeck)
        context.insert(alphaCard)
        context.insert(betaCard)
        alphaDeck.cards = [alphaCard]
        betaDeck.cards = [betaCard]
        alphaDeck.cardCount = 4
        betaDeck.cardCount = 3

        let viewModel = LibraryViewModel()
        viewModel.isSearching = true
        viewModel.cachedSearchPayloads = [
            DeckSearchPayload(
                id: alphaDeck.persistentModelID,
                title: "Alpha Deck",
                colorHex: "#FF9500",
                cardCount: 4,
                editedAt: .now,
                cards: [
                    CardSearchPayload(
                        id: alphaCard.persistentModelID,
                        frontText: "alpha prompt",
                        backText: "answer",
                        searchDocumentText: "alpha prompt answer"
                    )
                ]
            ),
            DeckSearchPayload(
                id: betaDeck.persistentModelID,
                title: "Beta Deck",
                colorHex: "#0A84FF",
                cardCount: 3,
                editedAt: .now,
                cards: [
                    CardSearchPayload(
                        id: betaCard.persistentModelID,
                        frontText: "beta prompt",
                        backText: "answer",
                        searchDocumentText: "beta prompt answer"
                    )
                ]
            )
        ]

        viewModel.debounceSearchInput("alpha")
        await TestAsyncHelpers.waitUntil {
            viewModel.renderedSearchQuery == "alpha"
        }

        let previousTitles = viewModel.searchResults.map(\.deckTitle)
        XCTAssertEqual(previousTitles, ["Alpha Deck"])

        viewModel.debounceSearchInput("beta")

        XCTAssertEqual(viewModel.renderedSearchQuery, "alpha")
        XCTAssertEqual(viewModel.searchResults.map(\.deckTitle), previousTitles)
        XCTAssertTrue(viewModel.isSearchLoading)

        await TestAsyncHelpers.waitUntil {
            viewModel.renderedSearchQuery == "beta"
        }

        XCTAssertEqual(viewModel.searchResults.map(\.deckTitle), ["Beta Deck"])
        XCTAssertFalse(viewModel.isSearchLoading)
        XCTAssertEqual(viewModel.searchPresentation, .searchResults)
    }

    func testEmptyQueryKeepsSearchChromeButReturnsBrowseContent() {
        let context = try! TestModelContainerFactory.makeContext()
        let deck = DeckModel(title: "Rendered", colorHex: "#FF9500")
        context.insert(deck)

        let viewModel = LibraryViewModel()
        viewModel.isSearching = true
        viewModel.searchResults = [
            DeckSearchResultItem(
                id: deck.persistentModelID,
                deckTitle: "Rendered",
                deckColorHex: "#FF9500",
                cardCount: 2,
                editedAt: .now,
                titleMatches: true,
                matchedCards: [],
                totalMatchedCardsCount: 0
            )
        ]
        viewModel.renderedSearchQuery = "rendered"

        viewModel.debounceSearchInput("")

        XCTAssertTrue(viewModel.isSearching)
        XCTAssertEqual(viewModel.searchPresentation, .searchEmpty)
        XCTAssertTrue(viewModel.searchResults.isEmpty)
        XCTAssertEqual(viewModel.renderedSearchQuery, "")
        XCTAssertFalse(viewModel.isSearchLoading)
    }

    func testClearSearchResetsRenderedSearchState() {
        let context = try! TestModelContainerFactory.makeContext()
        let deck = DeckModel(title: "Deck", colorHex: "#34C759")
        context.insert(deck)

        let viewModel = LibraryViewModel()
        viewModel.isSearching = true
        viewModel.searchText = "deck"
        viewModel.renderedSearchQuery = "deck"
        viewModel.isSearchLoading = true
        viewModel.searchResults = [
            DeckSearchResultItem(
                id: deck.persistentModelID,
                deckTitle: "Deck",
                deckColorHex: "#34C759",
                cardCount: 1,
                editedAt: .now,
                titleMatches: true,
                matchedCards: [],
                totalMatchedCardsCount: 0
            )
        ]

        viewModel.clearSearch()

        XCTAssertFalse(viewModel.isSearching)
        XCTAssertEqual(viewModel.searchPresentation, .browse)
        XCTAssertEqual(viewModel.searchText, "")
        XCTAssertEqual(viewModel.renderedSearchQuery, "")
        XCTAssertTrue(viewModel.searchResults.isEmpty)
        XCTAssertFalse(viewModel.isSearchLoading)
    }
}
