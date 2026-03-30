//
//  DeckPlayModeSettingsStoreTests.swift
//  QuizFlashTests
//
//  Covers the deck-scoped settings persistence bucket.
//

import XCTest
import SwiftData
@testable import QuizFlash

@MainActor
final class DeckPlayModeSettingsStoreTests: XCTestCase {
    func testResolveCreatesAndReusesDeckSettingsBucket() throws {
        let context = try TestModelContainerFactory.makeContext()
        let deck = DeckModel(title: "Settings", icon: "book", colorHex: "#FFFFFF")
        context.insert(deck)
        try context.save()

        let first = DeckPlayModeSettingsStore.resolve(for: deck, in: context)
        let second = DeckPlayModeSettingsStore.resolve(for: deck, in: context)

        XCTAssertEqual(first.persistentModelID, second.persistentModelID)
        XCTAssertEqual(deck.playModeSettings?.persistentModelID, first.persistentModelID)
        XCTAssertEqual(try context.fetchAll(DeckPlayModeSettingsModel.self).count, 1)
    }

    func testFlashcardSettingsDecodeLegacyPayloadDefaultsContentAlignmentToTop() throws {
        let legacyPayload = """
        {
          "order": "studyPriority",
          "retryWrongCards": true,
          "revealFlow": "questionFirst",
          "flipBehavior": "tapToFlip",
          "tapAnimationStyle": "flip3D",
          "staticSwapTextMotion": "animated"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(FlashcardModeSettings.self, from: legacyPayload)

        XCTAssertEqual(decoded.contentAlignment, .top)
    }

    func testFlashcardContentAlignmentPersistsThroughDeckSettingsBucket() throws {
        let context = try TestModelContainerFactory.makeContext()
        let deck = DeckModel(title: "Settings", icon: "book", colorHex: "#FFFFFF")
        context.insert(deck)
        try context.save()

        let settings = DeckPlayModeSettingsStore.resolve(for: deck, in: context)
        var flashcardSettings = settings.flashcardSettings
        flashcardSettings.contentAlignment = .center
        settings.flashcardSettings = flashcardSettings
        try context.save()

        let resolvedAgain = DeckPlayModeSettingsStore.resolve(for: deck, in: context)
        XCTAssertEqual(resolvedAgain.flashcardSettings.contentAlignment, .center)
    }
}
