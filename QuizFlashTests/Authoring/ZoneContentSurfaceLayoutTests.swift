//
//  ZoneContentSurfaceLayoutTests.swift
//  QuizFlashTests
//

import XCTest
@testable import QuizFlash

final class ZoneContentSurfaceLayoutTests: XCTestCase {
    func testIntrinsicContextUsesHostWidthWithoutVerticalScroll() {
        let context = ZoneContentSurfaceLayoutContext.intrinsic(
            width: 366,
            horizontalPadding: 12
        )

        let result = ZoneContentSurfaceLayoutResolver.resolve(
            context: context,
            estimatedContentSize: CGSize(width: 250, height: 120),
            measuredContentSize: CGSize(width: 250, height: 120)
        )

        XCTAssertEqual(result.availableContentWidth, 342)
        XCTAssertNil(result.viewportLayout)
        XCTAssertFalse(result.isVerticalScrollEnabled)
    }

    func testAutomaticViewportScrollStaysDisabledWhenContentFits() {
        let context = ZoneContentSurfaceLayoutContext.viewport(
            size: CGSize(width: 374, height: 617),
            horizontalPadding: 4,
            verticalPadding: 4,
            verticalAlignment: .center
        )

        let result = ZoneContentSurfaceLayoutResolver.resolve(
            context: context,
            estimatedContentSize: CGSize(width: 314, height: 120),
            measuredContentSize: CGSize(width: 314, height: 120)
        )

        XCTAssertEqual(result.availableContentWidth, 366)
        XCTAssertEqual(result.viewportLayout?.contentBodyHeight, 120)
        XCTAssertEqual(result.viewportLayout?.contentTopInset, 244.5)
        XCTAssertFalse(result.isVerticalScrollEnabled)
    }

    func testAutomaticViewportScrollEnablesOnlyForOverflow() {
        let context = ZoneContentSurfaceLayoutContext.viewport(
            size: CGSize(width: 374, height: 617),
            horizontalPadding: 4,
            verticalPadding: 4,
            verticalAlignment: .center
        )

        let result = ZoneContentSurfaceLayoutResolver.resolve(
            context: context,
            estimatedContentSize: CGSize(width: 366, height: 720),
            measuredContentSize: CGSize(width: 366, height: 720)
        )

        XCTAssertFalse(result.viewportLayout?.contentFitsVertically ?? true)
        XCTAssertTrue(result.isVerticalScrollEnabled)
    }

    func testDisabledViewportPolicyNeverEnablesScroll() {
        let context = ZoneContentSurfaceLayoutContext.viewport(
            size: CGSize(width: 320, height: 200),
            horizontalPadding: 8,
            verticalPadding: 8,
            verticalAlignment: .top,
            verticalScrollPolicy: .disabled
        )

        let result = ZoneContentSurfaceLayoutResolver.resolve(
            context: context,
            estimatedContentSize: CGSize(width: 304, height: 800),
            measuredContentSize: CGSize(width: 304, height: 800)
        )

        XCTAssertFalse(result.isVerticalScrollEnabled)
    }

    func testImplausiblySmallMeasurementFallsBackToEstimate() {
        let estimate = CGSize(width: 300, height: 120)

        let applied = ZoneContentSurface.appliedMeasurement(
            CGSize(width: 300, height: 20),
            estimatedContentSize: estimate
        )

        XCTAssertEqual(applied, .zero)

        let context = ZoneContentSurfaceLayoutContext.viewport(
            size: CGSize(width: 320, height: 500),
            horizontalPadding: 0,
            verticalPadding: 0,
            verticalAlignment: .center
        )
        let result = ZoneContentSurfaceLayoutResolver.resolve(
            context: context,
            estimatedContentSize: estimate,
            measuredContentSize: applied
        )

        XCTAssertEqual(result.viewportLayout?.contentBodyHeight, 120)
    }

    func testInvalidHostMetricsAreSanitized() {
        let context = ZoneContentSurfaceLayoutContext(
            containerWidth: .infinity,
            viewportHeight: -.infinity,
            horizontalPadding: -20,
            verticalPadding: .nan,
            verticalAlignment: .center,
            verticalScrollPolicy: .automatic,
            scrollResetToken: 0
        )

        XCTAssertEqual(context.sanitizedContainerWidth, 1)
        XCTAssertNil(context.sanitizedViewportHeight)
        XCTAssertEqual(context.sanitizedHorizontalPadding, 0)
        XCTAssertEqual(context.sanitizedVerticalPadding, 0)
        XCTAssertEqual(context.availableContentWidth, 1)
    }
}
