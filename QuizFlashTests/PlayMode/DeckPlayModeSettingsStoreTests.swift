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
          "revealFlow": "answerFirst",
          "flipBehavior": "locked",
          "tapAnimationStyle": "flip3D",
          "staticSwapTextMotion": "animated"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(FlashcardModeSettings.self, from: legacyPayload)

        XCTAssertEqual(decoded.contentAlignment, .center)
        XCTAssertEqual(decoded.zoneGroupAlignment, .auto)
        XCTAssertEqual(decoded.innerZoneAlignment, .auto)
        XCTAssertEqual(decoded.textSize, .large)
        XCTAssertTrue(decoded.usesAppTextSize)
    }

    func testFlashcardSettingsEncodingDropsRemovedFaceAndFlipFields() throws {
        let encoded = try JSONEncoder().encode(FlashcardModeSettings())
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertNil(payload["revealFlow"])
        XCTAssertNil(payload["flipBehavior"])
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
        XCTAssertTrue(decoded.usesAppTextSize)
    }

    func testLegacyMaximumTextSizeMigratesToAppDefault() throws {
        let legacyPayload = """
        {
          "schemaVersion": 5,
          "textSize": 10
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(FlashcardModeSettings.self, from: legacyPayload)

        XCTAssertEqual(decoded.textSize, .large)
        XCTAssertTrue(decoded.usesAppTextSize)
    }

    func testLegacyCustomTextSizePreservesAnApproximateOverride() throws {
        let legacyPayload = """
        {
          "schemaVersion": 5,
          "textSize": 4
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(FlashcardModeSettings.self, from: legacyPayload)

        XCTAssertEqual(decoded.textSize, .normal)
        XCTAssertFalse(decoded.usesAppTextSize)
    }

    func testLegacyTextSizeScaleMapsToSevenStableSteps() {
        XCTAssertEqual(FlashcardTextSize.migratedLegacyStep(0), FlashcardTextSize(step: 1))
        XCTAssertEqual(FlashcardTextSize.migratedLegacyStep(4), .normal)
        XCTAssertEqual(FlashcardTextSize.migratedLegacyStep(10), .large)
        XCTAssertEqual(FlashcardTextSize.allCases.count, 7)
        XCTAssertEqual(FlashcardTextSize(step: 0).playModeScale, 0.72)
    }

    func testNewModeSettingsResolveTheCurrentAppDefaults() {
        let globalSize = FlashcardTextSize(step: 1)
        let globalAlignments = ZoneAlignmentDefaults(
            group: .trailing,
            innerZone: .leading
        )

        XCTAssertEqual(
            FlashcardModeSettings().resolvedTextSize(default: globalSize),
            globalSize
        )
        XCTAssertEqual(
            QuizModeSettings().resolvedTextSize(default: globalSize),
            globalSize
        )
        XCTAssertEqual(
            FlashcardModeSettings().resolvedZoneAlignments(default: globalAlignments),
            globalAlignments
        )
        XCTAssertEqual(
            QuizModeSettings().resolvedZoneAlignments(default: globalAlignments),
            globalAlignments
        )
    }

    func testModeZoneAlignmentOverridesTheAppDefault() {
        let flashcardSettings = FlashcardModeSettings(
            zoneGroupAlignment: .leading,
            innerZoneAlignment: .trailing
        )
        let quizSettings = QuizModeSettings(
            zoneGroupAlignment: .trailing,
            innerZoneAlignment: .center
        )
        let appDefaults = ZoneAlignmentDefaults.standard

        XCTAssertEqual(
            flashcardSettings.resolvedZoneAlignments(default: appDefaults),
            ZoneAlignmentDefaults(group: .leading, innerZone: .trailing)
        )
        XCTAssertEqual(
            quizSettings.resolvedZoneAlignments(default: appDefaults),
            ZoneAlignmentDefaults(group: .trailing, innerZone: .center)
        )
    }

    func testModeZoneAlignmentRoundTripsForBothGameTypes() throws {
        let flashcardSettings = FlashcardModeSettings(
            zoneGroupAlignment: .leading,
            innerZoneAlignment: .trailing
        )
        let quizSettings = QuizModeSettings(
            zoneGroupAlignment: .trailing,
            innerZoneAlignment: .center
        )

        let decodedFlashcardSettings = try JSONDecoder().decode(
            FlashcardModeSettings.self,
            from: JSONEncoder().encode(flashcardSettings)
        )
        let decodedQuizSettings = try JSONDecoder().decode(
            QuizModeSettings.self,
            from: JSONEncoder().encode(quizSettings)
        )

        XCTAssertEqual(decodedFlashcardSettings.zoneGroupAlignment, .leading)
        XCTAssertEqual(decodedFlashcardSettings.innerZoneAlignment, .trailing)
        XCTAssertEqual(decodedQuizSettings.zoneGroupAlignment, .trailing)
        XCTAssertEqual(decodedQuizSettings.innerZoneAlignment, .center)
    }

    func testQuizSettingsDecodeLegacyPayloadInheritsZoneAlignment() throws {
        let legacyPayload = """
        {
          "schemaVersion": 2,
          "shuffleChoices": true
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(QuizModeSettings.self, from: legacyPayload)

        XCTAssertEqual(decoded.zoneGroupAlignment, .auto)
        XCTAssertEqual(decoded.innerZoneAlignment, .auto)
    }

    func testPreviousZoneAlignmentPayloadMigratesToInnerZones() throws {
        let previousPayload = """
        {
          "schemaVersion": 7,
          "zoneAlignment": "trailing"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(FlashcardModeSettings.self, from: previousPayload)

        XCTAssertEqual(decoded.zoneGroupAlignment, .auto)
        XCTAssertEqual(decoded.innerZoneAlignment, .trailing)
    }

    func testFlashcardLayoutSettingsPersistThroughDeckSettingsBucket() throws {
        let context = try TestModelContainerFactory.makeContext()
        let deck = DeckModel(title: "Settings", colorHex: "#FFFFFF")
        context.insert(deck)
        try context.save()

        let settings = DeckPlayModeSettingsStore.resolve(for: deck, in: context)
        var flashcardSettings = settings.flashcardSettings
        flashcardSettings.contentAlignment = .center
        flashcardSettings.zoneGroupAlignment = .center
        flashcardSettings.innerZoneAlignment = .trailing
        flashcardSettings.textSize = .normal
        flashcardSettings.usesAppTextSize = false
        settings.flashcardSettings = flashcardSettings
        try context.save()

        let resolvedAgain = DeckPlayModeSettingsStore.resolve(for: deck, in: context)
        XCTAssertEqual(resolvedAgain.flashcardSettings.contentAlignment, .center)
        XCTAssertEqual(resolvedAgain.flashcardSettings.zoneGroupAlignment, .center)
        XCTAssertEqual(resolvedAgain.flashcardSettings.innerZoneAlignment, .trailing)
        XCTAssertEqual(resolvedAgain.flashcardSettings.textSize, .normal)
        XCTAssertFalse(resolvedAgain.flashcardSettings.usesAppTextSize)
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
