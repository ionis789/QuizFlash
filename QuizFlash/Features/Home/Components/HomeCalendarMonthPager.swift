// HomeCalendarMonthPager.swift
// QuizFlash
//
// Expanded month pager extracted from HomeCalendarSectionView.

import SwiftUI
import UIKit

private struct ExpandedMonthPagerConfiguration: Equatable {
    let monthStarts: [Date]
    let selectedDateIDs: [String?]
    let progress: CGFloat
    let state: HomeCalendarAdaptiveLayout.State
    let insightsRevision: Int
}

// MARK: - Month Grid Page View

private struct MonthGridPageView: View {
    let snapshot: CalendarViewModel.MonthSnapshot
    let progress: CGFloat
    let state: HomeCalendarAdaptiveLayout.State
    let calendarInsightsCache: [String: HomeCalendarDayInsight]
    let onSelectDay: (Day) -> Void

    var body: some View {
        let totalGridHeight = CGFloat(snapshot.rows.count) * state.rowHeight

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
                            onSelectDay(day)
                        }
                    }
                }
                .frame(width: state.dayColumnWidth * 7, height: state.rowHeight, alignment: .leading)
                .opacity(rowOpacity)
                .transaction { $0.animation = nil }
            }
        }
        .frame(height: totalGridHeight, alignment: .top)
        .offset(y: -(snapshot.monthProgress * state.rowHeight) * progress)
    }
}

// MARK: - Expanded Month Pager Host

struct ExpandedMonthPagerHost: UIViewControllerRepresentable {
    let snapshots: [CalendarViewModel.MonthSnapshot]
    let progress: CGFloat
    let state: HomeCalendarAdaptiveLayout.State
    let calendarInsightsCache: [String: HomeCalendarDayInsight]
    let insightsRevision: Int
    let onSelectDay: (Day) -> Void
    let onMonthOffset: (Int) -> Void

    func makeUIViewController(context: Context) -> ExpandedMonthPagerController {
        let controller = ExpandedMonthPagerController()
        controller.view.backgroundColor = .clear
        controller.onMonthOffset = onMonthOffset
        controller.configure(
            snapshots: snapshots,
            progress: progress,
            state: state,
            calendarInsightsCache: calendarInsightsCache,
            insightsRevision: insightsRevision,
            onSelectDay: onSelectDay
        )
        return controller
    }

    func updateUIViewController(_ uiViewController: ExpandedMonthPagerController, context: Context) {
        uiViewController.onMonthOffset = onMonthOffset
        uiViewController.configure(
            snapshots: snapshots,
            progress: progress,
            state: state,
            calendarInsightsCache: calendarInsightsCache,
            insightsRevision: insightsRevision,
            onSelectDay: onSelectDay
        )
    }
}

final class ExpandedMonthPagerController: UIPageViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    var onMonthOffset: ((Int) -> Void)?

    private var pageControllers: [MonthGridHostingController] = []
    private var centeredMonthStart: Date?
    private var lastConfiguration: ExpandedMonthPagerConfiguration?
    private var pendingRecenteringID: UUID?

    init() {
        super.init(transitionStyle: .scroll, navigationOrientation: .horizontal)
        dataSource = self
        delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    func configure(
        snapshots: [CalendarViewModel.MonthSnapshot],
        progress: CGFloat,
        state: HomeCalendarAdaptiveLayout.State,
        calendarInsightsCache: [String: HomeCalendarDayInsight],
        insightsRevision: Int,
        onSelectDay: @escaping (Day) -> Void
    ) {
        guard snapshots.count == 3 else { return }

        let configuration = ExpandedMonthPagerConfiguration(
            monthStarts: snapshots.map(\.monthStart),
            selectedDateIDs: snapshots.map { snapshot in
                snapshot.rows.flatMap { $0 }.first { $0.isSelected }?.dateString
            },
            progress: progress,
            state: state,
            insightsRevision: insightsRevision
        )

        if lastConfiguration == configuration {
            return
        }

        let monthChanged = centeredMonthStart != snapshots[1].monthStart || pageControllers.count != snapshots.count

        if monthChanged {
            pageControllers = snapshots.enumerated().map { index, snapshot in
                MonthGridHostingController(
                    pageIndex: index,
                    rootView: MonthGridPageView(
                        snapshot: snapshot,
                        progress: progress,
                        state: state,
                        calendarInsightsCache: calendarInsightsCache,
                        onSelectDay: onSelectDay
                    )
                )
            }
            centeredMonthStart = snapshots[1].monthStart
            setViewControllers([pageControllers[1]], direction: .forward, animated: false)
            pendingRecenteringID = nil
            view.isUserInteractionEnabled = true
        } else {
            for (index, controller) in pageControllers.enumerated() {
                controller.rootView = MonthGridPageView(
                    snapshot: snapshots[index],
                    progress: progress,
                    state: state,
                    calendarInsightsCache: calendarInsightsCache,
                    onSelectDay: onSelectDay
                )
            }
        }

        lastConfiguration = configuration
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        guard
            let controller = viewController as? MonthGridHostingController,
            controller.pageIndex > 0
        else { return nil }

        return pageControllers[controller.pageIndex - 1]
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        guard
            let controller = viewController as? MonthGridHostingController,
            controller.pageIndex < pageControllers.count - 1
        else { return nil }

        return pageControllers[controller.pageIndex + 1]
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        guard
            finished,
            completed,
            let controller = viewControllers?.first as? MonthGridHostingController
        else { return }

        let offset: Int
        switch controller.pageIndex {
        case 0:
            offset = -1
        case 2:
            offset = 1
        default:
            return
        }

        view.isUserInteractionEnabled = false
        let recenteringID = UUID()
        pendingRecenteringID = recenteringID

        DispatchQueue.main.async { [weak self] in
            self?.onMonthOffset?(offset)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard
                let self,
                self.pendingRecenteringID == recenteringID
            else { return }

            self.pendingRecenteringID = nil
            if self.pageControllers.indices.contains(1) {
                self.setViewControllers([self.pageControllers[1]], direction: .forward, animated: false)
            }
            self.view.isUserInteractionEnabled = true
        }
    }
}

private final class MonthGridHostingController: UIHostingController<MonthGridPageView> {
    let pageIndex: Int

    init(pageIndex: Int, rootView: MonthGridPageView) {
        self.pageIndex = pageIndex
        super.init(rootView: rootView)
        view.backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
