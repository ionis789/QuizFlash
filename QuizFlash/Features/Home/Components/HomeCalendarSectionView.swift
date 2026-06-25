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
    @Environment(ThemeManager.self) private var themeManager

    // MARK: - Dependencies

    /// The view model managing date selection and grid data.
    var calendarVM: CalendarViewModel

    /// Width-aware layout metrics shared with `HomeView`.
    let layout: HomeCalendarAdaptiveLayout

    /// O(1) lookup dictionary providing per-day progress and marker insights.
    let calendarInsightsCache: [String: HomeCalendarDayInsight]
    let calendarInsightsRevision: Int
    let blurConfiguration: ScreenTopProgressiveBlurConfiguration
    let blurHeightOffset: CGFloat
    let blurColor: Color
    let blurEnabled: Bool

    init(
        calendarVM: CalendarViewModel,
        layout: HomeCalendarAdaptiveLayout,
        calendarInsightsCache: [String: HomeCalendarDayInsight],
        calendarInsightsRevision: Int,
        blurConfiguration: ScreenTopProgressiveBlurConfiguration = .quizFlashDefault,
        blurHeightOffset: CGFloat = 0,
        blurColor: Color = EdgeShadowDebugSettings.default.resolvedColor,
        blurEnabled: Bool = true
    ) {
        self.calendarVM = calendarVM
        self.layout = layout
        self.calendarInsightsCache = calendarInsightsCache
        self.calendarInsightsRevision = calendarInsightsRevision
        self.blurConfiguration = blurConfiguration
        self.blurHeightOffset = blurHeightOffset
        self.blurColor = blurColor
        self.blurEnabled = blurEnabled
    }

    // MARK: - Private Constants

    // MARK: - Body

    var body: some View {
        GeometryReader { proxy in
            let minY = proxy.frame(in: .scrollView(axis: .vertical)).minY
            let progress = max(0, min(-minY / layout.scrollDistance, 1.0))
            let stickyOffset: CGFloat = minY < 0 ? -minY : 0
            let state = layout.state(for: progress)
            let calendarColumnWidth = layout.capsuleWidth(for: progress)
            let contentLeadingInset = layout.contentLeadingInset(for: progress)

            ZStack(alignment: .topLeading) {
                persistentHeaderBlur()
                    .offset(y: stickyOffset)

                stickyHeaderContent(
                    progress: progress,
                    state: state,
                    calendarColumnWidth: calendarColumnWidth,
                    contentLeadingInset: contentLeadingInset
                )
                    .offset(y: stickyOffset)
            }
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
                .foregroundStyle(themeManager.roleColor(.buttonPrimaryFill))
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            monthNavigationControl(
                size: state.monthControlSize,
                spacing: state.monthControlSpacing
            )
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

    @ViewBuilder
    private func stickyHeaderContent(
        progress: CGFloat,
        state: HomeCalendarAdaptiveLayout.State,
        calendarColumnWidth: CGFloat,
        contentLeadingInset: CGFloat
    ) -> some View {
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
    }

    @ViewBuilder
    private func persistentHeaderBlur() -> some View {
        let baseBlurHeight = layout.safeAreaTop
            + layout.compactCapsuleHeight
            + 15
        let blurHeight = baseBlurHeight
            + blurHeightOffset

        if blurEnabled {
            TopProgressiveBlurOverlay(
                topHeight: blurHeight,
                revealProgress: 1,
                tintColor: blurColor,
                configuration: blurConfiguration,
                revealAnimation: nil
            )
                .allowsHitTesting(false)
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
        let usesMonthSwipe = progress < 0.001
        let visibleGridWidth = state.dayColumnWidth * 7
        let capsuleWidth = layout.capsuleWidth(for: progress)
        let calendarTrack = Group {
            if usesMonthSwipe {
                ExpandedMonthPagerHost(
                    snapshots: calendarVM.adjacentMonthSnapshots(),
                    progress: progress,
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
            } else {
                dayGrid(
                    totalGridHeight: totalGridHeight,
                    progress: progress,
                    state: state
                )
            }
        }
            .frame(width: visibleGridWidth, alignment: .leading)
            .frame(
            height: state.rowHeight + (totalGridHeight - state.rowHeight) * (1 - progress),
            alignment: .top
        )
            .clipped()
            .transaction { $0.animation = nil }

        let gridContent = VStack(spacing: 0) {
            weekdayLabels(state: state)
                .frame(width: visibleGridWidth, alignment: .leading)

            calendarTrack
        }
            .padding(.horizontal, state.horizontalPadding)
            .padding(.vertical, state.verticalPadding)
            .frame(width: capsuleWidth, alignment: .leading)
        gridContent
    }

    /// A horizontal row displaying abbreviated weekday symbols (e.g., Sun, Mon).
    private func weekdayLabels(state: HomeCalendarAdaptiveLayout.State) -> some View {
        HStack(spacing: 0) {
            ForEach(calendarVM.orderedWeekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: state.weekdayFontSize, weight: .bold, design: .rounded))
                    .frame(width: state.dayColumnWidth)
                    .foregroundStyle(.secondary)
            }
        }
            .frame(height: state.weekLabelHeight, alignment: .center)
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
        monthGridPage(
            rows: calendarVM.monthRows,
            selectedMonthProgress: calendarVM.monthProgress,
            totalGridHeight: totalGridHeight,
            progress: progress,
            state: state
        )
        .offset(y: -(calendarVM.monthProgress * state.rowHeight) * progress)
        .transaction { $0.animation = nil }
    }

    private func monthGridPage(
        rows: [[Day]],
        selectedMonthProgress: CGFloat,
        totalGridHeight: CGFloat,
        progress: CGFloat,
        state: HomeCalendarAdaptiveLayout.State
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.first?.id) { rowIndex, row in
                let distance = abs(CGFloat(rowIndex) - selectedMonthProgress)
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
                .transaction { $0.animation = nil }
            }
        }
        .frame(height: totalGridHeight, alignment: .top)
    }

    private func monthNavigationControl(size: CGFloat, spacing: CGFloat) -> some View {
        if size <= 0.1 {
            return AnyView(EmptyView())
        }

        let buttonDiameter = max(size * 1.28, 30)
        let buttonSpacing = max(spacing + 6, 12)
        let totalWidth = (buttonDiameter * 2) + buttonSpacing

        return AnyView(
            HStack(spacing: buttonSpacing) {
                monthChevronButton(
                    systemName: "chevron.compact.left",
                    size: buttonDiameter,
                    action: { calendarVM.monthUpdate(increment: false) }
                )

                monthChevronButton(
                    systemName: "chevron.compact.right",
                    size: buttonDiameter,
                    action: { calendarVM.monthUpdate(increment: true) }
                )
            }
            .frame(width: totalWidth, height: buttonDiameter)
        )
    }

    private func monthChevronButton(
        systemName: String,
        size: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        return Button {
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: size * 0.58, weight: .black, design: .rounded))
                .foregroundStyle(themeManager.roleColor(.circularToolbarForeground))
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
            .buttonStyle(.plain)
    }

}
// MARK: - Calendar Day Cell View

/// Renders a single day cell in the calendar grid.
///
/// Handles visual state mapping for today, productive study days, and the selected date.
/// Colours come exclusively from `ThemeManager` or semantic SwiftUI tokens.
struct CalendarDayCellView: View {
    @Environment(ThemeManager.self) private var themeManager

    // MARK: - Input

    let day: Day
    let insight: HomeCalendarDayInsight?
    let collapseProgress: CGFloat
    let dayColumnWidth: CGFloat
    let rowHeight: CGFloat

    // MARK: - Computed States

    private var isToday: Bool {
        day.isToday
    }

    private var usesCompactCapsulePresentation: Bool {
        collapseProgress >= 0.995
    }

    /// The active theme accent colour, resolved from `ThemeManager`.
    private var accent: Color {
        themeManager.roleColor(.buttonPrimaryFill)
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

    private var metrics: HomeCalendarDayMetrics {
        HomeCalendarDayMetrics(
            collapseProgress: collapseProgress,
            dayColumnWidth: dayColumnWidth,
            rowHeight: rowHeight,
            isHighlighted: day.isSelected || isToday || didStudy
        )
    }

    // MARK: - Styling

    private var tileFillColor: Color {
        if day.ignored { return usesCompactCapsulePresentation ? themeManager.roleColor(.widgetSurfaceFill) : .clear }
        if day.isSelected { return .white }
        if isToday { return accent }
        if isPerfectDay { return .green.opacity(0.88) }
        if didStudy { return accent }
        return themeManager.roleColor(.widgetSurfaceFill)
    }

    private var tileFillOpacity: Double {
        if day.ignored { return usesCompactCapsulePresentation ? 1 : 0 }
        return 1.0
    }

    private var textColor: Color {
        if day.ignored {
            return usesCompactCapsulePresentation ? themeManager.textSecondary.opacity(0.65) : .secondary.opacity(0.3)
        }
        if day.isSelected { return themeManager.screenBackground }
        if isToday || didStudy { return themeManager.screenBackground }
        if isPerfectDay { return themeManager.screenBackground }
        return themeManager.textPrimary
    }

    private var tileSize: CGFloat {
        if day.ignored && !usesCompactCapsulePresentation { return 0 }
        let cellMinDimension = min(dayColumnWidth, rowHeight)
        let scale: CGFloat = cellMinDimension >= 72 ? 0.62 : 0.70
        return max(cellMinDimension * scale, 0)
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
            .contentShape(Rectangle())
            .zIndex(day.isSelected ? 1 : 0)
    }
}
