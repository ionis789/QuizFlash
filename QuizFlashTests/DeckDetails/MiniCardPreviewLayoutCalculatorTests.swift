//
//  MiniCardPreviewLayoutCalculatorTests.swift
//  QuizFlashTests
//
//  Covers pure deck-grid preview centering math.
//

import XCTest
@testable import QuizFlash

final class MiniCardPreviewLayoutCalculatorTests: XCTestCase {
    func testAvailableTextWidthRespectsPaddingAndClampsToMinimum() {
        let calculator = MiniCardPreviewLayoutCalculator(
            containerSize: CGSize(width: 120, height: 180),
            contentPadding: 16
        )
        let narrowCalculator = MiniCardPreviewLayoutCalculator(
            containerSize: CGSize(width: 20, height: 180),
            contentPadding: 16
        )

        XCTAssertEqual(calculator.availableTextWidth, 88, accuracy: 0.001)
        XCTAssertEqual(narrowCalculator.availableTextWidth, 1, accuracy: 0.001)
    }

    func testResolvedTextBlockSizePrefersRenderedMeasurementAndClampsWidth() {
        let calculator = MiniCardPreviewLayoutCalculator(
            containerSize: CGSize(width: 120, height: 180),
            contentPadding: 16
        )

        let resolved = calculator.resolvedTextBlockSize(
            renderedTextSize: CGSize(width: 140, height: 52),
            estimatedTextSize: CGSize(width: 70, height: 30)
        )

        XCTAssertEqual(resolved.width, 88, accuracy: 0.001)
        XCTAssertEqual(resolved.height, 52, accuracy: 0.001)
    }

    func testResolvedTextBlockSizeFallsBackToEstimatedMeasurement() {
        let calculator = MiniCardPreviewLayoutCalculator(
            containerSize: CGSize(width: 150, height: 180),
            contentPadding: 20
        )

        let resolved = calculator.resolvedTextBlockSize(
            renderedTextSize: .zero,
            estimatedTextSize: CGSize(width: 95, height: 44)
        )

        XCTAssertEqual(resolved.width, 95, accuracy: 0.001)
        XCTAssertEqual(resolved.height, 44, accuracy: 0.001)
    }

    func testCenteredInsetsClampWhenSpaceIsTight() {
        let roomyCalculator = MiniCardPreviewLayoutCalculator(
            containerSize: CGSize(width: 180, height: 220),
            contentPadding: 16
        )
        let tightCalculator = MiniCardPreviewLayoutCalculator(
            containerSize: CGSize(width: 120, height: 72),
            contentPadding: 16
        )

        XCTAssertEqual(
            roomyCalculator.centeredTextLeadingInset(textWidth: 60),
            44,
            accuracy: 0.001
        )
        XCTAssertEqual(
            roomyCalculator.centeredTextTopInset(textHeight: 40),
            74,
            accuracy: 0.001
        )
        XCTAssertEqual(
            tightCalculator.centeredTextTopInset(textHeight: 40),
            0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            tightCalculator.centeredTextLeadingInset(textWidth: 140),
            0,
            accuracy: 0.001
        )
    }
}
