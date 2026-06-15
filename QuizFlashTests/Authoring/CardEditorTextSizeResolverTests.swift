//
//  CardEditorTextSizeResolverTests.swift
//  QuizFlashTests
//
//  Covers text-size resolution for card authoring.
//

import XCTest
@testable import QuizFlash

final class CardEditorTextSizeResolverTests: XCTestCase {
    func testDeckOverrideTakesPriorityOverGlobalDefault() {
        let resolved = CardEditorTextSizeResolver.resolve(
            override: FlashcardTextSize(step: 2),
            defaultTextSize: FlashcardTextSize(step: 8)
        )

        XCTAssertEqual(resolved, FlashcardTextSize(step: 2))
    }

    func testNewDeckUsesGlobalDefault() {
        let globalDefault = FlashcardTextSize(step: 4)

        let resolved = CardEditorTextSizeResolver.resolve(
            override: nil,
            defaultTextSize: globalDefault
        )

        XCTAssertEqual(resolved, globalDefault)
    }

    func testMissingDeckSettingsDoesNotForceLargeText() {
        let globalDefault = FlashcardTextSize(step: 1)

        let resolved = CardEditorTextSizeResolver.resolve(
            override: nil,
            defaultTextSize: globalDefault
        )

        XCTAssertNotEqual(resolved, .large)
        XCTAssertEqual(resolved, globalDefault)
    }
}
