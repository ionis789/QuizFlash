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
        mode.compatibleCardCount(in: availability, deck: deck)
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
                flashcardSettings.flipBehavior == .tapToFlip
                    ? "Tap reveal stays available in-session."
                    : "Cards stay locked on the opening face.",
                flashcardSettings.flipBehavior == .tapToFlip
                    ? "Tap animation: \(flashcardSettings.tapAnimationStyle.title)."
                    : "Tap animation is saved but inactive while the face is locked.",
                flashcardSettings.tapAnimationStyle == .staticSwap
                    ? "Static text motion: \(flashcardSettings.staticSwapTextMotion.title)."
                    : "Static text motion applies only when Static Swap is selected.",
                "Content alignment: \(flashcardSettings.contentAlignment.title)."
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
        }
        .buttonStyle(.plain)
    }

    // MARK: - Cards

    private var overviewCard: some View {
        PlayModeSettingsOverviewCard(
            mode: mode,
            tintColor: tintColor,
            compatibleCardCount: compatibleCardCount
        )
    }

    private var settingsCard: some View {
        PlayModeSettingsModeCard(
            mode: mode,
            tintColor: tintColor,
            flashcardSettings: $flashcardSettings,
            quizSettings: $quizSettings,
            matchSettings: $matchSettings,
            writeSettings: $writeSettings,
            learnSettings: $learnSettings
        )
    }

    private var readinessCard: some View {
        PlayModeSettingsReadinessCard(
            readinessCopy: readinessCopy,
            summaryLines: currentModeSummary
        )
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
