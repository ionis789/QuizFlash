//
//  HomeViewModelTests.swift
//  QuizFlashTests
//
//  Covers folder and exam-goal persistence mutations from Home.
//

import XCTest
import SwiftData
@testable import QuizFlash

@MainActor
final class HomeViewModelTests: XCTestCase {
    func testCreateFolderPersistsFolderAndResetsDraftState() throws {
        let context = try TestModelContainerFactory.makeContext()
        let viewModel = HomeViewModel()

        viewModel.newFolderTitle = "  Medical  "
        viewModel.newFolderColorHex = "#123456"
        viewModel.showCreateFolder = true
        viewModel.createFolder(context: context)

        let folders = try context.fetchAll(FolderModel.self)
        XCTAssertEqual(folders.count, 1)
        XCTAssertEqual(folders.first?.title, "Medical")
        XCTAssertEqual(folders.first?.colorHex, "#123456")
        XCTAssertEqual(viewModel.newFolderTitle, "")
        XCTAssertFalse(viewModel.showCreateFolder)
    }

    func testSaveExamGoalCreatesLinkedGoal() throws {
        let context = try TestModelContainerFactory.makeContext()
        let firstDeck = DeckModel(title: "Deck A", icon: "book", colorHex: "#AAA111")
        let secondDeck = DeckModel(title: "Deck B", icon: "book", colorHex: "#BBB222")
        context.insert(firstDeck)
        context.insert(secondDeck)
        try context.save()

        let viewModel = HomeViewModel()
        viewModel.presentCreateExamGoal()
        viewModel.newExamGoalTitle = "Final Exam"
        viewModel.newExamGoalNote = "High priority"
        viewModel.newExamGoalTargetWorkload = 45
        viewModel.toggleExamGoalDeckSelection(firstDeck.persistentModelID)
        viewModel.toggleExamGoalDeckSelection(secondDeck.persistentModelID)

        viewModel.saveExamGoal(
            context: context,
            availableDecks: [firstDeck, secondDeck],
            editingGoal: nil
        )

        let goals = try context.fetchAll(ExamGoalModel.self)
        XCTAssertEqual(goals.count, 1)

        let goal = try XCTUnwrap(goals.first)
        XCTAssertEqual(goal.title, "Final Exam")
        XCTAssertEqual(goal.note, "High priority")
        XCTAssertEqual(goal.status, .active)
        XCTAssertEqual(goal.targetWorkload, 45)
        XCTAssertEqual(Set(goal.linkedDecks.map(\.persistentModelID)), [firstDeck.persistentModelID, secondDeck.persistentModelID])
        XCTAssertNil(viewModel.examGoalSheetPresentation)
        XCTAssertTrue(viewModel.newExamGoalLinkedDeckIDs.isEmpty)
    }

    func testSaveExamGoalEditsExistingGoalAndStatus() throws {
        let context = try TestModelContainerFactory.makeContext()
        let originalDeck = DeckModel(title: "Original", icon: "book", colorHex: "#AAAAAA")
        let replacementDeck = DeckModel(title: "Replacement", icon: "book", colorHex: "#BBBBBB")
        let goal = ExamGoalModel(
            title: "Exam",
            note: "Old note",
            date: Date(),
            targetWorkload: 20,
            status: .active,
            linkedDecks: []
        )
        context.insert(originalDeck)
        context.insert(replacementDeck)
        context.insert(goal)
        goal.linkedDecks = [originalDeck]
        try context.save()

        let viewModel = HomeViewModel()
        viewModel.presentExamGoalEditor(for: goal)
        viewModel.newExamGoalTitle = "Edited Exam"
        viewModel.newExamGoalNote = "Updated note"
        viewModel.newExamGoalTargetWorkload = 60
        viewModel.newExamGoalStatus = .completed
        viewModel.newExamGoalLinkedDeckIDs = [replacementDeck.persistentModelID]

        viewModel.saveExamGoal(
            context: context,
            availableDecks: [originalDeck, replacementDeck],
            editingGoal: goal
        )

        XCTAssertEqual(goal.title, "Edited Exam")
        XCTAssertEqual(goal.note, "Updated note")
        XCTAssertEqual(goal.targetWorkload, 60)
        XCTAssertEqual(goal.status, .completed)
        XCTAssertEqual(goal.linkedDecks.map(\.persistentModelID), [replacementDeck.persistentModelID])
    }

    func testUpdateExamGoalStatusPersistsStatusMutation() throws {
        let context = try TestModelContainerFactory.makeContext()
        let deck = DeckModel(title: "Deck", icon: "book", colorHex: "#111111")
        let goal = ExamGoalModel(
            title: "Status Goal",
            note: "",
            date: Date(),
            targetWorkload: 15,
            status: .active,
            linkedDecks: []
        )
        context.insert(deck)
        context.insert(goal)
        goal.linkedDecks = [deck]
        try context.save()

        let viewModel = HomeViewModel()
        viewModel.updateExamGoalStatus(.archived, for: goal, context: context)

        XCTAssertEqual(goal.status, .archived)
    }
}
