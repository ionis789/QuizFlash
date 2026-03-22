// HomeCalendarSectionView.swift
// QuizFlash
//
// A sticky, collapsible calendar header for the Home screen.
// Transitions from a fully expanded month grid to a compact single-week row
// as the user scrolls the underlying content upward.

import SwiftUI

// MARK: - Home Calendar Section View

/// A sticky, collapsible calendar header that transitions from an expanded month grid
/// to a compact weekly row during vertical scrolling.
///
/// **Architecture notes:**
/// - Uses an absolute Z-axis layering system to avoid layout recalculation jumps
///   (jank) during rapid scrolling.
/// - Employs a static background composition to ensure zero memory leaks when
///   rendering `.ultraThinMaterial` inside a `GeometryReader`.
/// - All colours are sourced from `ThemeManager` or semantic SwiftUI tokens — no
///   hardcoded values.
struct HomeCalendarSectionView: View {
    @Environment(AppPreferences.self) private var appPreferences

    // MARK: - Dependencies

    /// The view model managing date selection and grid data.
    var calendarVM: CalendarViewModel

    /// Maximum height of the header when fully expanded.
    let extendedHeight: CGFloat

    /// Total scrollable distance required to fully collapse the header.
    let scrollDistance: CGFloat

    /// Top safe-area inset used to compute absolute anchor points.
    let safeAreaTop: CGFloat

    /// O(1) lookup dictionary providing per-day progress and marker insights.
    let calendarInsightsCache: [String: HomeCalendarDayInsight]

    /// The global navigation router (passed to `HomeAvatarView`).
    let router: NavigationManager

    // MARK: - Private Constants

    // MARK: - Body

    var body: some View {
        GeometryReader { proxy in
            let avatarSize = max(UIConstants.Size.actionButton, calendarVM.compactCapsuleHeight - 8)
            let availableContentWidth = max(0, proxy.size.width - (UIConstants.Layout.screenEdgeInset * 2))

            // MARK: Scroll Metrics

            let minY = proxy.frame(in: .scrollView(axis: .vertical)).minY

            /// Normalised collapse progress: 0.0 = fully expanded, 1.0 = fully compact.
            let progress = max(0, min(-minY / scrollDistance, 1.0))

            /// Vertical offset applied to keep the entire header pinned to the screen top.
            let stickyOffset: CGFloat = minY < 0 ? -minY : 0

            // MARK: Grid Geometry

            let compactLayout = HomeCompactCalendarLayout(
                collapseProgress: progress,
                avatarSize: avatarSize,
                outerHorizontalInset: UIConstants.Layout.screenEdgeInset,
                collapsedHorizontalPadding: calendarVM.compactCapsuleHorizontalPadding,
                collapsedVerticalPadding: calendarVM.compactCapsuleVerticalPadding,
                trailingGap: UIConstants.Layout.homeCalendarCompactTrailingGap,
                cornerRadius: calendarVM.compactCapsuleCornerRadius
            )

            // MARK: Avatar Absolute Positioning

            let expandedCenterY = safeAreaTop + calendarVM.topPaddingExpanded + (calendarVM.titleHeight / 2.0)
            let collapsedCenterY = safeAreaTop + calendarVM.topPaddingCollapsed + (calendarVM.compactCapsuleHeight / 2.0)
            let currentCenterY = expandedCenterY - ((expandedCenterY - collapsedCenterY) * progress)
            let avatarAbsoluteTop = currentCenterY - (avatarSize / 2.0)

            // MARK: Render Tree

            ZStack(alignment: .topTrailing) {

                // LAYER 1: Content & Background
                VStack(spacing: 0) {
                    Spacer().frame(height: safeAreaTop)

                    VStack(alignment: .leading, spacing: 0) {
                        titleRow(progress: progress, avatarSize: avatarSize)
                        calendarGrid(
                            progress: progress,
                            layout: compactLayout,
                            availableWidth: availableContentWidth
                        )
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
                .padding(.top, calendarVM.topPaddingExpanded - (calendarVM.topPaddingExpanded - calendarVM.topPaddingCollapsed) * progress)
                .padding(.bottom, calendarVM.bottomPadding)
                .shadow(color: .black.opacity(0.08 * progress), radius: 10, y: 4)

                // LAYER 2: Absolute Avatar (floats independently of the content stack)
                HomeAvatarView(router: router, iconSize: avatarSize)
                    .padding(.trailing, UIConstants.Layout.screenEdgeInset)
                    .padding(.top, avatarAbsoluteTop)
            }
            .offset(y: stickyOffset)
        }
        .frame(height: extendedHeight)
    }

    // MARK: - Subviews

    /// Renders the month and year title row with trailing month navigation.
    ///
    /// Fades out and collapses vertically as `progress` approaches 1.0 (fully compact).
    @ViewBuilder
    private func titleRow(progress: CGFloat, avatarSize: CGFloat) -> some View {
        HStack(alignment: .center, spacing: UIConstants.Spacing.standard) {
            Text(calendarVM.currentMonthString + " " + calendarVM.yearString)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 2) {
                chevronButton(increment: false)
                chevronButton(increment: true)
            }
            .padding(.trailing, avatarSize + UIConstants.Spacing.medium)
        }
        .frame(height: calendarVM.titleHeight * (1 - progress), alignment: .center)
        .padding(.bottom, calendarVM.titleBottomSpacing * (1 - progress))
        .clipped()
        .opacity(1.0 - progress * 2)
    }

    /// Renders the weekday labels and the scrollable grid of days.
    ///
    /// Compresses horizontally and scales down slightly as `progress` increases.
    @ViewBuilder
    private func calendarGrid(
        progress: CGFloat,
        layout: HomeCompactCalendarLayout,
        availableWidth: CGFloat
    ) -> some View {
        let totalGridHeight = CGFloat(calendarVM.monthRows.count) * calendarVM.rowHeight
        let isCompactStripActive = progress >= 0.999
        let capsuleWidth = capsuleWidth(layout: layout, availableWidth: availableWidth)
        let compactVisibleWidth = compactStripWidth(layout: layout, capsuleWidth: capsuleWidth)

        VStack(spacing: 0) {
            weekdayLabels

            ZStack(alignment: .top) {
                dayGrid(totalGridHeight: totalGridHeight, progress: progress)
                    .opacity(isCompactStripActive ? 0 : 1)

                if isCompactStripActive && !compactWeekPages.isEmpty {
                    CompactCalendarWeekStrip(
                        weeks: compactWeekPages,
                        visibleWidth: compactVisibleWidth,
                        dayRowHeight: calendarVM.rowHeight,
                        calendarInsightsCache: calendarInsightsCache,
                        onSelectDay: { day in
                            calendarVM.selectDate(day.date)
                        }
                    )
                    .transition(.identity)
                    .transaction { $0.animation = nil }
                }
            }
            .frame(
                height: calendarVM.rowHeight + (totalGridHeight - calendarVM.rowHeight) * (1 - progress),
                alignment: .top
            )
            .clipped()
            .transaction { $0.animation = nil }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, layout.verticalPadding)
        .padding(.horizontal, layout.horizontalPadding)
        .frame(width: capsuleWidth, alignment: .leading)
        .background {
            compactCalendarChrome(layout: layout, progress: progress)
        }
        .clipShape(RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous))
    }

    /// A horizontal row displaying abbreviated weekday symbols (e.g., Sun, Mon).
    private var weekdayLabels: some View {
        HStack(spacing: 0) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: 12, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: calendarVM.weekLabelHeight, alignment: .center)
    }

    private var weekdaySymbols: [String] {
        let calendar = appPreferences.resolvedCalendar
        let symbols = calendar.shortWeekdaySymbols
        let startIndex = max(calendar.firstWeekday - 1, 0)
        return Array(symbols[startIndex...]) + Array(symbols[..<startIndex])
    }

    /// The full month grid.
    ///
    /// Rows outside the selected week fade out based on their vertical distance from
    /// the active row's position during the collapse animation.
    @ViewBuilder
    private func dayGrid(totalGridHeight: CGFloat, progress: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(calendarVM.monthRows.enumerated()), id: \.element.first?.id) { rowIndex, row in
                let distance = abs(CGFloat(rowIndex) - calendarVM.monthProgress)
                let rowOpacity = max(0, 1.0 - distance * progress)

                HStack(spacing: 0) {
                    ForEach(row) { day in
                        CalendarDayCellView(
                            day: day,
                            insight: calendarInsightsCache[day.dateString],
                            collapseProgress: progress
                        )
                            .onTapGesture {
                                calendarVM.selectDate(day.date)
                            }
                    }
                }
                .frame(height: calendarVM.rowHeight)
                .opacity(rowOpacity)
                // Disable automatic opacity interpolation during month transitions.
                .transaction { $0.animation = nil }
            }
        }
        .frame(height: totalGridHeight, alignment: .top)
        .offset(y: -(calendarVM.monthProgress * calendarVM.rowHeight) * progress)
    }

    /// A minimal button for advancing or rewinding the displayed month.
    ///
    /// - Parameter increment: `true` to move forward one month, `false` to go back.
    private func chevronButton(increment: Bool) -> some View {
        Button {
            calendarVM.monthUpdate(increment: increment)
        } label: {
            Image(systemName: increment ? "chevron.right" : "chevron.left")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary.opacity(0.95))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func compactCalendarChrome(layout: HomeCompactCalendarLayout, progress: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
        let borderProgress = max(0, min((progress - 0.985) / 0.015, 1))

        Color.clear
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .opacity(progress)
                    .overlay {
                        shape
                            .fill(Color.white.opacity(0.35))
                            .blur(radius: 10)
                            .mask(shape.stroke(lineWidth: 4))
                            .blendMode(.overlay)
                            .opacity(borderProgress)
                    }
            }
    }

    private var compactWeekPages: [[Day]] {
        calendarVM.monthRows
    }

    private func capsuleWidth(layout: HomeCompactCalendarLayout, availableWidth: CGFloat) -> CGFloat {
        max(0, availableWidth - layout.trailingReservation)
    }

    private func compactStripWidth(layout: HomeCompactCalendarLayout, capsuleWidth: CGFloat) -> CGFloat {
        let availableWidth = capsuleWidth - (layout.horizontalPadding * 2)
        let cellWidth = floor(max(0, availableWidth) / 7)
        return cellWidth * 7
    }
}

// MARK: - Calendar Day Cell View

/// Renders a single day cell in the calendar grid.
///
/// Handles visual state mapping for today, productive study days, and the selected date.
/// Colours come exclusively from `ThemeManager` or semantic SwiftUI tokens.
struct CalendarDayCellView: View {

    // MARK: - Input

    let day: Day
    let insight: HomeCalendarDayInsight?
    let collapseProgress: CGFloat

    // MARK: - Computed States

    private var isToday: Bool {
        Calendar.current.isDateInToday(day.date)
    }

    /// The active theme accent colour, resolved from `ThemeManager`.
    private var accent: Color {
        ThemeManager.shared.accentColor.color
    }

    private var didStudy: Bool {
        insight?.didStudy ?? false
    }

    private var isPerfectDay: Bool {
        insight?.isPerfectDay ?? false
    }

    private var isStreakDay: Bool {
        insight?.isStreakDay ?? false
    }

    private var hasExamGoal: Bool {
        insight?.hasExamGoal ?? false
    }

    private var hasGoalNote: Bool {
        insight?.hasGoalNote ?? false
    }

    private var examGoalCount: Int {
        insight?.examGoalCount ?? 0
    }

    private var activityFraction: Double {
        insight?.activityFraction ?? 0
    }

    private var shouldShowInnerHighlight: Bool {
        day.isSelected || isToday || didStudy
    }

    private var metrics: HomeCalendarDayMetrics {
        HomeCalendarDayMetrics(
            collapseProgress: collapseProgress,
            hasGoalNote: hasGoalNote,
            hasExamGoalCount: examGoalCount > 1,
            isHighlighted: shouldShowInnerHighlight
        )
    }

    // MARK: - Styling

    private var highlightFillColor: Color {
        if day.isSelected { return .white }
        if isToday { return accent }
        if isPerfectDay { return .green }
        if didStudy { return accent }
        return .clear
    }

    private var highlightOpacity: Double {
        if day.isSelected { return 1.0 }
        if isToday { return didStudy ? 0.28 : 0.18 }
        if isPerfectDay { return 0.22 + (activityFraction * 0.18) }
        if didStudy { return 0.10 + (activityFraction * 0.18) }
        return 0
    }

    private var textColor: Color {
        if day.isSelected { return .black }
        if isToday { return accent }
        if isPerfectDay { return .green }
        if didStudy { return accent.opacity(0.92) }
        if day.ignored { return .secondary.opacity(0.3) }
        return .primary
    }

    private var streakStrokeColor: Color {
        if day.isSelected { return .white.opacity(0.28) }
        if isPerfectDay { return .green.opacity(0.85) }
        return accent.opacity(0.55)
    }

    private var shouldShowStreakRing: Bool {
        isStreakDay && !day.ignored && !isToday && !day.isSelected
    }

    private var examMarkerColor: Color {
        if examGoalCount > 1 {
            return accent.opacity(0.95)
        }
        return accent
    }

    private var noteMarkerColor: Color {
        .orange
    }

    // MARK: - Body

    var body: some View {
        Text(day.shortSymbol)
            .font(.system(
                size: metrics.fontSize,
                weight: (day.isSelected || isToday) ? .bold : .medium,
                design: .rounded
            ))
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                ZStack {
                    if shouldShowStreakRing {
                        Circle()
                            .stroke(streakStrokeColor, lineWidth: metrics.streakRingLineWidth)
                            .frame(width: metrics.streakRingDiameter, height: metrics.streakRingDiameter)
                    }

                    Circle()
                        .fill(highlightFillColor.opacity(highlightOpacity))
                        .frame(width: metrics.highlightDiameter, height: metrics.highlightDiameter)
                }
            }
            .overlay(alignment: .bottom) {
                if hasExamGoal && !day.isSelected {
                    HStack(spacing: metrics.markerSpacing) {
                        markerShape(color: examMarkerColor)

                        if metrics.showsSecondaryNoteMarker {
                            markerShape(color: noteMarkerColor)
                        }
                    }
                    .offset(y: metrics.markerOffsetY)
                }
            }
            .contentShape(Rectangle())
            .zIndex(day.isSelected ? 1 : 0)
    }

    @ViewBuilder
    private func markerShape(color: Color) -> some View {
        if metrics.usesMarkerCapsule {
            Capsule()
                .fill(color)
                .frame(width: metrics.markerCapsuleWidth, height: metrics.markerDotSize)
        } else {
            Circle()
                .fill(color)
                .frame(width: metrics.markerDotSize, height: metrics.markerDotSize)
        }
    }
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
        hasGoalNote: Bool,
        hasExamGoalCount: Bool,
        isHighlighted: Bool
    ) {
        let clampedProgress = min(max(collapseProgress, 0), 1)
        let compactHighlightDiameter = isHighlighted ? 30.0 : 28.0

        highlightDiameter = Self.interpolate(
            from: 36,
            to: compactHighlightDiameter,
            progress: clampedProgress
        )
        streakRingDiameter = highlightDiameter + Self.interpolate(from: 7, to: 4, progress: clampedProgress)
        streakRingLineWidth = Self.interpolate(from: 1.7, to: 1.1, progress: clampedProgress)
        fontSize = Self.interpolate(from: 16, to: 15, progress: clampedProgress)
        markerDotSize = Self.interpolate(from: 5, to: 4, progress: clampedProgress)
        markerCapsuleWidth = Self.interpolate(from: 10, to: 7, progress: clampedProgress)
        markerSpacing = Self.interpolate(from: 4, to: 3, progress: clampedProgress)
        markerOffsetY = Self.interpolate(from: -4, to: -2, progress: clampedProgress)
        showsSecondaryNoteMarker = hasGoalNote && clampedProgress < 0.72
        usesMarkerCapsule = hasExamGoalCount && clampedProgress < 0.82
    }

    private static func interpolate(from start: CGFloat, to end: CGFloat, progress: CGFloat) -> CGFloat {
        start + ((end - start) * progress)
    }
}

// MARK: - Compact Calendar Layout

/// Shared compact-layout metrics for the sticky Home calendar capsule.
struct HomeCompactCalendarLayout: Equatable {
    let verticalPadding: CGFloat
    let horizontalPadding: CGFloat
    let trailingReservation: CGFloat
    let cornerRadius: CGFloat

    static let minimumCollapsedDayWidth: CGFloat = 36

    init(
        collapseProgress: CGFloat,
        avatarSize: CGFloat,
        outerHorizontalInset: CGFloat,
        collapsedHorizontalPadding: CGFloat,
        collapsedVerticalPadding: CGFloat,
        trailingGap: CGFloat,
        cornerRadius: CGFloat
    ) {
        let progress = min(max(collapseProgress, 0), 1)
        verticalPadding = Self.interpolate(from: 0, to: collapsedVerticalPadding, progress: progress)
        horizontalPadding = Self.interpolate(from: 0, to: collapsedHorizontalPadding, progress: progress)
        trailingReservation = Self.interpolate(
            from: 0,
            to: avatarSize + trailingGap,
            progress: progress
        )
        self.cornerRadius = Self.interpolate(from: 0, to: cornerRadius, progress: progress)
    }

    func collapsedWeekContentWidth(for containerWidth: CGFloat) -> CGFloat {
        max(0, containerWidth - (horizontalPadding * 2) - trailingReservation)
    }

    private static func interpolate(from start: CGFloat, to end: CGFloat, progress: CGFloat) -> CGFloat {
        start + ((end - start) * progress)
    }
}

// MARK: - Compact Calendar Day Strip

/// Horizontally scrollable compact strip that pages calendar weeks while weekday labels stay fixed.
private struct CompactCalendarWeekStrip: View {
    let weeks: [[Day]]
    let visibleWidth: CGFloat
    let dayRowHeight: CGFloat
    let calendarInsightsCache: [String: HomeCalendarDayInsight]
    let onSelectDay: (Day) -> Void

    private var cellWidth: CGFloat {
        max(
            HomeCompactCalendarLayout.minimumCollapsedDayWidth,
            floor(max(visibleWidth, 0) / 7)
        )
    }

    private var pageWidth: CGFloat {
        max(visibleWidth, cellWidth * 7)
    }

    private var rowHorizontalInset: CGFloat {
        max(0, (pageWidth - (cellWidth * 7)) / 2)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(weeks.enumerated()), id: \.offset) { index, week in
                        HStack(spacing: 0) {
                            ForEach(week) { day in
                                CalendarDayCellView(
                                    day: day,
                                    insight: calendarInsightsCache[day.dateString],
                                    collapseProgress: 1
                                )
                                .frame(width: cellWidth, height: dayRowHeight)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onSelectDay(day)
                                }
                            }
                        }
                        .padding(.horizontal, rowHorizontalInset)
                        .frame(width: pageWidth, height: dayRowHeight, alignment: .leading)
                        .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .frame(width: pageWidth, height: dayRowHeight, alignment: .leading)
            .scrollTargetBehavior(.paging)
            .clipped()
            .onAppear {
                scrollToSelectedWeek(with: proxy, animated: false)
            }
            .onChange(of: selectedWeekIndex) { _, _ in
                scrollToSelectedWeek(with: proxy, animated: false)
            }
            .onChange(of: weeks.map { $0.map(\.dateString) }) { _, _ in
                scrollToSelectedWeek(with: proxy, animated: false)
            }
        }
    }

    private var selectedWeekIndex: Int? {
        weeks.firstIndex { week in
            week.contains(where: \.isSelected)
        }
    }

    private func scrollToSelectedWeek(with proxy: ScrollViewProxy, animated: Bool) {
        guard let selectedWeekIndex else { return }
        if animated {
            withAnimation(.selectionToolbarSpring) {
                proxy.scrollTo(selectedWeekIndex, anchor: .leading)
            }
        } else {
            proxy.scrollTo(selectedWeekIndex, anchor: .leading)
        }
    }
}
