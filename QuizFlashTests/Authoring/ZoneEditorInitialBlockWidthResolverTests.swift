//
//  ZoneEditorInitialBlockWidthResolverTests.swift
//  QuizFlashTests
//
//  Covers the first-pass width used before editor measurements arrive.
//

import XCTest
@testable import QuizFlash

final class ZoneEditorInitialBlockWidthResolverTests: XCTestCase {
    func testSimpleEditorTextGroupAlwaysUsesAvailableWidth() {
        let availableWidth: CGFloat = 369
        let fontScale = CGFloat(FlashcardTextSize(step: 0).playModeScale)
        let children = [
            ZoneModel.text("jnjnjnjknkjjnknkn"),
            ZoneModel.text("jnjnjknkjkjn"),
            ZoneModel.text("njnjnjjnjnj")
        ]
        var root = ZoneModel()
        root.children = children
        root.direction = .vertical

        let resolved = ZoneEditorInitialBlockWidthResolver.resolve(
            zone: root,
            fontScale: fontScale,
            availableWidth: availableWidth,
            usesFullWidthEditableText: true,
            minimumEmptyTextWidth: availableWidth
        )

        XCTAssertEqual(resolved, availableWidth)
    }

    func testRichRenderingKeepsIntrinsicTextWidth() {
        let availableWidth: CGFloat = 369
        let fontScale = CGFloat(FlashcardTextSize(step: 0).playModeScale)
        let zone = ZoneModel.text("jnjnjknkjkjn")

        let resolved = ZoneEditorInitialBlockWidthResolver.resolve(
            zone: zone,
            fontScale: fontScale,
            availableWidth: availableWidth,
            usesFullWidthEditableText: false,
            minimumEmptyTextWidth: 1
        )

        XCTAssertEqual(
            resolved,
            ZoneContentEstimator.estimatedBlockWidth(
                for: zone,
                fontScale: fontScale,
                availableWidth: availableWidth
            )
        )
        XCTAssertLessThan(resolved, availableWidth)
    }

    func testPlainTextIntrinsicWidthCoversMeasuredLineAndInsets() {
        let availableWidth: CGFloat = 369
        let fontScale = CGFloat(FlashcardTextSize(step: 0).playModeScale)
        let zone = ZoneModel.text("fdfsdsfdsfdsfdsfdsfsdfsfsd")
        let lineWidth = ZoneContentEstimator.debugLineWidths(
            for: zone,
            fontScale: fontScale,
            availableWidth: availableWidth - ZoneContentMetrics.textHorizontalPadding
        ).max() ?? 0

        let resolved = ZoneContentEstimator.estimatedBlockWidth(
            for: zone,
            fontScale: fontScale,
            availableWidth: availableWidth
        )

        XCTAssertGreaterThanOrEqual(
            resolved,
            ceil(lineWidth + ZoneContentMetrics.textHorizontalPadding)
        )
    }

    func testEmptyTextZoneUsesFullAvailableAuthoringWidth() {
        let resolved = ZoneEditorInitialBlockWidthResolver.resolve(
            zone: .text(),
            fontScale: 1,
            availableWidth: 369,
            usesFullWidthEditableText: true,
            minimumEmptyTextWidth: 369
        )

        XCTAssertEqual(resolved, 369)
    }
}
