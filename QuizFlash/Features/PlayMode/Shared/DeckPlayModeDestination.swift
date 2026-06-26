//
//  DeckPlayModeDestination.swift
//  QuizFlash
//
//  Type-safe deck play-mode destinations used by `DeckView`.
//

import SwiftUI

// MARK: - Deck Play Mode Destination

struct PlayModeSettingPreset: Identifiable, Hashable {
    let icon: String
    let title: String
    let detail: String

    var id: String { title }
}

struct PlayModeUnavailablePrompt: Equatable {
    let title: String
    let detail: String
    let actionTitle: String?
}

enum PlayModeImplementationStatus {
    case gameplayReady
}

enum DeckPlayModeDestination: String, CaseIterable, Hashable, Identifiable {
    case flashcards
    case quiz

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flashcards: return "Flashcards"
        case .quiz: return "Quiz"
        }
    }

    func localizedTitle(locale: Locale) -> String {
        AppLocalization.string(title, locale: locale)
    }

    var subtitle: String {
        switch self {
        case .flashcards: return "Swipe review"
        case .quiz: return "Multiple choice"
        }
    }

    func localizedSubtitle(locale: Locale) -> String {
        AppLocalization.string(subtitle, locale: locale)
    }

    var systemImage: String {
        switch self {
        case .flashcards: return "rectangle.stack.fill"
        case .quiz: return "questionmark.square.dashed"
        }
    }

    func tintColor(deckColor: Color, accentColor: Color) -> Color {
        switch self {
        case .flashcards: return accentColor
        case .quiz: return deckColor
        }
    }

    var implementationStatus: PlayModeImplementationStatus { .gameplayReady }

    var isGameplayImplemented: Bool {
        implementationStatus == .gameplayReady
    }

    func compatibleCardCount(
        in availability: PlayModeCardAvailability,
        deck: DeckModel
    ) -> Int {
        switch self {
        case .flashcards:
            return availability.flashcardCards
        case .quiz:
            return availability.quizCards
        }
    }

    func hasCompatibleCards(
        in availability: PlayModeCardAvailability,
        deck: DeckModel
    ) -> Bool {
        compatibleCardCount(in: availability, deck: deck) > 0
    }

    func canLaunch(with availability: PlayModeCardAvailability, deck: DeckModel) -> Bool {
        isGameplayImplemented && hasCompatibleCards(in: availability, deck: deck)
    }

    func unavailablePrompt(
        in availability: PlayModeCardAvailability,
        deck: DeckModel
    ) -> PlayModeUnavailablePrompt {
        switch self {
        case .flashcards:
            return PlayModeUnavailablePrompt(
                title: "Flashcards Isn't Ready",
                detail: "Add flashcards to this deck first.",
                actionTitle: nil
            )
        case .quiz:
            return PlayModeUnavailablePrompt(
                title: "Quiz Isn't Ready",
                detail: "Add quiz cards to this deck first.",
                actionTitle: nil
            )
        }
    }

    func localizedUnavailablePrompt(
        locale: Locale,
        in availability: PlayModeCardAvailability,
        deck: DeckModel
    ) -> PlayModeUnavailablePrompt {
        let prompt = unavailablePrompt(in: availability, deck: deck)
        return PlayModeUnavailablePrompt(
            title: AppLocalization.string(prompt.title, locale: locale),
            detail: AppLocalization.string(prompt.detail, locale: locale),
            actionTitle: nil
        )
    }

    func statusText(in availability: PlayModeCardAvailability, deck: DeckModel) -> String {
        let count = compatibleCardCount(in: availability, deck: deck)
        if count > 0 {
            return "\(count) \(compatibilityRequirementLabel) ready"
        }
        return "Add cards to unlock"
    }

    func localizedStatusText(
        locale: Locale,
        in availability: PlayModeCardAvailability,
        deck: DeckModel
    ) -> String {
        let count = compatibleCardCount(in: availability, deck: deck)
        if count > 0 {
            let format = AppLocalization.string(count == 1 ? "%d %@ ready" : "%d %@ ready", locale: locale)
            return String.localizedStringWithFormat(
                format,
                count,
                localizedCompatibilityRequirementLabel(locale: locale)
            )
        }
        return AppLocalization.string("Add cards to unlock", locale: locale)
    }

    var compatibilityRequirementLabel: String {
        switch self {
        case .flashcards:
            return "flashcards"
        case .quiz:
            return "quiz cards"
        }
    }

    func localizedCompatibilityRequirementLabel(locale: Locale) -> String {
        AppLocalization.string(compatibilityRequirementLabel, locale: locale)
    }

    var settingsHeadline: String {
        switch self {
        case .flashcards:
            return "Set up how this deck should behave before the session begins."
        case .quiz:
            return "Tune how quiz checks, explanations, and retry passes should behave."
        }
    }

    func localizedSettingsHeadline(locale: Locale) -> String {
        AppLocalization.string(settingsHeadline, locale: locale)
    }

    var settingsSupportingCopy: String {
        switch self {
        case .flashcards:
            return "These controls are stored per deck, so one deck can launch a tighter flashcard flow while another keeps a more forgiving session."
        case .quiz:
            return "Shuffle choices when the deck needs pressure, switch between instant checks and submit flow, and decide when explanations become visible."
        }
    }

    func localizedSettingsSupportingCopy(locale: Locale) -> String {
        AppLocalization.string(settingsSupportingCopy, locale: locale)
    }

    var settingPresets: [PlayModeSettingPreset] {
        switch self {
        case .flashcards:
            return [
                .init(icon: "shuffle", title: "Card Order", detail: "Random, deck order, or focused retry runs."),
                .init(icon: "repeat", title: "Wrong Card Retry", detail: "Decide if mistakes should loop back automatically."),
                .init(icon: "arrow.triangle.2.circlepath", title: "Reveal Flow", detail: "Control flip defaults and card progression.")
            ]
        case .quiz:
            return [
                .init(icon: "list.bullet.rectangle", title: "Choice Layout", detail: "Tune answer order and shuffling."),
                .init(icon: "timer", title: "Round Pace", detail: "Add timed pressure or keep the flow relaxed."),
                .init(icon: "checkmark.seal", title: "Scoring Rules", detail: "Define how quiz answers are graded.")
            ]
        }
    }

    func localizedSettingPresets(locale: Locale) -> [PlayModeSettingPreset] {
        settingPresets.map {
            PlayModeSettingPreset(
                icon: $0.icon,
                title: AppLocalization.string($0.title, locale: locale),
                detail: AppLocalization.string($0.detail, locale: locale)
            )
        }
    }

    @ViewBuilder
    func playSheetView(
        for deck: DeckModel,
        safeAreaInsets: UIEdgeInsets,
        availability: PlayModeCardAvailability
    ) -> some View {
        switch self {
        case .flashcards:
            DefaultModePlay(deck: deck, safeAreaInsets: safeAreaInsets)
        case .quiz:
            QuizModeView(deck: deck, safeAreaInsets: safeAreaInsets, availability: availability)
        }
    }

    @ViewBuilder
    func settingsSheetView(
        for deck: DeckModel,
        safeAreaInsets: UIEdgeInsets,
        availability: PlayModeCardAvailability,
        onContentHeightChange: @escaping (CGFloat) -> Void = { _ in }
    ) -> some View {
        PlayModeSettingsScreen(
            deck: deck,
            mode: self,
            availability: availability,
            safeAreaInsets: safeAreaInsets,
            onContentHeightChange: onContentHeightChange
        )
    }
}

extension DeckPlayModeSettingsModel {
    func recentUsageDate(for mode: DeckPlayModeDestination) -> Date? {
        switch mode {
        case .flashcards:
            return flashcardsLastUsedAt
        case .quiz:
            return quizLastUsedAt
        }
    }

    func markRecentlyUsed(_ mode: DeckPlayModeDestination, at date: Date = Date()) {
        switch mode {
        case .flashcards:
            flashcardsLastUsedAt = date
        case .quiz:
            quizLastUsedAt = date
        }
    }
}
