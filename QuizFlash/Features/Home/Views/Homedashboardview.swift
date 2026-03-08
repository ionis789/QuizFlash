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
/// Displays three sections in order:
/// 1. **Daily Activity** — stats for the currently selected calendar day.
/// 2. **Recent Decks** — a horizontal carousel of recently opened decks (shown only when non-empty).
/// 3. **Folders** — a two-column grid of user folders.
///
/// `HomeDashboardView` is a **dumb view**: it holds no `@State`, makes no decisions,
/// and contains no formatting logic. All data arrives as `let` constants from `HomeView`.
struct HomeDashboardView: View {

    // MARK: - Dependencies

    /// Business logic and sheet state for the Home screen.
    let viewModel: HomeViewModel

    /// The list of folders fetched by `HomeView`'s `@Query`.
    let folders: [FolderModel]

    /// The top 5 recently opened decks, pre-filtered and pre-sliced by `HomeView`.
    let recentDecks: [DeckModel]

    /// The active user profile, used to display the current study streak.
    let userProfile: UserProfile?

    /// The calendar view model; provides the selected date for looking up the day's log.
    let calendarVM: CalendarViewModel

    /// The global navigation router for pushing deck and folder destinations.
    let router: NavigationManager

    // MARK: - Derived Data

    /// The activity log for the date currently selected in the calendar.
    ///
    /// Uses the O(1) cache lookup from `HomeViewModel` to avoid scanning the full log array.
    private var selectedDayLog: DailyActivityLog? {
        viewModel.getFastLog(for: calendarVM.selectedDate)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            statsSection
                .padding(.top, UIConstants.Layout.homeDashboardTopPadding)
                .padding(.horizontal, UIConstants.Layout.screenEdgeInset)

            if !recentDecks.isEmpty {
                recentDecksSection
                    .padding(.top, UIConstants.Layout.sectionSpacing)
            }

            foldersSection
                .padding(.top, UIConstants.Layout.sectionSpacing)
                .padding(.horizontal, UIConstants.Layout.screenEdgeInset)

            Spacer(minLength: 150)
        }
    }

    // MARK: - Daily Activity Section

    /// Renders the hero goal-progress card and three compact secondary stat cards.
    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Daily Activity")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(.primary)

            // Hero card: daily cards reviewed vs. goal.
            DailyGoalProgressCard(
                cardsReviewed: selectedDayLog?.cardsReviewed ?? 0,
                dailyGoal: selectedDayLog?.dailyGoal ?? 50
            )

            // Secondary stats: XP, Streak, Learned — compact horizontal grid.
            HStack(spacing: 12) {
                MiniStatCardView(
                    title: "XP",
                    value: "\(selectedDayLog?.xpEarnedToday ?? 0)",
                    icon: "star.fill",
                    color: .orange
                )

                MiniStatCardView(
                    title: "Streak",
                    value: "\(userProfile?.currentStreak ?? 0)",
                    icon: "flame.fill",
                    color: .red
                )

                MiniStatCardView(
                    title: "Learned",
                    value: "\(selectedDayLog?.newCardsLearned ?? 0)",
                    icon: "brain.head.profile",
                    color: .purple
                )
            }
        }
    }

    // MARK: - Recent Decks Section

    /// Renders a horizontally scrollable carousel of recently opened deck cards.
    private var recentDecksSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent Decks")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, UIConstants.Layout.screenEdgeInset)

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
                .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
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
