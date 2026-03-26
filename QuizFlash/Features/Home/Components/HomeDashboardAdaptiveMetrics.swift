//
//  HomeDashboardAdaptiveMetrics.swift
//  QuizFlash
//
//  Width-derived dashboard composition rules for the Home screen.
//

import CoreGraphics

// MARK: - Home Dashboard Adaptive Metrics

/// Section-level adaptive rules for the Home dashboard.
///
/// This keeps structural composition decisions near the dashboard container
/// instead of pushing screen-level layout mode through every child card.
struct HomeDashboardAdaptiveMetrics: Equatable {
    let contentWidth: CGFloat

    static let compactSectionThreshold: CGFloat = 620
    static let regularMetricsThreshold: CGFloat = 700
    static let dashboardColumnsThreshold: CGFloat = 920
    static let recentDeckGridThreshold: CGFloat = 680
    static let recentDeckThreeColumnThreshold: CGFloat = 1120
    static let foldersThreeColumnThreshold: CGFloat = 1040
    static let quickStripExpandedThreshold: CGFloat = 440

    var isNarrowSection: Bool {
        contentWidth < Self.compactSectionThreshold
    }

    var usesRegularMetrics: Bool {
        contentWidth >= Self.regularMetricsThreshold
    }

    var usesDashboardColumns: Bool {
        contentWidth >= Self.dashboardColumnsThreshold
    }

    var usesRecentDeckGrid: Bool {
        contentWidth >= Self.recentDeckGridThreshold
    }

    var recentDeckColumnCount: Int {
        contentWidth >= Self.recentDeckThreeColumnThreshold ? 3 : 2
    }

    var folderColumnCount: Int {
        if contentWidth >= Self.foldersThreeColumnThreshold {
            return 3
        }
        if !isNarrowSection {
            return 2
        }
        return 1
    }

    var quickStripVisibleLimit: Int {
        contentWidth >= Self.quickStripExpandedThreshold ? 4 : 3
    }

    var quickStripChipWidth: CGFloat {
        min(max(contentWidth * 0.62, 220), 276)
    }

    var quickStripPromptWidth: CGFloat {
        min(max(contentWidth * 0.82, 252), 330)
    }

    var recentDeckCarouselCardWidth: CGFloat {
        min(max(contentWidth * 0.78, 260), 320)
    }
}
