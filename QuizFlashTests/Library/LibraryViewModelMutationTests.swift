//
//  LibraryViewModelMutationTests.swift
//  QuizFlashTests
//
//  Covers bulk library mutations like delete and move.
//

import XCTest
import SwiftData
@testable import QuizFlash

@MainActor
final class LibraryViewModelMutationTests: XCTestCase {
    func testDeleteSelectedDecksRemovesDecksAndClearsSelectionState() throws {
        let context = try TestModelContainerFactory.makeContext()
        let folder = FolderModel(title: "Folder", colorHex: "#112233")
        let selectedDeck = DeckModel(title: "Selected", icon: "book", colorHex: "#AAAAAA")
        let untouchedDeck = DeckModel(title: "Untouched", icon: "book", colorHex: "#BBBBBB")

        context.insert(folder)
        context.insert(selectedDeck)
        context.insert(untouchedDeck)

        selectedDeck.folder = folder
        untouchedDeck.folder = folder
        folder.deckCount = 2
        try context.save()

        let viewModel = LibraryViewModel()
        viewModel.isSelecting = true
        viewModel.selectedDecks = [selectedDeck.id]

        viewModel.deleteSelectedDecks(from: [selectedDeck, untouchedDeck], context: context)

        let decks = try context.fetchAll(DeckModel.self)
        XCTAssertEqual(decks.map(\.title), ["Untouched"])
        XCTAssertEqual(folder.deckCount, 1)
        XCTAssertFalse(viewModel.isSelecting)
        XCTAssertTrue(viewModel.selectedDecks.isEmpty)
    }

    func testConfirmSingleDeletionDeletesPendingDeck() throws {
        let context = try TestModelContainerFactory.makeContext()
        let folder = FolderModel(title: "Delete", colorHex: "#445566")
        let deck = DeckModel(title: "Disposable", icon: "book", colorHex: "#CCCCCC")

        context.insert(folder)
        context.insert(deck)

        deck.folder = folder
        folder.deckCount = 1
        try context.save()

        let viewModel = LibraryViewModel()
        viewModel.deckToDelete = deck

        viewModel.confirmSingleDeletion(context: context)

        XCTAssertTrue(try context.fetchAll(DeckModel.self).isEmpty)
        XCTAssertEqual(folder.deckCount, 0)
        XCTAssertNil(viewModel.deckToDelete)
    }

    func testMoveSelectedDecksUpdatesFolderCountsAndEditedDate() throws {
        let context = try TestModelContainerFactory.makeContext()
        let sourceFolder = FolderModel(title: "Source", colorHex: "#111111")
        let destinationFolder = FolderModel(title: "Destination", colorHex: "#222222")
        let movingDeck = DeckModel(title: "Move Me", icon: "book", colorHex: "#123123")
        let otherDeck = DeckModel(title: "Stay", icon: "book", colorHex: "#456456")

        context.insert(sourceFolder)
        context.insert(destinationFolder)
        context.insert(movingDeck)
        context.insert(otherDeck)

        movingDeck.folder = sourceFolder
        otherDeck.folder = sourceFolder
        sourceFolder.deckCount = 2
        destinationFolder.deckCount = 0
        try context.save()

        let originalEditedAt = movingDeck.editedAt

        let viewModel = LibraryViewModel()
        viewModel.isSelecting = true
        viewModel.selectedDecks = [movingDeck.id]
        viewModel.showMoveConfirmation = true

        viewModel.moveSelectedDecks(
            from: [movingDeck, otherDeck],
            to: destinationFolder,
            context: context
        )

        XCTAssertEqual(movingDeck.folder?.persistentModelID, destinationFolder.persistentModelID)
        XCTAssertEqual(sourceFolder.deckCount, 1)
        XCTAssertEqual(destinationFolder.deckCount, 1)
        XCTAssertGreaterThanOrEqual(movingDeck.editedAt, originalEditedAt)
        XCTAssertFalse(viewModel.isSelecting)
        XCTAssertTrue(viewModel.selectedDecks.isEmpty)
        XCTAssertFalse(viewModel.showMoveConfirmation)
        XCTAssertFalse(viewModel.showMoveError)
    }

    func testHandleFileImportRejectsNonQFlashFiles() throws {
        let context = try TestModelContainerFactory.makeContext()
        let invalidURL = FileManager.default.temporaryDirectory.appendingPathComponent("notes.txt")
        try Data("plain text".utf8).write(to: invalidURL)
        defer { try? FileManager.default.removeItem(at: invalidURL) }

        let viewModel = LibraryViewModel()
        viewModel.handleFileImport(.success([invalidURL]), context: context)

        XCTAssertTrue(viewModel.showImportError)
        XCTAssertEqual(viewModel.importErrorMessage, "Please select .qflash files")
        XCTAssertFalse(viewModel.isImporting)
    }

    func testHandleFileImportPersistsImportedDeckAndSuccessState() async throws {
        let exportContext = try TestModelContainerFactory.makeContext()
        let sourceDeck = DeckModel(title: "Import Me", icon: "book", colorHex: "#ABC123")
        let sourceCard = TestMutationFactory.makePersistedCard(
            content: TestMutationFactory.flashcard(front: "Q", back: "A"),
            cardNumber: 1
        )
        exportContext.insert(sourceDeck)
        exportContext.insert(sourceCard)
        sourceDeck.cards = [sourceCard]
        sourceDeck.cardCount = 1
        sourceDeck.lastAssignedCardNumber = 1
        try exportContext.save()

        let fileURL = try await DeckSharingManager.shared.exportDeck(sourceDeck)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let importContext = try TestModelContainerFactory.makeContext()
        let viewModel = LibraryViewModel()
        viewModel.handleFileImport(.success([fileURL]), context: importContext)

        await TestAsyncHelpers.waitUntil {
            !viewModel.isImporting && viewModel.showImportSuccess
        }

        let decks = try importContext.fetchAll(DeckModel.self)
        XCTAssertEqual(decks.count, 1)
        XCTAssertEqual(decks.first?.title, "Import Me")
        XCTAssertEqual(viewModel.importedDeckName, "Import Me")
        XCTAssertTrue(viewModel.showImportSuccess)
        XCTAssertFalse(viewModel.showImportError)
    }
}
