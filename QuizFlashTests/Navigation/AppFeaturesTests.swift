//
//  AppFeaturesTests.swift
//  QuizFlashTests
//
//  Covers release gating for development-only app features.
//

import SwiftUI
import XCTest
@testable import QuizFlash

final class AppFeaturesTests: XCTestCase {
    func testDevelopmentBuildEnablesDevelopmentFeatureSet() {
        let features = AppFeatures(buildFlavor: .development)

        XCTAssertTrue(features.showsVisualDebugOverlays)
        XCTAssertTrue(features.enablesAITraceTooling)
    }

    func testProductionBuildDisablesDevelopmentFeatureSet() {
        let features = AppFeatures(buildFlavor: .production)

        XCTAssertFalse(features.showsVisualDebugOverlays)
        XCTAssertFalse(features.enablesAITraceTooling)
    }

    func testVisibleTabsContainOnlyUserFacingDestinations() {
        XCTAssertEqual(
            AppTabBar.visibleTabs,
            [.home, .library, .create, .settings]
        )
        XCTAssertEqual(
            AppTabBar.allCases,
            [.home, .library, .create, .settings]
        )
    }
}
