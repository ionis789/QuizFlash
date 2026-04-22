//
//  DeckPlayModeDestination.swift
//  QuizFlash
//
//  Type-safe deck play-mode destinations used by `DeckView`.
//

import SwiftUI

// MARK: - Deck Play Mode Destination

/// Placeholder configuration row metadata shown inside mode settings screens.
struct PlayModeSettingPreset: Identifiable, Hashable {
    let icon: String
    let title: String
    let detail: String

    var id: String { title }
}

/// Compact deck-level explanation shown when a mode tile is tapped while unavailable.
struct PlayModeUnavailablePrompt: Equatable {
    let title: String
    let detail: String
    let actionTitle: String?
}

/// Static implementation status for one mode's dedicated gameplay flow.
enum PlayModeImplementationStatus {
    case gameplayReady
    case settingsPlaceholder
}

/// The deck-scoped play modes exposed from the deck detail screen.
///
/// This enum keeps the card metadata and destination mapping in one place so the
/// horizontal mode carousel and its navigation stay in sync.
enum DeckPlayModeDestination: String, CaseIterable, Hashable, Identifiable {
    case flashcards
    case quiz
    case learn
    case match
    case write

    /// Stable identifier used by `ForEach`.
    var id: String { rawValue }

    /// Primary label shown on the deck play-mode cards.
    var title: String {
        switch self {
        case .flashcards: return "Flashcards"
        case .quiz:       return "Quiz"
        case .learn:      return "Learn"
        case .match:      return "Match"
        case .write:      return "Write"
        }
    }

    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .flashcards: return AppLocalization.string("Flashcards", locale: locale)
        case .quiz:       return AppLocalization.string("Quiz", locale: locale)
        case .learn:      return AppLocalization.string("Learn", locale: locale)
        case .match:      return AppLocalization.string("Match", locale: locale)
        case .write:      return AppLocalization.string("Write", locale: locale)
        }
    }

    /// Secondary label shown under the play-mode title.
    var subtitle: String {
        switch self {
        case .flashcards: return "Swipe review"
        case .quiz:       return "Multiple choice"
        case .learn:      return "Summary report"
        case .match:      return "Grid matching"
        case .write:      return "Manual input"
        }
    }

    func localizedSubtitle(locale: Locale) -> String {
        switch self {
        case .flashcards: return AppLocalization.string("Swipe review", locale: locale)
        case .quiz:       return AppLocalization.string("Multiple choice", locale: locale)
        case .learn:      return AppLocalization.string("Summary report", locale: locale)
        case .match:      return AppLocalization.string("Grid matching", locale: locale)
        case .write:      return AppLocalization.string("Manual input", locale: locale)
        }
    }

    /// SF Symbol displayed on the play-mode card and placeholder screen.
    var systemImage: String {
        switch self {
        case .flashcards: return "rectangle.stack.fill"
        case .quiz:       return "questionmark.square.dashed"
        case .learn:      return "book.pages"
        case .match:      return "square.grid.2x2.fill"
        case .write:      return "pencil.and.scribble"
        }
    }

    /// Accent tint used by the play-mode card and placeholder surfaces.
    func tintColor(deckColor: Color, accentColor: Color) -> Color {
        switch self {
        case .flashcards: return accentColor
        case .quiz:       return deckColor
        case .learn:      return .teal
        case .match:      return .orange
        case .write:      return .indigo
        }
    }

    /// `true` when the gameplay flow exists today and can be launched from the deck screen.
    var implementationStatus: PlayModeImplementationStatus {
        switch self {
        case .flashcards:
            return .gameplayReady
        case .quiz, .learn, .match, .write:
            return .gameplayReady
        }
    }

    /// `true` when the gameplay flow exists today and can be launched if compatible cards exist.
    var isGameplayImplemented: Bool {
        implementationStatus == .gameplayReady
    }

    /// Number of compatible cards for this mode inside the current deck.
    func compatibleCardCount(
        in availability: PlayModeCardAvailability,
        deck: DeckModel
    ) -> Int {
        switch self {
        case .flashcards:
            return availability.flashcardCards
        case .match:
            if availability.matchCards > 0 {
                return availability.matchCards
            }
            let allowsFallback = deck.playModeSettings?.matchSettings.allowsFlashcardFallback ?? true
            return allowsFallback ? availability.flashcardCards : 0
        case .quiz:
            return availability.quizCards
        case .write:
            return availability.writeCards
        case .learn:
            return availability.totalCards
        }
    }

    /// `true` when the deck currently contains cards that this mode can consume.
    func hasCompatibleCards(
        in availability: PlayModeCardAvailability,
        deck: DeckModel
    ) -> Bool {
        compatibleCardCount(in: availability, deck: deck) > 0
    }

    /// `true` when the gameplay view exists and the deck can actually launch it.
    func canLaunch(with availability: PlayModeCardAvailability, deck: DeckModel) -> Bool {
        isGameplayImplemented && hasCompatibleCards(in: availability, deck: deck)
    }

    /// Card kind that the deck can convert into to unlock this mode, when applicable.
    var unavailableConversionTargetKind: CardKind? {
        switch self {
        case .flashcards:
            return .flashcard
        case .quiz:
            return .quiz
        case .match:
            return .match
        case .write:
            return .write
        case .learn:
            return nil
        }
    }

    /// Minimal explanation used by the deck screen when the tile is tapped while unavailable.
    func unavailablePrompt(
        in availability: PlayModeCardAvailability,
        deck: DeckModel
    ) -> PlayModeUnavailablePrompt {
        let deckHasAnyCards = availability.totalCards > 0

        switch self {
        case .flashcards:
            return PlayModeUnavailablePrompt(
                title: "Flashcards Isn't Ready",
                detail: deckHasAnyCards
                    ? "Convert the current cards to Flashcards to use this mode."
                    : "Add cards to this deck first.",
                actionTitle: deckHasAnyCards ? "Convert Cards" : nil
            )
        case .quiz:
            return PlayModeUnavailablePrompt(
                title: "Quiz Isn't Ready",
                detail: deckHasAnyCards
                    ? "Convert the current cards to Quiz to use this mode."
                    : "Add cards to this deck first.",
                actionTitle: deckHasAnyCards ? "Convert Cards" : nil
            )
        case .learn:
            return PlayModeUnavailablePrompt(
                title: "Learn Isn't Ready",
                detail: "Add cards to this deck first.",
                actionTitle: nil
            )
        case .match:
            return PlayModeUnavailablePrompt(
                title: "Match Isn't Ready",
                detail: deckHasAnyCards
                    ? "Convert the current cards to Match to use this mode."
                    : "Add cards to this deck first.",
                actionTitle: deckHasAnyCards ? "Convert Cards" : nil
            )
        case .write:
            return PlayModeUnavailablePrompt(
                title: "Write Isn't Ready",
                detail: deckHasAnyCards
                    ? "Convert the current cards to Write to use this mode."
                    : "Add cards to this deck first.",
                actionTitle: deckHasAnyCards ? "Convert Cards" : nil
            )
        }
    }

    func localizedUnavailablePrompt(
        locale: Locale,
        in availability: PlayModeCardAvailability,
        deck: DeckModel
    ) -> PlayModeUnavailablePrompt {
        let deckHasAnyCards = availability.totalCards > 0

        switch self {
        case .flashcards:
            return PlayModeUnavailablePrompt(
                title: AppLocalization.string("Flashcards Isn't Ready", locale: locale),
                detail: deckHasAnyCards
                    ? AppLocalization.string("Convert the current cards to Flashcards to use this mode.", locale: locale)
                    : AppLocalization.string("Add cards to this deck first.", locale: locale),
                actionTitle: deckHasAnyCards ? AppLocalization.string("Convert Cards", locale: locale) : nil
            )
        case .quiz:
            return PlayModeUnavailablePrompt(
                title: AppLocalization.string("Quiz Isn't Ready", locale: locale),
                detail: deckHasAnyCards
                    ? AppLocalization.string("Convert the current cards to Quiz to use this mode.", locale: locale)
                    : AppLocalization.string("Add cards to this deck first.", locale: locale),
                actionTitle: deckHasAnyCards ? AppLocalization.string("Convert Cards", locale: locale) : nil
            )
        case .learn:
            return PlayModeUnavailablePrompt(
                title: AppLocalization.string("Learn Isn't Ready", locale: locale),
                detail: AppLocalization.string("Add cards to this deck first.", locale: locale),
                actionTitle: nil
            )
        case .match:
            return PlayModeUnavailablePrompt(
                title: AppLocalization.string("Match Isn't Ready", locale: locale),
                detail: deckHasAnyCards
                    ? AppLocalization.string("Convert the current cards to Match to use this mode.", locale: locale)
                    : AppLocalization.string("Add cards to this deck first.", locale: locale),
                actionTitle: deckHasAnyCards ? AppLocalization.string("Convert Cards", locale: locale) : nil
            )
        case .write:
            return PlayModeUnavailablePrompt(
                title: AppLocalization.string("Write Isn't Ready", locale: locale),
                detail: deckHasAnyCards
                    ? AppLocalization.string("Convert the current cards to Write to use this mode.", locale: locale)
                    : AppLocalization.string("Add cards to this deck first.", locale: locale),
                actionTitle: deckHasAnyCards ? AppLocalization.string("Convert Cards", locale: locale) : nil
            )
        }
    }

    /// Minimal status line shown inside the deck play-mode tile.
    func statusText(in availability: PlayModeCardAvailability, deck: DeckModel) -> String {
        switch self {
        case .match:
            if availability.matchCards > 0 {
                let count = availability.matchCards
                return "\(count) match card\(count == 1 ? "" : "s") ready"
            }
            if canLaunch(with: availability, deck: deck) {
                return "Ready to play"
            }
            return availability.totalCards > 0
                ? "Convert cards to unlock"
                : "Add cards to unlock"
        case .learn:
            return availability.totalCards > 0 ? "Deck summary ready" : "Add cards to unlock"
        default:
            let count = compatibleCardCount(in: availability, deck: deck)
            if count > 0 {
                return "\(count) \(compatibilityRequirementLabel) ready"
            }
            return availability.totalCards > 0
                ? "Convert cards to unlock"
                : "Add cards to unlock"
        }
    }

    func localizedStatusText(
        locale: Locale,
        in availability: PlayModeCardAvailability,
        deck: DeckModel
    ) -> String {
        switch self {
        case .match:
            if availability.matchCards > 0 {
                let count = availability.matchCards
                let format = AppLocalization.string(count == 1 ? "%d match card ready" : "%d match cards ready",
                    locale: locale
                )
                return String.localizedStringWithFormat(format, count)
            }
            if canLaunch(with: availability, deck: deck) {
                return AppLocalization.string("Ready to play", locale: locale)
            }
            return availability.totalCards > 0
                ? AppLocalization.string("Convert cards to unlock", locale: locale)
                : AppLocalization.string("Add cards to unlock", locale: locale)
        case .learn:
            return availability.totalCards > 0
                ? AppLocalization.string("Deck summary ready", locale: locale)
                : AppLocalization.string("Add cards to unlock", locale: locale)
        default:
            let count = compatibleCardCount(in: availability, deck: deck)
            if count > 0 {
                let format = AppLocalization.string(count == 1 ? "%d %@ ready" : "%d %@ ready",
                    locale: locale
                )
                return String.localizedStringWithFormat(
                    format,
                    count,
                    localizedCompatibilityRequirementLabel(locale: locale)
                )
            }
            return availability.totalCards > 0
                ? AppLocalization.string("Convert cards to unlock", locale: locale)
                : AppLocalization.string("Add cards to unlock", locale: locale)
        }
    }

    /// Human-readable label for the compatible-card requirement of this mode.
    var compatibilityRequirementLabel: String {
        switch self {
        case .flashcards:
            return "flashcards"
        case .quiz:
            return "quiz cards"
        case .learn:
            return "cards"
        case .match:
            return "flashcards"
        case .write:
            return "write cards"
        }
    }

    func localizedCompatibilityRequirementLabel(locale: Locale) -> String {
        switch self {
        case .flashcards:
            return AppLocalization.string("flashcards", locale: locale)
        case .quiz:
            return AppLocalization.string("quiz cards", locale: locale)
        case .learn:
            return AppLocalization.string("cards", locale: locale)
        case .match:
            return AppLocalization.string("flashcards", locale: locale)
        case .write:
            return AppLocalization.string("write cards", locale: locale)
        }
    }

    /// Headline shown on the dedicated mode settings screen.
    var settingsHeadline: String {
        switch self {
        case .flashcards:
            return "Set up how this deck should behave before the session begins."
        case .quiz:
            return "Tune how quiz checks, explanations, and retry passes should behave."
        case .learn:
            return "Tune how the guided deck briefing should read for this deck."
        case .match:
            return "Tune board size, density, retries, and feedback for this deck."
        case .write:
            return "Tune answer entry, matching strictness, reveal timing, and retries."
        }
    }

    func localizedSettingsHeadline(locale: Locale) -> String {
        switch self {
        case .flashcards:
            return AppLocalization.string("Set up how this deck should behave before the session begins.", locale: locale)
        case .quiz:
            return AppLocalization.string("Tune how quiz checks, explanations, and retry passes should behave.", locale: locale)
        case .learn:
            return AppLocalization.string("Tune how the guided deck briefing should read for this deck.", locale: locale)
        case .match:
            return AppLocalization.string("Tune board size, density, retries, and feedback for this deck.", locale: locale)
        case .write:
            return AppLocalization.string("Tune answer entry, matching strictness, reveal timing, and retries.", locale: locale)
        }
    }

    /// Supporting copy shown under the settings headline.
    var settingsSupportingCopy: String {
        switch self {
        case .flashcards:
            return "These controls are stored per deck, so one deck can launch a tighter flashcard flow while another keeps a more forgiving session."
        case .quiz:
            return "Shuffle choices when the deck needs pressure, switch between instant checks and submit flow, and decide when explanations become visible."
        case .learn:
            return "Learn stays report-only, but the grouping and density can now be tailored to the deck you are reviewing."
        case .match:
            return "Choose how dense the board feels, whether missed pairs loop back, and when mixed decks are allowed to fall back internally."
        case .write:
            return "Write can stay loose and text-first, or switch into a stricter assisted flow when the deck contains formula-heavy prompts."
        }
    }

    func localizedSettingsSupportingCopy(locale: Locale) -> String {
        switch self {
        case .flashcards:
            return AppLocalization.string("These controls are stored per deck, so one deck can launch a tighter flashcard flow while another keeps a more forgiving session.", locale: locale)
        case .quiz:
            return AppLocalization.string("Shuffle choices when the deck needs pressure, switch between instant checks and submit flow, and decide when explanations become visible.", locale: locale)
        case .learn:
            return AppLocalization.string("Learn stays report-only, but the grouping and density can now be tailored to the deck you are reviewing.", locale: locale)
        case .match:
            return AppLocalization.string("Choose how dense the board feels, whether missed pairs loop back, and when mixed decks are allowed to fall back internally.", locale: locale)
        case .write:
            return AppLocalization.string("Write can stay loose and text-first, or switch into a stricter assisted flow when the deck contains formula-heavy prompts.", locale: locale)
        }
    }

    /// Planned settings rows shown as placeholders until real controls are implemented.
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
                .init(icon: "list.bullet.rectangle", title: "Choice Layout", detail: "Tune answer count, order, and shuffling."),
                .init(icon: "timer", title: "Round Pace", detail: "Add timed pressure or keep the flow relaxed."),
                .init(icon: "checkmark.seal", title: "Scoring Rules", detail: "Define how quiz answers are graded.")
            ]
        case .learn:
            return [
                .init(icon: "text.alignleft", title: "Reading Layout", detail: "Control how cards become a readable study summary."),
                .init(icon: "square.split.2x1", title: "Grouping", detail: "Choose how content is chunked into sections."),
                .init(icon: "character.book.closed", title: "Density", detail: "Set how detailed or compact the report should feel.")
            ]
        case .match:
            return [
                .init(icon: "square.grid.3x3", title: "Board Size", detail: "Choose how many pairs appear in a round."),
                .init(icon: "link", title: "Pair Rules", detail: "Define how prompts and answers get matched."),
                .init(icon: "bolt", title: "Speed", detail: "Adjust round tempo and pressure.")
            ]
        case .write:
            return [
                .init(icon: "keyboard", title: "Input Rules", detail: "Tune free-text vs guided entry."),
                .init(icon: "text.badge.checkmark", title: "Answer Tolerance", detail: "Set strict or forgiving matching."),
                .init(icon: "rectangle.and.pencil.and.ellipsis", title: "Prompt Flow", detail: "Control how answers are revealed and reviewed.")
            ]
        }
    }

    func localizedSettingPresets(locale: Locale) -> [PlayModeSettingPreset] {
        switch self {
        case .flashcards:
            return [
                .init(icon: "shuffle", title: AppLocalization.string("Card Order", locale: locale), detail: AppLocalization.string("Random, deck order, or focused retry runs.", locale: locale)),
                .init(icon: "repeat", title: AppLocalization.string("Wrong Card Retry", locale: locale), detail: AppLocalization.string("Decide if mistakes should loop back automatically.", locale: locale)),
                .init(icon: "arrow.triangle.2.circlepath", title: AppLocalization.string("Reveal Flow", locale: locale), detail: AppLocalization.string("Control flip defaults and card progression.", locale: locale))
            ]
        case .quiz:
            return [
                .init(icon: "list.bullet.rectangle", title: AppLocalization.string("Choice Layout", locale: locale), detail: AppLocalization.string("Tune answer count, order, and shuffling.", locale: locale)),
                .init(icon: "timer", title: AppLocalization.string("Round Pace", locale: locale), detail: AppLocalization.string("Add timed pressure or keep the flow relaxed.", locale: locale)),
                .init(icon: "checkmark.seal", title: AppLocalization.string("Scoring Rules", locale: locale), detail: AppLocalization.string("Define how quiz answers are graded.", locale: locale))
            ]
        case .learn:
            return [
                .init(icon: "text.alignleft", title: AppLocalization.string("Reading Layout", locale: locale), detail: AppLocalization.string("Control how cards become a readable study summary.", locale: locale)),
                .init(icon: "square.split.2x1", title: AppLocalization.string("Grouping", locale: locale), detail: AppLocalization.string("Choose how content is chunked into sections.", locale: locale)),
                .init(icon: "character.book.closed", title: AppLocalization.string("Density", locale: locale), detail: AppLocalization.string("Set how detailed or compact the report should feel.", locale: locale))
            ]
        case .match:
            return [
                .init(icon: "square.grid.3x3", title: AppLocalization.string("Board Size", locale: locale), detail: AppLocalization.string("Choose how many pairs appear in a round.", locale: locale)),
                .init(icon: "link", title: AppLocalization.string("Pair Rules", locale: locale), detail: AppLocalization.string("Define how prompts and answers get matched.", locale: locale)),
                .init(icon: "bolt", title: AppLocalization.string("Speed", locale: locale), detail: AppLocalization.string("Adjust round tempo and pressure.", locale: locale))
            ]
        case .write:
            return [
                .init(icon: "keyboard", title: AppLocalization.string("Input Rules", locale: locale), detail: AppLocalization.string("Tune free-text vs guided entry.", locale: locale)),
                .init(icon: "text.badge.checkmark", title: AppLocalization.string("Answer Tolerance", locale: locale), detail: AppLocalization.string("Set strict or forgiving matching.", locale: locale)),
                .init(icon: "rectangle.and.pencil.and.ellipsis", title: AppLocalization.string("Prompt Flow", locale: locale), detail: AppLocalization.string("Control how answers are revealed and reviewed.", locale: locale))
            ]
        }
    }

    /// Builds the concrete gameplay destination view for this play mode.
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
        case .learn:
            LearnModeView(deck: deck, safeAreaInsets: safeAreaInsets, availability: availability)
        case .match:
            MatchModeView(deck: deck, safeAreaInsets: safeAreaInsets, availability: availability)
        case .write:
            WriteModeView(deck: deck, safeAreaInsets: safeAreaInsets, availability: availability)
        }
    }

    /// Builds the dedicated settings sheet for this play mode.
    @ViewBuilder
    func settingsSheetView(
        for deck: DeckModel,
        safeAreaInsets: UIEdgeInsets,
        availability: PlayModeCardAvailability
    ) -> some View {
        PlayModeSettingsScreen(
            deck: deck,
            mode: self,
            availability: availability,
            safeAreaInsets: safeAreaInsets
        )
    }
}

extension DeckPlayModeSettingsModel {
    /// Returns the persisted recent-usage timestamp for one deck-scoped play mode.
    func recentUsageDate(for mode: DeckPlayModeDestination) -> Date? {
        switch mode {
        case .flashcards:
            return flashcardsLastUsedAt
        case .quiz:
            return quizLastUsedAt
        case .learn:
            return learnLastUsedAt
        case .match:
            return matchLastUsedAt
        case .write:
            return writeLastUsedAt
        }
    }

    /// Persists the last-used timestamp for one deck-scoped play mode without mutating the settings payloads.
    func markRecentlyUsed(_ mode: DeckPlayModeDestination, at date: Date = Date()) {
        switch mode {
        case .flashcards:
            flashcardsLastUsedAt = date
        case .quiz:
            quizLastUsedAt = date
        case .learn:
            learnLastUsedAt = date
        case .match:
            matchLastUsedAt = date
        case .write:
            writeLastUsedAt = date
        }
    }
}
