//
//  CustomContextMenuLayoutResolverTests.swift
//  QuizFlashTests
//
//  Covers pure placement decisions for the shared custom context menu.
//

import UIKit
import XCTest
@testable import QuizFlash

@MainActor
final class CustomContextMenuLayoutResolverTests: XCTestCase {
    private let windowBounds = CGRect(x: 0, y: 0, width: 390, height: 844)
    private let safeInsets = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)

    func testResolveLayoutAnchorsMenuBelowSourceWhenSpaceIsAvailable() {
        let layout = CustomContextMenuLayoutResolver.resolveLayout(
            sourceFrame: CGRect(x: 200, y: 100, width: 120, height: 80),
            measuredMenuSize: CGSize(width: 200, height: 180),
            config: CustomContextMenuConfig(),
            windowBounds: windowBounds,
            safeInsets: safeInsets
        )

        XCTAssertEqual(layout.mode, .anchoredBelowTrailing)
        XCTAssertEqual(layout.previewOffset.width, 0, accuracy: 0.001)
        XCTAssertEqual(layout.previewOffset.height, 0, accuracy: 0.001)
        XCTAssertEqual(layout.menuFrame.minX, 120, accuracy: 0.001)
        XCTAssertEqual(layout.menuFrame.minY, 196, accuracy: 0.001)
    }

    func testResolveLayoutPushesPreviewUpWhenBottomWouldOverflow() {
        var config = CustomContextMenuConfig()
        config.bottomReservedSpace = 60

        let layout = CustomContextMenuLayoutResolver.resolveLayout(
            sourceFrame: CGRect(x: 180, y: 650, width: 120, height: 80),
            measuredMenuSize: CGSize(width: 200, height: 180),
            config: config,
            windowBounds: windowBounds,
            safeInsets: safeInsets
        )

        XCTAssertEqual(layout.mode, .pushedUpToFitBelowTrailing)
        XCTAssertLessThan(layout.previewOffset.height, 0)
        XCTAssertLessThan(layout.menuFrame.maxY, windowBounds.maxY - safeInsets.bottom)
    }

    func testResolveLayoutPushesPreviewDownWhenSourceStartsAboveSafeArea() {
        let layout = CustomContextMenuLayoutResolver.resolveLayout(
            sourceFrame: CGRect(x: 40, y: 20, width: 120, height: 80),
            measuredMenuSize: CGSize(width: 180, height: 160),
            config: CustomContextMenuConfig(),
            windowBounds: windowBounds,
            safeInsets: safeInsets
        )

        XCTAssertEqual(layout.mode, .pushedDownToClearTopSafeArea)
        XCTAssertEqual(layout.previewOffset.height, 39, accuracy: 0.001)
        XCTAssertEqual(layout.menuFrame.minY, 155, accuracy: 0.001)
    }

    func testResolveLayoutFallsBackToDefaultMenuSizeWhenMeasurementIsZero() {
        let layout = CustomContextMenuLayoutResolver.resolveLayout(
            sourceFrame: CGRect(x: 140, y: 160, width: 120, height: 80),
            measuredMenuSize: .zero,
            config: CustomContextMenuConfig(),
            windowBounds: windowBounds,
            safeInsets: safeInsets
        )

        XCTAssertEqual(layout.menuFrame.width, 255, accuracy: 0.001)
        XCTAssertEqual(layout.menuFrame.height, 234, accuracy: 0.001)
    }
}
