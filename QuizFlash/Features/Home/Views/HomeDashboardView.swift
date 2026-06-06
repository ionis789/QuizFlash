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

    private var studyHeroHeadlineHeight: CGFloat {
        usesRegularMetrics ? 128 : 112
    }

    private var performanceSurfaceMinHeight: CGFloat {
        usesRegularMetrics ? 216 : 198
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
        VStack(spacing: usesRegularMetrics ? 18 : 16) {
            studyHeroSurface
            performanceSurface
        }
    }

    private var studyHeroSurface: some View {
        let overview = dashboardSnapshot.selectedDayOverview
        let heroTint = overview.didReachGoal ? Color.green : dangerColor

        return HomeDashboardSurface(highlight: dangerColor, usesRegularMetrics: usesRegularMetrics) {
            VStack(alignment: .leading, spacing: usesRegularMetrics ? 24 : 20) {
                HStack(alignment: .top, spacing: usesRegularMetrics ? 18 : 14) {
                    VStack(alignment: .leading, spacing: usesRegularMetrics ? 12 : 10) {
                        Text(greetingTitle)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(themeManager.textSecondary)

                        Text(heroPrimaryTitle(for: overview))
                            .font(.system(size: usesRegularMetrics ? 38 : 32, weight: .black, design: .rounded))
                            .foregroundStyle(themeManager.textPrimary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .frame(
                                maxWidth: .infinity,
                                minHeight: studyHeroHeadlineHeight,
                                maxHeight: studyHeroHeadlineHeight,
                                alignment: .topLeading
                            )

                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    AnimatedProgressRing(
                        progress: overview.goalCompletionFraction,
                        trackColor: themeManager.textPrimary.opacity(0.10),
                        progressColor: heroTint,
                        size: usesRegularMetrics ? 112 : 102,
                        strokeWidth: 12
                    ) { animatedProgress in
                        Text("\(Int((animatedProgress * 100).rounded()))%")
                            .font(.system(size: usesRegularMetrics ? 25 : 23, weight: .black, design: .rounded))
                            .foregroundStyle(themeManager.textPrimary)
                            .minimumScaleFactor(0.72)
                            .lineLimit(1)
                            .contentTransition(.numericText(value: animatedProgress * 100))
                    }
                    .frame(width: usesRegularMetrics ? 116 : 106, alignment: .trailing)
                }

                HomeDashboardDailyOutcomePanel(
                    reviewedTitle: localized("Reviewed"),
                    goodTitle: localized("Good cards"),
                    retryTitle: localized("Retry cards"),
                    reviewedCount: overview.cardsReviewed,
                    goodCount: overview.correctCardCount,
                    retryCount: overview.retryCardCount,
                    neutralTint: accentColor,
                    goodTint: .green,
                    retryTint: roseColor,
                    usesRegularMetrics: usesRegularMetrics
                )
            }
            .frame(
                minHeight: studyHeroMinHeight,
                alignment: .topLeading
            )
        }
    }

    private func heroPrimaryTitle(for overview: HomeSelectedDayOverviewSummary) -> String {
        if overview.didReachGoal {
            return localized("Target cleared for today")
        }
        if overview.cardsReviewed == 0 {
            return localizedFormat("%d cards lined up today", overview.dailyGoal)
        }
        return overview.remainingCardsToGoal == 1
            ? localized("1 card left today")
            : localizedFormat("%d cards left today", overview.remainingCardsToGoal)
    }

    private func performanceTrendLine(for summary: HomePastWeekPerformanceSummary) -> String {
        guard summary.activeDays > 0 else {
            return localized("Needs attention")
        }

        switch summary.trend {
        case .improving:
            return localized("Improving day by day")
        case .steady:
            return localized("Stable this week")
        case .slipping:
            return localized("Needs attention")
        }
    }

    private func activeDaysPillText(for summary: HomePastWeekPerformanceSummary) -> String {
        if summary.activeDays == 1 {
            return localized("1 active day")
        }

        return localizedFormat("%d/%d active", summary.activeDays, summary.scoredDayCount)
    }

    private func goalDaysPillText(for summary: HomePastWeekPerformanceSummary) -> String {
        if summary.goalHitDays == 1 {
            return localized("1 goal day")
        }

        return localizedFormat("%d goal days", summary.goalHitDays)
    }

    private var performanceSurface: some View {
        let summary = dashboardSnapshot.pastWeekPerformance
        let goalDayTint: Color = summary.deltaPercent > 0 ? .green : (summary.deltaPercent < 0 ? dangerColor : accentColor)

        return Button {
            viewModel.presentPerformanceDetail()
        } label: {
            HomeDashboardSurface(highlight: accentColor, usesRegularMetrics: usesRegularMetrics) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: usesRegularMetrics ? 176 : 152, weight: .black, design: .rounded))
                        .foregroundStyle(accentColor.opacity(0.18))
                        .offset(x: usesRegularMetrics ? 18 : 22, y: usesRegularMetrics ? -26 : -18)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: usesRegularMetrics ? 20 : 18) {
                        HStack(alignment: .top, spacing: 14) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(localized("Performance"))
                                    .font(.system(size: usesRegularMetrics ? 24 : 22, weight: .black, design: .rounded))
                                    .foregroundStyle(themeManager.textPrimary)

                                Text(localized("this week"))
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(themeManager.textSecondary)
                            }

                            Spacer(minLength: 0)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(summary.scorePercent)%")
                                .font(.system(size: usesRegularMetrics ? 68 : 60, weight: .black, design: .rounded))
                                .foregroundStyle(themeManager.textPrimary)
                                .minimumScaleFactor(0.72)
                                .lineLimit(1)
                                .contentTransition(.numericText(value: Double(summary.scorePercent)))

                            Text(performanceTrendLine(for: summary))
                                .font(.system(size: usesRegularMetrics ? 22 : 20, weight: .bold, design: .rounded))
                                .foregroundStyle(themeManager.textPrimary)
                                .lineLimit(1)
                        }

                        HStack(alignment: .center, spacing: 12) {
                            HomeDashboardPill(
                                text: activeDaysPillText(for: summary),
                                tint: accentColor,
                                backgroundTint: accentColor.opacity(0.12)
                            )

                            HomeDashboardPill(
                                text: goalDaysPillText(for: summary),
                                tint: goalDayTint,
                                backgroundTint: goalDayTint.opacity(0.14)
                            )

                            Spacer(minLength: 0)
                        }
                    }
                    .frame(minHeight: performanceSurfaceMinHeight, alignment: .topLeading)
                }
            }
        }
        .buttonStyle(.plain)
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
                title: localized("Recents"),
                count: recentDeckSnapshots.count
            )
            recentDecksSurface
        }
    }

    private var recentDecksSurface: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(recentDeckSnapshots, id: \.id) { deck in
                HomeDashboardRecentDeckCard(
                    snapshot: deck,
                    usesRegularMetrics: usesRegularMetrics
                ) {
                    onOpenDeck(deck.id)
                }
            }
        }
    }

    private var foldersSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HomeDashboardSectionHeader(
                title: localized("Folders"),
                count: folderSnapshots.count,
                trailingAccessory: {
                    Button {
                        onCreateFolder()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: UIConstants.Size.iconStandard, weight: .bold))
                            .fontDesign(.rounded)
                    }

                }
            )

            foldersSurface
        }
    }

    private var foldersSurface: some View {
        VStack(alignment: .leading, spacing: 12) {
            if folderSnapshots.isEmpty {
                HomeDashboardSurface(highlight: dangerColor, usesRegularMetrics: usesRegularMetrics) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(localized("No folders yet"))
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text(localized("Create one from the section header."))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
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

            if usesDashboardColumns {
                HStack(alignment: .top, spacing: 14) {
                    createDeckSurface
                    workspaceWhatChangesSurface
                }
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    createDeckSurface
                    workspaceWhatChangesSurface
                }
            }
        }
    }

    private var createDeckSurface: some View {
        HomeDashboardSurface(highlight: accentColor, usesRegularMetrics: usesRegularMetrics) {
            VStack(alignment: .leading, spacing: 14) {
                Text(localized("Create a deck"))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Button(localized("Open Create")) {
                    onCreateDeck()
                }
                .font(.subheadline.weight(.bold))
                .quizFlashButtonStyle(.primary)
            }
        }
    }

    private var workspaceWhatChangesSurface: some View {
        HomeDashboardSurface(highlight: dangerColor, usesRegularMetrics: usesRegularMetrics) {
            VStack(alignment: .leading, spacing: 14) {
                Text(localized("Next"))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                VStack(alignment: .leading, spacing: 10) {
                    HomeDashboardNarrativeLine(
                        label: localized("Today"),
                        text: localized("Progress and pace.")
                    )
                    HomeDashboardNarrativeLine(
                        label: localized("Recents"),
                        text: localized("Jump back into active decks.")
                    )
                    HomeDashboardNarrativeLine(
                        label: localized("Folders"),
                        text: localized("Keep decks grouped and easy to scan.")
                    )
                }
            }
        }
    }
}

// MARK: - Folder Snapshot

struct HomeFolderSnapshot: Identifiable, Equatable {
    let id: PersistentIdentifier
    let title: String
    let colorHex: String
    let deckCount: Int
}

// MARK: - Section Header

private struct HomeDashboardSectionHeader: View {
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
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let count {
                        Text("(\(count))")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let trailingAccessory {
                trailingAccessory
            }
        }
    }
}

// MARK: - Dashboard Surface

private struct HomeDashboardSurface<Content: View>: View {
    @Environment(ThemeManager.self) private var themeManager

    let highlight: Color
    let usesRegularMetrics: Bool
    let content: Content

    init(
        highlight: Color,
        usesRegularMetrics: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.highlight = highlight
        self.usesRegularMetrics = usesRegularMetrics
        self.content = content()
    }

    private var cornerRadius: CGFloat {
        usesRegularMetrics ? 34 : 30
    }

    private var paddingValue: CGFloat {
        usesRegularMetrics ? 22 : 20
    }

    var body: some View {
        content
            .padding(paddingValue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(themeManager.roleColor(.widgetSurfaceFill))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.035), lineWidth: 1)
                    }
                    .shadow(color: Color.black.opacity(0.34), radius: 22, x: 0, y: 14)
            }
    }
}

// MARK: - Supporting Views

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
        .background {
            RoundedRectangle(cornerRadius: usesRegularMetrics ? 26 : 24, style: .continuous)
                .fill(themeManager.surfacePrimary)
                .overlay {
                    RoundedRectangle(cornerRadius: usesRegularMetrics ? 26 : 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.03), lineWidth: 1)
                }
        }
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
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(badgeTint.opacity(card.wasCorrectAtEndOfDay ? 0.18 : 0.22))
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
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
        .background {
            RoundedRectangle(cornerRadius: usesRegularMetrics ? 26 : 24, style: .continuous)
                .fill(themeManager.surfacePrimary)
        }
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

    private var surfaceColor: Color {
        themeManager.roleColor(.widgetSurfaceFill)
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
        .background(surfaceColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(surfaceColor)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(tint.opacity(0.10))
                }
        }
    }
}

private struct HomeDashboardNarrativeLine: View {
    let label: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption2.weight(.black))
                .foregroundStyle(.secondary)

            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
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

private struct HomeDashboardLibraryDeckRow: View {
    let snapshot: LibraryDeckRowSnapshot
    let isFirst: Bool
    let action: @MainActor @Sendable () -> Void

    var body: some View {
        LibraryDeckListRow(
            deck: snapshot,
            isFirstInSection: isFirst,
            isSelecting: false,
            isSelected: false,
            showsContextMenu: false,
            onNavigate: action,
            onToggleSelection: {},
            onExport: {},
            onMoveToFolder: {},
            onDelete: {}
        )
    }
}

private struct HomeDashboardRecentDeckCard: View {
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager

    let snapshot: LibraryDeckRowSnapshot
    let usesRegularMetrics: Bool
    let action: () -> Void

    private var deckColor: Color {
        Color(hex: snapshot.colorHex) ?? themeManager.brandPrimary
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Text(snapshot.title)
                    .font(.system(size: usesRegularMetrics ? 20 : 18, weight: .bold, design: .rounded))
                    .foregroundStyle(themeManager.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(
                    AppLocalization.numbered(
                        snapshot.cardCount,
                        singular: "%d card",
                        plural: "%d cards",
                        locale: appPreferences.resolvedLocale
                    )
                )
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(themeManager.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, usesRegularMetrics ? 18 : 16)
            .padding(.vertical, usesRegularMetrics ? 18 : 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: usesRegularMetrics ? 28 : 24, style: .continuous)
                    .fill(themeManager.roleColor(.widgetSurfaceFill))
                    .overlay {
                        RoundedRectangle(cornerRadius: usesRegularMetrics ? 28 : 24, style: .continuous)
                            .strokeBorder(deckColor.opacity(0.08), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
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
