//
//  PlayModeDefaultsSettingsView.swift
//  QuizFlash
//
//  App-wide defaults for the four interactive play modes.
//

import SwiftUI

private let kPlayModeDefaultsChromeSpace = "PlayModeDefaultsChromeSpace"

// MARK: - Settings Study Mode Kind

enum SettingsStudyModeKind: String, CaseIterable, Identifiable {
    case flashcards
    case quiz
    case match
    case write

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flashcards:
            return "Flashcards"
        case .quiz:
            return "Quiz"
        case .match:
            return "Match"
        case .write:
            return "Write"
        }
    }

    var systemImage: String {
        switch self {
        case .flashcards:
            return "rectangle.on.rectangle"
        case .quiz:
            return "checklist"
        case .match:
            return "square.grid.2x2.fill"
        case .write:
            return "square.and.pencil"
        }
    }

    var tint: Color {
        switch self {
        case .flashcards:
            return .cyan
        case .quiz:
            return .orange
        case .match:
            return .pink
        case .write:
            return .green
        }
    }

    var subtitle: String {
        switch self {
        case .flashcards:
            return "Control flashcard session chrome, swipe feedback, and long-review comfort."
        case .quiz:
            return "Tune quiz pacing, progress visibility, and answer target size across decks."
        case .match:
            return "Set the global feel for round starts, feedback intensity, and motion in board play."
        case .write:
            return "Shape how answer fields behave so write sessions stay fast and keyboard-friendly."
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

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: UIConstants.Layout.sectionSpacing) {
                    LargeScreenTitle(title: "\(mode.title) Defaults")
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
                    case .match:
                        matchContent
                    case .write:
                        writeContent
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

            navigationBar
        }
        .coordinateSpace(name: kPlayModeDefaultsChromeSpace)
        .background(themeManager.groupedScreenBackground)
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
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
                ) { $0.title }

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
                ) { $0.title }
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

    private var matchContent: some View {
        VStack(alignment: .leading, spacing: UIConstants.Layout.sectionSpacing) {
            SettingsSectionCard(
                title: "Round Starts",
                subtitle: "These defaults shape how Match sessions prepare users before the board becomes active."
            ) {
                SettingsToggleRow(
                    icon: "timer",
                    tint: .pink,
                    title: "Show Round Countdown",
                    detail: "Display a short ready-set-go countdown before each board so starts feel deliberate instead of abrupt.",
                    isOn: matchShowsRoundCountdownBinding
                )
            }

            SettingsSectionCard(
                title: "Feedback & Motion",
                subtitle: "These defaults govern the sensory intensity of Match mode so players can choose speed or calmness."
            ) {
                SettingsMenuPickerRow(
                    icon: "textformat.size",
                    tint: .pink,
                    title: "Card Font Size",
                    detail: "Change how large Match cards render their preview content on the board.",
                    selection: matchCardFontSizeBinding,
                    options: AppMatchCardFontSizePreference.allCases
                ) { $0.title }

                if appPreferences.matchCardFontSize == .custom {
                    SettingsCardDivider()

                    SettingsSliderRow(
                        icon: "slider.horizontal.3",
                        tint: .pink,
                        title: "Custom Size",
                        detail: "Set the base text size in pixels for Match card content.",
                        valueSuffix: "px",
                        range: 14...34,
                        step: 1,
                        value: matchCustomCardFontSizePixelsBinding
                    )
                }

                SettingsCardDivider()

                SettingsMenuPickerRow(
                    icon: "waveform.path",
                    tint: .orange,
                    title: "Match Haptics",
                    detail: "Set the default tactile strength for correct pairs, misses, and round transitions.",
                    selection: matchHapticsBinding,
                    options: AppStudyHapticsPreference.allCases
                ) { $0.title }

                SettingsCardDivider()

                SettingsToggleRow(
                    icon: "figure.walk.motion",
                    tint: .teal,
                    title: "Reduce Board Motion",
                    detail: "Prefer calmer board transitions and less visual travel when Match mode animates swaps and resets.",
                    isOn: matchUsesReducedMotionBinding
                )
            }
        }
    }

    private var writeContent: some View {
        VStack(alignment: .leading, spacing: UIConstants.Layout.sectionSpacing) {
            SettingsSectionCard(
                title: "Input Flow",
                subtitle: "These defaults keep Write mode efficient when users move between prompts on phones and iPads."
            ) {
                SettingsToggleRow(
                    icon: "cursorarrow.rays",
                    tint: .green,
                    title: "Auto-focus Answer Field",
                    detail: "Place the cursor into the answer field as soon as a new write prompt loads.",
                    isOn: writeAutoFocusBinding
                )

                SettingsCardDivider()

                SettingsToggleRow(
                    icon: "keyboard",
                    tint: .mint,
                    title: "Keep Keyboard Visible",
                    detail: "Hold the keyboard between prompts so repeated recall feels continuous instead of stop-start.",
                    isOn: writeKeepsKeyboardVisibleBinding
                )
            }

            SettingsSectionCard(
                title: "Hinting",
                subtitle: "These defaults control how much structural support Write mode gives before the answer is revealed."
            ) {
                SettingsToggleRow(
                    icon: "textformat.abc",
                    tint: .yellow,
                    title: "Show Answer-length Hint",
                    detail: "Expose the expected answer length or shape in supported write layouts when users need a little orientation.",
                    isOn: writeShowsAnswerLengthHintBinding
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

    private var matchShowsRoundCountdownBinding: Binding<Bool> {
        Binding(
            get: { appPreferences.matchShowsRoundCountdown },
            set: { appPreferences.matchShowsRoundCountdown = $0 }
        )
    }

    private var matchHapticsBinding: Binding<AppStudyHapticsPreference> {
        Binding(
            get: { appPreferences.matchHapticsPreference },
            set: { appPreferences.matchHapticsPreference = $0 }
        )
    }

    private var matchUsesReducedMotionBinding: Binding<Bool> {
        Binding(
            get: { appPreferences.matchUsesReducedMotion },
            set: { appPreferences.matchUsesReducedMotion = $0 }
        )
    }

    private var matchCardFontSizeBinding: Binding<AppMatchCardFontSizePreference> {
        Binding(
            get: { appPreferences.matchCardFontSize },
            set: { appPreferences.matchCardFontSize = $0 }
        )
    }

    private var matchCustomCardFontSizePixelsBinding: Binding<Double> {
        Binding(
            get: { appPreferences.matchCustomCardFontSizePixels },
            set: { appPreferences.matchCustomCardFontSizePixels = $0 }
        )
    }

    private var writeAutoFocusBinding: Binding<Bool> {
        Binding(
            get: { appPreferences.writeAutoFocusesAnswerField },
            set: { appPreferences.writeAutoFocusesAnswerField = $0 }
        )
    }

    private var writeKeepsKeyboardVisibleBinding: Binding<Bool> {
        Binding(
            get: { appPreferences.writeKeepsKeyboardVisibleBetweenPrompts },
            set: { appPreferences.writeKeepsKeyboardVisibleBetweenPrompts = $0 }
        )
    }

    private var writeShowsAnswerLengthHintBinding: Binding<Bool> {
        Binding(
            get: { appPreferences.writeShowsAnswerLengthHint },
            set: { appPreferences.writeShowsAnswerLengthHint = $0 }
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
                title: "\(mode.title) Defaults",
                maxWidth: maxWidth,
                isVisible: isCollapsedTitleVisible
            )
        } trailing: {
            ChromeCirclePlaceholder()
        }
    }
}
