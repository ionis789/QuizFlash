//
//  PlayModeSettingsScreen.swift
//  QuizFlash
//
//  Shared mode-settings screen used by the deck play-mode carousel.
//

import SwiftData
import SwiftUI

// MARK: - Play Mode Settings Screen

/// A deck-scoped settings screen that persists mode preferences without launching gameplay.
struct PlayModeSettingsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fullScreenSheetDismiss) private var fullScreenSheetDismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var context

    /// The deck selected on the parent `DeckView`.
    let deck: DeckModel

    /// The mode currently being configured.
    let mode: DeckPlayModeDestination

    /// Lightweight compatibility counts for the active deck.
    let availability: PlayModeCardAvailability

    /// Safe-area values passed by the custom full-screen sheet container.
    let safeAreaInsets: UIEdgeInsets

    @State private var headerHeight: CGFloat = 0
    @State private var hasLoadedSettings = false
    @State private var settingsModel: DeckPlayModeSettingsModel?
    @State private var flashcardSettings = FlashcardModeSettings()
    @State private var quizSettings = QuizModeSettings()
    @State private var matchSettings = MatchModeSettings()
    @State private var writeSettings = WriteModeSettings()
    @State private var learnSettings = LearnModeSettings()

    private var accentColor: Color { ThemeManager.shared.accentColor.color }

    private var deckColor: Color {
        Color(hex: deck.colorHex) ?? accentColor
    }

    private var tintColor: Color {
        mode.tintColor(deckColor: deckColor, accentColor: accentColor)
    }

    private var compatibleCardCount: Int {
        mode.compatibleCardCount(in: availability)
    }

    private var horizontalInset: CGFloat {
        horizontalSizeClass == .compact
            ? UIConstants.Layout.compactScreenEdgeInset
            : UIConstants.Layout.screenEdgeInset
    }

    private var currentModeSummary: [String] {
        switch mode {
        case .flashcards:
            return [
                "Order: \(flashcardSettings.order.title)",
                flashcardSettings.retryWrongCards ? "Retry run enabled for missed cards." : "Session ends after the first pass.",
                flashcardSettings.revealFlow == .questionFirst ? "Cards open on the question side." : "Cards open on the answer side.",
                flashcardSettings.flipBehavior == .tapToFlip ? "Tap-to-flip stays available in-session." : "Cards stay locked on the opening face."
            ]
        case .quiz:
            return [
                quizSettings.shuffleChoices ? "Choices shuffle at runtime." : "Author order is preserved.",
                "Validation: \(quizSettings.answerValidation.title)",
                "Explanation: \(quizSettings.explanationTiming.title)",
                quizSettings.retryIncorrectQuestions ? "Wrong questions queue for one retry pass." : "Wrong questions do not replay automatically."
            ]
        case .learn:
            return [
                "Grouping: \(learnSettings.grouping.title)",
                "Density: \(learnSettings.density.title)",
                "Learn stays report-only and never mutates review history."
            ]
        case .match:
            return [
                matchSettings.allowsFlashcardFallback ? "Flashcard fallback is allowed." : "Flashcard fallback is disabled.",
                "Round size: \(matchSettings.roundSize.title)",
                "Density: \(matchSettings.contentDensity.title)",
                matchSettings.retryMissedPairs ? "Missed pairs replay before the next chunk." : "Missed pairs do not trigger retry rounds."
            ]
        case .write:
            return [
                "Input: \(writeSettings.inputMode.title)",
                "Strictness: \(writeSettings.strictness.title)",
                "Reveal: \(writeSettings.revealTiming.title)",
                writeSettings.retryIncorrectPrompts ? "Wrong prompts queue for one retry pass." : "Wrong prompts do not replay automatically."
            ]
        }
    }

    var body: some View {
        GeometryReader { geo in
            let resolvedSafeTopInset = max(safeAreaInsets.top, geo.safeAreaInsets.top)
            let resolvedSafeBottomInset = max(safeAreaInsets.bottom, geo.safeAreaInsets.bottom)

            ZStack(alignment: .top) {
                if fullScreenSheetDismiss == nil {
                    PlayModeSettingsBackground(deck: deck, mode: mode)
                        .ignoresSafeArea()
                }

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: UIConstants.Layout.sectionSpacing) {
                        overviewCard
                        settingsCard
                        readinessCard
                    }
                    .padding(.horizontal, horizontalInset)
                    .padding(.top, headerHeight + UIConstants.Spacing.large)
                    .padding(.bottom, resolvedSafeBottomInset + UIConstants.Spacing.huge)
                }

                header(safeTopInset: resolvedSafeTopInset)
            }
            .fullScreenSheetDragActivationHeight(headerHeight)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: deck.persistentModelID) {
            loadSettings()
        }
        .onChange(of: flashcardSettings) { _, _ in
            persistSettingsIfNeeded()
        }
        .onChange(of: quizSettings) { _, _ in
            persistSettingsIfNeeded()
        }
        .onChange(of: matchSettings) { _, _ in
            persistSettingsIfNeeded()
        }
        .onChange(of: writeSettings) { _, _ in
            persistSettingsIfNeeded()
        }
        .onChange(of: learnSettings) { _, _ in
            persistSettingsIfNeeded()
        }
    }

    // MARK: - Navigation Bar

    private func header(safeTopInset: CGFloat) -> some View {
        VStack(spacing: UIConstants.Spacing.small) {
            Capsule()
                .fill(Color.white.opacity(0.2))
                .frame(width: 56, height: 5)
                .accessibilityHidden(true)

            ZStack {
                VStack(spacing: 2) {
                    Text("\(mode.title) Settings")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(deck.title.uppercased())
                        .font(.system(size: UIConstants.Size.navigationChromeLabel, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack {
                    Spacer(minLength: 0)
                    dismissButton
                        .frame(width: UIConstants.Size.actionButton, alignment: .trailing)
                }
            }
            .frame(height: UIConstants.Size.capsuleHeight)
        }
        .padding(.top, safeTopInset + UIConstants.Spacing.tiny)
        .padding(.horizontal, horizontalInset)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { newHeight in
            if abs(headerHeight - newHeight) > 0.5 {
                headerHeight = newHeight
            }
        }
    }

    private var dismissButton: some View {
        Button(action: dismissSheet) {
            Image(systemName: "xmark")
                .font(.system(size: UIConstants.Size.actionIcon, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: UIConstants.Size.actionButton, height: UIConstants.Size.actionButton)
                .glassButton(shape: .circle)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Cards

    private var overviewCard: some View {
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
                settingsStatusChip(title: "Autosaved", icon: "checkmark.circle.fill")

                Spacer(minLength: 0)

                settingsStatusChip(
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

    @ViewBuilder
    private var settingsCard: some View {
        switch mode {
        case .flashcards:
            settingsContainer(title: "Session Controls", subtitle: "Tune order, retry behavior, and how flashcards open.") {
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
                    title: "Flip Behavior",
                    detail: "Lock the opening face or keep tap-to-flip enabled during the session.",
                    selection: $flashcardSettings.flipBehavior,
                    options: FlashcardFlipBehavior.allCases
                ) { $0.title }
            }
        case .quiz:
            settingsContainer(title: "Question Controls", subtitle: "Control validation pacing, explanation visibility, and replay rules.") {
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
            settingsContainer(title: "Report Controls", subtitle: "Adjust how the guided Learn briefing groups and trims content.") {
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
            settingsContainer(title: "Round Controls", subtitle: "Control board size, fallback behavior, and retry pressure.") {
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
            settingsContainer(title: "Recall Controls", subtitle: "Control how answers are entered, matched, revealed, and replayed.") {
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

    private var readinessCard: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
            Text("Current Summary")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(readinessCopy)
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                ForEach(currentModeSummary, id: \.self) { line in
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

    private func settingsContainer<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
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

    private func settingsStatusChip(title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .padding(.horizontal, UIConstants.Spacing.standard)
            .padding(.vertical, UIConstants.Spacing.small)
            .background(.ultraThinMaterial, in: Capsule())
    }

    // MARK: - Persistence

    private func loadSettings() {
        let isNewlyCreated = deck.playModeSettings == nil
        let model = DeckPlayModeSettingsStore.resolve(for: deck, in: context)
        settingsModel = model

        hasLoadedSettings = false
        flashcardSettings = model.flashcardSettings
        quizSettings = model.quizSettings
        matchSettings = model.matchSettings
        writeSettings = model.writeSettings
        learnSettings = model.learnSettings
        hasLoadedSettings = true

        if isNewlyCreated {
            persistSettingsIfNeeded()
        }
    }

    private func persistSettingsIfNeeded() {
        guard hasLoadedSettings, let settingsModel else { return }

        settingsModel.flashcardSettings = flashcardSettings
        settingsModel.quizSettings = quizSettings
        settingsModel.matchSettings = matchSettings
        settingsModel.writeSettings = writeSettings
        settingsModel.learnSettings = learnSettings
        deck.editedAt = Date()

        do {
            try context.save()
        } catch {
            assertionFailure("Failed to persist play mode settings: \(error)")
        }
    }

    private func dismissSheet() {
        if let fullScreenSheetDismiss {
            fullScreenSheetDismiss()
        } else {
            dismiss()
        }
    }

    private var readinessCopy: String {
        if compatibleCardCount > 0 {
            return "These preferences are stored on this deck and will be picked up the next time \(mode.title) launches."
        }

        return "The settings are already stored on this deck. \(mode.title) will become playable once this deck contains compatible \(mode.compatibilityRequirementLabel)."
    }
}

// MARK: - Settings Background

/// Decorative background shared by play-mode settings surfaces.
struct PlayModeSettingsBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    let deck: DeckModel
    let mode: DeckPlayModeDestination

    private var accentColor: Color { ThemeManager.shared.accentColor.color }
    private var deckColor: Color { Color(hex: deck.colorHex) ?? accentColor }
    private var tintColor: Color {
        mode.tintColor(deckColor: deckColor, accentColor: accentColor)
    }

    var body: some View {
        ZStack {
            if colorScheme == .dark {
                Color.black
            } else {
                Color(uiColor: .systemGroupedBackground)
            }

            LinearGradient(
                colors: [
                    deckColor.opacity(colorScheme == .dark ? 0.18 : 0.14),
                    tintColor.opacity(colorScheme == .dark ? 0.10 : 0.07),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(deckColor.opacity(0.18))
                .frame(
                    width: UIConstants.Spacing.huge * 8,
                    height: UIConstants.Spacing.huge * 8
                )
                .blur(radius: UIConstants.Spacing.huge * 2.5)
                .offset(
                    x: UIConstants.Spacing.huge * 2,
                    y: -UIConstants.Spacing.huge * 2
                )

            Circle()
                .fill(accentColor.opacity(0.12))
                .frame(
                    width: UIConstants.Spacing.huge * 7,
                    height: UIConstants.Spacing.huge * 7
                )
                .blur(radius: UIConstants.Spacing.huge * 2)
                .offset(
                    x: -UIConstants.Spacing.huge * 2,
                    y: UIConstants.Spacing.huge * 4
                )
        }
    }
}

// MARK: - Settings Rows

/// Shared toggle row used inside the play-mode settings screen.
private struct PlayModeSettingsToggleRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
            Toggle(isOn: $isOn) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            .tint(tint)

            Text(detail)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Shared segmented-control row used by small enum selections.
private struct PlayModeSettingsSegmentedRow<Option: Identifiable & Hashable>: View {
    let title: String
    let detail: String
    @Binding var selection: Option
    let options: [Option]
    let titleForOption: (Option) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            Text(detail)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker(title, selection: $selection) {
                ForEach(options) { option in
                    Text(titleForOption(option)).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

/// Shared menu row used by wider enum selections that do not fit comfortably in a segmented control.
private struct PlayModeSettingsMenuRow<Option: Identifiable & Hashable>: View {
    let title: String
    let detail: String
    @Binding var selection: Option
    let options: [Option]
    let titleForOption: (Option) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
            HStack(alignment: .center, spacing: UIConstants.Spacing.small) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text(detail)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: UIConstants.Spacing.standard)

                Menu {
                    Picker(title, selection: $selection) {
                        ForEach(options) { option in
                            Text(titleForOption(option)).tag(option)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(titleForOption(selection))
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, UIConstants.Spacing.standard)
                    .padding(.vertical, UIConstants.Spacing.small)
                    .background(.ultraThinMaterial, in: Capsule())
                }
            }
        }
    }
}
