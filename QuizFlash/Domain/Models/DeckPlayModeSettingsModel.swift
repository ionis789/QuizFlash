//
//  DeckPlayModeSettingsModel.swift
//  QuizFlash
//
//  Deck-scoped persisted settings for each play mode.
//

import Foundation
import SwiftData

// MARK: - Flashcards Settings

/// Controls how flashcards are ordered before a session begins.
nonisolated enum FlashcardSessionOrder: String, Codable, CaseIterable, Identifiable, Sendable {
    case studyPriority
    case newestFirst
    case oldestFirst
    case shuffled

    var id: String { rawValue }

    /// Human-readable option label shown in the settings UI.
    var title: String {
        switch self {
        case .studyPriority: return "Study Order"
        case .newestFirst:   return "Newest First"
        case .oldestFirst:   return "Oldest First"
        case .shuffled:      return "Shuffled"
        }
    }

    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .studyPriority: return AppLocalization.string("Study Order", locale: locale)
        case .newestFirst:   return AppLocalization.string("Newest First", locale: locale)
        case .oldestFirst:   return AppLocalization.string("Oldest First", locale: locale)
        case .shuffled:      return AppLocalization.string("Shuffled", locale: locale)
        }
    }
}

/// Controls which flashcard face is shown first when a card appears.
nonisolated enum FlashcardRevealFlow: String, Codable, CaseIterable, Identifiable, Sendable {
    case questionFirst
    case answerFirst

    var id: String { rawValue }

    /// Human-readable option label shown in the settings UI.
    var title: String {
        switch self {
        case .questionFirst: return "Question First"
        case .answerFirst:   return "Answer First"
        }
    }

    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .questionFirst: return AppLocalization.string("Question First", locale: locale)
        case .answerFirst:   return AppLocalization.string("Answer First", locale: locale)
        }
    }
}

/// Controls whether the flashcard can flip during the session.
nonisolated enum FlashcardFlipBehavior: String, Codable, CaseIterable, Identifiable, Sendable {
    case tapToFlip
    case locked

    var id: String { rawValue }

    /// Human-readable option label shown in the settings UI.
    var title: String {
        switch self {
        case .tapToFlip: return "Tap Enabled"
        case .locked:    return "Locked Face"
        }
    }

    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .tapToFlip: return AppLocalization.string("Tap Enabled", locale: locale)
        case .locked:    return AppLocalization.string("Locked Face", locale: locale)
        }
    }
}

/// Controls which visual treatment is used when tapping a flashcard.
nonisolated enum FlashcardTapAnimationStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case flip3D
    case staticSwap

    var id: String { rawValue }

    /// Human-readable option label shown in the settings UI.
    var title: String {
        switch self {
        case .flip3D:     return "3D Flip"
        case .staticSwap: return "Static Swap"
        }
    }

    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .flip3D:     return AppLocalization.string("3D Flip", locale: locale)
        case .staticSwap: return AppLocalization.string("Static Swap", locale: locale)
        }
    }
}

/// Controls how text changes behave when the flashcard uses the static swap mode.
nonisolated enum FlashcardStaticSwapTextMotion: String, Codable, CaseIterable, Identifiable, Sendable {
    case animated
    case instant

    var id: String { rawValue }

    /// Human-readable option label shown in the settings UI.
    var title: String {
        switch self {
        case .animated: return "Animated"
        case .instant:  return "Instant"
        }
    }

    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .animated: return AppLocalization.string("Animated", locale: locale)
        case .instant:  return AppLocalization.string("Instant", locale: locale)
        }
    }
}

/// Controls how short flashcard content is positioned vertically inside the card.
nonisolated enum FlashcardContentAlignment: String, Codable, CaseIterable, Identifiable, Sendable {
    case top
    case center

    var id: String { rawValue }

    /// Human-readable option label shown in the settings UI.
    var title: String {
        switch self {
        case .top:    return "Top"
        case .center: return "Center"
        }
    }

    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .top:    return AppLocalization.string("Top", locale: locale)
        case .center: return AppLocalization.string("Center", locale: locale)
        }
    }
}

/// Controls how large flashcard text renders during play mode.
nonisolated enum FlashcardTextSize: String, Codable, CaseIterable, Identifiable, Sendable {
    case normal
    case large

    var id: String { rawValue }

    /// Human-readable option label shown in the settings UI.
    var title: String {
        switch self {
        case .normal: return "Normal"
        case .large:  return "Large"
        }
    }

    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .normal: return AppLocalization.string("Normal", locale: locale)
        case .large:  return AppLocalization.string("Large", locale: locale)
        }
    }

    var playModeScale: Double {
        switch self {
        case .normal: return 1.32
        case .large:  return 1.5
        }
    }
}

/// Flashcards runtime preferences persisted per deck.
nonisolated struct FlashcardModeSettings: Codable, Equatable, Sendable {
    private static let currentSchemaVersion = 3

    private var schemaVersion: Int = Self.currentSchemaVersion
    var order: FlashcardSessionOrder = .studyPriority
    var retryWrongCards: Bool = true
    var revealFlow: FlashcardRevealFlow = .questionFirst
    var flipBehavior: FlashcardFlipBehavior = .tapToFlip
    var tapAnimationStyle: FlashcardTapAnimationStyle = .flip3D
    var staticSwapTextMotion: FlashcardStaticSwapTextMotion = .animated
    var contentAlignment: FlashcardContentAlignment = .center
    var textSize: FlashcardTextSize = .large

    init(
        order: FlashcardSessionOrder = .studyPriority,
        retryWrongCards: Bool = true,
        revealFlow: FlashcardRevealFlow = .questionFirst,
        flipBehavior: FlashcardFlipBehavior = .tapToFlip,
        tapAnimationStyle: FlashcardTapAnimationStyle = .flip3D,
        staticSwapTextMotion: FlashcardStaticSwapTextMotion = .animated,
        contentAlignment: FlashcardContentAlignment = .center,
        textSize: FlashcardTextSize = .large
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.order = order
        self.retryWrongCards = retryWrongCards
        self.revealFlow = revealFlow
        self.flipBehavior = flipBehavior
        self.tapAnimationStyle = tapAnimationStyle
        self.staticSwapTextMotion = staticSwapTextMotion
        self.contentAlignment = contentAlignment
        self.textSize = textSize
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case order
        case retryWrongCards
        case revealFlow
        case flipBehavior
        case tapAnimationStyle
        case staticSwapTextMotion
        case contentAlignment
        case textSize
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSchemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.order = try container.decodeIfPresent(FlashcardSessionOrder.self, forKey: .order) ?? .studyPriority
        self.retryWrongCards = try container.decodeIfPresent(Bool.self, forKey: .retryWrongCards) ?? true
        self.revealFlow = try container.decodeIfPresent(FlashcardRevealFlow.self, forKey: .revealFlow) ?? .questionFirst
        self.flipBehavior = try container.decodeIfPresent(FlashcardFlipBehavior.self, forKey: .flipBehavior) ?? .tapToFlip
        self.tapAnimationStyle = try container.decodeIfPresent(FlashcardTapAnimationStyle.self, forKey: .tapAnimationStyle) ?? .flip3D
        self.staticSwapTextMotion = try container.decodeIfPresent(FlashcardStaticSwapTextMotion.self, forKey: .staticSwapTextMotion) ?? .animated
        let decodedContentAlignment = try container.decodeIfPresent(FlashcardContentAlignment.self, forKey: .contentAlignment) ?? .center
        self.contentAlignment = decodedSchemaVersion < 2 && decodedContentAlignment == .top
            ? .center
            : decodedContentAlignment
        self.textSize = try container.decodeIfPresent(FlashcardTextSize.self, forKey: .textSize) ?? .large
        self.schemaVersion = Self.currentSchemaVersion
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try container.encode(order, forKey: .order)
        try container.encode(retryWrongCards, forKey: .retryWrongCards)
        try container.encode(revealFlow, forKey: .revealFlow)
        try container.encode(flipBehavior, forKey: .flipBehavior)
        try container.encode(tapAnimationStyle, forKey: .tapAnimationStyle)
        try container.encode(staticSwapTextMotion, forKey: .staticSwapTextMotion)
        try container.encode(contentAlignment, forKey: .contentAlignment)
        try container.encode(textSize, forKey: .textSize)
    }
}

// MARK: - Quiz Settings

/// Controls how quiz explanations become visible after evaluation.
nonisolated enum QuizExplanationTiming: String, Codable, CaseIterable, Identifiable, Sendable {
    case afterCheck
    case manualReveal

    var id: String { rawValue }

    /// Human-readable option label shown in the settings UI.
    var title: String {
        switch self {
        case .afterCheck:   return "After Check"
        case .manualReveal: return "Manual Reveal"
        }
    }

    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .afterCheck:   return AppLocalization.string("After Check", locale: locale)
        case .manualReveal: return AppLocalization.string("Manual Reveal", locale: locale)
        }
    }
}

/// Controls whether quiz answers evaluate immediately or wait for an explicit submit.
nonisolated enum QuizAnswerValidationMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case instantCheck
    case submit

    var id: String { rawValue }

    /// Human-readable option label shown in the settings UI.
    var title: String {
        switch self {
        case .instantCheck: return "Instant Check"
        case .submit:       return "Submit"
        }
    }

    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .instantCheck: return AppLocalization.string("Instant Check", locale: locale)
        case .submit:       return AppLocalization.string("Submit", locale: locale)
        }
    }
}

/// Quiz runtime preferences persisted per deck.
nonisolated struct QuizModeSettings: Codable, Equatable, Sendable {
    var shuffleChoices: Bool = false
    var explanationTiming: QuizExplanationTiming = .afterCheck
    var answerValidation: QuizAnswerValidationMode = .instantCheck
    var retryIncorrectQuestions: Bool = true
}

// MARK: - Learn Settings

/// Controls how the Learn report groups its sections.
nonisolated enum LearnReportGrouping: String, Codable, CaseIterable, Identifiable, Sendable {
    case readinessFirst
    case byCardKind
    case freshMaterialFirst

    var id: String { rawValue }

    /// Human-readable option label shown in the settings UI.
    var title: String {
        switch self {
        case .readinessFirst:   return "Readiness First"
        case .byCardKind:       return "By Card Kind"
        case .freshMaterialFirst: return "Fresh Material First"
        }
    }

    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .readinessFirst:
            return AppLocalization.string("Readiness First", locale: locale)
        case .byCardKind:
            return AppLocalization.string("By Card Kind", locale: locale)
        case .freshMaterialFirst:
            return AppLocalization.string("Fresh Material First", locale: locale)
        }
    }
}

/// Controls how much information Learn mode shows at once.
nonisolated enum LearnReportDensity: String, Codable, CaseIterable, Identifiable, Sendable {
    case compact
    case standard
    case detailed

    var id: String { rawValue }

    /// Human-readable option label shown in the settings UI.
    var title: String {
        switch self {
        case .compact:  return "Compact"
        case .standard: return "Standard"
        case .detailed: return "Detailed"
        }
    }

    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .compact:  return AppLocalization.string("Compact", locale: locale)
        case .standard: return AppLocalization.string("Standard", locale: locale)
        case .detailed: return AppLocalization.string("Detailed", locale: locale)
        }
    }
}

/// Learn report preferences persisted per deck.
nonisolated struct LearnModeSettings: Codable, Equatable, Sendable {
    var grouping: LearnReportGrouping = .readinessFirst
    var density: LearnReportDensity = .standard
}

// MARK: - Deck Play Mode Settings Model

/// One deck-scoped persistent bucket storing the active settings for every play mode.
@Model
final class DeckPlayModeSettingsModel {

    // MARK: - Stored Data

    @Attribute(.externalStorage)
    private var flashcardSettingsData: Data

    @Attribute(.externalStorage)
    private var quizSettingsData: Data

    @Attribute(.externalStorage)
    private var learnSettingsData: Data

    /// The date these settings were last changed.
    var updatedAt: Date

    /// The most recent time this deck launched Flashcards.
    var flashcardsLastUsedAt: Date?

    /// The most recent time this deck launched Quiz.
    var quizLastUsedAt: Date?

    /// The most recent time this deck launched Learn.
    var learnLastUsedAt: Date?

    // MARK: - Relationships

    /// The deck that owns this settings bucket.
    var deck: DeckModel?

    // MARK: - Computed Settings

    /// Flashcards settings decoded from the persistent payload blob.
    var flashcardSettings: FlashcardModeSettings {
        get {
            Self.decode(
                FlashcardModeSettings.self,
                from: flashcardSettingsData,
                defaultValue: FlashcardModeSettings()
            )
        }
        set {
            flashcardSettingsData = Self.encode(newValue)
            updatedAt = Date()
        }
    }

    /// Quiz settings decoded from the persistent payload blob.
    var quizSettings: QuizModeSettings {
        get {
            Self.decode(
                QuizModeSettings.self,
                from: quizSettingsData,
                defaultValue: QuizModeSettings()
            )
        }
        set {
            quizSettingsData = Self.encode(newValue)
            updatedAt = Date()
        }
    }

    /// Learn settings decoded from the persistent payload blob.
    var learnSettings: LearnModeSettings {
        get {
            Self.decode(
                LearnModeSettings.self,
                from: learnSettingsData,
                defaultValue: LearnModeSettings()
            )
        }
        set {
            learnSettingsData = Self.encode(newValue)
            updatedAt = Date()
        }
    }

    // MARK: - Init

    init(deck: DeckModel? = nil) {
        self.flashcardSettingsData = Self.encode(FlashcardModeSettings())
        self.quizSettingsData = Self.encode(QuizModeSettings())
        self.learnSettingsData = Self.encode(LearnModeSettings())
        self.updatedAt = Date()
        self.flashcardsLastUsedAt = nil
        self.quizLastUsedAt = nil
        self.learnLastUsedAt = nil
        self.deck = deck
    }

    // MARK: - Helpers

    private static func encode<Value: Encodable>(_ value: Value) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }

    private static func decode<Value: Decodable>(
        _ type: Value.Type,
        from data: Data,
        defaultValue: @autoclosure () -> Value
    ) -> Value {
        guard !data.isEmpty, let decoded = try? JSONDecoder().decode(type, from: data) else {
            return defaultValue()
        }
        return decoded
    }
}

// MARK: - Deck Play Mode Settings Store

/// Creates and returns the persistent settings bucket for a given deck.
enum DeckPlayModeSettingsStore {
    /// Returns the deck's existing settings bucket or creates a new one on demand.
    @MainActor
    static func resolve(for deck: DeckModel, in context: ModelContext) -> DeckPlayModeSettingsModel {
        if let existing = deck.playModeSettings {
            return existing
        }

        let settings = DeckPlayModeSettingsModel(deck: deck)
        deck.playModeSettings = settings
        context.insert(settings)
        return settings
    }
}
