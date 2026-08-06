//
//  ZoneEditorInitialBlockWidthResolverTests.swift
//  QuizFlashTests
//
//  Covers the first-pass width used before editor measurements arrive.
//

import XCTest
@testable import QuizFlash

final class ZoneEditorInitialBlockWidthResolverTests: XCTestCase {
    func testAutomaticNestedLeafAlignmentKeepsSideGapsSymmetric() {
        let alignment = ZoneContentLayoutEngine.resolvedLeafBlockAlignment(
            for: .auto,
            alignToGroupLeading: false,
            automaticAlignment: .center
        )
        let leadingInset = ZoneContentLayoutEngine.blockLeadingInset(
            for: alignment,
            blockWidth: 348,
            availableWidth: 366
        )

        XCTAssertEqual(alignment, .center)
        XCTAssertEqual(leadingInset, 9)
        XCTAssertEqual(366 - leadingInset - 348, leadingInset)
    }

    func testGroupLeadingOverrideStillAlignsLeafToLeadingEdge() {
        let alignment = ZoneContentLayoutEngine.resolvedLeafBlockAlignment(
            for: .auto,
            alignToGroupLeading: true,
            automaticAlignment: .trailing
        )

        XCTAssertEqual(alignment, .leading)
    }

    func testEditorAutomaticAlignmentUsesConfiguredDefault() {
        let alignment = ZoneContentLayoutEngine.resolvedEditorLeafBlockAlignment(
            for: .auto,
            defaultAlignment: .leading
        )

        XCTAssertEqual(alignment, .leading)
    }

    func testEditorAutomaticAlignmentSupportsTrailingDefault() {
        let alignment = ZoneContentLayoutEngine.resolvedEditorLeafBlockAlignment(
            for: .auto,
            defaultAlignment: .trailing
        )

        XCTAssertEqual(alignment, .trailing)
    }

    func testEditorAlignmentMenuPreservesExplicitAlignment() {
        let alignment = ZoneContentLayoutEngine.resolvedEditorLeafBlockAlignment(
            for: .trailing,
            defaultAlignment: .leading
        )

        XCTAssertEqual(alignment, .trailing)
    }

    func testAutomaticAlignmentFallsBackToLeadingWhenBothLevelsInherit() {
        XCTAssertEqual(
            ZoneBlockAlignment.auto.resolved(fallback: .auto),
            .leading
        )
    }

    func testExplicitCardAlignmentOverridesDeckDefault() {
        XCTAssertEqual(
            ZoneBlockAlignment.center.resolved(fallback: .trailing),
            .center
        )
    }

    func testSwiftUIIntrinsicWidthProducesSymmetricSideGaps() {
        let layout = ZoneContentLayoutEngine.leafLayout(
            for: ZoneModel.text("Direct access to database features (meta-data)."),
            spec: ZoneContentLayoutSpec(availableWidth: 365, fontScale: 1),
            measuredContentSize: CGSize(width: 353, height: 43)
        )

        XCTAssertEqual(layout.blockSize.width, 353)
        XCTAssertEqual(layout.leadingInset, 6)
        XCTAssertEqual(365 - layout.leadingInset - layout.blockSize.width, 6)
    }

    func testCenteredLeafKeepsOddRemainderSymmetric() {
        let layout = ZoneContentLayoutEngine.leafLayout(
            for: ZoneModel.text("Fine-grained control over SQL and high performance."),
            spec: ZoneContentLayoutSpec(availableWidth: 365, fontScale: 1),
            measuredContentSize: CGSize(width: 314, height: 68)
        )

        XCTAssertEqual(layout.blockSize.width, 314)
        XCTAssertEqual(layout.leadingInset, 25.5)
        XCTAssertEqual(365 - layout.leadingInset - layout.blockSize.width, layout.leadingInset)
    }

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

    func testPlainTextVerticalGroupDoesNotCollapseAfterWrappedMeasurement() {
        let children = [
            ZoneModel.text("Problema satisfiabilității pentru logica propozițională"),
            ZoneModel.text("Are aplicații practice în verificarea programelor")
        ]

        let resolved = ZoneContentWidthStabilityPolicy.resolvedVerticalGroupWidth(
            estimatedWidth: 345,
            measuredWidth: 234,
            children: children,
            availableWidth: 366
        )

        XCTAssertEqual(resolved, 345)
    }

    func testRichTextVerticalGroupKeepsAuthoritativeMeasuredWidth() {
        let children = [
            ZoneModel.text(#"Relația $\models$ este definită astfel"#),
            ZoneModel.text(#"Atribuirea $\tau$ este model al formulei $\varphi$"#)
        ]

        let resolved = ZoneContentWidthStabilityPolicy.resolvedVerticalGroupWidth(
            estimatedWidth: 357,
            measuredWidth: 341,
            children: children,
            availableWidth: 366
        )

        XCTAssertEqual(resolved, 341)
    }

    func testPlainTextBlockUsesWidestRenderedLineWithoutChangingWrappingWidth() {
        let availableWidth: CGFloat = 366
        let horizontalInsets: CGFloat = 24
        let cases: [(estimated: CGFloat, renderedLine: CGFloat, expectedBlock: CGFloat)] = [
            (355, 317, 341),
            (363, 331, 355),
            (348, 321, 345),
            (365, 329, 353)
        ]

        for item in cases {
            let wrappingWidth = ZoneContentWidthStabilityPolicy.stablePlainTextWrappingWidth(
                estimatedBlockWidth: item.estimated,
                horizontalInsets: horizontalInsets
            )
            let blockWidth = ZoneContentWidthStabilityPolicy.resolvedPlainTextBlockWidth(
                renderedTextWidth: item.renderedLine,
                horizontalInsets: horizontalInsets,
                availableWidth: availableWidth
            )
            let wrappingWidthAfterMeasurement = ZoneContentWidthStabilityPolicy.stablePlainTextWrappingWidth(
                estimatedBlockWidth: item.estimated,
                horizontalInsets: horizontalInsets
            )

            XCTAssertEqual(blockWidth, item.expectedBlock)
            XCTAssertEqual(wrappingWidthAfterMeasurement, wrappingWidth)
        }
    }

    func testPlainTextLineWidthIgnoresInvisibleTrailingWhitespace() {
        let fontScale = CGFloat(FlashcardTextSize(step: 3).playModeScale)
        let plainZone = ZoneModel.text("formula este adevărată și cel")
        let trailingSpaceZone = ZoneModel.text("formula este adevărată și cel ")

        let plainWidth = ZoneContentEstimator.debugLineWidths(
            for: plainZone,
            fontScale: fontScale,
            availableWidth: 1_000
        ).first
        let trailingSpaceWidth = ZoneContentEstimator.debugLineWidths(
            for: trailingSpaceZone,
            fontScale: fontScale,
            availableWidth: 1_000
        ).first

        XCTAssertEqual(trailingSpaceWidth, plainWidth)
    }

    func testWordFitsAtWrapBoundaryWithoutItsTrailingSeparator() {
        let fontScale = CGFloat(FlashcardTextSize(step: 3).playModeScale)
        let prefixZone = ZoneModel.text("formula este")
        let prefixWidth = ZoneContentEstimator.debugLineWidths(
            for: prefixZone,
            fontScale: fontScale,
            availableWidth: 1_000
        ).first ?? 1
        let wrappedZone = ZoneModel.text("formula este adevărată")
        let wrappedWidths = ZoneContentEstimator.debugLineWidths(
            for: wrappedZone,
            fontScale: fontScale,
            availableWidth: prefixWidth
        )

        XCTAssertEqual(wrappedWidths.count, 2)
        XCTAssertEqual(wrappedWidths.first, prefixWidth)
    }

    func testValidIntrinsicWidthSurvivesContainerWidthChanges() {
        XCTAssertFalse(
            ZoneContentWidthStabilityPolicy.shouldResetDegenerateMeasurement(
                measuredWidth: 258,
                availableWidth: 366
            )
        )
        XCTAssertFalse(
            ZoneContentWidthStabilityPolicy.shouldResetDegenerateMeasurement(
                measuredWidth: 284,
                availableWidth: 353
            )
        )
    }

    func testBootstrapWidthIsResetWhenRealContainerArrives() {
        XCTAssertTrue(
            ZoneContentWidthStabilityPolicy.shouldResetDegenerateMeasurement(
                measuredWidth: 1,
                availableWidth: 366
            )
        )
        XCTAssertFalse(
            ZoneContentWidthStabilityPolicy.shouldResetDegenerateMeasurement(
                measuredWidth: 0,
                availableWidth: 366
            )
        )
    }
}
