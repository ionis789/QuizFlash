// CalendarSectionView.swift
// QuizFlash
//
// Created by QuizFlash.
//

import SwiftUI

// MARK: - Calendar Section

/// A sticky, collapsible calendar header that seamlessly transitions from an expanded month grid
/// to a compact weekly row during vertical scrolling.
///
/// Architecture notes:
/// - Utilizes an absolute Z-axis layering system to prevent layout recalculation jumps (jank) during rapid scrolling.
/// - Employs a static background composition to ensure zero memory leaks when rendering `.ultraThinMaterial`.
struct CalendarSectionView: View {

    // MARK: - Dependencies

    /// The view model managing date selection and grid data generation.
    var calendarVM: CalendarViewModel

    /// The maximum height of the header when fully expanded.
    let extendedHeight: CGFloat

    /// The total scrollable distance required to fully collapse the header.
    let scrollDistance: CGFloat

    /// The top safe area inset used to compute absolute anchor points.
    let safeAreaTop: CGFloat

    /// A dictionary providing O(1) access to daily activity data.
    let logsCache: [String: DailyActivityLog]

    /// The global navigation router.
    let router: NavigationManager

    // MARK: - Layout Constants

    /// The fixed dimension for the profile avatar button.
    private let iconSize: CGFloat = 54.0

    // MARK: - Body

    // MARK: - Body

    var body: some View {
        GeometryReader { proxy in

            // MARK: Scroll Metrics

            let minY = proxy.frame(in: .scrollView(axis: .vertical)).minY

            /// Normalized collapse progress where 0.0 is fully expanded and 1.0 is fully compact.
            let progress = max(0, min(-minY / scrollDistance, 1.0))

            /// Vertical offset applied to keep the entire header pinned to the top.
            let stickyOffset: CGFloat = minY < 0 ? -minY : 0

            // MARK: Grid Geometry

            let containerWidth = proxy.size.width - 40
            let naturalEmptySpace = containerWidth * 0.10
            let targetSpace = iconSize + 20

            let requiredPush = max(0, (targetSpace - naturalEmptySpace) / 0.9)

            // MARK: Avatar Absolute Positioning

            let expandedCenterY = safeAreaTop + calendarVM.topPaddingExpanded + (calendarVM.titleHeight / 2.0)
            let collapsedCenterY = safeAreaTop + calendarVM.topPaddingCollapsed + (calendarVM.weekLabelHeight + calendarVM.rowHeight) / 2.0

            let currentCenterY = expandedCenterY - ((expandedCenterY - collapsedCenterY) * progress)
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

                    .padding(.horizontal, 20)
                    .padding(.top, calendarVM.topPaddingExpanded - (calendarVM.topPaddingExpanded - calendarVM.topPaddingCollapsed) * progress)
                    .padding(.bottom, calendarVM.bottomPadding)
                // 3. Dynamic drop shadow based strictly on scroll distance
                .shadow(color: .black.opacity(0.08 * progress), radius: 10, y: 4)

                // LAYER 2: Absolute Avatar
                avatarButton
                    .padding(.trailing, 20)
                    .padding(.top, avatarAbsoluteTop)
            }
                .offset(y: stickyOffset)
        }
            .frame(height: extendedHeight)
    }

    // MARK: - Subviews

    /// Renders the month and year title row, flanked by navigation chevrons.
    /// Fades out and collapses vertically as `progress` approaches 1.0.
    @ViewBuilder
    private func titleRow(progress: CGFloat) -> some View {
        ZStack {
            Text(calendarVM.currentMonthString + " " + calendarVM.yearString)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.trailing, iconSize + 8)

            // Navigation chevrons use an invisible anchor text to maintain symmetric
            // spacing regardless of the month string's width.
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

    /// The full month grid. Rows outside the selected week fade out based on their
    /// vertical distance from the active row during the collapse animation.
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

    /// A circular navigation button for advancing or rewinding the displayed month.
    private func chevronButton(increment: Bool) -> some View {
        Button {
            calendarVM.monthUpdate(increment: increment)
        } label: {
            Image(systemName: increment ? "chevron.right" : "chevron.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(Color.primary.opacity(0.06), in: Circle())
        }
    }

    /// A circular avatar button that navigates to the Settings screen.
    private var avatarButton: some View {
        Button {
            router.append(AppRoute.settings)
        } label: {
            ZStack {
                Circle()
                    .fill(Color(uiColor: .systemBackground))
                    .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)

                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)

                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(Color.primary.opacity(0.85))
                    .padding(2.5)
            }
                .frame(width: iconSize, height: iconSize)
        }
    }
}

// MARK: - Calendar Day Cell

/// Renders a single day cell in the calendar grid.
/// Handles visual state mapping for today, productivity streaks, and selection.
struct CalendarDayCellView: View {

    // MARK: - Properties

    let day: Day
    let log: DailyActivityLog?

    // MARK: - Computed States

    private var isToday: Bool {
        Calendar.current.isDateInToday(day.date)
    }

    /// Evaluates if the day had study activity. Excludes 'today' to prevent premature productivity styling.
    private var isProductiveDay: Bool {
        !isToday && (log?.cardsReviewed ?? 0) > 0
    }

    private var accent: Color {
        ThemeManager.shared.accentColor.color
    }

    // MARK: - Styling

    private var backgroundColor: Color {
        if isToday { return accent }
        if isProductiveDay { return .green }
        if day.isSelected { return .primary }
        return .clear
    }

    private var backgroundOpacity: Double {
        if day.isSelected { return 1.0 }
        if isToday { return 0.15 }
        if isProductiveDay { return 0.15 }
        return 0
    }

    private var textColor: Color {
        if day.isSelected && (isProductiveDay || isToday) { return .white }
        if day.isSelected { return Color(uiColor: .systemBackground) }
        if isToday { return accent }
        if isProductiveDay { return .green }
        if day.ignored { return .secondary.opacity(0.3) }
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
