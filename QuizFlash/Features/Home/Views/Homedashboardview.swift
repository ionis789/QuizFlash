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
    let folders: [FolderModel]
    let recentDecks: [DeckModel]
    let layoutContext: HomeAdaptiveLayoutContext
    let allDeckCount: Int
    let examGoals: [ExamGoalModel]
    let router: NavigationManager

    @Environment(\.modelContext) private var context
    @Environment(ThemeManager.self) private var themeManager

    // MARK: - Derived Data

    private var dashboardSnapshot: HomeDashboardSnapshot {
        viewModel.dashboardSnapshot
    }

    private var recentDeckSnapshots: [LibraryDeckRowSnapshot] {
        LibraryGrouping.makeDeckSnapshots(from: recentDecks)
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

    private var greetingTitle: String {
        let hour = Calendar.current.component(.hour, from: Date())

        switch hour {
        case 5..<12:
            return "Good morning"
        case 12..<17:
            return "Good afternoon"
        case 17..<22:
            return "Good evening"
        default:
            return "Good night"
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

    private var showsExamGoalsSection: Bool {
        !examGoals.isEmpty || !showsWorkspaceOnboarding
    }

    private var showsLibrarySection: Bool {
        !recentDecks.isEmpty || !folders.isEmpty || (!showsWorkspaceOnboarding && allDeckCount > 0)
    }

    private var sectionSpacing: CGFloat {
        usesRegularMetrics ? 24 : 20
    }

    private var studyHeroMinHeight: CGFloat {
        usesRegularMetrics ? 282 : 256
    }

    private var performanceSurfaceMinHeight: CGFloat {
        usesRegularMetrics ? 240 : 220
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

            if showsExamGoalsSection {
                boundedSection(examGoalsSection)
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

    private func openDeck(_ deckID: PersistentIdentifier) {
        router.append(
            DeckNavigationValue(
                deckID: deckID,
                backLabel: router.activeTab.rawValue
            )
        )
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
                            .fixedSize(horizontal: false, vertical: true)
                            .statusTextMotion(trigger: overview.remainingCardsToGoal)

                        Text(heroSecondaryLine(for: overview))
                            .font(.system(size: usesRegularMetrics ? 17 : 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(themeManager.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    AnimatedProgressRing(
                        progress: overview.goalCompletionFraction,
                        trackColor: themeManager.textPrimary.opacity(0.10),
                        progressColor: heroTint,
                        size: usesRegularMetrics ? 112 : 102,
                        strokeWidth: 12
                    ) { animatedProgress in
                        VStack(spacing: 2) {
                            Text("\(Int((animatedProgress * 100).rounded()))%")
                                .font(.system(size: usesRegularMetrics ? 25 : 23, weight: .black, design: .rounded))
                                .foregroundStyle(themeManager.textPrimary)
                                .minimumScaleFactor(0.72)
                                .lineLimit(1)
                                .contentTransition(.numericText(value: animatedProgress * 100))

                            Text("done")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(themeManager.textSecondary)
                        }
                    }
                    .frame(width: usesRegularMetrics ? 116 : 106, alignment: .trailing)
                }

                HStack(spacing: 12) {
                    HomeDashboardHeroStatTile(
                        title: "Reviewed",
                        value: "\(overview.cardsReviewed)",
                        detail: overview.rawReviewCount > overview.cardsReviewed
                            ? "\(overview.rawReviewCount) passes today"
                            : "unique cards today",
                        tint: heroTint,
                        usesRegularMetrics: usesRegularMetrics
                    )

                    HomeDashboardHeroStatTile(
                        title: "Landed",
                        value: "\(overview.correctCardCount)",
                        detail: overview.retryCardCount == 0
                            ? "clean finish"
                            : "\(overview.retryCardCount) still shaky",
                        tint: roseColor,
                        usesRegularMetrics: usesRegularMetrics
                    )

                    HomeDashboardHeroStatTile(
                        title: "Streak",
                        value: "\(overview.streakCount)",
                        detail: overview.streakCount == 1 ? "day live" : "days live",
                        tint: .green,
                        usesRegularMetrics: usesRegularMetrics
                    )
                }
            }
            .frame(
                minHeight: studyHeroMinHeight,
                alignment: .topLeading
            )
        }
    }

    private func heroPrimaryTitle(for overview: HomeSelectedDayOverviewSummary) -> String {
        if overview.didReachGoal {
            return "Target cleared for today"
        }
        if overview.cardsReviewed == 0 {
            return "\(overview.dailyGoal) cards lined up today"
        }
        return overview.remainingCardsToGoal == 1
            ? "1 card left today"
            : "\(overview.remainingCardsToGoal) cards left today"
    }

    private func heroSecondaryLine(for overview: HomeSelectedDayOverviewSummary) -> String {
        if overview.didReachGoal {
            return "\(overview.cardsReviewed) unique cards are locked in for today."
        }
        if overview.cardsReviewed == 0 {
            return "Start with one focused block and let the ring fill with you."
        }
        return "\(overview.cardsReviewed) unique cards already count toward today's target of \(overview.dailyGoal)."
    }

    private var performanceSurface: some View {
        let summary = dashboardSnapshot.pastWeekPerformance
        let deltaTint: Color = summary.deltaPercent > 0 ? .green : (summary.deltaPercent < 0 ? dangerColor : accentColor)

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
                                Text("Performance")
                                    .font(.system(size: usesRegularMetrics ? 24 : 22, weight: .black, design: .rounded))
                                    .foregroundStyle(themeManager.textPrimary)

                                Text("in the past 7 days")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(themeManager.textSecondary)
                            }

                            Spacer(minLength: 0)

                            HStack(spacing: 10) {
                                HomePerformanceDeltaBadge(
                                    deltaPercent: summary.deltaPercent,
                                    tint: deltaTint,
                                    backgroundTint: deltaTint.opacity(0.14)
                                )

                                Image(systemName: "arrow.up.right.circle.fill")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(themeManager.textPrimary.opacity(0.92))
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(summary.scorePercent)%")
                                .font(.system(size: usesRegularMetrics ? 68 : 60, weight: .black, design: .rounded))
                                .foregroundStyle(themeManager.textPrimary)
                                .minimumScaleFactor(0.72)
                                .lineLimit(1)
                                .contentTransition(.numericText(value: Double(summary.scorePercent)))

                            Text(summary.trendLine)
                                .font(.system(size: usesRegularMetrics ? 22 : 20, weight: .bold, design: .rounded))
                                .foregroundStyle(themeManager.textPrimary)
                                .lineLimit(1)
                        }

                        Text(summary.supportingLine)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(themeManager.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(alignment: .center, spacing: 12) {
                            HomeDashboardPill(
                                text: summary.activeDays == 1 ? "1 active day" : "\(summary.activeDays)/7 active",
                                tint: accentColor,
                                backgroundTint: accentColor.opacity(0.12)
                            )

                            HomeDashboardPill(
                                text: summary.goalHitDays == 1 ? "1 goal day" : "\(summary.goalHitDays) goal days",
                                tint: deltaTint,
                                backgroundTint: deltaTint.opacity(0.14)
                            )

                            Spacer(minLength: 0)

                            Text("Open analysis")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(themeManager.textPrimary)
                        }
                    }
                    .frame(minHeight: performanceSurfaceMinHeight, alignment: .topLeading)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Exam Goals

    private var examGoalsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HomeDashboardSectionHeader(
                title: "Exams",
                accessory: {
                    Button {
                        viewModel.presentCreateExamGoal()
                    } label: {
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .quizFlashButtonStyle(.accentAlt, shape: .circle, size: 38)
                }
            )

            if examGoals.isEmpty {
                HomeDashboardSurface(highlight: dangerColor, usesRegularMetrics: usesRegularMetrics) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("No exam goals")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Button("Create exam goal") {
                            viewModel.presentCreateExamGoal()
                        }
                        .font(.subheadline.weight(.bold))
                        .quizFlashButtonStyle(.primary)
                    }
                }
            } else {
                if let examPressure = dashboardSnapshot.examPressure
                    ?? dashboardSnapshot.upcomingExamSummaries.first.map(Self.fallbackPressureSummary) {
                    HomeDashboardSurface(highlight: dangerColor, usesRegularMetrics: usesRegularMetrics) {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .top, spacing: 12) {
                                Text("Most urgent")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                Spacer(minLength: 0)

                                HomeDashboardPill(
                                    text: examPressure.countdownLabel,
                                    tint: dangerColor,
                                    backgroundTint: roseColor
                                )
                            }

                            Text(examPressure.headline)
                                .font(.system(size: usesRegularMetrics ? 22 : 20, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)

                            HStack(spacing: 12) {
                                HomeDashboardMiniStat(label: "Ready", value: "\(Int((examPressure.readinessFraction * 100).rounded()))%", tint: .green)
                                HomeDashboardMiniStat(
                                    label: "Pace",
                                    value: "\(examPressure.dailyPaceNeeded)/d",
                                    tint: dangerColor,
                                    backgroundTint: roseColor
                                )
                                HomeDashboardMiniStat(
                                    label: "Due",
                                    value: examPressure.countdownLabel,
                                    tint: dangerColor,
                                    backgroundTint: roseColor
                                )
                            }
                        }
                    }
                }

                HomeDashboardSurface(highlight: accentColor, usesRegularMetrics: usesRegularMetrics) {
                    VStack(alignment: .leading, spacing: 0) {
                        if !dashboardSnapshot.selectedDayExamSummaries.isEmpty {
                            HomeDashboardSubsectionLabel("Selected day")
                                .padding(.bottom, 12)

                            examGoalRows(dashboardSnapshot.selectedDayExamSummaries)
                                .padding(.bottom, dashboardSnapshot.upcomingExamSummaries.isEmpty ? 0 : 18)

                            if !dashboardSnapshot.upcomingExamSummaries.isEmpty {
                                Divider()
                                    .overlay(Color.white.opacity(0.08))
                                    .padding(.bottom, 18)
                            }
                        }

                        if !dashboardSnapshot.upcomingExamSummaries.isEmpty {
                            HomeDashboardSubsectionLabel("Upcoming")
                                .padding(.bottom, 12)

                            examGoalRows(dashboardSnapshot.upcomingExamSummaries)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func examGoalRows(_ summaries: [HomeExamGoalSummary]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(summaries.enumerated()), id: \.element.id) { index, summary in
                HomeDashboardExamGoalRow(
                    summary: summary,
                    onOpenDeck: { deckID in
                        openDeck(deckID)
                    },
                    onEdit: {
                        guard let goal = examGoal(for: summary.id) else { return }
                        viewModel.presentExamGoalEditor(for: goal)
                    },
                    onStatusChange: { status in
                        guard let goal = examGoal(for: summary.id) else { return }
                        viewModel.updateExamGoalStatus(status, for: goal, context: context)
                    }
                )

                if index < summaries.count - 1 {
                    Divider()
                        .overlay(Color.white.opacity(0.08))
                        .padding(.vertical, 16)
                }
            }
        }
    }

    private func examGoal(for id: PersistentIdentifier) -> ExamGoalModel? {
        examGoals.first(where: { $0.persistentModelID == id })
    }

    // MARK: - Library

    private var librarySection: some View {
        Group {
            if usesDashboardColumns {
                HStack(alignment: .top, spacing: 14) {
                    if !recentDecks.isEmpty {
                        recentDecksSection
                    }
                    foldersSection
                }
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    if !recentDecks.isEmpty {
                        recentDecksSection
                    }
                    foldersSection
                }
            }
        }
    }

    private var recentDecksSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HomeDashboardSectionHeader(title: "Recents")
            recentDecksSurface
        }
    }

    private var recentDecksSurface: some View {
        HomeDashboardSurface(highlight: accentColor, usesRegularMetrics: usesRegularMetrics) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(recentDeckSnapshots.enumerated()), id: \.element.id) { index, deck in
                    HomeDashboardLibraryDeckRow(
                        snapshot: deck,
                        isFirst: index == 0
                    ) {
                        openDeck(deck.id)
                    }
                }
            }
        }
    }

    private var foldersSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HomeDashboardSectionHeader(
                title: "Folders",
                accessory: {
                    HStack(spacing: 10) {
                        if !folders.isEmpty {
                            HomeDashboardPill(text: "\(folders.count)", tint: dangerColor, backgroundTint: roseColor)
                        }

                        Button {
                            viewModel.showCreateFolder = true
                        } label: {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 16, weight: .bold))
                        }
                        .quizFlashButtonStyle(.accentAlt, shape: .circle, size: 34)
                    }
                }
            )

            foldersSurface
        }
    }

    private var foldersSurface: some View {
        HomeDashboardSurface(highlight: dangerColor, usesRegularMetrics: usesRegularMetrics) {
            VStack(alignment: .leading, spacing: 0) {
                if folders.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No folders yet")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text("Create one from the section header.")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(Array(folders.enumerated()), id: \.element.persistentModelID) { index, folder in
                        HomeDashboardFolderRow(folder: folder) {
                            router.append(AppRoute.folder(folder, backLabel: router.activeTab.rawValue))
                        }

                        if index < folders.count - 1 {
                            Divider()
                                .overlay(Color.white.opacity(0.08))
                                .padding(.vertical, 12)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Workspace

    private var workspaceSetupSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HomeDashboardSectionHeader(title: "Get started")

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
                Text("Create a deck")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Button("Open Create") {
                    router.activeTab = .create
                }
                .font(.subheadline.weight(.bold))
                .quizFlashButtonStyle(.primary)
            }
        }
    }

    private var workspaceWhatChangesSurface: some View {
        HomeDashboardSurface(highlight: dangerColor, usesRegularMetrics: usesRegularMetrics) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Next")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                VStack(alignment: .leading, spacing: 10) {
                    HomeDashboardNarrativeLine(
                        label: "Today",
                        text: "Progress and pace."
                    )
                    HomeDashboardNarrativeLine(
                        label: "Exams",
                        text: "Readiness and workload."
                    )
                    HomeDashboardNarrativeLine(
                        label: "Library",
                        text: "Recent decks and folders."
                    )
                }
            }
        }
    }

    nonisolated private static func fallbackPressureSummary(from summary: HomeExamGoalSummary) -> HomeExamPressureSummary {
        let trimmedNote = summary.note.trimmingCharacters(in: .whitespacesAndNewlines)

        return HomeExamPressureSummary(
            goalID: summary.id,
            goalTitle: summary.title,
            countdownLabel: summary.countdownLabel,
            readinessFraction: summary.readinessFraction,
            headline: summary.summaryLine,
            detailLine: trimmedNote.isEmpty ? summary.dateLabel : trimmedNote,
            actionLine: "\(summary.dailyPaceNeeded)/day",
            overdueCards: summary.overdueCount,
            dailyPaceNeeded: summary.dailyPaceNeeded,
            belowTargetDeckCount: summary.belowTargetDeckCount,
            weakestDeckTitle: summary.weakestDeck?.title,
            weakestDeckReadinessFraction: summary.weakestDeck?.readinessFraction
        )
    }
}

// MARK: - Section Header

private struct HomeDashboardSectionHeader: View {
    let title: String
    let subtitle: String?
    let accessory: AnyView?

    init(
        title: String,
        subtitle: String? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = nil
    }

    init<Accessory: View>(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = AnyView(accessory())
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let accessory {
                accessory
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

private struct HomeDashboardHeroStatTile: View {
    @Environment(ThemeManager.self) private var themeManager

    let title: String
    let value: String
    let detail: String
    let tint: Color
    let usesRegularMetrics: Bool

    private var cornerRadius: CGFloat {
        usesRegularMetrics ? 26 : 22
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(themeManager.textSecondary)

            Text(value)
                .font(.system(size: usesRegularMetrics ? 34 : 30, weight: .black, design: .rounded))
                .foregroundStyle(themeManager.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .statusTextMotion(trigger: value)

            Text(detail)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(themeManager.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: usesRegularMetrics ? 132 : 122, alignment: .topLeading)
        .padding(.horizontal, usesRegularMetrics ? 16 : 14)
        .padding(.vertical, usesRegularMetrics ? 16 : 14)
        .background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(themeManager.surfacePrimary)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(tint.opacity(0.12))
                }
        }
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

private struct HomeDashboardMiniStat: View {
    @Environment(ThemeManager.self) private var themeManager

    let label: String
    let value: String
    let tint: Color
    let backgroundTint: Color?

    init(
        label: String,
        value: String,
        tint: Color,
        backgroundTint: Color? = nil
    ) {
        self.label = label
        self.value = value
        self.tint = tint
        self.backgroundTint = backgroundTint
    }

    private var surfaceColor: Color {
        themeManager.surfacePrimary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)

                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(surfaceColor)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill((backgroundTint ?? tint).opacity(0.14))
                }
        }
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

private struct HomeDashboardSubsectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.black))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

private struct HomeDashboardExamGoalRow: View {
    @Environment(ThemeManager.self) private var themeManager

    let summary: HomeExamGoalSummary
    let onOpenDeck: (PersistentIdentifier) -> Void
    let onEdit: () -> Void
    let onStatusChange: (ExamGoalStatus) -> Void

    private var deckPreviewSnapshots: [LibraryDeckRowSnapshot] {
        summary.deckSummaries
            .sorted { lhs, rhs in
                if lhs.readinessFraction != rhs.readinessFraction {
                    return lhs.readinessFraction < rhs.readinessFraction
                }
                return lhs.remainingCards > rhs.remainingCards
            }
            .prefix(2)
            .map { deck in
                LibraryDeckRowSnapshot(
                    id: deck.id,
                    title: deck.title,
                    colorHex: deck.colorHex,
                    createdAt: summary.date,
                    editedAt: summary.date,
                    lastOpenedAt: nil,
                    cardCount: deck.totalCards,
                    folderTitle: nil
                )
            }
    }

    private var remainingDeckPreviewCount: Int {
        max(summary.deckSummaries.count - deckPreviewSnapshots.count, 0)
    }

    private var dangerColor: Color {
        themeManager.dangerPrimary
    }

    private var roseColor: Color {
        themeManager.highlightRose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(summary.title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(summary.summaryLine)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 10) {
                    HomeDashboardPill(
                        text: summary.countdownLabel,
                        tint: summary.status == .completed ? .green : dangerColor,
                        backgroundTint: summary.status == .completed ? .green : roseColor
                    )

                    HStack(spacing: 8) {
                        Button(action: onEdit) {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .quizFlashButtonStyle(.surface, shape: .circle, size: 30)

                        Menu {
                            ForEach(ExamGoalStatus.allCases) { status in
                                Button {
                                    onStatusChange(status)
                                } label: {
                                    Label(status.title, systemImage: status.systemImage)
                                }
                            }
                        } label: {
                            Image(systemName: summary.status.systemImage)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(statusTint)
                                .frame(width: 30, height: 30)
                                .background(statusTint.opacity(0.14), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 10) {
                HomeDashboardPill(
                    text: "\(Int((summary.readinessFraction * 100).rounded()))% ready",
                    tint: .green
                )
                HomeDashboardPill(
                    text: "\(summary.dailyPaceNeeded)/day",
                    tint: dangerColor,
                    backgroundTint: roseColor
                )
            }

            if !deckPreviewSnapshots.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(deckPreviewSnapshots.enumerated()), id: \.element.id) { index, deck in
                        HomeDashboardLibraryDeckRow(
                            snapshot: deck,
                            isFirst: index == 0
                        ) {
                            onOpenDeck(deck.id)
                        }
                    }

                    if remainingDeckPreviewCount > 0 {
                        Text("+\(remainingDeckPreviewCount) more deck" + (remainingDeckPreviewCount == 1 ? "" : "s"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 10)
                            .padding(.leading, 4)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private var statusTint: Color {
        switch summary.status {
        case .active:
            return dangerColor
        case .completed:
            return .green
        case .archived:
            return .secondary
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

private struct HomePerformanceDeltaBadge: View {
    let deltaPercent: Int
    let tint: Color
    let backgroundTint: Color

    private var text: String {
        if deltaPercent > 0 {
            return "+\(deltaPercent) vs prev"
        }
        if deltaPercent < 0 {
            return "\(deltaPercent) vs prev"
        }
        return "0 vs prev"
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                Capsule(style: .continuous)
                    .fill(backgroundTint)
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
            onImport: {},
            onMoveToFolder: {},
            onDelete: {}
        )
    }
}

private struct HomeDashboardFolderRow: View {
    @Environment(ThemeManager.self) private var themeManager

    let folder: FolderModel
    let action: () -> Void

    private var folderColor: Color {
        Color(hex: folder.colorHex) ?? themeManager.brandPrimary
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(folderColor.opacity(0.14))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(folderColor)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(folder.title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text("\(folder.deckCount) deck" + (folder.deckCount == 1 ? "" : "s"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(folderColor)
            }
            .contentShape(Rectangle())
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
