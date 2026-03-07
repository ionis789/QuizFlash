// HomeDashboardView.swift
// QuizFlash
//
// Renders the scrollable dashboard content below the sticky calendar header.
// This view is purely presentational — all state and logic live in HomeViewModel
// and CalendarViewModel, passed in as constants.

import SwiftUI
import SwiftData

// MARK: - Home Dashboard View

/// The scrollable body of the Home screen, rendered below the collapsible calendar header.
///
/// Displays three sections in order:
/// 1. **Daily Activity** — stats for the selected calendar day.
/// 2. **Recent Decks** — a horizontal carousel of recently opened decks (if any).
/// 3. **Folders** — a two-column grid of user folders.
struct HomeDashboardView: View {

    // MARK: - Properties

    let viewModel: HomeViewModel
    let folders: [FolderModel]
    let recentDecks: [DeckModel]
    let userProfile: UserProfile?
    let calendarVM: CalendarViewModel
    let router: NavigationManager

    // MARK: - Derived Data

    /// Activity log for the date currently selected in the calendar.
    private var selectedDayLog: DailyActivityLog? {
        viewModel.getFastLog(for: calendarVM.selectedDate)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            statsSection
                .padding(.top, 25)
                .padding(.horizontal, 20)

            if !recentDecks.isEmpty {
                recentDecksSection
                    .padding(.top, 24)
            }

            foldersSection
                .padding(.top, 24)
                .padding(.horizontal, 20)

            Spacer(minLength: 150)
        }
    }

    // MARK: - Daily Activity Section

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

    private var recentDecksSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent Decks")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(recentDecks) { deck in
                        HomeRecentDeckCardView(deck: deck) {
                            // Back label is frozen at push time — immune to cross-tab
                            // mutation of router state. HomeDashboardView is always
                            // rendered inside the Home tab's NavigationStack, so
                            // router.activeTab.rawValue == AppTab.home.rawValue here.
                            router.append(DeckNavigationValue(
                                deckID: deck.persistentModelID,
                                backLabel: router.activeTab.rawValue
                            ))
                        }
                    }
                }
                    .padding(.horizontal, 20)
                // Extra padding so card drop shadows are not clipped.
                .padding(.bottom, 16)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Folders Section

    private var foldersSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Folders")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)

                Spacer()

                Button {
                    viewModel.showCreateFolder = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.blue)
                        .symbolRenderingMode(.hierarchical)
                }
            }

            if folders.isEmpty {
                EmptyStatePlaceholderFolderCard(icon: "folder.badge.plus", message: "No folders yet. Create one to organize your decks.")
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

