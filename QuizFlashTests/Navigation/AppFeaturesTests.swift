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

        XCTAssertFalse(features.showsLabsTab)
        XCTAssertTrue(features.allowsDevelopmentRoutes)
        XCTAssertTrue(features.showsInternalLabs)
        XCTAssertTrue(features.showsVisualDebugOverlays)
        XCTAssertTrue(features.enablesAITraceTooling)
    }

    func testProductionBuildDisablesDevelopmentFeatureSet() {
        let features = AppFeatures(buildFlavor: .production)

        XCTAssertFalse(features.showsLabsTab)
        XCTAssertFalse(features.allowsDevelopmentRoutes)
        XCTAssertFalse(features.showsInternalLabs)
        XCTAssertFalse(features.showsVisualDebugOverlays)
        XCTAssertFalse(features.enablesAITraceTooling)
    }

    func testVisibleTabsExcludeLabsInProduction() {
        let features = AppFeatures(buildFlavor: .production)

        XCTAssertEqual(
            AppTabBar.visibleTabs(features: features),
            [.home, .library, .create, .settings]
        )
    }

    func testVisibleTabsExcludeLabsInDevelopment() {
        let features = AppFeatures(buildFlavor: .development)

        XCTAssertEqual(
            AppTabBar.visibleTabs(features: features),
            [.home, .library, .create, .settings]
        )
    }

    func testFeatureLabRoutesFollowBuildGates() {
        let developmentFeatures = AppFeatures(buildFlavor: .development)
        let productionFeatures = AppFeatures(buildFlavor: .production)

        XCTAssertEqual(
            FeatureLabRoute.visibleRoutes(in: developmentFeatures),
            [
                .developmentSettings,
                .flashCardsPlayModeSimulation,
                .animatedObjectsLab,
                .sharedUICatalog,
                .contextMenu,
                .progressiveBlurHeaderLab
            ]
        )
        XCTAssertEqual(
            FeatureLabRoute.visibleRoutes(in: productionFeatures),
            []
        )
        XCTAssertFalse(
            FeatureLabRoute.developmentSettings.isAvailable(in: productionFeatures)
        )
    }

    func testSanitizeForFeaturesClearsLabsNavigationAndFallsBackToSettings() {
        let router = NavigationManager()
        router.activeTab = .labs
        router.append(FeatureLabRoute.contextMenu)

        XCTAssertEqual(router.labsPath.count, 1)

        router.sanitizeForFeatures(AppFeatures(buildFlavor: .production))

        XCTAssertEqual(router.activeTab, .settings)
        XCTAssertEqual(router.labsPath.count, 0)
    }
}
