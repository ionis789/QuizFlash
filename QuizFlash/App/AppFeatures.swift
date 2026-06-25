//
//  AppFeatures.swift
//  QuizFlash
//
//  Centralized feature gates derived from the active build flavor.
//

import Foundation

nonisolated struct AppFeatures: Sendable {
    let buildFlavor: AppBuildFlavor

    static let current = AppFeatures(buildFlavor: AppBuildConfiguration.current)

    init(buildFlavor: AppBuildFlavor) {
        self.buildFlavor = buildFlavor
    }

    var showsLabsTab: Bool {
        false
    }

    var allowsDevelopmentRoutes: Bool {
        true
    }

    var showsInternalLabs: Bool {
        true
    }

    var showsVisualDebugOverlays: Bool {
        true
    }

    var enablesAITraceTooling: Bool {
        true
    }
}
