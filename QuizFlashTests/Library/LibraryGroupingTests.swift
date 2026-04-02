//
//  LibraryGroupingTests.swift
//  QuizFlashTests
//
//  Covers lightweight Library row snapshots and section grouping.
//

import XCTest
import SwiftData
@testable import QuizFlash

@MainActor
final class LibraryGroupingTests: XCTestCase {
    func testMakeDeckSnapshotsCopiesPrimitiveDeckMetadata() throws {
        let context = try TestModelContainerFactory.makeContext()
        let folder = FolderModel(title: "Algorithms", colorHex: "#123456")
        let deck = DeckModel(title: "Graphs", colorHex: "#ABCDEF")

        context.insert(folder)
        context.insert(deck)

        deck.folder = folder
        deck.cardCount = 12
        try context.save()

        let snapshot = try XCTUnwrap(LibraryGrouping.makeDeckSnapshots(from: [deck]).first)

        XCTAssertEqual(snapshot.id, deck.persistentModelID)
        XCTAssertEqual(snapshot.title, "Graphs")
        XCTAssertEqual(snapshot.colorHex, "#ABCDEF")
        XCTAssertEqual(snapshot.cardCount, 12)
        XCTAssertEqual(snapshot.folderTitle, "Algorithms")

        deck.title = "Mutated Title"
        deck.cardCount = 99

        XCTAssertEqual(snapshot.title, "Graphs")
        XCTAssertEqual(snapshot.cardCount, 12)
    }

    func testSectionsGroupSnapshotsByCalendarDay() throws {
        let calendar = Calendar(identifier: .gregorian)
        let dayOne = calendar.date(from: DateComponents(year: 2026, month: 3, day: 17, hour: 10))!
        let sameDayLater = calendar.date(from: DateComponents(year: 2026, month: 3, day: 17, hour: 18))!
        let previousDay = calendar.date(from: DateComponents(year: 2026, month: 3, day: 16, hour: 8))!

        let context = try TestModelContainerFactory.makeContext()
        let first = DeckModel(title: "First", colorHex: "#111111")
        let second = DeckModel(title: "Second", colorHex: "#222222")
        let third = DeckModel(title: "Third", colorHex: "#333333")

        context.insert(first)
        context.insert(second)
        context.insert(third)

        first.createdAt = dayOne
        first.editedAt = dayOne
        first.cardCount = 3

        second.createdAt = sameDayLater
        second.editedAt = sameDayLater
        second.cardCount = 5

        third.createdAt = previousDay
        third.editedAt = previousDay
        third.cardCount = 8

        let snapshots = LibraryGrouping.makeDeckSnapshots(from: [first, second, third])

        let sections = LibraryGrouping.sections(decks: snapshots, sortOrder: .lastEdited)

        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].decks.map(\.title), ["Second", "First"])
        XCTAssertEqual(sections[1].decks.map(\.title), ["Third"])
    }
}
