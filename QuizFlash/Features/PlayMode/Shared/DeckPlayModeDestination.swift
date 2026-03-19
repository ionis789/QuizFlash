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
        case .learn:
            return .gameplayReady
        case .quiz, .match, .write:
            return .settingsPlaceholder
        }
    }

    /// `true` when the gameplay flow exists today and can be launched if compatible cards exist.
    var isGameplayImplemented: Bool {
        implementationStatus == .gameplayReady
    }

    /// Number of compatible cards for this mode inside the current deck.
    func compatibleCardCount(in availability: PlayModeCardAvailability) -> Int {
        switch self {
        case .flashcards, .match:
            return availability.flashcardCards
        case .quiz:
            return availability.quizCards
        case .write:
            return availability.writeCards
        case .learn:
            return availability.totalCards
        }
    }

    /// `true` when the deck currently contains cards that this mode can consume.
    func hasCompatibleCards(in availability: PlayModeCardAvailability) -> Bool {
        compatibleCardCount(in: availability) > 0
    }

    /// `true` when the gameplay view exists and the deck can actually launch it.
    func canLaunch(with availability: PlayModeCardAvailability) -> Bool {
        isGameplayImplemented && hasCompatibleCards(in: availability)
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

    /// Headline shown on the dedicated mode settings screen.
    var settingsHeadline: String {
        switch self {
        case .flashcards:
            return "Set up the swipe session before you begin."
        case .quiz:
            return "Prepare the multiple-choice flow before launch."
        case .learn:
            return "Tune how the guided deck briefing should read."
        case .match:
            return "Control how the matching board should behave."
        case .write:
            return "Define the manual answer session defaults."
        }
    }

    /// Supporting copy shown under the settings headline.
    var settingsSupportingCopy: String {
        switch self {
        case .flashcards:
            return "This screen will hold card order, retry rules, and other study-session controls for the flashcards mode."
        case .quiz:
            return "Use this area to decide how choices, grading rules, and round pacing should work once quiz mode is implemented."
        case .learn:
            return "Learn mode already builds a guided report from this deck. This screen is reserved for future layout, grouping, and reading preferences."
        case .match:
            return "This area is reserved for grid size, pair generation, and pacing controls for match mode."
        case .write:
            return "This area is reserved for answer checking, tolerance rules, and prompt flow for write mode."
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
        switch self {
        case .flashcards:
            FlashCardsModeSettingsView(deck: deck, safeAreaInsets: safeAreaInsets, availability: availability)
        case .quiz:
            QuizModeView(deck: deck, safeAreaInsets: safeAreaInsets, availability: availability)
        case .learn:
            PlayModeSettingsScreen(
                deck: deck,
                mode: .learn,
                availability: availability,
                safeAreaInsets: safeAreaInsets
            )
        case .match:
            MatchModeView(deck: deck, safeAreaInsets: safeAreaInsets, availability: availability)
        case .write:
            WriteModeView(deck: deck, safeAreaInsets: safeAreaInsets, availability: availability)
        }
    }
}
