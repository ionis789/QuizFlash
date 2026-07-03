//
//  HomeTopHeaderSectionView.swift
//  QuizFlash
//
//  Coordinated iPad Home top header with a sticky Today Focus companion and calendar.
//

import SwiftUI

// MARK: - Home Top Header Section View

/// iPad-only Home top header with a sticky calendar and a static weekly momentum companion.
struct HomeTopHeaderSectionView: View {
    let calendarVM: CalendarViewModel
    let layout: HomeCalendarAdaptiveLayout
    let calendarInsightsCache: [String: HomeCalendarDayInsight]
    let weeklyMomentumSummary: HomeWeeklyMomentumSummary
    let router: NavigationManager

    var body: some View {
        GeometryReader { proxy in
            let minY = proxy.frame(in: .scrollView(axis: .vertical)).minY
            let progress = max(0, min(-minY / layout.scrollDistance, 1.0))
            let stickyOffset: CGFloat = minY < 0 ? -minY : 0
            let headerState = layout.topHeaderState(for: progress, stickyOffset: stickyOffset)

            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: layout.safeAreaTop)

                    HomePadCalendarColumnView(
                        calendarVM: calendarVM,
                        layout: layout,
                        calendarInsightsCache: calendarInsightsCache,
                        headerState: headerState
                    )
                    .frame(width: headerState.calendarWidth, alignment: .leading)
                    .padding(.leading, layout.outerHorizontalInset)
                    .padding(.top, headerState.calendarState.topPadding)
                    .offset(y: headerState.stickyOffset)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                HomeWeeklyMomentumHeaderView(
                    summary: weeklyMomentumSummary,
                    layout: layout
                )
                .frame(
                    width: layout.expandedCompanionWidth,
                    height: layout.expandedContentHeight,
                    alignment: .topLeading
                )
                .padding(.leading, layout.outerHorizontalInset + layout.expandedCalendarWidth + layout.expandedColumnSpacing)
                .padding(.top, layout.safeAreaTop + layout.expanded.topPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                HomeAvatarView(router: router, iconSize: layout.avatarSize)
                    .padding(.trailing, layout.outerHorizontalInset)
                    .padding(.top, headerState.avatarTop)
                    .offset(y: headerState.stickyOffset)
            }
        }
        .frame(height: layout.extendedHeight)
    }
}

// MARK: - Weekly Momentum Header View

/// Static weekly momentum companion shown to the right of the Home calendar.
struct HomeWeeklyMomentumHeaderView: View {
    let summary: HomeWeeklyMomentumSummary
    let layout: HomeCalendarAdaptiveLayout

    private enum CompanionMode {
        case condensed
        case regular
    }

    private var tintColor: Color {
        ThemeManager.shared.accentColor.color
    }

    private var compactHeadline: String {
        "\(summary.activeDays)/7"
    }

    private var companionMode: CompanionMode {
        layout.expandedCompanionWidth < 240 ? .condensed : .regular
    }

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            switch companionMode {
            case .condensed:
                condensedCompanionBody
            case .regular:
                regularCompanionBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var regularCompanionBody: some View {
        let titleFontSize = max(layout.expanded.titleFontSize - 1, 22)
        let titleHeight = layout.expanded.titleHeight
        let titleBottomSpacing = layout.expanded.titleBottomSpacing
        let contentWidth = min(max(layout.expandedCompanionWidth - 16, 0), 440)

        return VStack(alignment: .center, spacing: 0) {
            Text("Weekly Momentum")
                .font(.system(size: titleFontSize, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .frame(
                    maxWidth: .infinity,
                    minHeight: titleHeight,
                    maxHeight: titleHeight,
                    alignment: .center
                )
                .padding(.bottom, max(titleBottomSpacing - 6, 6))

            Text(compactHeadline)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .multilineTextAlignment(.center)

            Spacer(minLength: 16)

            VStack(alignment: .center, spacing: 24) {
                HStack(alignment: .bottom, spacing: 12) {
                    ForEach(summary.daySummaries) { day in
                        HomeWeeklyMomentumHeaderBar(day: day, accentColor: tintColor)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .animation(.snappy(duration: 0.34, extraBounce: 0.08), value: summary.daySummaries)

                HStack(spacing: 0) {
                    HomeTopHeaderStatLine(
                        label: "Cards",
                        value: "\(summary.totalCardsReviewed)",
                        tint: tintColor
                    )
                    HomeTopHeaderStatLine(
                        label: "XP",
                        value: "\(summary.totalXPEarned)",
                        tint: .orange
                    )

                    if let bestDayLabel = summary.bestDayLabel {
                        HomeTopHeaderStatLine(
                            label: "Best",
                            value: bestDayLabel,
                            tint: .green
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .frame(width: contentWidth, alignment: .center)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var condensedCompanionBody: some View {
        let companionWidth = max(layout.expandedCompanionWidth - 8, 0)
        let barSpacing: CGFloat = 4
        let barWidth = max(min((companionWidth - (barSpacing * 6)) / 7, 16), 10)

        return VStack(alignment: .center, spacing: 12) {
            Text("Momentum")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(compactHeadline)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            HStack(alignment: .bottom, spacing: barSpacing) {
                ForEach(summary.daySummaries) { day in
                    HomeWeeklyMomentumHeaderBar(
                        day: day,
                        accentColor: tintColor,
                        barWidth: barWidth,
                        showsLabels: false
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            VStack(alignment: .center, spacing: 6) {
                condensedStatLine(label: "Cards", value: "\(summary.totalCardsReviewed)", tint: tintColor)
                condensedStatLine(label: "XP", value: "\(summary.totalXPEarned)", tint: .orange)

                if let bestDayLabel = summary.bestDayLabel {
                    condensedStatLine(label: "Best", value: bestDayLabel, tint: .green)
                }
            }
        }
        .frame(width: companionWidth, alignment: .center)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func condensedStatLine(label: String, value: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct HomeWeeklyMomentumHeaderBar: View {
    let day: HomeWeeklyDaySummary
    let accentColor: Color
    var barWidth: CGFloat = 34
    var showsLabels: Bool = true

    private var fillColor: Color {
        if day.didReachGoal { return .green }
        if day.isSelectedDay { return accentColor }
        if day.didStudy { return accentColor.opacity(0.65) }
        return .secondary.opacity(0.22)
    }

    private var barHeight: CGFloat {
        let baseHeight: CGFloat = showsLabels ? 30 : 24
        let variableHeight: CGFloat = showsLabels ? 52 : 34
        return baseHeight + (variableHeight * day.intensityFraction)
    }

    private var borderColor: Color {
        if day.isToday { return accentColor.opacity(0.9) }
        if day.isSelectedDay { return Color.white.opacity(0.42) }
        return .clear
    }

    private var borderWidth: CGFloat {
        if day.isToday { return 2 }
        if day.isSelectedDay { return 1.25 }
        return 0
    }

    var body: some View {
        VStack(spacing: showsLabels ? 10 : 6) {
            if showsLabels {
                Text(day.shortWeekday)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(day.isSelectedDay ? .primary : .secondary)
            }

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(fillColor)
                .frame(width: barWidth, height: barHeight)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: borderWidth)
                }

            if showsLabels {
                Text("\(day.cardsReviewed)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .animation(.snappy(duration: 0.34, extraBounce: 0.08), value: day.intensityFraction)
        .animation(.snappy(duration: 0.34, extraBounce: 0.08), value: day.isSelectedDay)
    }
}

private struct HomeTopHeaderStatLine: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - iPad Calendar Column

/// Left-side calendar column used by the coordinated iPad Home header.
private struct HomePadCalendarColumnView: View {
    @Environment(ThemeManager.self) private var themeManager
    @State private var isMonthTransitionAnimating = false
    @State private var monthTransitionDirection = 1

    let calendarVM: CalendarViewModel
    let layout: HomeCalendarAdaptiveLayout
    let calendarInsightsCache: [String: HomeCalendarDayInsight]
    let headerState: HomeTopHeaderLayoutState

    private var monthTransitionAnimation: Animation {
        .easeInOut(duration: 0.24)
    }

    private var monthGridTransition: AnyTransition {
        let insertionEdge: Edge = monthTransitionDirection >= 0 ? .trailing : .leading
        let removalEdge: Edge = monthTransitionDirection >= 0 ? .leading : .trailing

        return .asymmetric(
            insertion: .move(edge: insertionEdge),
            removal: .move(edge: removalEdge)
        )
    }

    private var compactWeekPages: [[Day]] {
        calendarVM.monthRows
    }

    var body: some View {
        VStack(spacing: 0) {
            titleRow

            calendarGrid
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var titleRow: some View {
        let fadeStart: CGFloat = 0.84
        let fadeEnd: CGFloat = 0.998
        let rawFadeProgress = min(max((headerState.progress - fadeStart) / (fadeEnd - fadeStart), 0), 1)
        let fadeProgress = pow(rawFadeProgress, 2.6)

        return HStack(alignment: .center, spacing: headerState.calendarState.monthControlSpacing) {
            Text(calendarVM.currentMonthString + " " + calendarVM.yearString)
                .font(.system(size: headerState.calendarState.titleFontSize, weight: .black))
                .foregroundStyle(themeManager.textPrimary.opacity(0.92))
                .textCase(.uppercase)
                .tracking(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            HStack(spacing: headerState.calendarState.monthControlSpacing) {
                chevronButton(increment: false, size: headerState.calendarState.monthControlSize)
                chevronButton(increment: true, size: headerState.calendarState.monthControlSize)
            }
        }
        .frame(height: headerState.calendarState.titleHeight, alignment: .center)
        .padding(.bottom, headerState.calendarState.titleBottomSpacing)
        .clipped()
        .scaleEffect(1.0 - (fadeProgress * 0.14), anchor: .leading)
        .opacity(1.0 - fadeProgress)
    }

    private var calendarGrid: some View {
        let totalGridHeight = CGFloat(calendarVM.monthRows.count) * headerState.calendarState.rowHeight
        let isCompactStripActive = headerState.progress >= 0.999
        let visibleGridWidth = headerState.calendarState.dayColumnWidth * 7
        let visibleGridHeight = headerState.calendarState.rowHeight + (totalGridHeight - headerState.calendarState.rowHeight) * (1 - headerState.progress)

        return VStack(spacing: 0) {
            weekdayLabels
                .frame(width: visibleGridWidth, alignment: .leading)

            ZStack(alignment: .top) {
                dayGrid(totalGridHeight: totalGridHeight)
                    .id(calendarVM.selectedMonth)
                    .transition(monthGridTransition)
                    .opacity(isCompactStripActive ? 0 : 1)
                    .frame(width: visibleGridWidth, alignment: .leading)

                if isCompactStripActive && !compactWeekPages.isEmpty {
                    CompactCalendarWeekStrip(
                        weeks: compactWeekPages,
                        visibleWidth: visibleGridWidth,
                        dayColumnWidth: headerState.calendarState.dayColumnWidth,
                        dayRowHeight: headerState.calendarState.rowHeight,
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
                height: visibleGridHeight,
                alignment: .top
            )
            .clipped()
            .transaction { transaction in
                if !isMonthTransitionAnimating {
                    transaction.animation = nil
                }
            }
        }
        .padding(.horizontal, headerState.calendarState.horizontalPadding)
        .padding(.vertical, headerState.calendarState.verticalPadding)
        .frame(width: headerState.calendarWidth, alignment: .leading)
        .background {
            if headerState.progress > 0.001 {
                Color.clear
                    .opacity(headerState.progress)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: headerState.calendarState.cornerRadius, style: .continuous))
    }

    private var weekdayLabels: some View {
        HStack(spacing: 0) {
            ForEach(calendarVM.orderedWeekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: headerState.calendarState.weekdayFontSize, weight: .bold))
                    .frame(width: headerState.calendarState.dayColumnWidth)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: headerState.calendarState.weekLabelHeight, alignment: .center)
    }

    private func dayGrid(totalGridHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(calendarVM.monthRows.enumerated()), id: \.element.first?.id) { rowIndex, row in
                let distance = abs(CGFloat(rowIndex) - calendarVM.monthProgress)
                let rowOpacity = max(0, 1.0 - distance * headerState.progress)

                HStack(spacing: 0) {
                    ForEach(row) { day in
                        CalendarDayCellView(
                            day: day,
                            insight: calendarInsightsCache[day.dateString],
                            collapseProgress: headerState.progress,
                            dayColumnWidth: headerState.calendarState.dayColumnWidth,
                            rowHeight: headerState.calendarState.rowHeight
                        )
                        .frame(
                            width: headerState.calendarState.dayColumnWidth,
                            height: headerState.calendarState.rowHeight
                        )
                        .onTapGesture {
                            calendarVM.selectDate(day.date)
                        }
                    }
                }
                .frame(
                    width: headerState.calendarState.dayColumnWidth * 7,
                    height: headerState.calendarState.rowHeight,
                    alignment: .leading
                )
                .opacity(rowOpacity)
                .transaction { $0.animation = nil }
            }
        }
        .frame(height: totalGridHeight, alignment: .top)
        .offset(y: -(calendarVM.monthProgress * headerState.calendarState.rowHeight) * headerState.progress)
    }

    private func chevronButton(increment: Bool, size: CGFloat) -> some View {
        Button {
            changeMonth(increment: increment)
        } label: {
            Image(systemName: increment ? "chevron.compact.right" : "chevron.compact.left")
                .font(.system(size: size * 0.48, weight: .black))
                .foregroundStyle(themeManager.textPrimary.opacity(0.92))
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func changeMonth(increment: Bool) {
        monthTransitionDirection = increment ? 1 : -1

        withAnimation(monthTransitionAnimation) {
            isMonthTransitionAnimating = true
            calendarVM.monthUpdate(increment: increment)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            isMonthTransitionAnimating = false
        }
    }
}
