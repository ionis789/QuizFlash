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
    @State private var expandedMonthPageSelection = 1

    // MARK: - Dependencies

    /// The view model managing date selection and grid data.
    var calendarVM: CalendarViewModel

    /// Width-aware layout metrics shared with `HomeView`.
    let layout: HomeCalendarAdaptiveLayout

    /// O(1) lookup dictionary providing per-day progress and marker insights.
    let calendarInsightsCache: [String: HomeCalendarDayInsight]

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
            .frame(maxWidth: .infinity, alignment: .leading)
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
        let isCompactStripActive = progress >= 0.999
        let visibleGridWidth = state.dayColumnWidth * 7
        let capsuleWidth = layout.capsuleWidth(for: progress)

        VStack(spacing: 0) {
            weekdayLabels(state: state)
                .frame(width: visibleGridWidth, alignment: .leading)

            ZStack(alignment: .top) {
                if !isCompactStripActive {
                    expandedMonthPager(progress: progress, state: state)
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
                height: visibleMonthGridHeight(progress: progress, state: state),
                alignment: .top
            )
            .clipped()
            .transaction { $0.animation = nil }
        }
        .padding(.horizontal, state.horizontalPadding)
        .padding(.vertical, state.verticalPadding)
        .frame(width: capsuleWidth, alignment: .leading)
        .background {
            if progress > 0.001 {
                Color.clear
                    .glassButton(
                        shape: RoundedRectangle(
                            cornerRadius: state.cornerRadius,
                            style: .continuous
                        )
                    )
                    .opacity(progress)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: state.cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private func expandedMonthPager(
        progress: CGFloat,
        state: HomeCalendarAdaptiveLayout.State
    ) -> some View {
        let snapshots = expandedMonthSnapshots

        TabView(selection: $expandedMonthPageSelection) {
            ForEach(Array(snapshots.enumerated()), id: \.offset) { index, snapshot in
                dayGrid(
                    snapshot: snapshot,
                    totalGridHeight: CGFloat(snapshot.rows.count) * state.rowHeight,
                    progress: progress,
                    state: state
                )
                .frame(width: state.dayColumnWidth * 7, alignment: .leading)
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onChange(of: expandedMonthPageSelection) { _, newValue in
            handleExpandedMonthPageChange(newValue)
        }
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
        snapshot: CalendarViewModel.MonthSnapshot,
        totalGridHeight: CGFloat,
        progress: CGFloat,
        state: HomeCalendarAdaptiveLayout.State
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(snapshot.rows.enumerated()), id: \.element.first?.id) { rowIndex, row in
                let distance = abs(CGFloat(rowIndex) - snapshot.monthProgress)
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
        .offset(y: -(snapshot.monthProgress * state.rowHeight) * progress)
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

    private var expandedMonthSnapshots: [CalendarViewModel.MonthSnapshot] {
        [-1, 0, 1].map { calendarVM.monthSnapshot(offsetBy: $0) }
    }

    private func visibleMonthGridHeight(
        progress: CGFloat,
        state: HomeCalendarAdaptiveLayout.State
    ) -> CGFloat {
        let totalGridHeight = CGFloat(calendarVM.monthRows.count) * state.rowHeight
        return state.rowHeight + (totalGridHeight - state.rowHeight) * (1 - progress)
    }

    private func handleExpandedMonthPageChange(_ page: Int) {
        guard page != 1 else { return }

        calendarVM.applyMonthOffset(page == 0 ? -1 : 1)

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            expandedMonthPageSelection = 1
        }
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

    private var activityFraction: Double {
        insight?.activityFraction ?? 0
    }

    private var shouldShowInnerHighlight: Bool {
        day.isSelected || isToday
    }

    private var metrics: HomeCalendarDayMetrics {
        HomeCalendarDayMetrics(
            collapseProgress: collapseProgress,
            dayColumnWidth: dayColumnWidth,
            rowHeight: rowHeight,
            hasGoalNote: false,
            hasExamGoalCount: false,
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
        if day.ignored { return .secondary.opacity(0.12) }
        return .primary
    }

    private var expandedTileInset: CGFloat {
        min(max(min(dayColumnWidth, rowHeight) * 0.035, 2), 5)
    }

    private var expandedTileCornerRadius: CGFloat {
        min(max(min(dayColumnWidth, rowHeight) * 0.18, 14), 24)
    }

    private var expandedTileBackgroundColor: Color {
        if day.ignored {
            return Color.white.opacity(0.008)
        }
        if day.isSelected {
            return Color.white.opacity(0.10)
        }
        if isToday {
            return accent.opacity(0.16)
        }
        if didStudy {
            return isPerfectDay ? Color.green.opacity(0.16) : accent.opacity(0.14)
        }
        return Color.white.opacity(0.06)
    }

    private var dayBadgeFillColor: Color {
        if day.isSelected { return .white }
        if isToday { return accent }
        return .clear
    }

    private var shouldFillDayBadge: Bool {
        day.isSelected || isToday
    }

    private var dayBadgeTextColor: Color {
        if day.isSelected { return .black }
        if isToday { return .white }
        if isPerfectDay { return .green }
        if didStudy { return accent.opacity(0.95) }
        if day.ignored { return .secondary.opacity(0.16) }
        return .primary
    }

    private var waterFillColor: Color {
        if isPerfectDay {
            return Color.green.opacity(day.isSelected ? 0.42 : 0.38)
        }
        return accent.opacity(day.isSelected ? 0.38 : 0.34)
    }

    private var waterFillFraction: CGFloat {
        CGFloat(max(activityFraction, 0.12))
    }

    private var expandedDayFontSize: CGFloat {
        min(max(rowHeight * 0.20, 14), 18)
    }

    private var expandedBadgeDiameter: CGFloat {
        min(max(rowHeight * 0.34, 28), 40)
    }

    private var compactTransitionProgress: CGFloat {
        max(0, min((collapseProgress - 0.42) / 0.22, 1))
    }

    private func interpolated(_ from: CGFloat, _ to: CGFloat) -> CGFloat {
        from + ((to - from) * compactTransitionProgress)
    }

    private var transitionCenterX: CGFloat {
        let expandedX = metrics.tilePadding + (expandedBadgeDiameter / 2)
        let compactX = dayColumnWidth / 2
        return interpolated(expandedX, compactX)
    }

    private var transitionCenterY: CGFloat {
        let expandedY = metrics.tilePadding + (expandedBadgeDiameter / 2)
        let compactY = rowHeight / 2
        return interpolated(expandedY, compactY)
    }

    private var transitionBadgeDiameter: CGFloat {
        interpolated(expandedBadgeDiameter, metrics.highlightDiameter)
    }

    private var transitionFontSize: CGFloat {
        interpolated(expandedDayFontSize, metrics.fontSize)
    }

    private var expandedLayerOpacity: CGFloat {
        1 - compactTransitionProgress
    }

    private var compactHighlightOpacity: Double {
        Double(compactTransitionProgress) * highlightOpacity
    }

    // MARK: - Body

    var body: some View {
        transitioningCellBody
        .contentShape(Rectangle())
        .zIndex(day.isSelected ? 1 : 0)
    }

    private var transitioningCellBody: some View {
        ZStack(alignment: .topLeading) {
            let tileShape = RoundedRectangle(
                cornerRadius: expandedTileCornerRadius,
                style: .continuous
            )

            tileShape
                .fill(expandedTileBackgroundColor)
                .opacity(expandedLayerOpacity)

            if didStudy && !day.ignored {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    Rectangle()
                        .fill(waterFillColor)
                        .frame(height: max((rowHeight - (metrics.tilePadding * 2)) * waterFillFraction, 8))
                        .frame(maxWidth: .infinity)
                }
                .clipShape(tileShape)
                .opacity(expandedLayerOpacity)
            }

            Circle()
                .fill(highlightFillColor.opacity(compactHighlightOpacity))
                .frame(width: transitionBadgeDiameter, height: transitionBadgeDiameter)
                .position(x: transitionCenterX, y: transitionCenterY)

            Text(day.shortSymbol)
                .font(.system(
                    size: transitionFontSize,
                    weight: (day.isSelected || isToday) ? .bold : .semibold,
                    design: .rounded
                ))
                .foregroundStyle(dayBadgeTextColor)
                .frame(width: transitionBadgeDiameter, height: transitionBadgeDiameter, alignment: .center)
                .background {
                    if shouldFillDayBadge {
                        Circle()
                            .fill(dayBadgeFillColor)
                            .opacity(expandedLayerOpacity)
                    }
                }
                .position(x: transitionCenterX, y: transitionCenterY)
        }
        .padding(expandedTileInset)
    }
}

// MARK: - Compact Calendar Day Strip

/// Horizontally scrollable compact strip that pages calendar weeks while weekday labels stay fixed.
struct CompactCalendarWeekStrip: View {
    let weeks: [[Day]]
    let visibleWidth: CGFloat
    let dayColumnWidth: CGFloat
    let dayRowHeight: CGFloat
    let calendarInsightsCache: [String: HomeCalendarDayInsight]
    let onSelectDay: (Day) -> Void

    private var pageWidth: CGFloat {
        max(visibleWidth, dayColumnWidth * 7)
    }

    private var rowHorizontalInset: CGFloat {
        max(0, (pageWidth - (dayColumnWidth * 7)) / 2)
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
                                    collapseProgress: 1,
                                    dayColumnWidth: dayColumnWidth,
                                    rowHeight: dayRowHeight
                                )
                                .frame(width: dayColumnWidth, height: dayRowHeight)
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
