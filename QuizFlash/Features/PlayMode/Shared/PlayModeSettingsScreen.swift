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

    /// Reports the content height required by this sheet so the presenter can
    /// size the custom sheet around the current settings rows.
    let onContentHeightChange: (CGFloat) -> Void

    @State private var headerHeight: CGFloat = 0
    @State private var settingsContentHeight: CGFloat = 0
    @State private var lastReportedContentHeight: CGFloat = 0
    @State private var hasLoadedSettings = false
    @State private var settingsModel: DeckPlayModeSettingsModel?
    @State private var flashcardSettings = FlashcardModeSettings()
    @State private var quizSettings = QuizModeSettings()
    @State private var showSaveErrorAlert = false
    @State private var saveErrorMessage = ""

    init(
        deck: DeckModel,
        mode: DeckPlayModeDestination,
        availability: PlayModeCardAvailability,
        safeAreaInsets: UIEdgeInsets,
        onContentHeightChange: @escaping (CGFloat) -> Void
    ) {
        self.deck = deck
        self.mode = mode
        self.availability = availability
        self.safeAreaInsets = safeAreaInsets
        self.onContentHeightChange = onContentHeightChange

        let persistedSettings = deck.playModeSettings
        _settingsModel = State(initialValue: persistedSettings)
        _flashcardSettings = State(initialValue: persistedSettings?.flashcardSettings ?? FlashcardModeSettings())
        _quizSettings = State(initialValue: persistedSettings?.quizSettings ?? QuizModeSettings())
    }

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
                AppLocalization.string("Zone alignment: %@.", locale: locale).replacingOccurrences(
                    of: "%@",
                    with: flashcardSettings.zoneAlignment.localizedDeckSettingTitle(
                        locale: locale,
                        appDefault: appPreferences.defaultZoneAlignment
                    )
                ),
                AppLocalization.string("Text size: %@.", locale: locale).replacingOccurrences(
                    of: "%@",
                    with: flashcardSettings
                        .resolvedTextSize(default: appPreferences.defaultTextSize)
                        .localizedTitle(locale: locale)
                )
            ]
        case .quiz:
            return [
                quizSettings.shuffleChoices ? AppLocalization.string("Choices shuffle at runtime.", locale: locale) : AppLocalization.string("Author order is preserved.", locale: locale),
                AppLocalization.string("Validation: %@", locale: locale).replacingOccurrences(of: "%@", with: quizSettings.answerValidation.localizedTitle(locale: locale)),
                AppLocalization.string("Explanation: %@", locale: locale).replacingOccurrences(of: "%@", with: quizSettings.explanationTiming.localizedTitle(locale: locale)),
                quizSettings.retryIncorrectQuestions ? AppLocalization.string("Wrong questions queue for one retry pass.", locale: locale) : AppLocalization.string("Wrong questions do not replay automatically.", locale: locale),
                AppLocalization.string("Zone alignment: %@.", locale: locale).replacingOccurrences(
                    of: "%@",
                    with: quizSettings.zoneAlignment.localizedDeckSettingTitle(
                        locale: locale,
                        appDefault: appPreferences.defaultZoneAlignment
                    )
                ),
                AppLocalization.string("Text size: %@.", locale: locale).replacingOccurrences(
                    of: "%@",
                    with: quizSettings
                        .resolvedTextSize(default: appPreferences.defaultTextSize)
                        .localizedTitle(locale: locale)
                )
            ]
        }
    }

    var body: some View {
        GeometryReader { geo in
            let resolvedSafeTopInset = max(safeAreaInsets.top, geo.safeAreaInsets.top)
            let resolvedSafeBottomInset = max(safeAreaInsets.bottom, geo.safeAreaInsets.bottom)
            let resolvedBottomPadding = resolvedSafeBottomInset + UIConstants.Spacing.large

            ZStack(alignment: .top) {
                if fullScreenSheetDismiss == nil {
                    PlayModeSettingsBackground(deck: deck, mode: mode)
                        .ignoresSafeArea()
                }

                VStack(spacing: 0) {
                    header(safeTopInset: resolvedSafeTopInset)

                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            settingsCard
                        }
                        .padding(.horizontal, horizontalInset)
                        .padding(.top, UIConstants.Spacing.standard)
                        .padding(.bottom, resolvedBottomPadding)
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.height
                        } action: { newHeight in
                            updateSettingsContentHeight(newHeight)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

    private func updateSettingsContentHeight(_ height: CGFloat) {
        let roundedHeight = ceil(height)
        guard roundedHeight > 0,
              abs(settingsContentHeight - roundedHeight) > 0.5 else {
            return
        }

        settingsContentHeight = roundedHeight
        reportContentHeight(headerHeight: headerHeight, settingsContentHeight: roundedHeight)
    }

    private func reportContentHeight(headerHeight: CGFloat, settingsContentHeight: CGFloat) {
        let roundedHeight = ceil(headerHeight + settingsContentHeight)
        guard headerHeight > 0,
              settingsContentHeight > 0,
              roundedHeight > 0,
              abs(lastReportedContentHeight - roundedHeight) > 0.5 else {
            return
        }

        lastReportedContentHeight = roundedHeight
        onContentHeightChange(roundedHeight)
    }

    // MARK: - Navigation Bar

    private func header(safeTopInset: CGFloat) -> some View {
        VStack(spacing: UIConstants.Spacing.small) {
            ZStack {
                Text(deck.title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                    .padding(.horizontal, UIConstants.Size.actionButton + UIConstants.Spacing.medium)

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
            updateHeaderHeight(newHeight)
        }
    }

    private func updateHeaderHeight(_ height: CGFloat) {
        let roundedHeight = ceil(height)
        guard roundedHeight > 0,
              abs(headerHeight - roundedHeight) > 0.5 else {
            return
        }

        headerHeight = roundedHeight
        reportContentHeight(headerHeight: roundedHeight, settingsContentHeight: settingsContentHeight)
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
        hasLoadedSettings = false
        if let model = deck.playModeSettings {
            settingsModel = model
            flashcardSettings = model.flashcardSettings
            quizSettings = model.quizSettings
        } else {
            settingsModel = nil
            flashcardSettings = FlashcardModeSettings()
            quizSettings = QuizModeSettings()
        }
        hasLoadedSettings = true
    }

    private func persistSettingsIfNeeded() {
        guard hasLoadedSettings else { return }

        let resolvedModel: DeckPlayModeSettingsModel
        if let settingsModel {
            resolvedModel = settingsModel
        } else {
            resolvedModel = DeckPlayModeSettingsStore.resolve(for: deck, in: context)
            settingsModel = resolvedModel
        }

        resolvedModel.flashcardSettings = flashcardSettings
        resolvedModel.quizSettings = quizSettings
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
