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
nonisolated struct FlashcardTextSize: Codable, CaseIterable, Identifiable, Hashable, Sendable {
    static let minimumStep = 0
    static let maximumStep = 6
    static let normal = FlashcardTextSize(step: 3)
    static let large = FlashcardTextSize(step: 6)
    static let allCases: [FlashcardTextSize] = (minimumStep...maximumStep).map { FlashcardTextSize(step: $0) }

    let step: Int

    var id: Int { step }
    var rawValue: Int { step }

    init(step: Int) {
        self.step = min(max(step, Self.minimumStep), Self.maximumStep)
    }

    /// Human-readable option label shown in the settings UI.
    var title: String {
        switch step {
        case 0...1: return "Small"
        case 2:     return "Medium"
        case 3:     return "Normal"
        default:    return "Large"
        }
    }

    func localizedTitle(locale: Locale) -> String {
        switch step {
        case 0...1: return AppLocalization.string("Small", locale: locale)
        case 2:     return AppLocalization.string("Medium", locale: locale)
        case 3:     return AppLocalization.string("Normal", locale: locale)
        default:    return AppLocalization.string("Large", locale: locale)
        }
    }

    var playModeScale: Double {
        switch step {
        case 0: return 0.72
        case 1: return 0.84
        case 2: return 0.96
        case 3: return 1.08
        case 4: return 1.22
        case 5: return 1.40
        default: return 1.62
        }
    }

    /// Maps the former 11-step scale to the closest size on the current
    /// seven-step scale. This keeps existing preferences visually stable
    /// without exposing legacy index values in the UI.
    static func migratedLegacyStep(_ legacyStep: Int) -> FlashcardTextSize {
        switch min(max(legacyStep, 0), 10) {
        case 0...1: return FlashcardTextSize(step: 1)
        case 2:     return FlashcardTextSize(step: 2)
        case 3...4: return FlashcardTextSize(step: 3)
        case 5...6: return FlashcardTextSize(step: 4)
        case 7...8: return FlashcardTextSize(step: 5)
        default:    return FlashcardTextSize(step: 6)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let step = try? container.decode(Int.self) {
            self.init(step: step)
            return
        }

        let rawValue = try container.decode(String.self)
        switch rawValue {
        case "normal":
            self = .normal
        case "large":
            self = .large
        case "small":
            self.init(step: 1)
        case "medium":
            self.init(step: 4)
        default:
            self = .large
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(step)
    }
}

/// Flashcards runtime preferences persisted per deck.
nonisolated struct FlashcardModeSettings: Codable, Equatable, Sendable {
    private static let currentSchemaVersion = 6

    private var schemaVersion: Int = Self.currentSchemaVersion
    var order: FlashcardSessionOrder = .studyPriority
    var retryWrongCards: Bool = true
    var tapAnimationStyle: FlashcardTapAnimationStyle = .flip3D
    var staticSwapTextMotion: FlashcardStaticSwapTextMotion = .animated
    var contentAlignment: FlashcardContentAlignment = .center
    var textSize: FlashcardTextSize = .large
    var usesAppTextSize: Bool = true

    init(
        order: FlashcardSessionOrder = .studyPriority,
        retryWrongCards: Bool = true,
        tapAnimationStyle: FlashcardTapAnimationStyle = .flip3D,
        staticSwapTextMotion: FlashcardStaticSwapTextMotion = .animated,
        contentAlignment: FlashcardContentAlignment = .center,
        textSize: FlashcardTextSize = .large,
        usesAppTextSize: Bool = true
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.order = order
        self.retryWrongCards = retryWrongCards
        self.tapAnimationStyle = tapAnimationStyle
        self.staticSwapTextMotion = staticSwapTextMotion
        self.contentAlignment = contentAlignment
        self.textSize = textSize
        self.usesAppTextSize = usesAppTextSize
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case order
        case retryWrongCards
        case tapAnimationStyle
        case staticSwapTextMotion
        case contentAlignment
        case textSize
        case usesAppTextSize
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSchemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.order = try container.decodeIfPresent(FlashcardSessionOrder.self, forKey: .order) ?? .studyPriority
        self.retryWrongCards = try container.decodeIfPresent(Bool.self, forKey: .retryWrongCards) ?? true
        self.tapAnimationStyle = try container.decodeIfPresent(FlashcardTapAnimationStyle.self, forKey: .tapAnimationStyle) ?? .flip3D
        self.staticSwapTextMotion = try container.decodeIfPresent(FlashcardStaticSwapTextMotion.self, forKey: .staticSwapTextMotion) ?? .animated
        let decodedContentAlignment = try container.decodeIfPresent(FlashcardContentAlignment.self, forKey: .contentAlignment) ?? .center
        self.contentAlignment = decodedSchemaVersion < 2 && decodedContentAlignment == .top
            ? .center
            : decodedContentAlignment
        let legacyTextSizeStep: Int? = decodedSchemaVersion < Self.currentSchemaVersion
            ? try? container.decode(Int.self, forKey: .textSize)
            : nil
        let storedTextSize = try container.decodeIfPresent(FlashcardTextSize.self, forKey: .textSize)
        let decodedTextSize = legacyTextSizeStep.map(FlashcardTextSize.migratedLegacyStep)
            ?? storedTextSize
            ?? .large
        self.textSize = decodedTextSize
        self.usesAppTextSize = try container.decodeIfPresent(Bool.self, forKey: .usesAppTextSize)
            ?? (legacyTextSizeStep == nil || legacyTextSizeStep == 10)
        self.schemaVersion = Self.currentSchemaVersion
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try container.encode(order, forKey: .order)
        try container.encode(retryWrongCards, forKey: .retryWrongCards)
        try container.encode(tapAnimationStyle, forKey: .tapAnimationStyle)
        try container.encode(staticSwapTextMotion, forKey: .staticSwapTextMotion)
        try container.encode(contentAlignment, forKey: .contentAlignment)
        try container.encode(textSize, forKey: .textSize)
        try container.encode(usesAppTextSize, forKey: .usesAppTextSize)
    }

    func resolvedTextSize(default defaultTextSize: FlashcardTextSize) -> FlashcardTextSize {
        usesAppTextSize ? defaultTextSize : textSize
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
    private static let currentSchemaVersion = 2

    private var schemaVersion: Int = Self.currentSchemaVersion
    var shuffleChoices: Bool = false
    var explanationTiming: QuizExplanationTiming = .afterCheck
    var answerValidation: QuizAnswerValidationMode = .instantCheck
    var retryIncorrectQuestions: Bool = true
    var textSize: FlashcardTextSize = .large
    var usesAppTextSize: Bool = true

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case shuffleChoices
        case explanationTiming
        case answerValidation
        case retryIncorrectQuestions
        case textSize
        case usesAppTextSize
    }

    init(
        shuffleChoices: Bool = false,
        explanationTiming: QuizExplanationTiming = .afterCheck,
        answerValidation: QuizAnswerValidationMode = .instantCheck,
        retryIncorrectQuestions: Bool = true,
        textSize: FlashcardTextSize = .large,
        usesAppTextSize: Bool = true
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.shuffleChoices = shuffleChoices
        self.explanationTiming = explanationTiming
        self.answerValidation = answerValidation
        self.retryIncorrectQuestions = retryIncorrectQuestions
        self.textSize = textSize
        self.usesAppTextSize = usesAppTextSize
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSchemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.shuffleChoices = try container.decodeIfPresent(Bool.self, forKey: .shuffleChoices) ?? false
        self.explanationTiming = try container.decodeIfPresent(QuizExplanationTiming.self, forKey: .explanationTiming) ?? .afterCheck
        self.answerValidation = try container.decodeIfPresent(QuizAnswerValidationMode.self, forKey: .answerValidation) ?? .instantCheck
        self.retryIncorrectQuestions = try container.decodeIfPresent(Bool.self, forKey: .retryIncorrectQuestions) ?? true
        let legacyTextSizeStep: Int? = decodedSchemaVersion < Self.currentSchemaVersion
            ? try? container.decode(Int.self, forKey: .textSize)
            : nil
        let storedTextSize = try container.decodeIfPresent(FlashcardTextSize.self, forKey: .textSize)
        let decodedTextSize = legacyTextSizeStep.map(FlashcardTextSize.migratedLegacyStep)
            ?? storedTextSize
            ?? .large
        self.textSize = decodedTextSize
        self.usesAppTextSize = try container.decodeIfPresent(Bool.self, forKey: .usesAppTextSize)
            ?? (legacyTextSizeStep == nil || legacyTextSizeStep == 10)
        self.schemaVersion = Self.currentSchemaVersion
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try container.encode(shuffleChoices, forKey: .shuffleChoices)
        try container.encode(explanationTiming, forKey: .explanationTiming)
        try container.encode(answerValidation, forKey: .answerValidation)
        try container.encode(retryIncorrectQuestions, forKey: .retryIncorrectQuestions)
        try container.encode(textSize, forKey: .textSize)
        try container.encode(usesAppTextSize, forKey: .usesAppTextSize)
    }

    func resolvedTextSize(default defaultTextSize: FlashcardTextSize) -> FlashcardTextSize {
        usesAppTextSize ? defaultTextSize : textSize
    }
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

    /// The date these settings were last changed.
    var updatedAt: Date

    /// The most recent time this deck launched Flashcards.
    var flashcardsLastUsedAt: Date?

    /// The most recent time this deck launched Quiz.
    var quizLastUsedAt: Date?

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

    // MARK: - Init

    init(deck: DeckModel? = nil) {
        self.flashcardSettingsData = Self.encode(FlashcardModeSettings())
        self.quizSettingsData = Self.encode(QuizModeSettings())
        self.updatedAt = Date()
        self.flashcardsLastUsedAt = nil
        self.quizLastUsedAt = nil
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
