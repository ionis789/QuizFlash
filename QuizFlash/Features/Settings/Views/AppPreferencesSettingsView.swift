//
//  AppPreferencesSettingsView.swift
//  QuizFlash
//
//  App-wide settings grouped around calendar, navigation, and Create Deck defaults.
//

import SwiftUI

private let kAppPreferencesChromeSpace = "AppPreferencesChromeSpace"

// MARK: - App Preferences Settings View

struct AppPreferencesSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager
    @State private var isCollapsedTitleVisible = false
    @State private var navigationBarHeight: CGFloat =
        UIConstants.Size.capsuleHeight + UIConstants.Layout.deckNavigationTopPadding
    @State private var navigationBarBottomY: CGFloat = 0

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: UIConstants.Layout.sectionSpacing) {
                    LargeScreenTitle(title: "App Defaults")
                        .collapsibleTitleRevealAnchor(
                            in: kAppPreferencesChromeSpace,
                            navigationBarBottomY: navigationBarBottomY,
                            revealClearance: SettingsChromeMetrics.pillRevealClearance,
                            isVisible: $isCollapsedTitleVisible
                        )

                    SettingsSectionCard(
                        title: "Calendar & Navigation",
                        subtitle: "These defaults shape the Home calendar and the way QuizFlash anchors shared navigation surfaces."
                    ) {
                        SettingsMenuPickerRow(
                            icon: "calendar",
                            tint: .blue,
                            title: "Week Starts On",
                            detail: "Choose whether Home follows the system weekday anchor or forces Monday or Sunday.",
                            selection: weekStartBinding,
                            options: AppWeekStartDayPreference.allCases
                        ) { $0.title }

                        SettingsCardDivider()

                        SettingsMenuPickerRow(
                            icon: "rectangle.3.group.bubble.left",
                            tint: .teal,
                            title: "iPad Tab Bar Position",
                            detail: "Controls where the floating tab bar lands on wider iPad layouts.",
                            selection: padTabBarPositionBinding,
                            options: AppPadTabBarPosition.allCases
                        ) { $0.title }
                    }

                    SettingsSectionCard(
                        title: "Create Deck",
                        subtitle: "These defaults tune the first-pass editor experience before deck-specific AI flows take over."
                    ) {
                        SettingsMenuPickerRow(
                            icon: "arrow.up.arrow.down",
                            tint: .orange,
                            title: "Default Sort Order",
                            detail: "Choose whether new AI session cards appear first or whether the editor keeps older cards at the top.",
                            selection: createDeckSortBinding,
                            options: CreateDeckSortOrder.allCases
                        ) { $0.title }

                        SettingsCardDivider()

                        SettingsToggleRow(
                            icon: "rectangle.compress.vertical",
                            tint: .mint,
                            title: "Auto-collapse Earlier Cards",
                            detail: "Start AI sessions with historical deck cards folded away so the current batch stays in focus.",
                            isOn: autoCollapseBinding
                        )
                    }

                    SettingsInfoCard(
                        icon: "square.stack.3d.up",
                        tint: themeManager.accentColor.color,
                        text: "App defaults live above deck-level rules. When a deck exposes its own mode settings, those settings still remain the final local source of truth."
                    )
                }
                .padding(.horizontal, UIConstants.Spacing.large)
                .padding(.top, UIConstants.Spacing.large)
                .padding(.bottom, UIConstants.Spacing.huge)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: navigationBarHeight + UIConstants.Spacing.small)
            }

            navigationBar
        }
        .coordinateSpace(name: kAppPreferencesChromeSpace)
        .background(themeManager.groupedScreenBackground)
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
    }

    private var weekStartBinding: Binding<AppWeekStartDayPreference> {
        Binding(
            get: { appPreferences.weekStartDay },
            set: { appPreferences.weekStartDay = $0 }
        )
    }

    private var createDeckSortBinding: Binding<CreateDeckSortOrder> {
        Binding(
            get: { appPreferences.createDeckSortOrder },
            set: { appPreferences.createDeckSortOrder = $0 }
        )
    }

    private var padTabBarPositionBinding: Binding<AppPadTabBarPosition> {
        Binding(
            get: { appPreferences.padTabBarPosition },
            set: { appPreferences.padTabBarPosition = $0 }
        )
    }

    private var autoCollapseBinding: Binding<Bool> {
        Binding(
            get: { appPreferences.autoCollapseEarlierCardsInAISession },
            set: { appPreferences.autoCollapseEarlierCardsInAISession = $0 }
        )
    }

    private var navigationBar: some View {
        CollapsibleTitleNavigationBar(
            coordinateSpaceName: kAppPreferencesChromeSpace,
            onHeightChange: { navigationBarHeight = $0 },
            onBottomChange: { navigationBarBottomY = $0 }
        ) {
            ChromeCircleIconButton(systemName: "chevron.left") {
                dismiss()
            }
        } center: { maxWidth in
            CollapsibleTitlePill(
                title: "App Defaults",
                maxWidth: maxWidth,
                isVisible: isCollapsedTitleVisible
            )
        } trailing: {
            ChromeCirclePlaceholder()
        }
    }
}
