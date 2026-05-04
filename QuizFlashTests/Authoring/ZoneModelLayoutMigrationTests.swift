//
//  ZoneModelLayoutMigrationTests.swift
//  QuizFlashTests
//

import XCTest
@testable import QuizFlash

final class ZoneModelLayoutMigrationTests: XCTestCase {
    func testLegacyLeadingAlignmentMigratesToAutoBlockLayout() throws {
        let zone = try decodeLegacyZone(textAlignment: "leading")

        XCTAssertEqual(zone.sizeMode, .auto)
        XCTAssertEqual(zone.blockAlignment, .auto)
        XCTAssertEqual(zone.verticalAlignment, .auto)
        XCTAssertEqual(zone.textAlignment, .leading)
    }

    func testLegacyCenteredAlignmentMigratesToFillWidthTextAlignment() throws {
        let zone = try decodeLegacyZone(textAlignment: "center")

        XCTAssertEqual(zone.sizeMode, .fillWidth)
        XCTAssertEqual(zone.blockAlignment, .leading)
        XCTAssertEqual(zone.verticalAlignment, .auto)
        XCTAssertEqual(zone.textAlignment, .center)
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
        XCTAssertEqual(zone.textAlignment, .trailing)
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

        content.duplicateZone(at: .root)
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

        let layout = CardZoneLayoutEngine.leafLayout(
            for: zone,
            spec: CardZoneLayoutSpec(availableWidth: 300, fontScale: 1),
            measuredContentSize: CGSize(width: 150, height: 128)
        )

        XCTAssertEqual(layout.blockSize.height, 128)
    }

    func testFixedZoneHeightRemainsMinimumWhenContentIsShorter() {
        var zone = ZoneModel.text("Short content")
        zone.sizeMode = .fixed
        zone.fixedWidth = 160
        zone.fixedHeight = 96

        let layout = CardZoneLayoutEngine.leafLayout(
            for: zone,
            spec: CardZoneLayoutSpec(availableWidth: 300, fontScale: 1),
            measuredContentSize: CGSize(width: 150, height: 42)
        )

        XCTAssertEqual(layout.blockSize.height, 96)
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
