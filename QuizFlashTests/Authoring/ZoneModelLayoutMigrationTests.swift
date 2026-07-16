//
//  ZoneModelLayoutMigrationTests.swift
//  QuizFlashTests
//

import XCTest
@testable import QuizFlash

final class ZoneModelLayoutMigrationTests: XCTestCase {
    func testWhitespaceOnlyTextZoneCountsAsAuthorContent() {
        XCTAssertTrue(ZoneModel.text("   \n  ").hasContent)
        XCTAssertFalse(ZoneModel.text("").hasContent)
    }

    func testLegacyLeadingAlignmentDecodesWithAutoBlockLayout() throws {
        let zone = try decodeLegacyZone(textAlignment: "leading")

        XCTAssertEqual(zone.sizeMode, .auto)
        XCTAssertEqual(zone.blockAlignment, .auto)
        XCTAssertEqual(zone.verticalAlignment, .auto)
    }

    func testLegacyCenteredAlignmentMigratesToFillWidthBlockLayout() throws {
        let zone = try decodeLegacyZone(textAlignment: "center")

        XCTAssertEqual(zone.sizeMode, .fillWidth)
        XCTAssertEqual(zone.blockAlignment, .leading)
        XCTAssertEqual(zone.verticalAlignment, .auto)
    }

    func testExplicitZoneLayoutFieldsDecodeWithoutMigration() throws {
        let payload = """
        {
          "contentType": "text",
          "text": "Fixed block",
          "textAlignment": "trailing",
          "sizeMode": "fixed",
          "blockAlignment": "trailing",
          "verticalAlignment": "top",
          "fixedWidth": 184,
          "fixedHeight": 72
        }
        """.data(using: .utf8)!

        let zone = try JSONDecoder().decode(ZoneModel.self, from: payload)

        XCTAssertEqual(zone.sizeMode, .fixed)
        XCTAssertEqual(zone.blockAlignment, .trailing)
        XCTAssertEqual(zone.verticalAlignment, .top)
        XCTAssertEqual(zone.fixedWidth, 184)
        XCTAssertEqual(zone.fixedHeight, 72)
    }

    func testAutoVerticalAlignmentResolvesAgainstFallback() {
        XCTAssertEqual(ZoneVerticalAlignment.auto.resolved(fallback: .top), .top)
        XCTAssertEqual(ZoneVerticalAlignment.auto.resolved(fallback: .auto), .center)
        XCTAssertEqual(ZoneVerticalAlignment.bottom.resolved(fallback: .top), .bottom)
    }

    func testRootAuthoringMutationsPreserveVerticalAlignment() {
        var root = ZoneModel.text("Question")
        root.verticalAlignment = .top
        let content = ZoneCardContent(rootZone: root)

        content.addZone(relativeTo: .root, direction: .down)
        XCTAssertEqual(content.rootZone.verticalAlignment, .top)

        content.deleteZone(at: .root)
        XCTAssertEqual(content.rootZone.verticalAlignment, .top)
    }

    func testAuthoringInitializationNormalizesHorizontalContainersToVertical() {
        let root = ZoneModel.container(
            direction: .horizontal,
            children: [
                ZoneModel.text("Left"),
                ZoneModel.text("Right")
            ]
        )

        let content = ZoneCardContent(rootZone: root)

        XCTAssertEqual(content.rootZone.direction, .vertical)
        XCTAssertEqual(content.rootZone.children?.map(\.text), ["Left", "Right"])
    }

    func testAuthoringInsertionUsesVerticalOrder() {
        let content = ZoneCardContent(rootZone: ZoneModel.text("Root"))

        _ = content.addTextZone(relativeTo: .root, direction: .down)

        XCTAssertEqual(content.rootZone.direction, .vertical)
        XCTAssertEqual(content.rootZone.children?.first?.text, "Root")
        XCTAssertEqual(content.rootZone.children?.last?.contentType, .empty)
    }

    func testFixedTextZoneHeightExpandsWhenContentIsTaller() {
        var zone = ZoneModel.text("Tall content")
        zone.sizeMode = .fixed
        zone.fixedWidth = 160
        zone.fixedHeight = 40

        let layout = ZoneContentLayoutEngine.leafLayout(
            for: zone,
            spec: ZoneContentLayoutSpec(availableWidth: 300, fontScale: 1),
            measuredContentSize: CGSize(width: 150, height: 128)
        )

        XCTAssertEqual(layout.blockSize.height, 152)
    }

    func testFixedZoneHeightRemainsMinimumWhenContentIsShorter() {
        var zone = ZoneModel.text("Short content")
        zone.sizeMode = .fixed
        zone.fixedWidth = 160
        zone.fixedHeight = 96

        let layout = ZoneContentLayoutEngine.leafLayout(
            for: zone,
            spec: ZoneContentLayoutSpec(availableWidth: 300, fontScale: 1),
            measuredContentSize: CGSize(width: 150, height: 42)
        )

        XCTAssertEqual(layout.blockSize.height, 96)
    }

    func testAutoMathZoneUsesRenderedContentWidthFromWebView() {
        let zone = ZoneModel.text(#"$S' \cdot A_{\tilde{B},\tilde{B}'} = A_{B,B'} \cdot S$"#)

        let layout = ZoneContentLayoutEngine.leafLayout(
            for: zone,
            spec: ZoneContentLayoutSpec(availableWidth: 329, fontScale: 1),
            measuredContentSize: CGSize(width: 166, height: 113)
        )

        XCTAssertEqual(layout.blockSize.width, 190)
        XCTAssertEqual(layout.textWidthLimit, 166)
        XCTAssertEqual(layout.leadingInset, 70)
        XCTAssertTrue(layout.usesIntrinsicTextMeasurement)
    }

    func testAutoMathZoneConstrainsTextToInnerWidth() {
        let zone = ZoneModel.text(#"Cum se reprezintă un operator liniar $T: \mathbb{R}^n \to \mathbb{R}^m$ în bazele canonice?"#)

        let layout = ZoneContentLayoutEngine.leafLayout(
            for: zone,
            spec: ZoneContentLayoutSpec(availableWidth: 329, fontScale: 1),
            measuredContentSize: CGSize(width: 329, height: 140)
        )

        XCTAssertEqual(layout.blockSize.width, 329)
        XCTAssertEqual(layout.contentLayoutWidth, 329)
        XCTAssertEqual(layout.textHorizontalInsets, 24)
        XCTAssertEqual(layout.textWidthLimit, 305)
        XCTAssertTrue(layout.usesIntrinsicTextMeasurement)
    }

    func testAutoMathZoneShrinksToStableRenderedContentWidth() {
        let zone = ZoneModel.text("def(T − λ·1V) = dim(Ker(T − λ·1V))")

        let layout = ZoneContentLayoutEngine.leafLayout(
            for: zone,
            spec: ZoneContentLayoutSpec(availableWidth: 329, fontScale: 1),
            measuredContentSize: CGSize(width: 289, height: 107)
        )

        XCTAssertEqual(layout.blockSize.width, 313)
        XCTAssertEqual(layout.textWidthLimit, 289)
        XCTAssertTrue(layout.usesIntrinsicTextMeasurement)
    }

    func testAutoMathListItemUsesStableRenderedContentWidth() {
        let zone = ZoneModel.text(#"a) $T$ este injectivă;"#)

        let layout = ZoneContentLayoutEngine.leafLayout(
            for: zone,
            spec: ZoneContentLayoutSpec(availableWidth: 329, fontScale: 1),
            measuredContentSize: CGSize(width: 220, height: 70)
        )

        XCTAssertEqual(layout.blockSize.width, 244)
        XCTAssertEqual(layout.contentLayoutWidth, 244)
        XCTAssertEqual(layout.textWidthLimit, 220)
        XCTAssertEqual(layout.leadingInset, 43)
        XCTAssertTrue(layout.usesIntrinsicTextMeasurement)
    }

    func testLongMixedMathQuestionUsesRenderedContentWidth() {
        let zone = ZoneModel.text(#"Definiți condițiile pe care trebuie să le satisfacă o submulțime $f \subseteq X \times Y$ pentru a fi o funcție $f: X \to Y$."#)

        let layout = ZoneContentLayoutEngine.leafLayout(
            for: zone,
            spec: ZoneContentLayoutSpec(availableWidth: 329, fontScale: 1),
            measuredContentSize: CGSize(width: 236, height: 254)
        )

        XCTAssertEqual(layout.blockSize.width, 260)
        XCTAssertEqual(layout.contentLayoutWidth, 260)
        XCTAssertEqual(layout.textWidthLimit, 236)
        XCTAssertEqual(layout.leadingInset, 35)
        XCTAssertTrue(layout.usesIntrinsicTextMeasurement)
    }

    func testOversizedTextTraitsInvalidateWhenSameZoneChangesToCodeFence() {
        var zone = ZoneModel.text(String(repeating: "a", count: 40_000))
        let spec = ZoneContentLayoutSpec(availableWidth: 320, fontScale: 1)

        let plainLayout = ZoneContentLayoutEngine.leafLayout(
            for: zone,
            spec: spec,
            measuredContentSize: CGSize(width: 320, height: 100)
        )

        zone.text = "```" + String(repeating: "a", count: 39_997)
        let codeLayout = ZoneContentLayoutEngine.leafLayout(
            for: zone,
            spec: spec,
            measuredContentSize: CGSize(width: 320, height: 100)
        )

        XCTAssertTrue(plainLayout.usesIntrinsicTextMeasurement)
        XCTAssertFalse(codeLayout.usesIntrinsicTextMeasurement)
    }

    func testOversizedEstimateInvalidatesForSameLengthLineChanges() {
        var zone = ZoneModel.text(String(repeating: "a", count: 40_000))
        let singleLineSize = ZoneTextPerformancePolicy.estimatedPlainTextSize(
            text: zone.text,
            zone: zone,
            fontScale: 1,
            availableWidth: 320,
            horizontalInsets: 24,
            verticalPadding: 24
        )

        zone.text = String(repeating: "a\n", count: 20_000)
        let manyLinesSize = ZoneTextPerformancePolicy.estimatedPlainTextSize(
            text: zone.text,
            zone: zone,
            fontScale: 1,
            availableWidth: 320,
            horizontalInsets: 24,
            verticalPadding: 24
        )

        XCTAssertGreaterThan(manyLinesSize.height, singleLineSize.height)
    }

    func testShortMathListItemUsesRendererMeasuredWidth() {
        let zone = ZoneModel.text(#"b) $\operatorname{def}(T) = 0$;"#)

        let layout = ZoneContentLayoutEngine.leafLayout(
            for: zone,
            spec: ZoneContentLayoutSpec(availableWidth: 329, fontScale: 1),
            measuredContentSize: CGSize(width: 191, height: 70)
        )

        XCTAssertEqual(layout.blockSize.width, 215)
        XCTAssertEqual(layout.contentLayoutWidth, 215)
        XCTAssertEqual(layout.textWidthLimit, 191)
        XCTAssertEqual(layout.leadingInset, 57)
        XCTAssertTrue(layout.usesIntrinsicTextMeasurement)
    }

    private func decodeLegacyZone(textAlignment: String) throws -> ZoneModel {
        let payload = """
        {
          "contentType": "text",
          "text": "Legacy text",
          "textAlignment": "\(textAlignment)"
        }
        """.data(using: .utf8)!

        return try JSONDecoder().decode(ZoneModel.self, from: payload)
    }
}
