//
//  PlayModeSettingsCards.swift
//  QuizFlash
//
//  Extracted cards for the shared play-mode settings screen.
//

import SwiftUI

// MARK: - Play Mode Settings Cards

struct PlayModeSettingsOverviewCard: View {
    let mode: DeckPlayModeDestination
    let tintColor: Color
    let compatibleCardCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.large) {
            HStack(alignment: .top, spacing: UIConstants.Spacing.medium) {
                ZStack {
                    RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous)
                        .fill(tintColor.opacity(0.12))
                        .frame(
                            width: UIConstants.Size.actionButton + UIConstants.Spacing.extraLarge,
                            height: UIConstants.Size.actionButton + UIConstants.Spacing.extraLarge
                        )

                    Image(systemName: mode.systemImage)
                        .font(.system(size: UIConstants.Size.iconLarge, weight: .black))
                        .foregroundStyle(tintColor)
                }

                VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                    Text("DECK-SCOPED SETTINGS")
                        .font(.system(size: UIConstants.Size.navigationChromeLabel, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)

                    Text(mode.settingsHeadline)
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(mode.settingsSupportingCopy)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: UIConstants.Spacing.small) {
                PlayModeSettingsStatusChip(title: "Autosaved", icon: "checkmark.circle.fill")

                Spacer(minLength: 0)

                PlayModeSettingsStatusChip(
                    title: compatibleCardCount > 0
                        ? "\(compatibleCardCount) Compatible"
                        : "No Compatible Cards",
                    icon: compatibleCardCount > 0 ? "bolt.fill" : "exclamationmark.circle"
                )
            }
        }
        .padding(UIConstants.Spacing.large)
        .widgetStyle(cornerRadius: UIConstants.Radius.maximum)
        .overlay {
            RoundedRectangle(cornerRadius: UIConstants.Radius.maximum, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.75)
        }
        .shadow(
            color: tintColor.opacity(0.12),
            radius: UIConstants.Shadow.heavyRadius,
            y: UIConstants.Shadow.yOffset
        )
    }
}

struct PlayModeSettingsModeCard: View {
    let mode: DeckPlayModeDestination
    let tintColor: Color
    @Binding var flashcardSettings: FlashcardModeSettings
    @Binding var quizSettings: QuizModeSettings
    @Binding var matchSettings: MatchModeSettings
    @Binding var writeSettings: WriteModeSettings
    @Binding var learnSettings: LearnModeSettings

    @ViewBuilder
    var body: some View {
        switch mode {
        case .flashcards:
            PlayModeSettingsSectionCard(
                title: "Session Controls",
                subtitle: "Tune order, retry behavior, and how flashcards open."
            ) {
                PlayModeSettingsMenuRow(
                    title: "Card Order",
                    detail: "Study order prioritizes new and short-interval cards. Other orders follow deck numbering.",
                    selection: $flashcardSettings.order,
                    options: FlashcardSessionOrder.allCases
                ) { $0.title }

                PlayModeSettingsToggleRow(
                    title: "Retry Wrong Cards",
                    detail: "Queue missed flashcards into one more run after the main pass.",
                    isOn: $flashcardSettings.retryWrongCards,
                    tint: tintColor
                )

                PlayModeSettingsSegmentedRow(
                    title: "Opening Face",
                    detail: "Choose whether each card starts on the question side or the answer side.",
                    selection: $flashcardSettings.revealFlow,
                    options: FlashcardRevealFlow.allCases
                ) { $0.title }

                PlayModeSettingsSegmentedRow(
                    title: "Tap Behavior",
                    detail: "Allow tap-based reveal during the session or keep the opening face locked.",
                    selection: $flashcardSettings.flipBehavior,
                    options: FlashcardFlipBehavior.allCases
                ) { $0.title }

                PlayModeSettingsSegmentedRow(
                    title: "Tap Animation",
                    detail: "Choose between the current 3D flip and a static card that swaps only the content with the lighter snappy motion.",
                    selection: $flashcardSettings.tapAnimationStyle,
                    options: FlashcardTapAnimationStyle.allCases
                ) { $0.title }

                if flashcardSettings.tapAnimationStyle == .staticSwap {
                    PlayModeSettingsSegmentedRow(
                        title: "Static Text Motion",
                        detail: "Keep the current snappy text transition or switch the content instantly with no text animation.",
                        selection: $flashcardSettings.staticSwapTextMotion,
                        options: FlashcardStaticSwapTextMotion.allCases
                    ) { $0.title }
                }
            }
        case .quiz:
            PlayModeSettingsSectionCard(
                title: "Question Controls",
                subtitle: "Control validation pacing, explanation visibility, and replay rules."
            ) {
                PlayModeSettingsToggleRow(
                    title: "Shuffle Choices",
                    detail: "Randomize answer order before each quiz session starts.",
                    isOn: $quizSettings.shuffleChoices,
                    tint: tintColor
                )

                PlayModeSettingsSegmentedRow(
                    title: "Validation",
                    detail: "Single-answer questions can check immediately or wait for an explicit submit.",
                    selection: $quizSettings.answerValidation,
                    options: QuizAnswerValidationMode.allCases
                ) { $0.title }

                PlayModeSettingsSegmentedRow(
                    title: "Explanation",
                    detail: "Show explanations immediately after checking or keep them behind a manual reveal.",
                    selection: $quizSettings.explanationTiming,
                    options: QuizExplanationTiming.allCases
                ) { $0.title }

                PlayModeSettingsToggleRow(
                    title: "Retry Wrong Questions",
                    detail: "Run one dedicated retry pass for questions missed in the first pass.",
                    isOn: $quizSettings.retryIncorrectQuestions,
                    tint: tintColor
                )
            }
        case .learn:
            PlayModeSettingsSectionCard(
                title: "Report Controls",
                subtitle: "Adjust how the guided Learn briefing groups and trims content."
            ) {
                PlayModeSettingsMenuRow(
                    title: "Grouping",
                    detail: "Change which insight section appears first in the Learn briefing.",
                    selection: $learnSettings.grouping,
                    options: LearnReportGrouping.allCases
                ) { $0.title }

                PlayModeSettingsSegmentedRow(
                    title: "Density",
                    detail: "Compact shows fewer cards per section. Detailed expands each group.",
                    selection: $learnSettings.density,
                    options: LearnReportDensity.allCases
                ) { $0.title }
            }
        case .match:
            PlayModeSettingsSectionCard(
                title: "Round Controls",
                subtitle: "Control board size, fallback behavior, and retry pressure."
            ) {
                PlayModeSettingsToggleRow(
                    title: "Allow Flashcard Fallback",
                    detail: "Match currently builds prompt-and-answer pairs from flashcard previews when dedicated match cards are unavailable.",
                    isOn: $matchSettings.allowsFlashcardFallback,
                    tint: tintColor
                )

                PlayModeSettingsSegmentedRow(
                    title: "Round Size",
                    detail: "Choose how many pairs appear in each match board.",
                    selection: $matchSettings.roundSize,
                    options: MatchRoundSize.allCases
                ) { $0.title }

                PlayModeSettingsSegmentedRow(
                    title: "Density",
                    detail: "Compact tiles fit more text on smaller screens. Standard uses roomier cards.",
                    selection: $matchSettings.contentDensity,
                    options: MatchContentDensity.allCases
                ) { $0.title }

                PlayModeSettingsSegmentedRow(
                    title: "Feedback",
                    detail: "Subtle feedback clears mismatch highlights faster. Standard lingers longer.",
                    selection: $matchSettings.feedbackIntensity,
                    options: MatchFeedbackIntensity.allCases
                ) { $0.title }

                PlayModeSettingsToggleRow(
                    title: "Retry Missed Pairs",
                    detail: "Replay only the pairs you missed before moving into the next chunk.",
                    isOn: $matchSettings.retryMissedPairs,
                    tint: tintColor
                )
            }
        case .write:
            PlayModeSettingsSectionCard(
                title: "Recall Controls",
                subtitle: "Control how answers are entered, matched, revealed, and replayed."
            ) {
                PlayModeSettingsSegmentedRow(
                    title: "Input Mode",
                    detail: "Auto switches formula-heavy answers into the assisted builder.",
                    selection: $writeSettings.inputMode,
                    options: WriteAnswerInputMode.allCases
                ) { $0.title }

                PlayModeSettingsSegmentedRow(
                    title: "Strictness",
                    detail: "Normalized matching ignores punctuation and spacing variance. Exact keeps the canonical text intact.",
                    selection: $writeSettings.strictness,
                    options: WriteAnswerStrictness.allCases
                ) { $0.title }

                PlayModeSettingsSegmentedRow(
                    title: "Reveal",
                    detail: "Show the stored answer immediately after checking or require a manual reveal.",
                    selection: $writeSettings.revealTiming,
                    options: WriteRevealTiming.allCases
                ) { $0.title }

                PlayModeSettingsToggleRow(
                    title: "Retry Wrong Prompts",
                    detail: "Run one dedicated retry pass for prompts missed in the first pass.",
                    isOn: $writeSettings.retryIncorrectPrompts,
                    tint: tintColor
                )
            }
        }
    }
}

struct PlayModeSettingsReadinessCard: View {
    let readinessCopy: String
    let summaryLines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
            Text("Current Summary")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(readinessCopy)
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                ForEach(summaryLines, id: \.self) { line in
                    Text("• \(line)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(UIConstants.Spacing.large)
        .widgetStyle(cornerRadius: UIConstants.Radius.large)
        .overlay {
            RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.75)
        }
    }
}

private struct PlayModeSettingsSectionCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.large) {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                Text(title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content()
        }
        .padding(UIConstants.Spacing.large)
        .widgetStyle(cornerRadius: UIConstants.Radius.large)
        .overlay {
            RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.75)
        }
    }
}

private struct PlayModeSettingsStatusChip: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .padding(.horizontal, UIConstants.Spacing.standard)
            .padding(.vertical, UIConstants.Spacing.small)
            .background(.ultraThinMaterial, in: Capsule())
    }
}
