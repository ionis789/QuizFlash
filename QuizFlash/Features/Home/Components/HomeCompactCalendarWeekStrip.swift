// HomeCompactCalendarWeekStrip.swift
// QuizFlash
//
// Compact week strip extracted from HomeCalendarSectionView.

import SwiftUI

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
