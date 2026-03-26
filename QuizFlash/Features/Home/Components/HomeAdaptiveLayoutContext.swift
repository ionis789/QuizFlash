//
//  HomeAdaptiveLayoutContext.swift
//  QuizFlash
//
//  Home-specific adaptive layout decisions derived from the real container width.
//

import SwiftUI

// MARK: - Home Header Scaffold

/// Distinct top-shell scaffolds for Home.
///
/// Home currently uses a single calendar surface for every width. The enum
/// stays in place so existing layout helpers keep a stable API.
enum HomeHeaderScaffold: Equatable {
    case compact
    case regular
}

// MARK: - Home Layout Mode

/// Structural composition modes for Home derived from the available container width.
enum HomeLayoutMode: Equatable {
    case narrow
    case medium
    case wide

    var widthClass: ContainerWidthClass {
        switch self {
        case .narrow:
            return .narrow
        case .medium:
            return .medium
        case .wide:
            return .wide
        }
    }

    var usesRegularMetrics: Bool {
        self != .narrow
    }

    var usesWideMetrics: Bool {
        self == .wide
    }

    var screenEdgeInset: CGFloat {
        switch self {
        case .narrow, .medium:
            return UIConstants.Spacing.large
        case .wide:
            return UIConstants.Spacing.extraLarge
        }
    }

    var dashboardHorizontalInset: CGFloat {
        switch self {
        case .narrow:
            return UIConstants.Spacing.small
        case .medium:
            return UIConstants.Spacing.standard
        case .wide:
            return UIConstants.Spacing.huge
        }
    }

    var quickStripVisibleLimit: Int {
        self == .wide ? 5 : 4
    }

    var quickStripChipWidth: CGFloat {
        switch self {
        case .narrow:
            return 176
        case .medium:
            return 196
        case .wide:
            return 212
        }
    }

    var quickStripPromptWidth: CGFloat {
        switch self {
        case .narrow:
            return 260
        case .medium:
            return 288
        case .wide:
            return 320
        }
    }

    var recentDeckCardWidth: CGFloat {
        switch self {
        case .narrow:
            return 260
        case .medium:
            return 296
        case .wide:
            return 320
        }
    }

    var recentDeckIconSize: CGFloat {
        switch self {
        case .narrow:
            return 60
        case .medium:
            return 64
        case .wide:
            return 68
        }
    }
}

// MARK: - Home Adaptive Layout Context

/// The single source of truth for Home composition and width-driven layout decisions.
struct HomeAdaptiveLayoutContext: Equatable {
    static let widthThresholds = AdaptiveLayoutWidthThresholds(
        medium: 430,
        wide: 860
    )
    static let minimumRegularCalendarWidth: CGFloat = 500
    static let minimumRegularCompanionWidth: CGFloat = 200
    static let minimumRegularHeaderSpacing: CGFloat = 16
    static let dashboardMaxContentWidth: CGFloat = 1180
    static let multiColumnDashboardThreshold: CGFloat = 900
    static let singleFolderColumnThreshold: CGFloat = 560

    let containerWidth: CGFloat
    let headerScaffold: HomeHeaderScaffold
    let calendarContext: AdaptiveLayoutContext
    let dashboardContext: AdaptiveLayoutContext
    let mode: HomeLayoutMode

    init(containerWidth: CGFloat) {
        self.containerWidth = containerWidth

        let modeContext = AdaptiveLayoutContext(
            containerWidth: containerWidth,
            horizontalInset: UIConstants.Spacing.large,
            thresholds: Self.widthThresholds
        )
        let mode = HomeLayoutMode(widthClass: modeContext.widthClass)
        self.mode = mode

        calendarContext = AdaptiveLayoutContext(
            containerWidth: containerWidth,
            horizontalInset: mode.screenEdgeInset,
            thresholds: Self.widthThresholds
        )
        headerScaffold = .compact
        dashboardContext = AdaptiveLayoutContext(
            containerWidth: containerWidth,
            horizontalInset: mode.dashboardHorizontalInset,
            thresholds: Self.widthThresholds,
            maxContentWidth: mode == .wide ? Self.dashboardMaxContentWidth : nil
        )
    }

    var usesRegularMetrics: Bool {
        mode.usesRegularMetrics
    }

    var usesWideMetrics: Bool {
        mode.usesWideMetrics
    }

    var usesDashboardColumns: Bool {
        dashboardContext.contentWidth >= Self.multiColumnDashboardThreshold
    }

    var folderColumnCount: Int {
        if dashboardContext.contentWidth < Self.singleFolderColumnThreshold {
            return 1
        }
        if mode == .wide && dashboardContext.contentWidth >= 1180 {
            return 3
        }
        return 2
    }
}

private extension HomeLayoutMode {
    init(widthClass: ContainerWidthClass) {
        switch widthClass {
        case .narrow:
            self = .narrow
        case .medium:
            self = .medium
        case .wide:
            self = .wide
        }
    }
}
