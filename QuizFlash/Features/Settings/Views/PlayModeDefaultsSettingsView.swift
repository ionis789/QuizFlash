//
//  PlayModeDefaultsSettingsView.swift
//  QuizFlash
//
//  App-wide defaults for the supported play modes.
//

import SwiftUI

private let kPlayModeDefaultsChromeSpace = "PlayModeDefaultsChromeSpace"

// MARK: - Settings Study Mode Kind

enum SettingsStudyModeKind: String, CaseIterable, Identifiable {
    case flashcards
    case quiz

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flashcards:
            return "Flashcards"
        case .quiz:
            return "Quiz"
        }
    }

    var systemImage: String {
        switch self {
        case .flashcards:
            return "rectangle.on.rectangle"
        case .quiz:
            return "checklist"
        }
    }

    var tint: Color {
        switch self {
        case .flashcards:
            return .cyan
        case .quiz:
            return .orange
        }
    }

    var subtitle: String {
        switch self {
        case .flashcards:
            return "Control flashcard session chrome, swipe feedback, and long-review comfort."
        case .quiz:
            return "Tune quiz pacing, progress visibility, and answer target size across decks."
        }
    }

    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .flashcards:
            return AppLocalization.string("Flashcards", locale: locale)
        case .quiz:
            return AppLocalization.string("Quiz", locale: locale)
        }
    }

    func localizedSubtitle(locale: Locale) -> String {
        switch self {
        case .flashcards:
            return AppLocalization.string("Control flashcard session chrome, swipe feedback, and long-review comfort.",
                locale: locale
            )
        case .quiz:
            return AppLocalization.string("Tune quiz pacing, progress visibility, and answer target size across decks.",
                locale: locale
            )
        }
    }
}

// MARK: - Play Mode Defaults Settings View

struct PlayModeDefaultsSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager
    @State private var isCollapsedTitleVisible = false
    @State private var navigationBarHeight: CGFloat =
        UIConstants.Size.capsuleHeight + UIConstants.Layout.deckNavigationTopPadding
    @State private var navigationBarBottomY: CGFloat = 0

    let mode: SettingsStudyModeKind

    private var localizedDefaultsTitle: String {
        let locale = appPreferences.resolvedLocale
        let format = AppLocalization.string("%@ Defaults", locale: locale)
        return String.localizedStringWithFormat(format, mode.localizedTitle(locale: locale))
    }

    var body: some View {
        ZStack(alignment: .top) {
            ZStack {
                themeManager.groupedScreenBackground
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: UIConstants.Layout.sectionSpacing) {
                        LargeScreenTitle(
                            title: .verbatim(localizedDefaultsTitle)
                        )
                            .collapsibleTitleRevealAnchor(
                                in: kPlayModeDefaultsChromeSpace,
                                navigationBarBottomY: navigationBarBottomY,
                                revealClearance: SettingsChromeMetrics.pillRevealClearance,
                                isVisible: $isCollapsedTitleVisible
                            )

                        switch mode {
                        case .flashcards:
                            flashcardsContent
                        case .quiz:
                            quizContent
                        }

                        SettingsInfoCard(
                            icon: "square.stack.3d.up",
                            tint: themeManager.accentColor.color,
                            text: "These are app-wide defaults for future sessions. Deck-level play mode settings still own content rules such as order, validation, reveal timing, and per-deck retry behavior."
                        )
                    }
                    .padding(.horizontal, UIConstants.Spacing.large)
                    .padding(.top, UIConstants.Spacing.large)
                    .padding(.bottom, UIConstants.Spacing.huge)
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    Color.clear.frame(height: navigationBarHeight + UIConstants.Spacing.small)
                }
            }
            .screenTopEdgeShadow(
                topHeight: structuralTopEdgeShadowHeight,
                topRevealProgress: isCollapsedTitleVisible ? 1 : 0,
                debugScreenID: "settings.play-mode-defaults",
                style: .progressiveBlur()
            )

            navigationBar
        }
        .coordinateSpace(name: kPlayModeDefaultsChromeSpace)
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
    }

    private var structuralTopEdgeShadowHeight: CGFloat {
        if navigationBarBottomY > 0 {
            return navigationBarBottomY
        }
        return UIConstants.Layout.topEdgeShadowHeight
    }

    private var flashcardsContent: some View {
        VStack(alignment: .leading, spacing: UIConstants.Layout.sectionSpacing) {
            SettingsSectionCard(
                title: "Session Chrome",
                subtitle: "These defaults change how much guidance the flashcard surface shows while you move through a deck."
            ) {
                SettingsMenuPickerRow(
                    icon: "chart.bar.fill",
                    tint: .cyan,
                    title: "Progress Display",
                    detail: "Choose whether flashcard sessions show a strong progress treatment, a smaller compact version, or stay visually quiet.",
                    selection: flashcardsProgressStyleBinding,
                    options: AppStudySessionProgressStyle.allCases
                ) { option, locale in
                    option.localizedTitle(locale: locale)
                }

                SettingsCardDivider()

                SettingsToggleRow(
                    icon: "sun.max.fill",
                    tint: .yellow,
                    title: "Keep Screen Awake",
                    detail: "Useful for longer review passes where you do not want the device dimming between cards.",
                    isOn: flashcardsKeepsScreenAwakeBinding
                )
            }

            SettingsSectionCard(
                title: "Interaction",
                subtitle: "Tune how tactile flashcards feel when users swipe through known, uncertain, and difficult cards."
            ) {
                SettingsMenuPickerRow(
                    icon: "iphone.radiowaves.left.and.right",
                    tint: .mint,
                    title: "Swipe Haptics",
                    detail: "Set the default haptic intensity for card transitions and result feedback in flashcard sessions.",
                    selection: flashcardsSwipeHapticsBinding,
                    options: AppStudyHapticsPreference.allCases
                ) { option, locale in
                    option.localizedTitle(locale: locale)
                }
            }
        }
    }

    private var quizContent: some View {
        VStack(alignment: .leading, spacing: UIConstants.Layout.sectionSpacing) {
            SettingsSectionCard(
                title: "Session Flow",
                subtitle: "These defaults govern pacing and how much structure Quiz mode exposes during a run."
            ) {
                SettingsToggleRow(
                    icon: "forward.fill",
                    tint: .orange,
                    title: "Auto-advance Correct Answers",
                    detail: "Jump to the next question immediately after a correct answer when the current deck setup allows it.",
                    isOn: quizAutoAdvanceBinding
                )

                SettingsCardDivider()

                SettingsToggleRow(
                    icon: "chart.line.uptrend.xyaxis",
                    tint: .blue,
                    title: "Show Question Progress",
                    detail: "Keep the current question position visible so quizzes feel more predictable during longer runs.",
                    isOn: quizShowsQuestionProgressBinding
                )
            }

            SettingsSectionCard(
                title: "Answer Targets",
                subtitle: "These defaults control the physical comfort of multiple-choice answering, especially on phones and one-handed sessions."
            ) {
                SettingsToggleRow(
                    icon: "rectangle.expand.vertical",
                    tint: .purple,
                    title: "Prefer Large Choice Buttons",
                    detail: "Render roomier answer targets in supported quiz layouts for faster taps and cleaner accessibility.",
                    isOn: quizUsesLargeChoiceButtonsBinding
                )
            }
        }
    }

    private var flashcardsProgressStyleBinding: Binding<AppStudySessionProgressStyle> {
        Binding(
            get: { appPreferences.flashcardsProgressStyle },
            set: { appPreferences.flashcardsProgressStyle = $0 }
        )
    }

    private var flashcardsSwipeHapticsBinding: Binding<AppStudyHapticsPreference> {
        Binding(
            get: { appPreferences.flashcardsSwipeHaptics },
            set: { appPreferences.flashcardsSwipeHaptics = $0 }
        )
    }

    private var flashcardsKeepsScreenAwakeBinding: Binding<Bool> {
        Binding(
            get: { appPreferences.flashcardsKeepsScreenAwake },
            set: { appPreferences.flashcardsKeepsScreenAwake = $0 }
        )
    }

    private var quizAutoAdvanceBinding: Binding<Bool> {
        Binding(
            get: { appPreferences.quizAutoAdvanceCorrectAnswers },
            set: { appPreferences.quizAutoAdvanceCorrectAnswers = $0 }
        )
    }

    private var quizShowsQuestionProgressBinding: Binding<Bool> {
        Binding(
            get: { appPreferences.quizShowsQuestionProgress },
            set: { appPreferences.quizShowsQuestionProgress = $0 }
        )
    }

    private var quizUsesLargeChoiceButtonsBinding: Binding<Bool> {
        Binding(
            get: { appPreferences.quizUsesLargeChoiceButtons },
            set: { appPreferences.quizUsesLargeChoiceButtons = $0 }
        )
    }

    @ViewBuilder
    private var navigationBar: some View {
        CollapsibleTitleNavigationBar(
            coordinateSpaceName: kPlayModeDefaultsChromeSpace,
            onHeightChange: { navigationBarHeight = $0 },
            onBottomChange: { navigationBarBottomY = $0 }
        ) {
            ChromeCircleIconButton(systemName: "chevron.left") {
                dismiss()
            }
        } center: { maxWidth in
            CollapsibleTitlePill(
                title: .verbatim(localizedDefaultsTitle),
                maxWidth: maxWidth,
                isVisible: isCollapsedTitleVisible
            )
        } trailing: {
            ChromeCirclePlaceholder()
        }
    }
}
