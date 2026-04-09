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
        buildFlavor == .development
    }

    var allowsDevelopmentRoutes: Bool {
        buildFlavor == .development
    }

    var showsInternalLabs: Bool {
        buildFlavor == .development
    }

    var showsVisualDebugOverlays: Bool {
        buildFlavor == .development
    }

    var enablesAITraceTooling: Bool {
        buildFlavor == .development
    }
}
