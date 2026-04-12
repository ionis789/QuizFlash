// HomeCalendarSectionView.swift
// QuizFlash
//
// A sticky, collapsible calendar header for the Home screen.
// Transitions from a fully expanded month grid to a compact single-week row
// as the user scrolls the underlying content upward.
import SwiftUI
import UIKit

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

    /// Width-aware layout metrics shared with `HomeView`.
    let layout: HomeCalendarAdaptiveLayout

    /// O(1) lookup dictionary providing per-day progress and marker insights.
    let calendarInsightsCache: [String: HomeCalendarDayInsight]
    let calendarInsightsRevision: Int

    // MARK: - Private Constants

    // MARK: - Body

    var body: some View {
        GeometryReader { proxy in
            // MARK: Scroll Metrics

            let minY = proxy.frame(in: .scrollView(axis: .vertical)).minY

            /// Normalised collapse progress: 0.0 = fully expanded, 1.0 = fully compact.
            let progress = max(0, min(-minY / layout.scrollDistance, 1.0))

            /// Vertical offset applied to keep the entire header pinned to the screen top.
            let stickyOffset: CGFloat = minY < 0 ? -minY : 0

            let state = layout.state(for: progress)
            let calendarColumnWidth = layout.capsuleWidth(for: progress)
            let contentLeadingInset = layout.contentLeadingInset(for: progress)

            // MARK: Render Tree

            VStack(spacing: 0) {
                Spacer().frame(height: layout.safeAreaTop)

                VStack(spacing: 0) {
                    titleRow(progress: progress, state: state)
                        .frame(width: layout.headerColumnWidth, alignment: .leading)
                        .frame(
                            maxWidth: .infinity,
                            alignment: layout.kind == .pad ? .center : .leading
                        )

                    headerContent(
                        progress: progress,
                        state: state,
                        calendarColumnWidth: calendarColumnWidth
                    )
                }
                .padding(.leading, contentLeadingInset)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, layout.outerHorizontalInset)
            .padding(.top, state.topPadding)
            .padding(.bottom, layout.bottomPadding)
            .offset(y: stickyOffset)
        }
        .frame(height: layout.extendedHeight)
    }

    // MARK: - Subviews

    /// Renders the month and year title row with trailing month navigation.
    ///
    /// Fades out and collapses vertically as `progress` approaches 1.0 (fully compact).
    @ViewBuilder
    private func titleRow(progress: CGFloat, state: HomeCalendarAdaptiveLayout.State) -> some View {
        HStack(alignment: .center, spacing: UIConstants.Spacing.medium) {
            Text(calendarVM.currentMonthString + " " + calendarVM.yearString)
                .font(.system(size: state.titleFontSize, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            HStack(spacing: state.monthControlSpacing) {
                chevronButton(increment: false, size: state.monthControlSize)
                chevronButton(increment: true, size: state.monthControlSize)
            }
        }
        .frame(height: state.titleHeight, alignment: .center)
        .padding(.bottom, state.titleBottomSpacing)
        .clipped()
        .opacity(max(0, 1.0 - (progress * 1.6)))
    }

    @ViewBuilder
    private func headerContent(
        progress: CGFloat,
        state: HomeCalendarAdaptiveLayout.State,
        calendarColumnWidth: CGFloat
    ) -> some View {
        if layout.kind == .pad {
            calendarGrid(
                progress: progress,
                state: state
            )
            .frame(width: calendarColumnWidth, alignment: .leading)
            .frame(width: layout.headerColumnWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        } else {
            calendarGrid(
                progress: progress,
                state: state
            )
            .frame(width: calendarColumnWidth, alignment: .leading)
            .frame(width: layout.headerColumnWidth, alignment: .center)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    /// Renders the weekday labels and the scrollable grid of days.
    ///
    /// Compresses horizontally and scales down slightly as `progress` increases.
    @ViewBuilder
    private func calendarGrid(
        progress: CGFloat,
        state: HomeCalendarAdaptiveLayout.State
    ) -> some View {
        let totalGridHeight = CGFloat(calendarVM.monthRows.count) * state.rowHeight
        let isCompactStripActive = progress >= 0.999
        let usesMonthPager = progress < 0.001
        let pagerState = layout.expanded
        let visibleGridWidth = (usesMonthPager ? pagerState.dayColumnWidth : state.dayColumnWidth) * 7
        let capsuleWidth = layout.capsuleWidth(for: progress)
        let compactBackdropProgress = max(0, min((progress - 0.44) / 0.56, 1.0))
        let compactContentShadowProgress = max(0, min((progress - 0.40) / 0.60, 1.0))

        VStack(spacing: 0) {
            weekdayLabels(state: state)
                .frame(width: visibleGridWidth, alignment: .leading)

            ZStack(alignment: .top) {
                if !isCompactStripActive && usesMonthPager {
                    expandedMonthPager(progress: 0, state: pagerState)
                        .frame(width: visibleGridWidth, alignment: .leading)
                }

                if !isCompactStripActive && !usesMonthPager {
                    dayGrid(
                        totalGridHeight: totalGridHeight,
                        progress: progress,
                        state: state
                    )
                    .frame(width: visibleGridWidth, alignment: .leading)
                }

                if isCompactStripActive && !compactWeekPages.isEmpty {
                    CompactCalendarWeekStrip(
                        weeks: compactWeekPages,
                        visibleWidth: visibleGridWidth,
                        dayColumnWidth: state.dayColumnWidth,
                        dayRowHeight: state.rowHeight,
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
                height: state.rowHeight + (totalGridHeight - state.rowHeight) * (1 - progress),
                alignment: .top
            )
            .clipped()
            .transaction { $0.animation = nil }
        }
        .padding(.horizontal, state.horizontalPadding)
        .padding(.vertical, state.verticalPadding)
        .frame(width: capsuleWidth, alignment: .leading)
        .background {
            if compactBackdropProgress > 0.001 {
                RoundedRectangle(cornerRadius: state.cornerRadius, style: .continuous)
                    .fill(.thinMaterial)
                    .opacity(compactBackdropProgress)
                    .shadow(
                        color: Color.black.opacity(0.18 * compactBackdropProgress),
                        radius: 22 * compactBackdropProgress,
                        x: 0,
                        y: 10 * compactBackdropProgress
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: state.cornerRadius, style: .continuous))
        .compositingGroup()
        .shadow(
            color: Color.black.opacity(0.52 * compactContentShadowProgress),
            radius: 16 * compactContentShadowProgress,
            x: 0,
            y: 6 * compactContentShadowProgress
        )
        .shadow(
            color: Color.black.opacity(0.34 * compactContentShadowProgress),
            radius: 34 * compactContentShadowProgress,
            x: 0,
            y: 12 * compactContentShadowProgress
        )
        .shadow(
            color: Color.black.opacity(0.18 * compactContentShadowProgress),
            radius: 58 * compactContentShadowProgress,
            x: 0,
            y: 20 * compactContentShadowProgress
        )
    }

    @ViewBuilder
    private func expandedMonthPager(
        progress: CGFloat,
        state: HomeCalendarAdaptiveLayout.State
    ) -> some View {
        ExpandedMonthPagerHost(
            snapshots: calendarVM.visibleMonthSnapshots,
            progress: 0,
            state: state,
            calendarInsightsCache: calendarInsightsCache,
            insightsRevision: calendarInsightsRevision,
            onSelectDay: { day in
                calendarVM.selectDate(day.date)
            },
            onMonthOffset: { offset in
                calendarVM.applyMonthOffset(offset)
            }
        )
        .frame(width: state.dayColumnWidth * 7)
        .clipped()
    }

    /// A horizontal row displaying abbreviated weekday symbols (e.g., Sun, Mon).
    private func weekdayLabels(state: HomeCalendarAdaptiveLayout.State) -> some View {
        HStack(spacing: 0) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: state.weekdayFontSize, weight: .bold, design: .rounded))
                    .frame(width: state.dayColumnWidth)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: state.weekLabelHeight, alignment: .center)
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
    private func dayGrid(
        totalGridHeight: CGFloat,
        progress: CGFloat,
        state: HomeCalendarAdaptiveLayout.State
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(calendarVM.monthRows.enumerated()), id: \.element.first?.id) { rowIndex, row in
                let distance = abs(CGFloat(rowIndex) - calendarVM.monthProgress)
                let rowOpacity = max(0, 1.0 - distance * progress)

                HStack(spacing: 0) {
                    ForEach(row) { day in
                        CalendarDayCellView(
                            day: day,
                            insight: calendarInsightsCache[day.dateString],
                            collapseProgress: progress,
                            dayColumnWidth: state.dayColumnWidth,
                            rowHeight: state.rowHeight
                        )
                        .frame(width: state.dayColumnWidth, height: state.rowHeight)
                        .onTapGesture {
                            calendarVM.selectDate(day.date)
                        }
                    }
                }
                .frame(width: state.dayColumnWidth * 7, height: state.rowHeight, alignment: .leading)
                .opacity(rowOpacity)
                // Disable automatic opacity interpolation during month transitions.
                .transaction { $0.animation = nil }
            }
        }
        .frame(height: totalGridHeight, alignment: .top)
        .offset(y: -(calendarVM.monthProgress * state.rowHeight) * progress)
    }

    /// A minimal button for advancing or rewinding the displayed month.
    ///
    /// - Parameter increment: `true` to move forward one month, `false` to go back.
    private func chevronButton(increment: Bool, size: CGFloat) -> some View {
        Button {
            calendarVM.monthUpdate(increment: increment)
        } label: {
            Image(systemName: increment ? "chevron.right" : "chevron.left")
                .font(.system(size: size * 0.48, weight: .semibold))
                .foregroundStyle(.secondary.opacity(0.95))
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var compactWeekPages: [[Day]] {
        calendarVM.monthRows
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
    let dayColumnWidth: CGFloat
    let rowHeight: CGFloat

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

    private var metrics: HomeCalendarDayMetrics {
        HomeCalendarDayMetrics(
            collapseProgress: collapseProgress,
            dayColumnWidth: dayColumnWidth,
            rowHeight: rowHeight,
            hasGoalNote: hasGoalNote,
            hasExamGoalCount: examGoalCount > 1,
            isHighlighted: day.isSelected || isToday || didStudy
        )
    }

    // MARK: - Styling

    private var tileFillColor: Color {
        if day.ignored { return .clear }
        if day.isSelected { return .white }
        if isToday { return accent }
        if isPerfectDay { return .green }
        if didStudy { return accent }
        return .white
    }

    private var tileFillOpacity: Double {
        if day.ignored { return 0 }
        if day.isSelected { return 1.0 }
        if isToday { return didStudy ? 0.24 : 0.16 }
        if isPerfectDay { return 0.18 + (activityFraction * 0.10) }
        if didStudy { return 0.12 + (activityFraction * 0.08) }
        return 0.06
    }

    private var textColor: Color {
        if day.isSelected { return .black }
        if isToday { return accent }
        if isPerfectDay { return .green }
        if didStudy { return accent.opacity(0.92) }
        if day.ignored { return .secondary.opacity(0.3) }
        return .primary
    }

    private var tileSize: CGFloat {
        if day.ignored { return 0 }
        let cellMinDimension = min(dayColumnWidth, rowHeight)
        let scale: CGFloat = cellMinDimension >= 72 ? 0.62 : 0.70
        return max(cellMinDimension * scale, 0)
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
                    Circle()
                        .fill(tileFillColor.opacity(tileFillOpacity))
                        .frame(width: tileSize, height: tileSize)
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
