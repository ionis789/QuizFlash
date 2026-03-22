// HomeDashboardView.swift
// QuizFlash
//
// Renders the scrollable dashboard content below the sticky calendar header.
// This view is purely presentational — all state and logic live in HomeViewModel
// and CalendarViewModel, passed in as immutable constants.

import SwiftUI
import SwiftData

// MARK: - Home Dashboard View

/// The scrollable body of the Home screen, rendered below the collapsible calendar header.
///
/// Displays Home's analytics and navigation surfaces in order:
/// 1. **Overview** — the selected-day hero and momentum insights.
/// 2. **Exam Goals** — readiness and agenda around upcoming deadlines.
/// 3. **Deck Health** — the decks that most need attention right now.
/// 4. **Recent Decks** — a horizontal carousel of recently opened decks.
/// 5. **Folders** — a two-column grid of user folders.
///
/// `HomeDashboardView` is a **dumb view**: it holds no `@State`, makes no decisions,
/// and contains no formatting logic. All data arrives as `let` constants from `HomeView`.
struct HomeDashboardView: View {

    private let contentHorizontalInset = UIConstants.Layout.homeContentEdgeInset
    private let topSectionInset: CGFloat = 0

    // MARK: - Dependencies

    /// Business logic and sheet state for the Home screen.
    let viewModel: HomeViewModel

    /// The list of folders fetched by `HomeView`'s `@Query`.
    let folders: [FolderModel]

    /// The top 5 recently opened decks, pre-filtered and pre-sliced by `HomeView`.
    let recentDecks: [DeckModel]

    /// Persisted exam goals fetched by `HomeView`.
    let examGoals: [ExamGoalModel]

    /// The global navigation router for pushing deck and folder destinations.
    let router: NavigationManager

    @Environment(\.modelContext) private var context

    // MARK: - Derived Data

    /// Cached analytics snapshot derived in `HomeViewModel`.
    private var dashboardSnapshot: HomeDashboardSnapshot {
        viewModel.dashboardSnapshot
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            statsSection
                .padding(.top, topSectionInset)
                .padding(.horizontal, contentHorizontalInset)
                .homeDashboardSectionMotion()

            examGoalsSection
                .padding(.top, UIConstants.Layout.sectionSpacing)
                .padding(.horizontal, contentHorizontalInset)
                .homeDashboardSectionMotion()

            if !viewModel.deckHealthSummaries.isEmpty {
                deckHealthSection
                    .padding(.top, UIConstants.Layout.sectionSpacing)
                    .padding(.horizontal, contentHorizontalInset)
                    .homeDashboardSectionMotion()
            }

            if !recentDecks.isEmpty {
                recentDecksSection
                    .padding(.top, UIConstants.Layout.sectionSpacing)
                    .homeDashboardSectionMotion()
            }

            foldersSection
                .padding(.top, UIConstants.Layout.sectionSpacing)
                .padding(.horizontal, contentHorizontalInset)
                .homeDashboardSectionMotion()

            Spacer(minLength: 150)
        }
    }

    // MARK: - Deck Health Section

    /// Renders the highest-priority deck summaries so Home can steer the next study action.
    private var deckHealthSection: some View {
        HomeDeckHealthSection(
            summaries: viewModel.deckHealthSummaries,
            onOpenDeck: { deckID in
                router.append(
                    DeckNavigationValue(
                        deckID: deckID,
                        backLabel: router.activeTab.rawValue
                    )
                )
            }
        )
    }

    // MARK: - Exam Goals Section

    /// Renders Home-level upcoming exam readiness plus selected-day exam agenda.
    private var examGoalsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Exam Goals")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)

                Spacer()

                Button {
                    viewModel.presentCreateExamGoal()
                } label: {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: UIConstants.Size.actionIcon, weight: .semibold))
                        .foregroundStyle(ThemeManager.shared.accentColor.color)
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: UIConstants.Size.actionButton, height: UIConstants.Size.actionButton)
                        .glassButton(shape: .circle)
                }
                .buttonStyle(.plain)
            }

            if examGoals.isEmpty {
                HomeExamGoalsEmptyCard {
                    viewModel.presentCreateExamGoal()
                }
            } else {
                if let examPressure = dashboardSnapshot.examPressure {
                    HomeExamPressureCard(summary: examPressure)
                }

                if let examNarrative = dashboardSnapshot.examNarrative,
                   !examNarrative.visibleLines.isEmpty {
                    HomeExamNarrativeCard(lines: examNarrative.visibleLines)
                }

                if !dashboardSnapshot.selectedDayExamSummaries.isEmpty {
                    VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                        Text("Selected Day")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.secondary)

                        ForEach(dashboardSnapshot.selectedDayExamSummaries) { summary in
                            HomeSelectedDayExamCard(
                                summary: summary,
                                onEdit: {
                                    guard let goal = examGoal(for: summary.id) else { return }
                                    viewModel.presentExamGoalEditor(for: goal)
                                },
                                onStatusChange: { status in
                                    guard let goal = examGoal(for: summary.id) else { return }
                                    viewModel.updateExamGoalStatus(status, for: goal, context: context)
                                }
                            )
                        }
                    }
                }

                VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                    Text("Upcoming")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)

                    ForEach(dashboardSnapshot.upcomingExamSummaries) { summary in
                        HomeExamGoalSummaryCard(
                            summary: summary,
                            onEdit: {
                                guard let goal = examGoal(for: summary.id) else { return }
                                viewModel.presentExamGoalEditor(for: goal)
                            },
                            onStatusChange: { status in
                                guard let goal = examGoal(for: summary.id) else { return }
                                viewModel.updateExamGoalStatus(status, for: goal, context: context)
                            }
                        )
                    }
                }
            }
        }
    }

    private func examGoal(for id: PersistentIdentifier) -> ExamGoalModel? {
        examGoals.first(where: { $0.persistentModelID == id })
    }

    // MARK: - Daily Activity Section

    /// Renders the selected-day hero plus action-oriented learning insights.
    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HomeAnalyticsHeroCard(
                overview: dashboardSnapshot.selectedDayOverview,
                weeklyMomentum: dashboardSnapshot.weeklyMomentum
            )

            HomeSelectedDayInsightsCard(summary: dashboardSnapshot.selectedDayInsight)

            HomeWeeklyMomentumCard(summary: dashboardSnapshot.weeklyMomentum)
        }
    }

    // MARK: - Recent Decks Section

    /// Renders a horizontally scrollable carousel of recently opened deck cards.
    private var recentDecksSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent Decks")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, contentHorizontalInset)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(recentDecks) { deck in
                        HomeRecentDeckCardView(deck: deck) {
                            // Back label is frozen at push time — immune to cross-tab
                            // mutation of router.activeTab during tab-switch animations.
                            router.append(DeckNavigationValue(
                                deckID: deck.persistentModelID,
                                backLabel: router.activeTab.rawValue
                            ))
                        }
                    }
                }
                .padding(.horizontal, contentHorizontalInset)
                // Extra vertical padding so card drop shadows are not clipped.
                .padding(.bottom, 16)
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Folders Section

    /// Renders the folder grid, including the "add folder" header button and an empty state.
    private var foldersSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Folders")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)

                Spacer()

                // Uses the current theme accent colour — no hardcoded colours.
                Button {
                    viewModel.showCreateFolder = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: UIConstants.Size.actionIcon, weight: .semibold))
                        .foregroundStyle(ThemeManager.shared.accentColor.color)
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: UIConstants.Size.actionButton, height: UIConstants.Size.actionButton)
                        .glassButton(shape: .circle)
                }
                .buttonStyle(.plain)
            }

            if folders.isEmpty {
                EmptyStatePlaceholderFolderCard(
                    icon: "folder.badge.plus",
                    message: "No folders yet. Create one to organize your decks."
                )
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)],
                    spacing: 16
                ) {
                    ForEach(folders) { folder in
                        FolderCardView(folder: folder) {
                            // Back label is frozen at push time — immune to subsequent
                            // router.activeTab mutations during tab-switch animations.
                            router.append(AppRoute.folder(folder, backLabel: router.activeTab.rawValue))
                        }
                    }
                }
            }
        }
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
