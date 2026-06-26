// HomeDashboardView.swift
// QuizFlash
//
// Renders the Home dashboard below the sticky calendar header using a small
// set of clean sections instead of a widget stack.

import SwiftUI
import SwiftData

// MARK: - Home Dashboard View

/// The scrollable Home body rendered below the collapsible calendar header.
///
/// `HomeDashboardView` remains a pure rendering layer. All derived values come
/// from `HomeViewModel` and `HomeDashboardSnapshot`.
struct HomeDashboardView: View {
    private let topSectionInset: CGFloat = 12

    // MARK: - Dependencies

    let viewModel: HomeViewModel
    let folderSnapshots: [HomeFolderSnapshot]
    let recentDeckSnapshots: [LibraryDeckRowSnapshot]
    let layoutContext: HomeAdaptiveLayoutContext
    let allDeckCount: Int
    let onOpenDeck: (PersistentIdentifier) -> Void
    let onOpenFolder: (PersistentIdentifier) -> Void
    let onCreateFolder: () -> Void
    let onCreateDeck: () -> Void

    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager

    // MARK: - Derived Data

    private var dashboardSnapshot: HomeDashboardSnapshot {
        viewModel.dashboardSnapshot
    }

    private var accentColor: Color {
        themeManager.roleColor(.buttonPrimaryFill)
    }

    private var dangerColor: Color {
        themeManager.roleColor(.buttonDangerFill)
    }

    private var roseColor: Color {
        themeManager.roleColor(.labelDangerFill)
    }

    private var locale: Locale {
        appPreferences.resolvedLocale
    }

    private func localized(_ value: String.LocalizationValue) -> String {
        AppLocalization.string(value, locale: locale)
    }

    private func localizedFormat(_ value: String.LocalizationValue, _ arguments: CVarArg...) -> String {
        let format = AppLocalization.string(value, locale: locale)
        return String(format: format, locale: locale, arguments: arguments)
    }

    private var greetingTitle: String {
        let hour = appPreferences.resolvedCalendar.component(.hour, from: Date())

        switch hour {
        case 5..<12:
            return localized("Good morning")
        case 12..<17:
            return localized("Good afternoon")
        case 17..<22:
            return localized("Good evening")
        default:
            return localized("Good night")
        }
    }

    private var contentHorizontalInset: CGFloat {
        layoutContext.dashboardContext.horizontalInset
    }

    private var availableSectionWidth: CGFloat {
        layoutContext.dashboardContext.contentWidth
    }

    private var dashboardMetrics: HomeDashboardAdaptiveMetrics {
        HomeDashboardAdaptiveMetrics(contentWidth: availableSectionWidth)
    }

    private var dashboardMaxWidth: CGFloat? {
        layoutContext.dashboardContext.maxContentWidth
    }

    private var usesDashboardColumns: Bool {
        dashboardMetrics.usesDashboardColumns
    }

    private var usesRegularMetrics: Bool {
        dashboardMetrics.usesRegularMetrics
    }

    private var showsWorkspaceOnboarding: Bool {
        allDeckCount == 0
    }

    private var showsLibrarySection: Bool {
        !recentDeckSnapshots.isEmpty || !folderSnapshots.isEmpty || (!showsWorkspaceOnboarding && allDeckCount > 0)
    }

    private var sectionSpacing: CGFloat {
        usesRegularMetrics ? 24 : 20
    }

    private var studyHeroMinHeight: CGFloat {
        usesRegularMetrics ? 282 : 256
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            boundedSection(studySection)
                .padding(.top, topSectionInset)
                .padding(.horizontal, contentHorizontalInset)
                .homeDashboardSectionMotion()

            if showsLibrarySection {
                boundedSection(librarySection)
                    .padding(.top, sectionSpacing)
                    .padding(.horizontal, contentHorizontalInset)
                    .homeDashboardSectionMotion()
            }

            if showsWorkspaceOnboarding {
                boundedSection(workspaceSetupSection)
                    .padding(.top, sectionSpacing)
                    .padding(.horizontal, contentHorizontalInset)
                    .homeDashboardSectionMotion()
            }

            Spacer(minLength: 170)
        }
    }

    @ViewBuilder
    private func boundedSection<Content: View>(_ content: Content) -> some View {
        if let dashboardMaxWidth {
            content
                .frame(maxWidth: dashboardMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            content
        }
    }

    // MARK: - Study

    private var studySection: some View {
        VStack(alignment: .leading, spacing: usesRegularMetrics ? 12 : 10) {
            duoStudyCard {
                selectedDayStatsContent(for: dashboardSnapshot.selectedDayOverview)
            }

            weeklyStatsButton(for: dashboardSnapshot.pastWeekPerformance)
        }
    }

    private func duoStudyCard<Content: View>(isInteractive: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        content()
            .modifier(HomeDashboardStudyCardModifier(
                usesRegularMetrics: usesRegularMetrics,
                isInteractive: isInteractive
            ))
    }

    private func selectedDayStatsContent(for overview: HomeSelectedDayOverviewSummary) -> some View {
        VStack(alignment: .leading, spacing: usesRegularMetrics ? 9 : 8) {
            Text(selectedDayTitle(for: overview))
                .font(.system(size: usesRegularMetrics ? 22 : 20, weight: .black, design: .rounded))
                .foregroundStyle(accentColor)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Text(selectedDayReviewedLine(for: overview))
                .font(.system(size: usesRegularMetrics ? 28 : 25, weight: .black, design: .rounded))
                .foregroundStyle(themeManager.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.68)
                .multilineTextAlignment(.leading)
                .contentTransition(.numericText())

            selectedDayMetricsRow(for: overview)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func selectedDayTitle(for overview: HomeSelectedDayOverviewSummary) -> String {
        appPreferences.resolvedCalendar.isDateInToday(overview.selectedDate)
            ? localized("Today")
            : overview.selectedDateLabel
    }

    private func selectedDayReviewedLine(for overview: HomeSelectedDayOverviewSummary) -> String {
        let calendar = appPreferences.resolvedCalendar
        if calendar.startOfDay(for: overview.selectedDate) > calendar.startOfDay(for: Date()) {
            if let dailyGoal = overview.dailyGoal {
                return localizedFormat("Goal: %d cards", dailyGoal)
            }
            return localized("No reviews yet")
        }

        if let dailyGoal = overview.dailyGoal {
            return localizedFormat("%d / %d cards reviewed", overview.cardsReviewed, dailyGoal)
        }
        return localizedFormat("%d cards reviewed", overview.cardsReviewed)
    }

    private func selectedDayMetricsRow(for overview: HomeSelectedDayOverviewSummary) -> some View {
        HStack(spacing: usesRegularMetrics ? 16 : 12) {
            metricPill(localizedFormat("Good %d", overview.correctCardCount), tint: .green)
            metricPill(localizedFormat("Retry %d", overview.retryCardCount), tint: themeManager.roleColor(.buttonDangerFill))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func activeDaysText(for summary: HomePastWeekPerformanceSummary) -> String {
        if summary.activeDays == 1 {
            return localized("1 active day")
        }

        return localizedFormat("%d active days", summary.activeDays)
    }

    private func goalDaysText(for summary: HomePastWeekPerformanceSummary) -> String {
        if summary.goalHitDays == 1 {
            return localized("1 goal day")
        }

        return localizedFormat("%d goal days", summary.goalHitDays)
    }

    private func weeklyStatsButton(for summary: HomePastWeekPerformanceSummary) -> some View {
        Button {
            viewModel.presentPerformanceDetail()
        } label: {
            HStack(alignment: .center, spacing: usesRegularMetrics ? 16 : 14) {
                VStack(alignment: .leading, spacing: usesRegularMetrics ? 9 : 8) {
                    Text(localized("This week"))
                        .font(.system(size: usesRegularMetrics ? 22 : 20, weight: .black, design: .rounded))
                        .foregroundStyle(accentColor)
                        .lineLimit(1)

                    Text(weeklyPerformanceHeadline(for: summary))
                        .font(.system(size: usesRegularMetrics ? 28 : 25, weight: .black, design: .rounded))
                        .foregroundStyle(themeManager.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .contentTransition(.numericText())

                    weeklyMetricsRow(for: summary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: usesRegularMetrics ? 16 : 15, weight: .black, design: .rounded))
                    .foregroundStyle(accentColor)
                    .frame(width: usesRegularMetrics ? 32 : 30, height: usesRegularMetrics ? 32 : 30)
                    .background {
                        Circle()
                            .fill(accentColor.opacity(0.14))
                    }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(HomeDashboardStudyCardModifier(
                usesRegularMetrics: usesRegularMetrics,
                isInteractive: true
            ))
        }
        .buttonStyle(.plain)
    }

    private func weeklyPerformanceHeadline(for summary: HomePastWeekPerformanceSummary) -> String {
        guard summary.hasActivity else {
            return localized("No reviews this week")
        }

        return localizedFormat("%d%% good cards", summary.goodRatePercent)
    }

    @ViewBuilder
    private func weeklyMetricsRow(for summary: HomePastWeekPerformanceSummary) -> some View {
        HStack(spacing: usesRegularMetrics ? 16 : 12) {
            metricPill(activeDaysText(for: summary))

            if summary.hasGoal {
                metricPill(goalDaysText(for: summary))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricPill(_ text: String, tint: Color? = nil) -> some View {
        let resolvedTint = tint ?? themeManager.textSecondary

        return Text(text)
            .font(.system(size: usesRegularMetrics ? 15 : 14, weight: .bold, design: .rounded))
            .foregroundStyle(tint == nil ? themeManager.textSecondary : themeManager.textPrimary.opacity(0.92))
            .lineLimit(2)
            .minimumScaleFactor(0.78)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, usesRegularMetrics ? 11 : 9)
            .padding(.vertical, usesRegularMetrics ? 7 : 6)
            .background {
                RoundedRectangle(cornerRadius: usesRegularMetrics ? 14 : 12, style: .continuous)
                    .fill(themeManager.surfacePrimary.opacity(0.52))
                    .overlay {
                        RoundedRectangle(cornerRadius: usesRegularMetrics ? 14 : 12, style: .continuous)
                            .strokeBorder(resolvedTint.opacity(tint == nil ? 0.20 : 0.46), lineWidth: 1.4)
                    }
            }
    }

    // MARK: - Library

    private var librarySection: some View {
        Group {
            if usesDashboardColumns {
                HStack(alignment: .top, spacing: 14) {
                    if !recentDeckSnapshots.isEmpty {
                        recentDecksSection
                    }
                    foldersSection
                }
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    if !recentDeckSnapshots.isEmpty {
                        recentDecksSection
                    }
                    foldersSection
                }
            }
        }
    }

    private var recentDecksSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HomeDashboardSectionHeader(
                title: localized("Recent decks"),
                count: recentDeckSnapshots.count
            )
            recentDecksSurface
        }
    }

    private var recentDecksSurface: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(recentDeckSnapshots.enumerated()), id: \.element.id) { index, deck in
                HomeDashboardRecentDeckRow(
                    snapshot: deck,
                    showsSeparator: index < recentDeckSnapshots.count - 1
                ) {
                    onOpenDeck(deck.id)
                }
            }
        }
        .padding(.horizontal, usesRegularMetrics ? 18 : 16)
        .padding(.vertical, usesRegularMetrics ? 8 : 6)
        .duoSurface(cornerRadius: usesRegularMetrics ? 26 : 24)
    }

    private var foldersSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HomeDashboardSectionHeader(
                title: localized("Folders"),
                count: folderSnapshots.count,
                trailingAccessory: {
                    ChromeSoftCircleSymbolButton(
                        systemName: "plus",
                        accessibilityLabel: localized("Folders"),
                        action: onCreateFolder
                    )
                }
            )

            foldersSurface
        }
    }

    private var foldersSurface: some View {
        VStack(alignment: .leading, spacing: 12) {
            if folderSnapshots.isEmpty {
                HomeDashboardCreateFolderPlaceholder(
                    title: localized("No folders yet"),
                    usesRegularMetrics: usesRegularMetrics,
                    action: onCreateFolder
                )
            } else {
                ForEach(folderSnapshots) { folder in
                    HomeDashboardFolderCard(snapshot: folder, usesRegularMetrics: usesRegularMetrics) {
                        onOpenFolder(folder.id)
                    }
                }
            }
        }
    }

    // MARK: - Workspace

    private var workspaceSetupSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HomeDashboardSectionHeader(title: localized("Get started"))

            createDeckSurface
        }
    }

    private var createDeckSurface: some View {
        VStack(alignment: .center, spacing: 12) {
            HomeDashboardEmptyPlaceholderContent(
                title: localized("No decks yet"),
                usesRegularMetrics: usesRegularMetrics
            )

            Button(localized("Open Create")) {
                onCreateDeck()
            }
            .font(.subheadline.weight(.bold))
            .quizFlashButtonStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

}

// MARK: - Folder Snapshot

struct HomeFolderSnapshot: Identifiable, Equatable {
    let id: PersistentIdentifier
    let title: String
    let colorHex: String
    let deckCount: Int
}

private struct HomeDashboardStudyCardModifier: ViewModifier {
    @Environment(ThemeManager.self) private var themeManager

    let usesRegularMetrics: Bool
    let isInteractive: Bool

    private var cornerRadius: CGFloat {
        usesRegularMetrics ? 24 : 22
    }

    private var borderOpacity: CGFloat {
        isInteractive ? 0.22 : 0.18
    }

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, usesRegularMetrics ? 20 : 18)
            .padding(.vertical, usesRegularMetrics ? 15 : 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(themeManager.roleColor(.widgetSurfaceFill).opacity(0.72))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                themeManager.textSecondary.opacity(borderOpacity),
                                lineWidth: 1.15
                            )
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Section Header

private struct HomeDashboardSectionHeader: View {
    @Environment(ThemeManager.self) private var themeManager

    let title: String
    let count: Int?
    let subtitle: String?
    let trailingAccessory: AnyView?

    init(
        title: String,
        count: Int? = nil,
        subtitle: String? = nil
    ) {
        self.title = title
        self.count = count
        self.subtitle = subtitle
        self.trailingAccessory = nil
    }

    init<TrailingAccessory: View>(
        title: String,
        count: Int? = nil,
        subtitle: String? = nil,
        @ViewBuilder trailingAccessory: () -> TrailingAccessory
    ) {
        self.title = title
        self.count = count
        self.subtitle = subtitle
        self.trailingAccessory = AnyView(trailingAccessory())
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(themeManager.textPrimary.opacity(0.92))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let count {
                Text("\(count)")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(themeManager.textSecondary)
                    .contentTransition(.numericText())
                    .fixedSize()
            }

            if let trailingAccessory {
                trailingAccessory
            }
        }
    }
}

private struct HomeDashboardCreateFolderPlaceholder: View {
    @Environment(ThemeManager.self) private var themeManager

    let title: String
    let usesRegularMetrics: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(themeManager.roleColor(.buttonPrimaryFill).opacity(0.10))

                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: usesRegularMetrics ? 34 : 30, weight: .bold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(themeManager.roleColor(.buttonPrimaryFill))
                }
                .frame(width: usesRegularMetrics ? 76 : 68, height: usesRegularMetrics ? 76 : 68)

                Text(title)
                    .font(.system(size: usesRegularMetrics ? 20 : 18, weight: .bold, design: .rounded))
                    .foregroundStyle(themeManager.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: usesRegularMetrics ? 150 : 134)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct HomeDashboardEmptyPlaceholder: View {
    let title: String
    let usesRegularMetrics: Bool

    var body: some View {
        HomeDashboardEmptyPlaceholderContent(
            title: title,
            usesRegularMetrics: usesRegularMetrics
        )
    }
}

private struct HomeDashboardEmptyPlaceholderContent: View {
    @Environment(ThemeManager.self) private var themeManager

    let title: String
    let usesRegularMetrics: Bool

    var body: some View {
        Text(title)
            .font(.system(size: usesRegularMetrics ? 20 : 18, weight: .bold, design: .rounded))
            .foregroundStyle(themeManager.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: usesRegularMetrics ? 48 : 44, alignment: .center)
    }
}

private struct HomeDashboardDailyOutcomePanel: View {
    @Environment(ThemeManager.self) private var themeManager

    let reviewedTitle: String
    let goodTitle: String
    let retryTitle: String
    let reviewedCount: Int
    let goodCount: Int
    let retryCount: Int
    let neutralTint: Color
    let goodTint: Color
    let retryTint: Color
    let usesRegularMetrics: Bool

    private var cornerRadius: CGFloat {
        usesRegularMetrics ? 24 : 22
    }

    private var totalOutcomeCount: Int {
        max(reviewedCount, goodCount + retryCount, 1)
    }

    private var neutralCount: Int {
        max(reviewedCount - goodCount - retryCount, 0)
    }

    var body: some View {
        VStack(spacing: usesRegularMetrics ? 16 : 14) {
            outcomeBar

            HStack(spacing: 0) {
                HomeDashboardOutcomeMetric(
                    title: reviewedTitle,
                    value: "\(reviewedCount)",
                    tint: neutralTint,
                    usesRegularMetrics: usesRegularMetrics
                )

                outcomeDivider

                HomeDashboardOutcomeMetric(
                    title: goodTitle,
                    value: "\(goodCount)",
                    tint: goodTint,
                    usesRegularMetrics: usesRegularMetrics
                )

                outcomeDivider

                HomeDashboardOutcomeMetric(
                    title: retryTitle,
                    value: "\(retryCount)",
                    tint: retryTint,
                    usesRegularMetrics: usesRegularMetrics
                )
            }
        }
        .padding(.horizontal, usesRegularMetrics ? 18 : 16)
        .padding(.vertical, usesRegularMetrics ? 18 : 16)
        .background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(themeManager.surfacePrimary)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.055), lineWidth: 1)
                }
        }
        .accessibilityElement(children: .combine)
    }

    private var outcomeBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.12))

                HStack(spacing: 0) {
                    if goodCount > 0 {
                        Rectangle()
                            .fill(goodTint)
                            .frame(width: proxy.size.width * CGFloat(goodCount) / CGFloat(totalOutcomeCount))
                    }

                    if retryCount > 0 {
                        Rectangle()
                            .fill(retryTint)
                            .frame(width: proxy.size.width * CGFloat(retryCount) / CGFloat(totalOutcomeCount))
                    }

                    if neutralCount > 0 {
                        Rectangle()
                            .fill(neutralTint.opacity(0.42))
                            .frame(width: proxy.size.width * CGFloat(neutralCount) / CGFloat(totalOutcomeCount))
                    }
                }
                .clipShape(Capsule())
            }
        }
        .frame(height: usesRegularMetrics ? 13 : 12)
    }

    private var outcomeDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 1, height: usesRegularMetrics ? 48 : 42)
            .padding(.horizontal, usesRegularMetrics ? 12 : 10)
    }
}

private struct HomeDashboardOutcomeMetric: View {
    @Environment(ThemeManager.self) private var themeManager

    let title: String
    let value: String
    let tint: Color
    let usesRegularMetrics: Bool

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(themeManager.textSecondary)
                .lineLimit(1)

            Text(value)
                .font(.system(size: usesRegularMetrics ? 32 : 29, weight: .black, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct HomeWeeklyCoverageBarsView: View {
    @Environment(ThemeManager.self) private var themeManager

    let daySummaries: [HomeWeeklyDaySummary]
    let tint: Color
    let usesRegularMetrics: Bool
    let onSelectDate: (Date) -> Void

    private var maxReviewedCount: Int {
        max(daySummaries.map(\.cardsReviewed).max() ?? 0, 1)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: usesRegularMetrics ? 14 : 10) {
            ForEach(daySummaries) { day in
                Button {
                    onSelectDate(day.date)
                } label: {
                    HomeWeeklyCoverageBar(
                        day: day,
                        maxReviewedCount: maxReviewedCount,
                        tint: tint,
                        usesRegularMetrics: usesRegularMetrics
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct HomeWeeklyCoverageBar: View {
    @Environment(ThemeManager.self) private var themeManager

    let day: HomeWeeklyDaySummary
    let maxReviewedCount: Int
    let tint: Color
    let usesRegularMetrics: Bool

    private var maxBarHeight: CGFloat {
        usesRegularMetrics ? 134 : 118
    }

    private var barWidth: CGFloat {
        day.isSelectedDay
            ? (usesRegularMetrics ? 34 : 30)
            : (usesRegularMetrics ? 28 : 24)
    }

    private var normalizedHeight: CGFloat {
        guard day.cardsReviewed > 0 else { return 10 }
        let ratio = CGFloat(day.cardsReviewed) / CGFloat(max(maxReviewedCount, 1))
        return max(20, maxBarHeight * ratio)
    }

    private var fillColor: Color {
        if day.isSelectedDay { return tint }
        if day.didStudy { return tint.opacity(0.52) }
        return Color.white.opacity(0.12)
    }

    var body: some View {
        VStack(spacing: 10) {
            Text("\(day.cardsReviewed)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(day.isSelectedDay ? themeManager.textPrimary : themeManager.textSecondary)
                .contentTransition(.numericText(value: Double(day.cardsReviewed)))
                .frame(height: 16)

            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(Color.white.opacity(0.05))
                    .frame(width: barWidth, height: maxBarHeight)

                Capsule()
                    .fill(fillColor)
                    .frame(width: barWidth, height: normalizedHeight)
                    .overlay(alignment: .top) {
                        if day.isSelectedDay {
                            Capsule()
                                .fill(Color.white.opacity(0.18))
                                .frame(width: barWidth - 6, height: 10)
                                .blur(radius: 6)
                                .padding(.top, 6)
                        }
                    }
            }
            .animation(.circularSelectionSpring, value: day.isSelectedDay)
            .animation(.circularSelectionSpring, value: day.cardsReviewed)

            Text(day.shortWeekday)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(day.isSelectedDay ? tint : themeManager.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .bottom)
    }
}

private struct HomeWeeklyCoverageMetricChip: View {
    @Environment(ThemeManager.self) private var themeManager

    let title: String
    let value: String
    let detail: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(themeManager.textSecondary)

            Text(value)
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(themeManager.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(detail)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(themeManager.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(themeManager.surfacePrimary)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(tint.opacity(0.12))
                }
        }
    }
}

private struct HomeSelectedDayDeckRow: View {
    @Environment(ThemeManager.self) private var themeManager

    let summary: HomeWeeklyDeckActivitySummary
    let isSelected: Bool
    let usesRegularMetrics: Bool
    let action: () -> Void

    private var deckColor: Color {
        Color(hex: summary.colorHex) ?? themeManager.brandPrimary
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Circle()
                    .fill(deckColor)
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(themeManager.textPrimary)
                        .lineLimit(1)

                    Text("\(summary.uniqueCardCount) unique • \(summary.correctCardCount) landed • \(summary.retryCardCount) retry")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(themeManager.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(deckColor)
                }
            }
            .padding(.horizontal, usesRegularMetrics ? 16 : 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: usesRegularMetrics ? 22 : 20, style: .continuous)
                    .fill(themeManager.surfacePrimary)
                    .overlay {
                        RoundedRectangle(cornerRadius: usesRegularMetrics ? 22 : 20, style: .continuous)
                            .fill(deckColor.opacity(isSelected ? 0.16 : 0.08))
                    }
            }
        }
        .buttonStyle(.plain)
        .animation(.circularSelectionSpring, value: isSelected)
    }
}

private struct HomeSelectedDayDeckViewport: View {
    @Environment(ThemeManager.self) private var themeManager

    let summary: HomeWeeklyDeckActivitySummary?
    let usesRegularMetrics: Bool

    private var minHeight: CGFloat {
        usesRegularMetrics ? 154 : 142
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let summary {
                HStack(spacing: 10) {
                    Text(summary.title)
                        .font(.system(size: usesRegularMetrics ? 18 : 17, weight: .black, design: .rounded))
                        .foregroundStyle(themeManager.textPrimary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    HomeDashboardPill(
                        text: summary.retryCardCount == 0 ? "Clean finish" : "\(summary.retryCardCount) retry",
                        tint: summary.retryCardCount == 0 ? .green : themeManager.roleColor(.buttonDangerFill),
                        backgroundTint: summary.retryCardCount == 0 ? .green.opacity(0.18) : themeManager.roleColor(.labelDangerFill)
                    )
                }

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        ForEach(summary.cards) { card in
                            HomeWeeklyCoverageReviewedCardRow(card: card)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Choose a deck")
                        .font(.system(size: usesRegularMetrics ? 18 : 17, weight: .black, design: .rounded))
                        .foregroundStyle(themeManager.textPrimary)

                    Text("Pick a deck row above to inspect the cards that landed cleanly and the ones that still need another pass.")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(themeManager.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: minHeight, alignment: .topLeading)
        .padding(usesRegularMetrics ? 16 : 14)
        .background {
            RoundedRectangle(cornerRadius: usesRegularMetrics ? 24 : 22, style: .continuous)
                .fill(themeManager.surfacePrimary)
                .overlay {
                    RoundedRectangle(cornerRadius: usesRegularMetrics ? 24 : 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.03), lineWidth: 1)
                }
        }
    }
}

private struct HomeWeeklyCoverageDeckBreakdownCard: View {
    @Environment(ThemeManager.self) private var themeManager

    let summary: HomeWeeklyDeckActivitySummary
    let usesRegularMetrics: Bool

    private var deckColor: Color {
        Color(hex: summary.colorHex) ?? themeManager.brandPrimary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(deckColor)
                    .frame(width: 10, height: 10)

                Text(summary.title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(themeManager.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text("\(summary.uniqueCardCount) unique")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(themeManager.textSecondary)
            }

            HStack(spacing: 8) {
                HomeDashboardPill(
                    text: "\(summary.correctCardCount) landed",
                    tint: deckColor,
                    backgroundTint: deckColor.opacity(0.14)
                )

                if summary.retryCardCount > 0 {
                    HomeDashboardPill(
                        text: "\(summary.retryCardCount) retry",
                        tint: .white,
                        backgroundTint: Color.white.opacity(0.08)
                    )
                }
            }

            VStack(spacing: 8) {
                ForEach(Array(summary.cards.prefix(3))) { card in
                    HomeWeeklyCoverageReviewedCardRow(card: card)
                }
            }

            if summary.cards.count > 3 {
                Text("+\(summary.cards.count - 3) more card\(summary.cards.count - 3 == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(themeManager.textSecondary)
            }
        }
        .padding(usesRegularMetrics ? 18 : 16)
        .duoSurface(cornerRadius: usesRegularMetrics ? 26 : 24)
    }
}

private struct HomeWeeklyCoverageReviewedCardRow: View {
    @Environment(ThemeManager.self) private var themeManager

    let card: HomeWeeklyReviewedCardSummary

    private var badgeTint: Color {
        card.wasCorrectAtEndOfDay ? themeManager.brandPrimary : themeManager.roleColor(.buttonDangerFill)
    }

    private var badgeText: String {
        card.wasCorrectAtEndOfDay ? "Good" : "Retry"
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(card.title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(themeManager.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if card.reviewCount > 1 {
                Text("\(card.reviewCount)x")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(themeManager.textSecondary)
            }

            Text(badgeText)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(themeManager.textPrimary)
                .duoMetricPill(tint: badgeTint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .duoControlSurface(cornerRadius: 18, tint: badgeTint)
    }
}

private struct HomeWeeklyCoverageEmptyState: View {
    @Environment(ThemeManager.self) private var themeManager

    let label: String
    let usesRegularMetrics: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nothing landed on \(label.lowercased())")
                .font(.system(size: usesRegularMetrics ? 20 : 18, weight: .bold, design: .rounded))
                .foregroundStyle(themeManager.textPrimary)

            Text("Tap another day in the chart or start a short review block to build this week with meaningful history.")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(themeManager.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .duoSurface(cornerRadius: usesRegularMetrics ? 26 : 24)
    }
}

private extension HomeWeeklyDaySummary {
    var selectedDatePillLabel: String {
        HomeViewModel.labelForSelectedDay(date)
    }
}

private struct HomeDashboardProgressBar: View {
    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let clampedProgress = min(max(progress, 0), 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.06))

                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * clampedProgress)
            }
        }
        .frame(height: 8)
    }
}

private struct HomeDashboardRangeStub: View {
    var body: some View {
        HStack(spacing: 6) {
            HomeDashboardRangeChip(title: "Week", isActive: true)
            HomeDashboardRangeChip(title: "Month", isActive: false)
        }
    }
}

private struct HomeDashboardRangeChip: View {
    let title: String
    let isActive: Bool

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .quizFlashLabelChrome(
                isActive ? .primary : .surface,
                size: 34,
                horizontalPadding: 14
            )
    }
}

private struct HomeDashboardTrendPlaceholder: View {
    @Environment(ThemeManager.self) private var themeManager

    private var accentColor: Color {
        themeManager.roleColor(.buttonPrimaryFill)
    }

    private var dangerColor: Color {
        themeManager.roleColor(.buttonDangerFill)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            let values: [Double] = [0.28, 0.54, 0.4, 0.76, 0.48, 0.64, 0.34]

            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                Capsule()
                    .fill(index.isMultiple(of: 3) ? dangerColor.opacity(0.24) : accentColor.opacity(0.22))
                    .frame(maxWidth: .infinity)
                    .frame(height: 28 + (value * 54))
            }
        }
        .frame(height: 110, alignment: .bottom)
        .padding(.horizontal, 6)
        .padding(.vertical, 10)
        .duoControlSurface(cornerRadius: 18)
    }
}

private struct HomeDashboardInlineBadge: View {
    @Environment(ThemeManager.self) private var themeManager

    let title: String
    let subtitle: String
    let tint: Color

    private var surfaceColor: Color {
        themeManager.roleColor(.widgetSurfaceFill)
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(subtitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .duoControlSurface(cornerRadius: 18, tint: tint)
    }
}

private struct HomeDashboardPill: View {
    @Environment(ThemeManager.self) private var themeManager

    let text: String
    let tint: Color
    let backgroundTint: Color?

    init(
        text: String,
        tint: Color,
        backgroundTint: Color? = nil
    ) {
        self.text = text
        self.tint = tint
        self.backgroundTint = backgroundTint
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                Capsule(style: .continuous)
                    .fill(themeManager.surfacePrimary)
                    .overlay {
                        Capsule(style: .continuous)
                            .fill((backgroundTint ?? tint).opacity(0.18))
                    }
            }
    }
}

private struct HomeDashboardRecentDeckRow: View {
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager

    let snapshot: LibraryDeckRowSnapshot
    let showsSeparator: Bool
    let action: @MainActor @Sendable () -> Void

    private var locale: Locale {
        appPreferences.resolvedLocale
    }

    private var localizedCardCount: String {
        AppLocalization.numbered(
            snapshot.cardCount,
            singular: "%d card",
            plural: "%d cards",
            locale: locale
        )
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(verbatim: snapshot.title)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(themeManager.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(localizedCardCount)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(themeManager.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 14)

                if showsSeparator {
                    AppSectionSeparator()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
    }
}

private struct HomeDashboardFolderCard: View {
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager

    let snapshot: HomeFolderSnapshot
    let usesRegularMetrics: Bool
    let action: () -> Void

    private var folderColor: Color {
        Color(hex: snapshot.colorHex) ?? themeManager.brandPrimary
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(folderColor.opacity(0.14))
                    .frame(width: usesRegularMetrics ? 54 : 48, height: usesRegularMetrics ? 54 : 48)
                    .overlay {
                        Image(systemName: "folder.fill")
                            .font(.system(size: usesRegularMetrics ? 22 : 20, weight: .bold))
                            .foregroundStyle(folderColor)
                    }

                VStack(alignment: .leading, spacing: 6) {
                    Text(snapshot.title)
                        .font(.system(size: usesRegularMetrics ? 20 : 18, weight: .bold, design: .rounded))
                        .foregroundStyle(themeManager.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(
                        AppLocalization.numbered(
                            snapshot.deckCount,
                            singular: "%d deck",
                            plural: "%d decks",
                            locale: appPreferences.resolvedLocale
                        )
                    )
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(themeManager.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(folderColor)
                    .padding(10)
                    .background(folderColor.opacity(0.12), in: Circle())
            }
            .padding(.horizontal, usesRegularMetrics ? 18 : 16)
            .padding(.vertical, usesRegularMetrics ? 18 : 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: usesRegularMetrics ? 28 : 24, style: .continuous)
                    .fill(themeManager.roleColor(.widgetSurfaceFill))
                    .overlay {
                        RoundedRectangle(cornerRadius: usesRegularMetrics ? 28 : 24, style: .continuous)
                            .strokeBorder(folderColor.opacity(0.08), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Scroll Motion

private struct HomeDashboardSectionMotionModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}

private extension View {
    func homeDashboardSectionMotion() -> some View {
        modifier(HomeDashboardSectionMotionModifier())
    }
}
