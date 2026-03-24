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

    // MARK: - Lifecycle

    init(
        containerWidth: CGFloat,
        safeAreaTop: CGFloat,
        monthRowCount: Int,
        kind: Kind
    ) {
        self.kind = kind
        self.safeAreaTop = safeAreaTop
        self.monthRowCount = monthRowCount

        let horizontalInset = UIConstants.Layout.screenEdgeInset
        outerHorizontalInset = horizontalInset
        availableContentWidth = max(containerWidth - (horizontalInset * 2), 0)

        let widthProgress = Self.normalizedProgress(
            value: availableContentWidth,
            lower: kind == .pad ? 700 : 320,
            upper: kind == .pad ? 1400 : 430
        )

        avatarSize = kind == .pad
            ? UIConstants.Size.actionButton + 4
            : UIConstants.Size.actionButton
        trailingGap = kind == .pad
            ? UIConstants.Layout.homeCalendarCompactTrailingGap + 2
            : UIConstants.Layout.homeCalendarCompactTrailingGap
        let avatarCollisionInset: CGFloat = 0
        trailingReservation = avatarSize + trailingGap + avatarCollisionInset
        if kind == .pad {
            let headerBudget = max(availableContentWidth - trailingReservation, 0)
            let preferredGap = availableContentWidth >= 900 ? 24.0 : 20.0
            let preferredCalendarShare = availableContentWidth >= 1100 ? 0.54 : 0.56
            let preferredCalendarWidth = max(
                min(headerBudget * preferredCalendarShare, headerBudget - preferredGap - 340),
                360
            )
            let preferredCompanionWidth = max(
                min(headerBudget - preferredCalendarWidth - preferredGap, 460),
                300
            )
            expandedColumnSpacing = preferredGap
            if preferredCalendarWidth + preferredCompanionWidth + preferredGap <= headerBudget {
                expandedCalendarWidth = preferredCalendarWidth
                expandedCompanionWidth = preferredCompanionWidth
            } else {
                expandedCompanionWidth = max(headerBudget * 0.36, 280)
                expandedCalendarWidth = max(
                    headerBudget - expandedCompanionWidth - preferredGap,
                    320
                )
            }
        } else {
            expandedColumnSpacing = 0
            expandedCalendarWidth = availableContentWidth
            expandedCompanionWidth = 0
        }
        expandedContentLeadingInset = 0
        expandedCompanionHeight = kind == .pad
            ? max(188, min(Self.interpolate(from: 196, to: 232, progress: widthProgress), 232))
            : 0

        if kind == .pad {
            compactColumnSpacing = 0
            compactCapsuleWidth = expandedCalendarWidth
            compactCompanionWidth = 0
        } else {
            compactCompanionWidth = 0
            compactColumnSpacing = 0
            compactCapsuleWidth = max(0, availableContentWidth - trailingReservation)
        }

        let collapsedHorizontalPadding = kind == .pad
            ? max(UIConstants.Layout.homeCalendarCompactCapsuleHorizontalPadding, 16)
            : UIConstants.Layout.homeCalendarCompactCapsuleHorizontalPadding
        let expandedTopPadding = UIConstants.Layout.homeCalendarExpandedTopPadding
        let expandedTitleFontSize = kind == .pad
            ? Self.rounded(Self.interpolate(from: 28, to: 34, progress: widthProgress))
            : Self.rounded(Self.interpolate(from: 22, to: 24, progress: widthProgress))
        let expandedTitleHeight = kind == .pad
            ? Self.rounded(Self.interpolate(from: 64, to: 76, progress: widthProgress))
            : 52
        let expandedTitleBottomSpacing = kind == .pad ? UIConstants.Spacing.medium : UIConstants.Spacing.small
        let expandedWeekdayFontSize = kind == .pad
            ? Self.rounded(Self.interpolate(from: 12, to: 14, progress: widthProgress))
            : Self.rounded(Self.interpolate(from: 11, to: 12, progress: widthProgress))
        let expandedWeekLabelHeight = kind == .pad
            ? Self.rounded(Self.interpolate(from: 22, to: 24, progress: widthProgress))
            : 18
        let expandedRowHeight = kind == .pad
            ? Self.rounded(Self.interpolate(from: 44, to: 58, progress: widthProgress))
            : Self.rounded(Self.interpolate(from: 38, to: 42, progress: widthProgress))

        let collapsedWeekdayFontSize: CGFloat = kind == .pad ? 12 : 11
        let collapsedWeekLabelHeight: CGFloat = kind == .pad ? 18 : 16
        let collapsedRowHeight = kind == .pad
            ? Self.rounded(Self.interpolate(from: 34, to: 38, progress: widthProgress))
            : Self.rounded(Self.interpolate(from: 34, to: 38, progress: widthProgress))
        let collapsedVerticalPadding = UIConstants.Layout.homeCalendarCompactCapsuleVerticalPadding
        let collapsedCapsuleHeight = collapsedWeekLabelHeight + collapsedRowHeight + (collapsedVerticalPadding * 2)
        let collapsedTopPadding = kind == .pad
            ? max(
                safeAreaTop + expandedTopPadding + (expandedTitleHeight / 2) - safeAreaTop - (collapsedCapsuleHeight / 2),
                0
            )
            : 0
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
            monthControlSize: kind == .pad ? UIConstants.Size.actionButtonMedium : 30,
            monthControlSpacing: kind == .pad ? UIConstants.Spacing.small : 2
        )

        collapsed = State(
            topPadding: collapsedTopPadding,
            titleFontSize: 0,
            titleHeight: 0,
            titleBottomSpacing: 0,
            weekdayFontSize: collapsedWeekdayFontSize,
            weekLabelHeight: collapsedWeekLabelHeight,
            rowHeight: collapsedRowHeight,
            dayColumnWidth: max(kind == .pad ? 34 : 36, collapsedGridWidth / 7),
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
        if kind == .pad {
            return expandedCalendarWidth
        }

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

    private static func rounded(_ value: CGFloat) -> CGFloat {
        (value * 10).rounded() / 10
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
    let highlightDiameter: CGFloat
    let streakRingDiameter: CGFloat
    let streakRingLineWidth: CGFloat
    let fontSize: CGFloat
    let markerDotSize: CGFloat
    let markerCapsuleWidth: CGFloat
    let markerSpacing: CGFloat
    let markerOffsetY: CGFloat
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
        streakRingDiameter = highlightDiameter + min(max(rowHeight * HomeCalendarAdaptiveLayout.interpolate(from: 0.12, to: 0.08, progress: progress), 3), 6)
        streakRingLineWidth = HomeCalendarAdaptiveLayout.interpolate(from: 1.5, to: 1.0, progress: progress)
        fontSize = min(max(rowHeight * HomeCalendarAdaptiveLayout.interpolate(from: 0.38, to: 0.36, progress: progress), 12), 16)
        markerDotSize = min(max(dayColumnWidth * HomeCalendarAdaptiveLayout.interpolate(from: 0.10, to: 0.08, progress: progress), 3), 5)
        markerCapsuleWidth = min(max(dayColumnWidth * HomeCalendarAdaptiveLayout.interpolate(from: 0.18, to: 0.14, progress: progress), 6), 10)
        markerSpacing = HomeCalendarAdaptiveLayout.interpolate(from: 4, to: 3, progress: progress)
        markerOffsetY = HomeCalendarAdaptiveLayout.interpolate(from: -4, to: -2, progress: progress)
        showsSecondaryNoteMarker = hasGoalNote && progress < 0.72
        usesMarkerCapsule = hasExamGoalCount && progress < 0.82
    }
}
