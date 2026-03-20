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
}

/// Controls whether the flashcard can flip during the session.
nonisolated enum FlashcardFlipBehavior: String, Codable, CaseIterable, Identifiable, Sendable {
    case tapToFlip
    case locked

    var id: String { rawValue }

    /// Human-readable option label shown in the settings UI.
    var title: String {
        switch self {
        case .tapToFlip: return "Tap To Flip"
        case .locked:    return "Locked Face"
        }
    }
}

/// Flashcards runtime preferences persisted per deck.
nonisolated struct FlashcardModeSettings: Codable, Equatable, Sendable {
    var order: FlashcardSessionOrder = .studyPriority
    var retryWrongCards: Bool = true
    var revealFlow: FlashcardRevealFlow = .questionFirst
    var flipBehavior: FlashcardFlipBehavior = .tapToFlip
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
}

/// Quiz runtime preferences persisted per deck.
nonisolated struct QuizModeSettings: Codable, Equatable, Sendable {
    var shuffleChoices: Bool = false
    var explanationTiming: QuizExplanationTiming = .afterCheck
    var answerValidation: QuizAnswerValidationMode = .instantCheck
    var retryIncorrectQuestions: Bool = true
}

// MARK: - Match Settings

/// Controls the number of pairs that appear in a single match round.
nonisolated enum MatchRoundSize: Int, Codable, CaseIterable, Identifiable, Sendable {
    case four = 4
    case six = 6
    case eight = 8

    var id: Int { rawValue }

    /// Human-readable option label shown in the settings UI.
    var title: String { "\(rawValue) Pairs" }
}

/// Controls how dense the match tiles look on screen.
nonisolated enum MatchContentDensity: String, Codable, CaseIterable, Identifiable, Sendable {
    case compact
    case standard

    var id: String { rawValue }

    /// Human-readable option label shown in the settings UI.
    var title: String {
        switch self {
        case .compact:  return "Compact"
        case .standard: return "Standard"
        }
    }
}

/// Controls how aggressive mismatch feedback feels during a round.
nonisolated enum MatchFeedbackIntensity: String, Codable, CaseIterable, Identifiable, Sendable {
    case subtle
    case standard

    var id: String { rawValue }

    /// Human-readable option label shown in the settings UI.
    var title: String {
        switch self {
        case .subtle:   return "Subtle"
        case .standard: return "Standard"
        }
    }
}

/// Match runtime preferences persisted per deck.
nonisolated struct MatchModeSettings: Codable, Equatable, Sendable {
    var allowsFlashcardFallback: Bool = true
    var roundSize: MatchRoundSize = .six
    var contentDensity: MatchContentDensity = .compact
    var retryMissedPairs: Bool = true
    var feedbackIntensity: MatchFeedbackIntensity = .standard
}

// MARK: - Write Settings

/// Controls which answer-entry surface Write mode uses.
nonisolated enum WriteAnswerInputMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto
    case freeText
    case assistedBuilder

    var id: String { rawValue }

    /// Human-readable option label shown in the settings UI.
    var title: String {
        switch self {
        case .auto:            return "Auto"
        case .freeText:        return "Free Text"
        case .assistedBuilder: return "Builder"
        }
    }
}

/// Controls how strictly the typed answer is matched against the canonical blank.
nonisolated enum WriteAnswerStrictness: String, Codable, CaseIterable, Identifiable, Sendable {
    case normalized
    case exact

    var id: String { rawValue }

    /// Human-readable option label shown in the settings UI.
    var title: String {
        switch self {
        case .normalized: return "Normalized"
        case .exact:      return "Exact"
        }
    }
}

/// Controls when the canonical answer becomes visible after checking.
nonisolated enum WriteRevealTiming: String, Codable, CaseIterable, Identifiable, Sendable {
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
}

/// Write runtime preferences persisted per deck.
nonisolated struct WriteModeSettings: Codable, Equatable, Sendable {
    var inputMode: WriteAnswerInputMode = .auto
    var strictness: WriteAnswerStrictness = .normalized
    var revealTiming: WriteRevealTiming = .afterCheck
    var retryIncorrectPrompts: Bool = true
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
    private var matchSettingsData: Data

    @Attribute(.externalStorage)
    private var writeSettingsData: Data

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

    /// The most recent time this deck launched Match.
    var matchLastUsedAt: Date?

    /// The most recent time this deck launched Write.
    var writeLastUsedAt: Date?

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

    /// Match settings decoded from the persistent payload blob.
    var matchSettings: MatchModeSettings {
        get {
            Self.decode(
                MatchModeSettings.self,
                from: matchSettingsData,
                defaultValue: MatchModeSettings()
            )
        }
        set {
            matchSettingsData = Self.encode(newValue)
            updatedAt = Date()
        }
    }

    /// Write settings decoded from the persistent payload blob.
    var writeSettings: WriteModeSettings {
        get {
            Self.decode(
                WriteModeSettings.self,
                from: writeSettingsData,
                defaultValue: WriteModeSettings()
            )
        }
        set {
            writeSettingsData = Self.encode(newValue)
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
        self.matchSettingsData = Self.encode(MatchModeSettings())
        self.writeSettingsData = Self.encode(WriteModeSettings())
        self.learnSettingsData = Self.encode(LearnModeSettings())
        self.updatedAt = Date()
        self.flashcardsLastUsedAt = nil
        self.quizLastUsedAt = nil
        self.learnLastUsedAt = nil
        self.matchLastUsedAt = nil
        self.writeLastUsedAt = nil
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
