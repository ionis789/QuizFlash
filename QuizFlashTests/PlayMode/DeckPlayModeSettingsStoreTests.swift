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
        let deck = DeckModel(title: "Settings", colorHex: "#FFFFFF")
        context.insert(deck)
        try context.save()

        let first = DeckPlayModeSettingsStore.resolve(for: deck, in: context)
        let second = DeckPlayModeSettingsStore.resolve(for: deck, in: context)

        XCTAssertEqual(first.persistentModelID, second.persistentModelID)
        XCTAssertEqual(deck.playModeSettings?.persistentModelID, first.persistentModelID)
        XCTAssertEqual(try context.fetchAll(DeckPlayModeSettingsModel.self).count, 1)
    }

    func testFlashcardSettingsDecodeLegacyPayloadDefaultsContentAlignmentToCenter() throws {
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

        XCTAssertEqual(decoded.contentAlignment, .center)
        XCTAssertEqual(decoded.textSize, .large)
    }

    func testFlashcardSettingsDecodeSchemaTwoPreservesSavedContentAlignmentAndDefaultsTextSizeToLarge() throws {
        let schemaTwoPayload = """
        {
          "schemaVersion": 2,
          "order": "studyPriority",
          "retryWrongCards": true,
          "revealFlow": "questionFirst",
          "flipBehavior": "tapToFlip",
          "tapAnimationStyle": "flip3D",
          "staticSwapTextMotion": "animated",
          "contentAlignment": "top"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(FlashcardModeSettings.self, from: schemaTwoPayload)

        XCTAssertEqual(decoded.contentAlignment, .top)
        XCTAssertEqual(decoded.textSize, .large)
    }

    func testFlashcardLayoutSettingsPersistThroughDeckSettingsBucket() throws {
        let context = try TestModelContainerFactory.makeContext()
        let deck = DeckModel(title: "Settings", colorHex: "#FFFFFF")
        context.insert(deck)
        try context.save()

        let settings = DeckPlayModeSettingsStore.resolve(for: deck, in: context)
        var flashcardSettings = settings.flashcardSettings
        flashcardSettings.contentAlignment = .center
        flashcardSettings.textSize = .normal
        settings.flashcardSettings = flashcardSettings
        try context.save()

        let resolvedAgain = DeckPlayModeSettingsStore.resolve(for: deck, in: context)
        XCTAssertEqual(resolvedAgain.flashcardSettings.contentAlignment, .center)
        XCTAssertEqual(resolvedAgain.flashcardSettings.textSize, .normal)
    }
}

final class SwipeGestureEvaluatorTests: XCTestCase {
    func testSlowDragKeepsProjectedProgressBoundToActualDistance() {
        let evaluator = SwipeGestureEvaluator(
            tuning: SwipeGestureTuning(
                flickSensitivity: 1.9,
                dismissDistanceThreshold: 180
            )
        )

        let evaluation = evaluator.evaluate(displacementX: -95, velocityX: -9)

        XCTAssertEqual(evaluation.distanceProgress, 95.0 / 180.0, accuracy: 0.0001)
        XCTAssertEqual(evaluation.projectedProgress, evaluation.distanceProgress, accuracy: 0.0001)
        XCTAssertNil(evaluation.projectedCommitDirection)
        XCTAssertNil(evaluation.commitDecision)
    }

    func testPullBackBeforeReleaseClearsVelocityAssist() {
        let evaluator = SwipeGestureEvaluator(tuning: .default)

        let evaluation = evaluator.evaluate(displacementX: -82, velocityX: 420)

        XCTAssertEqual(evaluation.projectedProgress, evaluation.distanceProgress, accuracy: 0.0001)
        XCTAssertNil(evaluation.projectedCommitDirection)
        XCTAssertNil(evaluation.commitDecision)
    }

    func testShortFastFlickStillCommitsThroughVelocityLane() {
        let evaluator = SwipeGestureEvaluator(tuning: .default)

        let evaluation = evaluator.evaluate(displacementX: -24, velocityX: -1500)

        XCTAssertEqual(evaluation.projectedCommitDirection, .left)
        XCTAssertEqual(evaluation.commitDecision?.direction, .left)
        XCTAssertEqual(evaluation.commitDecision?.reason, .flick)
        XCTAssertTrue(evaluation.fastSwipeDetected)
    }

    func testDistanceThresholdWinsWithoutProjection() {
        let evaluator = SwipeGestureEvaluator(tuning: .default)

        let evaluation = evaluator.evaluate(displacementX: 124, velocityX: 0)

        XCTAssertEqual(evaluation.commitDecision?.direction, .right)
        XCTAssertEqual(evaluation.commitDecision?.reason, .distance)
        XCTAssertFalse(evaluation.fastSwipeDetected)
    }
}
