//
//  PlayModeSettingsScreen.swift
//  QuizFlash
//
//  Shared mode-settings screen used by the deck play-mode carousel.
//

import OSLog
import SwiftData
import SwiftUI

// MARK: - Play Mode Settings Screen

/// A deck-scoped settings screen that persists mode preferences without launching gameplay.
struct PlayModeSettingsScreen: View {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "QuizFlash",
        category: "PlayModeSettingsScreen"
    )

    @Environment(\.dismiss) private var dismiss
    @Environment(\.fullScreenSheetDismiss) private var fullScreenSheetDismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var context
    @Environment(AppPreferences.self) private var appPreferences

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
    @State private var showSaveErrorAlert = false
    @State private var saveErrorMessage = ""

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
        let locale = appPreferences.resolvedLocale
        switch mode {
        case .flashcards:
            return [
                AppLocalization.string("Order: %@", locale: locale).replacingOccurrences(of: "%@", with: flashcardSettings.order.localizedTitle(locale: locale)),
                flashcardSettings.retryWrongCards ? AppLocalization.string("Retry run enabled for missed cards.", locale: locale) : AppLocalization.string("Session ends after the first pass.", locale: locale),
                AppLocalization.string("Tap animation: %@.", locale: locale).replacingOccurrences(of: "%@", with: flashcardSettings.tapAnimationStyle.localizedTitle(locale: locale)),
                flashcardSettings.tapAnimationStyle == .staticSwap
                    ? AppLocalization.string("Static text motion: %@.", locale: locale).replacingOccurrences(of: "%@", with: flashcardSettings.staticSwapTextMotion.localizedTitle(locale: locale))
                    : AppLocalization.string("Static text motion applies only when Static Swap is selected.", locale: locale),
                AppLocalization.string("Content alignment: %@.", locale: locale).replacingOccurrences(of: "%@", with: flashcardSettings.contentAlignment.localizedTitle(locale: locale)),
                AppLocalization.string("Text size: %@.", locale: locale).replacingOccurrences(of: "%@", with: flashcardSettings.textSize.localizedTitle(locale: locale))
            ]
        case .quiz:
            return [
                quizSettings.shuffleChoices ? AppLocalization.string("Choices shuffle at runtime.", locale: locale) : AppLocalization.string("Author order is preserved.", locale: locale),
                AppLocalization.string("Validation: %@", locale: locale).replacingOccurrences(of: "%@", with: quizSettings.answerValidation.localizedTitle(locale: locale)),
                AppLocalization.string("Explanation: %@", locale: locale).replacingOccurrences(of: "%@", with: quizSettings.explanationTiming.localizedTitle(locale: locale)),
                quizSettings.retryIncorrectQuestions ? AppLocalization.string("Wrong questions queue for one retry pass.", locale: locale) : AppLocalization.string("Wrong questions do not replay automatically.", locale: locale),
                AppLocalization.string("Text size: %@.", locale: locale).replacingOccurrences(of: "%@", with: quizSettings.textSize.localizedTitle(locale: locale))
            ]
        }
    }

    var body: some View {
        GeometryReader { geo in
            let resolvedSafeTopInset = max(safeAreaInsets.top, geo.safeAreaInsets.top)
            let resolvedSafeBottomInset = max(safeAreaInsets.bottom, geo.safeAreaInsets.bottom)
            let resolvedHeaderClearance = max(
                headerHeight + UIConstants.Spacing.standard,
                resolvedSafeTopInset
                    + UIConstants.Spacing.standard
                    + UIConstants.Size.capsuleHeight
                    + UIConstants.Spacing.medium
            )

            ZStack(alignment: .top) {
                if fullScreenSheetDismiss == nil {
                    PlayModeSettingsBackground(deck: deck, mode: mode)
                        .ignoresSafeArea()
                }

                VStack(alignment: .leading, spacing: 0) {
                    settingsCard
                }
                .padding(.horizontal, horizontalInset)
                .padding(.top, resolvedHeaderClearance)
                .padding(.bottom, resolvedSafeBottomInset + UIConstants.Spacing.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                header(safeTopInset: resolvedSafeTopInset)
            }
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
        .alert(AppLocalization.string("Save Error", locale: appPreferences.resolvedLocale), isPresented: $showSaveErrorAlert) {
            Button(AppLocalization.string("OK", locale: appPreferences.resolvedLocale), role: .cancel) { }
        } message: {
            Text(
                saveErrorMessage.isEmpty
                    ? AppLocalization.string("These play mode settings couldn't be saved right now.", locale: appPreferences.resolvedLocale)
                    : saveErrorMessage
            )
        }
    }

    // MARK: - Navigation Bar

    private func header(safeTopInset: CGFloat) -> some View {
        VStack(spacing: UIConstants.Spacing.small) {
            ZStack {
                VStack(spacing: 2) {
                    Text("\(mode.localizedTitle(locale: appPreferences.resolvedLocale)) \(AppLocalization.string("Settings", locale: appPreferences.resolvedLocale))")
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
        .padding(.top, safeTopInset + UIConstants.Spacing.standard)
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
        ChromeSoftCircleSymbolButton(
            systemName: "xmark",
            accessibilityLabel: AppLocalization.string("Close", locale: appPreferences.resolvedLocale),
            action: dismissSheet
        )
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
            quizSettings: $quizSettings
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
        if isNewlyCreated {
            flashcardSettings.textSize = appPreferences.defaultTextSize
            quizSettings.textSize = appPreferences.defaultTextSize
        }
        hasLoadedSettings = true

        if isNewlyCreated {
            persistSettingsIfNeeded()
        }
    }

    private func persistSettingsIfNeeded() {
        guard hasLoadedSettings, let settingsModel else { return }

        settingsModel.flashcardSettings = flashcardSettings
        settingsModel.quizSettings = quizSettings
        deck.editedAt = Date()

        do {
            try context.save()
        } catch {
            Self.logger.error("Failed to persist play mode settings: \(error.localizedDescription, privacy: .public)")
            let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            saveErrorMessage = description.isEmpty
                ? AppLocalization.string("These play mode settings couldn't be saved right now.", locale: appPreferences.resolvedLocale)
                : description
            showSaveErrorAlert = true
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
        let locale = appPreferences.resolvedLocale
        if compatibleCardCount > 0 {
            let format = AppLocalization.string("These preferences are stored on this deck and will be picked up the next time %@ launches.",
                locale: locale
            )
            return String.localizedStringWithFormat(format, mode.localizedTitle(locale: locale))
        }

        let format = AppLocalization.string("The settings are already stored on this deck. %@ will become playable once this deck contains compatible %@.",
            locale: locale
        )
        return String.localizedStringWithFormat(
            format,
            mode.localizedTitle(locale: locale),
            mode.localizedCompatibilityRequirementLabel(locale: locale)
        )
    }
}
