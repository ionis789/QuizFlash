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

    // MARK: - Dependencies

    /// The view model managing date selection and grid data.
    var calendarVM: CalendarViewModel

    /// Maximum height of the header when fully expanded.
    let extendedHeight: CGFloat

    /// Total scrollable distance required to fully collapse the header.
    let scrollDistance: CGFloat

    /// Top safe-area inset used to compute absolute anchor points.
    let safeAreaTop: CGFloat

    /// O(1) lookup dictionary providing daily activity data keyed by `yyyy-MM-dd`.
    let logsCache: [String: DailyActivityLog]

    /// The global navigation router (passed to `HomeAvatarView`).
    let router: NavigationManager

    // MARK: - Private Constants

    /// Fixed dimension for the profile avatar button.
    private let iconSize: CGFloat = UIConstants.Size.actionButton

    // MARK: - Body

    var body: some View {
        GeometryReader { proxy in

            // MARK: Scroll Metrics

            let minY = proxy.frame(in: .scrollView(axis: .vertical)).minY

            /// Normalised collapse progress: 0.0 = fully expanded, 1.0 = fully compact.
            let progress = max(0, min(-minY / scrollDistance, 1.0))

            /// Vertical offset applied to keep the entire header pinned to the screen top.
            let stickyOffset: CGFloat = minY < 0 ? -minY : 0

            // MARK: Grid Geometry

            let containerWidth = proxy.size.width - (UIConstants.Layout.screenEdgeInset * 2)
            let naturalEmptySpace = containerWidth * 0.10
            let targetSpace = iconSize + UIConstants.Layout.screenEdgeInset
            let requiredPush = max(0, (targetSpace - naturalEmptySpace) / 0.9)

            // MARK: Avatar Absolute Positioning

            let expandedCenterY  = safeAreaTop + calendarVM.topPaddingExpanded  + (calendarVM.titleHeight / 2.0)
            let collapsedCenterY = safeAreaTop + calendarVM.topPaddingCollapsed + (calendarVM.weekLabelHeight + calendarVM.rowHeight) / 2.0
            let currentCenterY   = expandedCenterY - ((expandedCenterY - collapsedCenterY) * progress)
            let avatarAbsoluteTop = currentCenterY - (iconSize / 2.0)

            // MARK: Render Tree

            ZStack(alignment: .topTrailing) {

                // LAYER 1: Content & Background
                VStack(spacing: 0) {
                    Spacer().frame(height: safeAreaTop)

                    VStack(spacing: 0) {
                        titleRow(progress: progress)
                        calendarGrid(progress: progress, requiredPush: requiredPush)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
                .padding(.top, calendarVM.topPaddingExpanded - (calendarVM.topPaddingExpanded - calendarVM.topPaddingCollapsed) * progress)
                .padding(.bottom, calendarVM.bottomPadding)
                .shadow(color: .black.opacity(0.08 * progress), radius: 10, y: 4)

                // LAYER 2: Absolute Avatar (floats independently of the content stack)
                HomeAvatarView(router: router)
                    .padding(.trailing, UIConstants.Layout.screenEdgeInset)
                    .padding(.top, avatarAbsoluteTop)
            }
            .offset(y: stickyOffset)
        }
        .frame(height: extendedHeight)
    }

    // MARK: - Subviews

    /// Renders the month and year title row, flanked by navigation chevrons.
    ///
    /// Fades out and collapses vertically as `progress` approaches 1.0 (fully compact).
    @ViewBuilder
    private func titleRow(progress: CGFloat) -> some View {
        ZStack {
            Text(calendarVM.currentMonthString + " " + calendarVM.yearString)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.trailing, iconSize + 8)

            // Invisible anchor text maintains symmetric chevron spacing
            // regardless of the variable month string width.
            HStack(spacing: 8) {
                chevronButton(increment: false)

                Text(calendarVM.currentMonthString + " " + calendarVM.yearString)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .fixedSize()
                    .foregroundStyle(.clear)
                    .accessibilityHidden(true)

                chevronButton(increment: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.trailing, iconSize + 8)
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
    private func calendarGrid(progress: CGFloat, requiredPush: CGFloat) -> some View {
        let totalGridHeight = CGFloat(calendarVM.monthRows.count) * calendarVM.rowHeight

        VStack(spacing: 0) {
            weekdayLabels

            ZStack(alignment: .top) {
                dayGrid(totalGridHeight: totalGridHeight, progress: progress)
            }
            .frame(
                height: calendarVM.rowHeight + (totalGridHeight - calendarVM.rowHeight) * (1 - progress),
                alignment: .top
            )
            .clipped()
        }
        .padding(7 * progress)
        .padding(.horizontal, 12 * progress)
        .background {
            RoundedRectangle(cornerRadius: 30)
                .fill(.ultraThinMaterial.opacity(progress))
        }
        .padding(.trailing, requiredPush * progress)
        .scaleEffect(1 - 0.10 * progress, anchor: .topLeading)
        .clipped()
    }

    /// A horizontal row displaying abbreviated weekday symbols (e.g., Sun, Mon).
    private var weekdayLabels: some View {
        HStack(spacing: 0) {
            ForEach(Calendar.current.shortWeekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: 12, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: calendarVM.weekLabelHeight, alignment: .center)
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
                        CalendarDayCellView(day: day, log: logsCache[day.dateString])
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

    /// A circular button for advancing or rewinding the displayed month.
    ///
    /// - Parameter increment: `true` to move forward one month, `false` to go back.
    private func chevronButton(increment: Bool) -> some View {
        Button {
            calendarVM.monthUpdate(increment: increment)
        } label: {
            Image(systemName: increment ? "chevron.right" : "chevron.left")
                .font(.system(size: UIConstants.Size.actionIcon, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: UIConstants.Size.actionButton, height: UIConstants.Size.actionButton)
                .glassButton(shape: .circle)
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

    // MARK: - Input

    let day: Day
    let log: DailyActivityLog?

    // MARK: - Computed States

    private var isToday: Bool {
        Calendar.current.isDateInToday(day.date)
    }

    /// `true` when the day had study activity.
    ///
    /// Excludes today to prevent premature productivity styling before the session ends.
    private var isProductiveDay: Bool {
        !isToday && (log?.cardsReviewed ?? 0) > 0
    }

    /// The active theme accent colour, resolved from `ThemeManager`.
    private var accent: Color {
        ThemeManager.shared.accentColor.color
    }

    // MARK: - Styling

    private var backgroundColor: Color {
        if isToday          { return accent }
        if isProductiveDay  { return .green }
        if day.isSelected   { return .primary }
        return .clear
    }

    private var backgroundOpacity: Double {
        if day.isSelected   { return 1.0 }
        if isToday          { return 0.15 }
        if isProductiveDay  { return 0.15 }
        return 0
    }

    private var textColor: Color {
        if day.isSelected && (isProductiveDay || isToday) { return .white }
        if day.isSelected   { return Color(uiColor: .systemBackground) }
        if isToday          { return accent }
        if isProductiveDay  { return .green }
        if day.ignored      { return .secondary.opacity(0.3) }
        return .primary
    }

    // MARK: - Body

    var body: some View {
        Text(day.shortSymbol)
            .font(.system(
                size: 16,
                weight: (day.isSelected || isToday) ? .bold : .medium,
                design: .rounded
            ))
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                Circle()
                    .fill(backgroundColor.opacity(backgroundOpacity))
                    .frame(width: 40, height: 40)
            }
            .contentShape(Rectangle())
    }
}
