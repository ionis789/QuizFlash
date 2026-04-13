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

    private var surfaceColor: Color {
        themeManager.roleColor(.widgetSurfaceFill)
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
        VStack(alignment: .leading, spacing: 14) {
            HomeDashboardSectionHeader(title: greetingTitle)

            if usesDashboardColumns {
                HStack(alignment: .top, spacing: 14) {
                    selectedDaySurface
                    studyTrendSurface
                }
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    selectedDaySurface
                    studyTrendSurface
                }
            }
        }
    }

    private var selectedDaySurface: some View {
        let overview = dashboardSnapshot.selectedDayOverview

        return HomeDashboardSurface(highlight: dangerColor, usesRegularMetrics: usesRegularMetrics) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    Text("Today")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)

                    HomeDashboardPill(
                        text: overview.didReachGoal ? "Done" : "\(overview.remainingCardsToGoal) left",
                        tint: overview.didReachGoal ? .green : dangerColor,
                        backgroundTint: overview.didReachGoal ? .green : roseColor
                    )
                }

                Text(overview.headline)
                    .font(.system(size: usesRegularMetrics ? 26 : 23, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                HomeDashboardProgressBar(
                    progress: overview.goalCompletionFraction,
                    tint: overview.didReachGoal ? .green : dangerColor
                )

                HStack(spacing: 10) {
                    HomeDashboardMiniStat(label: "Reviewed", value: "\(overview.cardsReviewed)", tint: accentColor)
                    HomeDashboardMiniStat(
                        label: "Goal",
                        value: "\(overview.dailyGoal)",
                        tint: dangerColor,
                        backgroundTint: roseColor
                    )
                    HomeDashboardMiniStat(label: "Streak", value: "\(overview.streakCount)", tint: .green)
                }
            }
        }
    }

    private var studyTrendSurface: some View {
        let momentum = dashboardSnapshot.weeklyMomentum

        return HomeDashboardSurface(highlight: accentColor, usesRegularMetrics: usesRegularMetrics) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Trend")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)

                    HomeDashboardRangeStub()
                }

                Text(momentum.headline)
                    .font(.system(size: usesRegularMetrics ? 24 : 21, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                HomeDashboardTrendPlaceholder()

                HStack(spacing: 12) {
                    HomeDashboardMiniStat(label: "Active", value: "\(momentum.activeDays)/7", tint: accentColor)
                    HomeDashboardMiniStat(label: "Goals", value: "\(momentum.goalHitDays)", tint: .green)
                    HomeDashboardMiniStat(
                        label: "Avg",
                        value: "\(momentum.averageCardsPerActiveDay)",
                        tint: dangerColor,
                        backgroundTint: roseColor
                    )
                }

            }
        }
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
        usesRegularMetrics ? 28 : 24
    }

    private var paddingValue: CGFloat {
        usesRegularMetrics ? 18 : 16
    }

    var body: some View {
        content
            .padding(paddingValue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.backgroundSecondary)
                    .overlay(alignment: .topLeading) {
                        Capsule(style: .continuous)
                            .fill(highlight)
                            .frame(width: usesRegularMetrics ? 58 : 48, height: 5)
                            .padding(.top, 14)
                            .padding(.leading, 16)
                    }
                    .shadow(color: Color.black.opacity(0.38), radius: 22, x: 0, y: 14)
            }
    }
}

// MARK: - Supporting Views

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
