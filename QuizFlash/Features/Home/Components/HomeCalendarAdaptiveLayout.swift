//
//  HomeCalendarAdaptiveLayout.swift
//  QuizFlash
//
//  Home-specific layout metrics for phone and iPad calendar variants.
//

import SwiftUI

// MARK: - Home Calendar Adaptive Layout

/// Width-aware calendar metrics reused by `HomeView` and `HomeCalendarSectionView`.
///
/// Home intentionally uses two layout families:
/// - `phone`: preserves the dense compact capsule geometry used on iPhone.
/// - `pad`: stretches across the available window width while still reserving
///   trailing space for the floating avatar in compact mode.
struct HomeCalendarAdaptiveLayout: Equatable {

    enum Kind: Equatable {
        case phone
        case pad
    }

    // MARK: - State

    struct State: Equatable {
        let topPadding: CGFloat
        let titleFontSize: CGFloat
        let titleHeight: CGFloat
        let titleBottomSpacing: CGFloat
        let weekdayFontSize: CGFloat
        let weekLabelHeight: CGFloat
        let rowHeight: CGFloat
        let dayColumnWidth: CGFloat
        let verticalPadding: CGFloat
        let horizontalPadding: CGFloat
        let cornerRadius: CGFloat
        let monthControlSize: CGFloat
        let monthControlSpacing: CGFloat
    }

    // MARK: - Stored Metrics

    let scaffold: HomeHeaderScaffold
    let mode: HomeLayoutMode
    let kind: Kind
    let safeAreaTop: CGFloat
    let monthRowCount: Int
    let outerHorizontalInset: CGFloat
    let availableContentWidth: CGFloat
    let avatarSize: CGFloat
    let trailingGap: CGFloat
    let trailingReservation: CGFloat
    let compactCapsuleWidth: CGFloat
    let compactCompanionWidth: CGFloat
    let compactColumnSpacing: CGFloat
    let expandedContentLeadingInset: CGFloat
    let expandedCalendarWidth: CGFloat
    let expandedCompanionWidth: CGFloat
    let expandedCompanionHeight: CGFloat
    let expandedColumnSpacing: CGFloat
    let expanded: State
    let collapsed: State
    let bottomPadding: CGFloat = 0

    static func availableContentWidth(for containerWidth: CGFloat) -> CGFloat {
        max(containerWidth - (UIConstants.Spacing.large * 2), 0)
    }

    static func usesPadLayout(containerWidth: CGFloat, isPadDevice: Bool) -> Bool {
        _ = isPadDevice
        return resolvedMode(containerWidth: containerWidth).usesRegularMetrics
    }

    static func resolvedKind(containerWidth: CGFloat, isPadDevice: Bool) -> Kind {
        _ = isPadDevice
        return resolvedMode(containerWidth: containerWidth).kind
    }

    static func resolvedMode(containerWidth: CGFloat) -> HomeLayoutMode {
        HomeAdaptiveLayoutContext(containerWidth: containerWidth).mode
    }

    static func resolvedScaffold(containerWidth: CGFloat) -> HomeHeaderScaffold {
        HomeAdaptiveLayoutContext(containerWidth: containerWidth).headerScaffold
    }

    var usesSplitTopHeader: Bool {
        scaffold == .regular
    }

    var showsInlineAvatar: Bool {
        false
    }

    var showsFloatingAvatar: Bool {
        false
    }

    // MARK: - Lifecycle

    init(
        containerWidth: CGFloat,
        safeAreaTop: CGFloat,
        monthRowCount: Int,
        mode: HomeLayoutMode,
        scaffold: HomeHeaderScaffold
    ) {
        self.scaffold = scaffold
        self.mode = mode
        let resolvedKind: Kind = scaffold == .regular ? .pad : mode.kind
        self.kind = resolvedKind
        self.safeAreaTop = safeAreaTop
        self.monthRowCount = monthRowCount

        let usesRegularMetrics = mode.usesRegularMetrics

        let horizontalInset = mode.screenEdgeInset
        outerHorizontalInset = horizontalInset
        availableContentWidth = max(containerWidth - (horizontalInset * 2), 0)

        let widthProgress = Self.normalizedProgress(
            value: availableContentWidth,
            lower: usesRegularMetrics ? 700 : 320,
            upper: usesRegularMetrics ? 1400 : 430
        )

        avatarSize = usesRegularMetrics
            ? UIConstants.Size.actionButton + 4
            : UIConstants.Size.actionButton
        trailingGap = 0
        trailingReservation = 0
        if scaffold == .regular {
            let headerBudget = max(availableContentWidth - trailingReservation, 0)
            let split = Self.resolveRegularHeaderSplit(
                availableContentWidth: availableContentWidth,
                headerBudget: headerBudget
            )
            expandedColumnSpacing = split.spacing
            expandedCalendarWidth = split.calendarWidth
            expandedCompanionWidth = split.companionWidth
        } else {
            expandedColumnSpacing = 0
            if resolvedKind == .pad {
                let targetShare: CGFloat = mode == .wide ? 0.68 : 0.72
                let minimumWidth = min(availableContentWidth, 500.0)
                expandedCalendarWidth = max(
                    HomeCalendarAdaptiveLayout
                        .rounded(availableContentWidth * targetShare),
                    minimumWidth
                )
            } else {
                expandedCalendarWidth = availableContentWidth
            }
            expandedCompanionWidth = 0
        }
        expandedContentLeadingInset = 0
        expandedCompanionHeight = scaffold == .regular
            ? max(188, min(Self.interpolate(from: 196, to: 232, progress: widthProgress), 232))
            : 0

        if usesRegularMetrics {
            compactColumnSpacing = 0
            compactCapsuleWidth = max(0, expandedCalendarWidth - trailingReservation)
            compactCompanionWidth = 0
        } else {
            compactCompanionWidth = 0
            compactColumnSpacing = 0
            compactCapsuleWidth = max(0, availableContentWidth - trailingReservation)
        }

        let collapsedHorizontalPadding = usesRegularMetrics
            ? max(UIConstants.Layout.homeCalendarCompactCapsuleHorizontalPadding, 16)
            : UIConstants.Layout.homeCalendarCompactCapsuleHorizontalPadding
        let expandedTopPadding = UIConstants.Layout.homeCalendarExpandedTopPadding
        let expandedTitleFontSize = usesRegularMetrics
            ? Self.rounded(Self.interpolate(from: 28, to: 34, progress: widthProgress))
            : Self.rounded(Self.interpolate(from: 22, to: 24, progress: widthProgress))
        let expandedTitleHeight = usesRegularMetrics
            ? Self.rounded(Self.interpolate(from: 64, to: 76, progress: widthProgress))
            : 52
        let expandedTitleBottomSpacing = usesRegularMetrics ? UIConstants.Spacing.medium : UIConstants.Spacing.small
        let expandedWeekdayFontSize = usesRegularMetrics
            ? Self.rounded(Self.interpolate(from: 12, to: 14, progress: widthProgress))
            : Self.rounded(Self.interpolate(from: 11, to: 12, progress: widthProgress))
        let expandedWeekLabelHeight = usesRegularMetrics
            ? Self.rounded(Self.interpolate(from: 22, to: 24, progress: widthProgress))
            : 18
        let expandedRowHeight = usesRegularMetrics
            ? Self.rounded(min(max((expandedCalendarWidth / 7) * 0.62, 50), 76))
            : Self.rounded(Self.interpolate(from: 40, to: 48, progress: widthProgress))

        let collapsedWeekdayFontSize: CGFloat = usesRegularMetrics ? 12 : 11
        let collapsedWeekLabelHeight: CGFloat = usesRegularMetrics ? 18 : 16
        let collapsedRowHeight = usesRegularMetrics
            ? Self.rounded(Self.interpolate(from: 34, to: 38, progress: widthProgress))
            : Self.rounded(Self.interpolate(from: 34, to: 38, progress: widthProgress))
        let collapsedVerticalPadding = UIConstants.Layout.homeCalendarCompactCapsuleVerticalPadding
        let collapsedCapsuleHeight = collapsedWeekLabelHeight + collapsedRowHeight + (collapsedVerticalPadding * 2)
        let collapsedTopPadding: CGFloat
        if scaffold == .compact {
            collapsedTopPadding = 0
        } else if usesRegularMetrics {
            collapsedTopPadding = max(
                safeAreaTop + expandedTopPadding + (expandedTitleHeight / 2) - safeAreaTop - (collapsedCapsuleHeight / 2),
                0
            )
        } else {
            collapsedTopPadding = 0
        }
        let collapsedGridWidth = max(0, compactCapsuleWidth - (collapsedHorizontalPadding * 2))

        expanded = State(
            topPadding: expandedTopPadding,
            titleFontSize: expandedTitleFontSize,
            titleHeight: expandedTitleHeight,
            titleBottomSpacing: expandedTitleBottomSpacing,
            weekdayFontSize: expandedWeekdayFontSize,
            weekLabelHeight: expandedWeekLabelHeight,
            rowHeight: expandedRowHeight,
            dayColumnWidth: max(28, expandedCalendarWidth / 7),
            verticalPadding: 0,
            horizontalPadding: 0,
            cornerRadius: 0,
            monthControlSize: usesRegularMetrics ? UIConstants.Size.actionButtonMedium : 30,
            monthControlSpacing: usesRegularMetrics ? UIConstants.Spacing.small : 2
        )

        collapsed = State(
            topPadding: collapsedTopPadding,
            titleFontSize: 0,
            titleHeight: 0,
            titleBottomSpacing: 0,
            weekdayFontSize: collapsedWeekdayFontSize,
            weekLabelHeight: collapsedWeekLabelHeight,
            rowHeight: collapsedRowHeight,
            dayColumnWidth: max(usesRegularMetrics ? 34 : 36, collapsedGridWidth / 7),
            verticalPadding: collapsedVerticalPadding,
            horizontalPadding: collapsedHorizontalPadding,
            cornerRadius: UIConstants.Radius.maximum,
            monthControlSize: 0,
            monthControlSpacing: 0
        )
    }

    // MARK: - Derived Metrics

    var headerColumnWidth: CGFloat {
        kind == .pad ? expandedCalendarWidth : availableContentWidth
    }

    var expandedGridWidth: CGFloat {
        expanded.dayColumnWidth * 7
    }

    var collapsedGridWidth: CGFloat {
        collapsed.dayColumnWidth * 7
    }

    var compactCapsuleHeight: CGFloat {
        collapsed.weekLabelHeight + collapsed.rowHeight + (collapsed.verticalPadding * 2)
    }

    var extendedHeight: CGFloat {
        safeAreaTop
            + expanded.topPadding
            + expanded.titleHeight
            + expanded.titleBottomSpacing
            + expanded.weekLabelHeight
            + (CGFloat(monthRowCount) * expanded.rowHeight)
            + bottomPadding
    }

    var compactHeight: CGFloat {
        safeAreaTop
            + collapsed.topPadding
            + compactCapsuleHeight
            + bottomPadding
    }

    var expandedContentHeight: CGFloat {
        expanded.titleHeight
            + expanded.titleBottomSpacing
            + expanded.weekLabelHeight
            + (CGFloat(monthRowCount) * expanded.rowHeight)
    }

    var compactAvailableHeaderWidth: CGFloat {
        max(0, availableContentWidth - trailingReservation)
    }

    var scrollDistance: CGFloat {
        max(extendedHeight - compactHeight, 1)
    }

    var expandedAvatarCenterY: CGFloat {
        safeAreaTop + expanded.topPadding + (expanded.titleHeight / 2)
    }

    var collapsedAvatarCenterY: CGFloat {
        safeAreaTop + collapsed.topPadding + (compactCapsuleHeight / 2)
    }

    var expandedAvatarTop: CGFloat {
        expandedAvatarCenterY - (avatarSize / 2)
    }

    var collapsedAvatarTop: CGFloat {
        collapsedAvatarCenterY - (avatarSize / 2)
    }

    // MARK: - Interpolation

    func state(for progress: CGFloat) -> State {
        let clampedProgress = Self.clamped(progress)

        return State(
            topPadding: Self.interpolate(from: expanded.topPadding, to: collapsed.topPadding, progress: clampedProgress),
            titleFontSize: Self.interpolate(from: expanded.titleFontSize, to: collapsed.titleFontSize, progress: clampedProgress),
            titleHeight: Self.interpolate(from: expanded.titleHeight, to: collapsed.titleHeight, progress: clampedProgress),
            titleBottomSpacing: Self.interpolate(from: expanded.titleBottomSpacing, to: collapsed.titleBottomSpacing, progress: clampedProgress),
            weekdayFontSize: Self.interpolate(from: expanded.weekdayFontSize, to: collapsed.weekdayFontSize, progress: clampedProgress),
            weekLabelHeight: Self.interpolate(from: expanded.weekLabelHeight, to: collapsed.weekLabelHeight, progress: clampedProgress),
            rowHeight: Self.interpolate(from: expanded.rowHeight, to: collapsed.rowHeight, progress: clampedProgress),
            dayColumnWidth: Self.interpolate(from: expanded.dayColumnWidth, to: collapsed.dayColumnWidth, progress: clampedProgress),
            verticalPadding: Self.interpolate(from: expanded.verticalPadding, to: collapsed.verticalPadding, progress: clampedProgress),
            horizontalPadding: Self.interpolate(from: expanded.horizontalPadding, to: collapsed.horizontalPadding, progress: clampedProgress),
            cornerRadius: Self.interpolate(from: expanded.cornerRadius, to: collapsed.cornerRadius, progress: clampedProgress),
            monthControlSize: Self.interpolate(from: expanded.monthControlSize, to: collapsed.monthControlSize, progress: clampedProgress),
            monthControlSpacing: Self.interpolate(from: expanded.monthControlSpacing, to: collapsed.monthControlSpacing, progress: clampedProgress)
        )
    }

    func capsuleWidth(for progress: CGFloat) -> CGFloat {
        return Self.interpolate(
            from: expandedCalendarWidth,
            to: compactCapsuleWidth,
            progress: Self.clamped(progress)
        )
    }

    func contentLeadingInset(for progress: CGFloat) -> CGFloat {
        return Self.interpolate(
            from: expandedContentLeadingInset,
            to: 0,
            progress: Self.clamped(progress)
        )
    }

    func companionWidth(for progress: CGFloat) -> CGFloat {
        if kind == .pad {
            return expandedCompanionWidth
        }

        let resolvedProgress = companionProgress(for: progress)
        return Self.interpolate(
            from: expandedCompanionWidth,
            to: compactCompanionWidth,
            progress: resolvedProgress
        )
    }

    func columnSpacing(for progress: CGFloat) -> CGFloat {
        if kind == .pad {
            return expandedColumnSpacing
        }

        let resolvedProgress = companionProgress(for: progress)
        return Self.interpolate(
            from: expandedColumnSpacing,
            to: compactColumnSpacing,
            progress: resolvedProgress
        )
    }

    func companionHeight(for progress: CGFloat) -> CGFloat {
        if kind == .pad {
            return expandedContentHeight
        }

        let resolvedProgress = companionProgress(for: progress)
        return Self.interpolate(
            from: expandedCompanionHeight,
            to: compactCapsuleHeight,
            progress: resolvedProgress
        )
    }

    func avatarTop(for progress: CGFloat) -> CGFloat {
        if kind == .pad {
            return expandedAvatarTop
        }

        return Self.interpolate(
            from: expandedAvatarTop,
            to: collapsedAvatarTop,
            progress: Self.clamped(progress)
        )
    }

    func floatingAvatarOpacity(for progress: CGFloat) -> CGFloat {
        guard showsFloatingAvatar else { return 0 }

        if kind == .pad || mode == .narrow {
            return 1
        }

        return Self.clamped((progress - 0.52) / 0.20)
    }

    func topHeaderState(for progress: CGFloat, stickyOffset: CGFloat) -> HomeTopHeaderLayoutState {
        let clampedProgress = Self.clamped(progress)
        let companionProgress = companionProgress(for: clampedProgress)
        return HomeTopHeaderLayoutState(
            progress: clampedProgress,
            companionProgress: companionProgress,
            stickyOffset: stickyOffset,
            calendarState: state(for: clampedProgress),
            calendarWidth: capsuleWidth(for: clampedProgress),
            companionWidth: companionWidth(for: clampedProgress),
            companionHeight: companionHeight(for: clampedProgress),
            columnSpacing: columnSpacing(for: clampedProgress),
            companionOffsetY: companionOffsetY(for: clampedProgress),
            avatarTop: avatarTop(for: clampedProgress)
        )
    }

    // MARK: - Helpers

    fileprivate static func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }

    private static func normalizedProgress(value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        guard upper > lower else { return 0 }
        return clamped((value - lower) / (upper - lower))
    }

    private func companionProgress(for progress: CGFloat) -> CGFloat {
        if kind == .pad {
            return 0
        }

        return Self.clamped(progress)
    }

    private func companionOffsetY(for progress: CGFloat) -> CGFloat {
        0
    }

    private func calendarColumnHeight(for progress: CGFloat) -> CGFloat {
        let resolvedProgress = Self.clamped(progress)
        let calendarState = state(for: resolvedProgress)
        let totalGridHeight = CGFloat(monthRowCount) * calendarState.rowHeight
        let visibleGridHeight = calendarState.rowHeight + ((totalGridHeight - calendarState.rowHeight) * (1 - resolvedProgress))

        return calendarState.titleHeight
            + calendarState.titleBottomSpacing
            + calendarState.weekLabelHeight
            + visibleGridHeight
            + (calendarState.verticalPadding * 2)
    }

    fileprivate static func interpolate(from start: CGFloat, to end: CGFloat, progress: CGFloat) -> CGFloat {
        start + ((end - start) * progress)
    }

    private static func resolveRegularHeaderSplit(
        availableContentWidth: CGFloat,
        headerBudget: CGFloat
    ) -> (calendarWidth: CGFloat, companionWidth: CGFloat, spacing: CGFloat) {
        let minimumCalendarWidth = HomeAdaptiveLayoutContext.minimumRegularCalendarWidth
        let minimumCompanionWidth = HomeAdaptiveLayoutContext.minimumRegularCompanionWidth
        let maximumCompanionWidth: CGFloat
        let preferredSpacing: CGFloat
        let companionShare: CGFloat

        if availableContentWidth >= 1080 {
            maximumCompanionWidth = 360
            preferredSpacing = 24
            companionShare = 0.31
        } else if availableContentWidth >= 820 {
            maximumCompanionWidth = 300
            preferredSpacing = 20
            companionShare = 0.30
        } else {
            maximumCompanionWidth = 240
            preferredSpacing = 16
            companionShare = 0.29
        }

        let spacing = min(
            preferredSpacing,
            max(
                headerBudget - minimumCalendarWidth - minimumCompanionWidth,
                HomeAdaptiveLayoutContext.minimumRegularHeaderSpacing
            )
        )
        let usableWidth = max(headerBudget - spacing, 0)
        let maxCompanionAllowed = max(usableWidth - minimumCalendarWidth, minimumCompanionWidth)
        let companionWidth = min(
            max(usableWidth * companionShare, minimumCompanionWidth),
            min(maximumCompanionWidth, maxCompanionAllowed)
        )
        let calendarWidth = max(usableWidth - companionWidth, minimumCalendarWidth)

        return (
            calendarWidth: rounded(calendarWidth),
            companionWidth: rounded(companionWidth),
            spacing: rounded(spacing)
        )
    }

    private static func rounded(_ value: CGFloat) -> CGFloat {
        (value * 10).rounded() / 10
    }
}

private extension HomeLayoutMode {
    var kind: HomeCalendarAdaptiveLayout.Kind {
        usesRegularMetrics ? .pad : .phone
    }
}

// MARK: - Home Top Header Layout State

/// Shared sticky-header geometry consumed by the iPad companion widget and calendar.
struct HomeTopHeaderLayoutState: Equatable {
    let progress: CGFloat
    let companionProgress: CGFloat
    let stickyOffset: CGFloat
    let calendarState: HomeCalendarAdaptiveLayout.State
    let calendarWidth: CGFloat
    let companionWidth: CGFloat
    let companionHeight: CGFloat
    let columnSpacing: CGFloat
    let companionOffsetY: CGFloat
    let avatarTop: CGFloat
}

// MARK: - Calendar Day Metrics

/// Visual metrics for one Home calendar day cell across expanded and compact states.
struct HomeCalendarDayMetrics: Equatable {
    enum ContentMode: Equatable {
        case compact
        case summary
        case detail
    }

    let contentMode: ContentMode
    let highlightDiameter: CGFloat
    let streakRingLineWidth: CGFloat
    let fontSize: CGFloat
    let valueFontSize: CGFloat
    let captionFontSize: CGFloat
    let tilePadding: CGFloat
    let contentSpacing: CGFloat
    let markerDotSize: CGFloat
    let markerCapsuleWidth: CGFloat
    let markerSpacing: CGFloat
    let markerOffsetY: CGFloat
    let progressBarHeight: CGFloat
    let strokeLineWidth: CGFloat
    let usesMarkerCapsule: Bool
    let showsSecondaryNoteMarker: Bool

    init(
        collapseProgress: CGFloat,
        dayColumnWidth: CGFloat,
        rowHeight: CGFloat,
        hasGoalNote: Bool,
        hasExamGoalCount: Bool,
        isHighlighted: Bool
    ) {
        let progress = min(max(collapseProgress, 0), 1)
        let minDimension = min(dayColumnWidth, rowHeight)
        if progress > 0.68 || minDimension < 48 {
            contentMode = .compact
        } else if dayColumnWidth >= 110 && rowHeight >= 86 {
            contentMode = .detail
        } else {
            contentMode = .summary
        }

        let highlightWidthScale = HomeCalendarAdaptiveLayout.interpolate(
            from: isHighlighted ? 0.72 : 0.64,
            to: isHighlighted ? 0.64 : 0.58,
            progress: progress
        )
        let highlightHeightScale = HomeCalendarAdaptiveLayout.interpolate(
            from: isHighlighted ? 0.84 : 0.76,
            to: isHighlighted ? 0.74 : 0.68,
            progress: progress
        )

        highlightDiameter = min(dayColumnWidth * highlightWidthScale, rowHeight * highlightHeightScale)
        streakRingLineWidth = HomeCalendarAdaptiveLayout.interpolate(from: 1.5, to: 1.0, progress: progress)
        fontSize = min(max(rowHeight * HomeCalendarAdaptiveLayout.interpolate(from: 0.23, to: 0.36, progress: progress), 12), 18)
        valueFontSize = min(max(rowHeight * 0.20, 14), 22)
        captionFontSize = min(max(rowHeight * 0.11, 10), 12)
        tilePadding = min(max(minDimension * 0.12, 6), 10)
        contentSpacing = HomeCalendarAdaptiveLayout.interpolate(from: 5, to: 2, progress: progress)
        markerDotSize = min(max(dayColumnWidth * HomeCalendarAdaptiveLayout.interpolate(from: 0.10, to: 0.08, progress: progress), 3), 5)
        markerCapsuleWidth = min(max(dayColumnWidth * HomeCalendarAdaptiveLayout.interpolate(from: 0.18, to: 0.14, progress: progress), 6), 10)
        markerSpacing = HomeCalendarAdaptiveLayout.interpolate(from: 4, to: 3, progress: progress)
        markerOffsetY = HomeCalendarAdaptiveLayout.interpolate(from: -4, to: -2, progress: progress)
        progressBarHeight = min(max(rowHeight * 0.06, 3), 6)
        strokeLineWidth = progress < 0.28 ? 1.0 : 0.8
        showsSecondaryNoteMarker = hasGoalNote && progress < 0.72
        usesMarkerCapsule = hasExamGoalCount && progress < 0.82
    }
}
