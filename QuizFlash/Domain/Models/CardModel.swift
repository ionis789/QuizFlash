//
//  CardModel.swift
//  QuizFlash
//
//  A SwiftData model representing a single mixed card.
//  This file must remain free of SwiftUI and UIKit imports -
//  it is a pure data layer that the entire app depends on.
//

import Foundation
import SwiftData

// MARK: - Card Content Type

/// Describes the rendering mode for one side of a flashcard.
nonisolated enum CardContentType: String, Codable, Sendable {
    case text
    case canvas
}

// MARK: - Card Creation Source

/// Describes how a card entered the deck originally.
nonisolated enum CardCreationSource: String, Codable, Sendable {
    case manual
    case ai
}

// MARK: - Card Kind

/// Identifies the persisted content kind for one deck card.
nonisolated enum CardKind: String, Codable, CaseIterable, Sendable {
    case flashcard
    case quiz
}

// MARK: - Mixed Card Payloads

/// Flashcard payload used as the backward-compatible baseline card content.
nonisolated struct FlashcardCardContent: Codable, Equatable, Sendable {
    var frontZone: ZoneModel
    var backZone: ZoneModel
    var frontType: CardContentType
    var backType: CardContentType

    static let empty = FlashcardCardContent(
        frontZone: .text(),
        backZone: .text(),
        frontType: .text,
        backType: .text
    )
}

/// One answer choice inside a quiz card draft or persisted quiz payload.
nonisolated struct QuizChoiceDraft: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var contentZone: ZoneModel
    var isCorrect: Bool

    init(
        id: UUID = UUID(),
        contentZone: ZoneModel = .text(),
        isCorrect: Bool = false
    ) {
        self.id = id
        self.contentZone = contentZone
        self.isCorrect = isCorrect
    }
}

/// Persisted content for a quiz card.
nonisolated struct QuizCardContent: Codable, Equatable, Sendable {
    var questionZone: ZoneModel
    var choices: [QuizChoiceDraft]
    var explanationZone: ZoneModel?
    var allowsMultipleCorrect: Bool

    static let empty = QuizCardContent(
        questionZone: .text(),
        choices: [],
        explanationZone: nil,
        allowsMultipleCorrect: false
    )
}

/// Helper describing which play surfaces can consume a given card kind.
nonisolated struct CardModeCompatibility: Equatable, Sendable {
    let supportsFlashcards: Bool
    let supportsQuiz: Bool

    init(kind: CardKind) {
        switch kind {
        case .flashcard:
            supportsFlashcards = true
            supportsQuiz = false
        case .quiz:
            supportsFlashcards = false
            supportsQuiz = true
        }
    }
}

// MARK: - Draft Card Content

/// Heterogeneous card payload used by the editor, persistence bridges, and export/session layers.
nonisolated enum DraftCardContent: Equatable, Sendable {
    case flashcard(FlashcardCardContent)
    case quiz(QuizCardContent)
}

extension DraftCardContent: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case flashcard
        case quiz
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(CardKind.self, forKey: .kind)

        switch kind {
        case .flashcard:
            let content = try container.decode(FlashcardCardContent.self, forKey: .flashcard)
            self = .flashcard(content)
        case .quiz:
            let content = try container.decode(QuizCardContent.self, forKey: .quiz)
            self = .quiz(content)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)

        switch self {
        case .flashcard(let content):
            try container.encode(content, forKey: .flashcard)
        case .quiz(let content):
            try container.encode(content, forKey: .quiz)
        }
    }
}

extension DraftCardContent {
    /// The discriminant describing the stored content family.
    nonisolated var kind: CardKind {
        switch self {
        case .flashcard:
            return .flashcard
        case .quiz:
            return .quiz
        }
    }

    /// Compatibility projection used by legacy flashcard-only surfaces during the migration.
    nonisolated var flashcardCompatibilityContent: FlashcardCardContent {
        switch self {
        case .flashcard(let content):
            return content
        case .quiz(let content):
            let answers = content.choices.map(\.contentZone)
            let answerZone: ZoneModel
            switch answers.count {
            case 0:
                answerZone = .text()
            case 1:
                answerZone = answers[0]
            default:
                answerZone = .container(direction: .vertical, children: answers)
            }

            return FlashcardCardContent(
                frontZone: content.questionZone,
                backZone: answerZone,
                frontType: .text,
                backType: .text
            )
        }
    }

    /// Canonical preview caches reused by rows, snapshots, search, and export.
    nonisolated var previewCache: (front: String, back: String) {
        switch self {
        case .flashcard(let content):
            return (
                front: content.frontZone.previewText(maxLength: 200),
                back: content.backZone.previewText(maxLength: 200)
            )
        case .quiz(let content):
            let questionPreview = content.questionZone.previewText(maxLength: 200)
            let correctChoicePreview = Self.joinedChoicePreview(
                content.choices.filter(\.isCorrect).map(\.contentZone),
                maxLength: 200
            )

            return (front: questionPreview, back: correctChoicePreview)
        }
    }

    /// Flattened plain text used by search and other lightweight scans.
    nonisolated var searchDocumentText: String {
        switch self {
        case .flashcard(let content):
            return [content.frontZone.previewText(maxLength: 800), content.backZone.previewText(maxLength: 800)]
                .joined(separator: "\n")
        case .quiz(let content):
            let choiceText = content.choices
                .map { $0.contentZone.previewText(maxLength: 300) }
                .joined(separator: "\n")
            let explanationText = content.explanationZone?.previewText(maxLength: 400) ?? ""
            return [content.questionZone.previewText(maxLength: 800), choiceText, explanationText]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        }
    }

    /// Returns the zone roots that should contribute to editor metrics and compatibility previews.
    nonisolated var metricZones: [ZoneModel] {
        switch self {
        case .flashcard(let content):
            return [content.frontZone, content.backZone]
        case .quiz(let content):
            return [content.questionZone] + content.choices.map(\.contentZone) + [content.explanationZone].compactMap { $0 }
        }
    }

    /// Whether the content can participate in each play surface.
    nonisolated var modeCompatibility: CardModeCompatibility {
        CardModeCompatibility(kind: kind)
    }

    private nonisolated static func joinedChoicePreview(_ zones: [ZoneModel], maxLength: Int) -> String {
        let joined = zones
            .map { $0.previewText(maxLength: maxLength) }
            .filter { !$0.isEmpty && $0 != "Empty" }
            .joined(separator: " • ")

        guard !joined.isEmpty else { return "Empty" }
        guard joined.count > maxLength else { return joined }
        return String(joined.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    private nonisolated static func normalizedShortText(_ text: String, fallback: String) -> String {
        let trimmed = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else { return fallback }
        return String(trimmed.prefix(200))
    }
}

// MARK: - Card Model

/// A SwiftData persistent model representing a single mixed card within a deck.
///
/// `CardModel` is a pure data entity. It must not import SwiftUI or UIKit,
/// and must not contain any presentation logic or UI state.
/// All UI-related behaviour belongs in the ViewModel or View layers.
@Model
class CardModel {

    // MARK: - Raw Content Storage

    /// Raw string storing the `CardKind` discriminant for this card.
    var kindRaw: String = CardKind.flashcard.rawValue

    /// Raw string storing the `CardContentType` for the front face.
    var frontTypeRaw: String = CardContentType.text.rawValue

    /// Raw string storing the `CardContentType` for the back face.
    var backTypeRaw: String = CardContentType.text.rawValue

    /// Serialised compatibility `ZoneModel` tree for the front face, stored externally.
    @Attribute(.externalStorage)
    var frontZoneData: Data?

    /// Serialised compatibility `ZoneModel` tree for the back face, stored externally.
    @Attribute(.externalStorage)
    var backZoneData: Data?

    /// Serialised quiz payload stored externally for memory efficiency.
    @Attribute(.externalStorage)
    var quizContentData: Data?

    // MARK: - Text Preview Cache

    /// Denormalised plain-text preview of the primary prompt/question side.
    var frontText: String = ""

    /// Denormalised plain-text preview of the answer/response side.
    var backText: String = ""

    // MARK: - Metadata

    /// The date this card was first created.
    var createdAt: Date = Date()

    /// The date this card was last edited.
    var editedAt: Date = Date()

    /// The sequential display number assigned by the parent deck.
    var cardNumber: Int = 0

    /// Keeps the card surfaced at the top of deck views regardless of the active sort order.
    var isPinned: Bool = false

    /// Raw string backing `creationSource` for SwiftData persistence.
    var creationSourceRaw: String = CardCreationSource.manual.rawValue

    // MARK: - Relationships

    /// The deck that owns this card. Nil if the card has been orphaned.
    var deck: DeckModel?

    /// Full review history for this card, used by the SRS engine.
    @Relationship(deleteRule: .cascade, inverse: \ReviewEvent.card)
    var reviewHistory: [ReviewEvent] = []

    // MARK: - Spaced Repetition Parameters

    /// The next review date calculated by the SRS algorithm.
    var dueDate: Date = Date()

    /// The SM-2 ease factor (difficulty multiplier). Defaults to 2.5.
    var easeFactor: Double = 2.5

    /// Interval in days until the next scheduled review.
    var interval: Int = 0

    /// Number of consecutive correct answers since the last lapse.
    var consecutiveCorrectAnswers: Int = 0

    // MARK: - Cache

    /// In-memory cache for the decoded front compatibility `ZoneModel`.
    @Transient private var cachedFrontZone: ZoneModel?

    /// In-memory cache for the decoded back compatibility `ZoneModel`.
    @Transient private var cachedBackZone: ZoneModel?

    /// In-memory cache for the decoded quiz payload.
    @Transient private var cachedQuizContent: QuizCardContent?

    // MARK: - Computed Properties

    /// The mixed-card kind for this persisted card.
    var kind: CardKind {
        get { CardKind(rawValue: kindRaw) ?? .flashcard }
        set { kindRaw = newValue.rawValue }
    }

    /// The content type for the front face. Backed by `frontTypeRaw` for SwiftData compatibility.
    var frontType: CardContentType {
        get { CardContentType(rawValue: frontTypeRaw) ?? .text }
        set { frontTypeRaw = newValue.rawValue }
    }

    /// The content type for the back face. Backed by `backTypeRaw` for SwiftData compatibility.
    var backType: CardContentType {
        get { CardContentType(rawValue: backTypeRaw) ?? .text }
        set { backTypeRaw = newValue.rawValue }
    }

    /// The origin of the card, used for future deck-level creation-source stats.
    var creationSource: CardCreationSource {
        get { CardCreationSource(rawValue: creationSourceRaw) ?? .manual }
        set { creationSourceRaw = newValue.rawValue }
    }

    /// The decoded front compatibility `ZoneModel` tree.
    var frontZone: ZoneModel {
        get {
            if kind != .flashcard {
                return cardContent.flashcardCompatibilityContent.frontZone
            }

            if let cached = cachedFrontZone { return cached }
            if let data = frontZoneData, let zone = ZoneModel.decode(from: data) {
                cachedFrontZone = zone
                return zone
            }
            return .text()
        }
        set {
            var compatibility = cardContent.flashcardCompatibilityContent
            compatibility.frontZone = newValue
            cardContent = .flashcard(compatibility)
        }
    }

    /// The decoded back compatibility `ZoneModel` tree.
    var backZone: ZoneModel {
        get {
            if kind != .flashcard {
                return cardContent.flashcardCompatibilityContent.backZone
            }

            if let cached = cachedBackZone { return cached }
            if let data = backZoneData, let zone = ZoneModel.decode(from: data) {
                cachedBackZone = zone
                return zone
            }
            return .text()
        }
        set {
            var compatibility = cardContent.flashcardCompatibilityContent
            compatibility.backZone = newValue
            cardContent = .flashcard(compatibility)
        }
    }

    /// The decoded quiz payload for `.quiz` cards.
    var quizContent: QuizCardContent? {
        get {
            guard kind == .quiz else { return nil }
            if let cachedQuizContent { return cachedQuizContent }
            if let data = quizContentData, let decoded = try? JSONDecoder().decode(QuizCardContent.self, from: data) {
                cachedQuizContent = decoded
                return decoded
            }
            return nil
        }
        set {
            guard let newValue else {
                cachedQuizContent = nil
                quizContentData = nil
                if kind == .quiz {
                    cardContent = .quiz(.empty)
                }
                return
            }

            cardContent = .quiz(newValue)
        }
    }

    /// The canonical heterogeneous payload for this card.
    var cardContent: DraftCardContent {
        get {
            switch kind {
            case .flashcard:
                return .flashcard(
                    FlashcardCardContent(
                        frontZone: decodeCompatibilityFrontZone(),
                        backZone: decodeCompatibilityBackZone(),
                        frontType: frontType,
                        backType: backType
                    )
                )
            case .quiz:
                return .quiz(quizContent ?? .empty)
            }
        }
        set {
            apply(content: newValue)
        }
    }

    /// Flattened text suitable for search or other lightweight matching surfaces.
    var searchDocumentText: String {
        cardContent.searchDocumentText
    }

    /// Play-surface compatibility for this persisted card.
    var modeCompatibility: CardModeCompatibility {
        cardContent.modeCompatibility
    }

    // MARK: - Cache Management

    /// Releases decoded payload caches, immediately reclaiming memory.
    func clearZoneCache() {
        cachedFrontZone = nil
        cachedBackZone = nil
        cachedQuizContent = nil
    }

    // MARK: - Initializers

    /// Creates a new `CardModel` with flashcard content and metadata.
    init(
        frontZone: ZoneModel,
        backZone: ZoneModel,
        frontType: CardContentType = .text,
        backType: CardContentType = .text,
        cardNumber: Int = 0,
        isPinned: Bool = false,
        creationSource: CardCreationSource = .manual
    ) {
        self.cardNumber = cardNumber
        self.isPinned = isPinned
        self.creationSourceRaw = creationSource.rawValue
        self.createdAt = Date()
        self.editedAt = Date()
        self.dueDate = Date()
        self.easeFactor = 2.5
        self.interval = 0
        self.consecutiveCorrectAnswers = 0

        self.cardContent = .flashcard(
            FlashcardCardContent(
                frontZone: frontZone,
                backZone: backZone,
                frontType: frontType,
                backType: backType
            )
        )
    }

    /// Creates a new `CardModel` with heterogeneous payload content and metadata.
    init(
        content: DraftCardContent,
        cardNumber: Int = 0,
        isPinned: Bool = false,
        creationSource: CardCreationSource = .manual
    ) {
        self.cardNumber = cardNumber
        self.isPinned = isPinned
        self.creationSourceRaw = creationSource.rawValue
        self.createdAt = Date()
        self.editedAt = Date()
        self.dueDate = Date()
        self.easeFactor = 2.5
        self.interval = 0
        self.consecutiveCorrectAnswers = 0

        self.cardContent = content
    }

    // MARK: - Private Helpers

    private func decodeCompatibilityFrontZone() -> ZoneModel {
        if let cachedFrontZone { return cachedFrontZone }
        if let data = frontZoneData, let zone = ZoneModel.decode(from: data) {
            cachedFrontZone = zone
            return zone
        }
        return .text()
    }

    private func decodeCompatibilityBackZone() -> ZoneModel {
        if let cachedBackZone { return cachedBackZone }
        if let data = backZoneData, let zone = ZoneModel.decode(from: data) {
            cachedBackZone = zone
            return zone
        }
        return .text()
    }

    private func apply(content: DraftCardContent) {
        let compatibility = content.flashcardCompatibilityContent
        let previewCache = content.previewCache

        kind = content.kind
        frontType = compatibility.frontType
        backType = compatibility.backType
        cachedFrontZone = compatibility.frontZone
        cachedBackZone = compatibility.backZone
        frontZoneData = compatibility.frontZone.encode()
        backZoneData = compatibility.backZone.encode()
        frontText = previewCache.front
        backText = previewCache.back

        switch content {
        case .flashcard:
            quizContentData = nil
            cachedQuizContent = nil
        case .quiz(let quizContent):
            cachedQuizContent = quizContent
            quizContentData = try? JSONEncoder().encode(quizContent)
        }
    }
}

// MARK: - Draft Card

/// A transient value type used to buffer edits before they are committed to SwiftData.
nonisolated struct DraftCard: Identifiable, Codable, Equatable {

    // MARK: - Properties

    /// A stable unique identifier for this draft, used for SwiftUI list diffing.
    var id: UUID = UUID()

    /// The `PersistentIdentifier` of the `CardModel` being edited, or `nil` for new cards.
    var originalCardID: PersistentIdentifier?

    /// Stable display number mirrored from `CardModel.cardNumber`.
    var cardNumber: Int

    /// The heterogeneous draft content.
    var content: DraftCardContent

    /// Whether this draft should be pinned in deck views once saved.
    var isPinned: Bool

    /// How this draft card was originally created.
    var creationSource: CardCreationSource

    /// The date this draft was originally created (mirrors the source `CardModel`).
    var createdAt: Date?

    /// The date this draft was last edited (mirrors the source `CardModel`).
    var editedAt: Date?

    /// Convenience accessor returning the last edit date. Alias for `editedAt`.
    var lastEditDate: Date? { editedAt }

    /// The mixed-card discriminant for this draft.
    var kind: CardKind { content.kind }

    /// Compatibility accessor used by flashcard-only surfaces during the migration.
    var frontZone: ZoneModel {
        get { content.flashcardCompatibilityContent.frontZone }
        set {
            var compatibility = content.flashcardCompatibilityContent
            compatibility.frontZone = newValue
            content = .flashcard(compatibility)
        }
    }

    /// Compatibility accessor used by flashcard-only surfaces during the migration.
    var backZone: ZoneModel {
        get { content.flashcardCompatibilityContent.backZone }
        set {
            var compatibility = content.flashcardCompatibilityContent
            compatibility.backZone = newValue
            content = .flashcard(compatibility)
        }
    }

    /// Compatibility accessor used by flashcard-only surfaces during the migration.
    var frontType: CardContentType {
        get { content.flashcardCompatibilityContent.frontType }
        set {
            var compatibility = content.flashcardCompatibilityContent
            compatibility.frontType = newValue
            content = .flashcard(compatibility)
        }
    }

    /// Compatibility accessor used by flashcard-only surfaces during the migration.
    var backType: CardContentType {
        get { content.flashcardCompatibilityContent.backType }
        set {
            var compatibility = content.flashcardCompatibilityContent
            compatibility.backType = newValue
            content = .flashcard(compatibility)
        }
    }

    /// Flattened text suitable for search or other lightweight matching surfaces.
    var searchDocumentText: String {
        content.searchDocumentText
    }

    /// Play-surface compatibility for this draft.
    var modeCompatibility: CardModeCompatibility {
        content.modeCompatibility
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id
        case originalCardID
        case cardNumber
        case kind
        case content
        case frontZone
        case backZone
        case frontType
        case backType
        case isPinned
        case creationSource
        case createdAt
        case editedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()

        if let originalCardIDString = try container.decodeIfPresent(String.self, forKey: .originalCardID),
           let data = originalCardIDString.data(using: .utf8),
           let persistentIdentifier = try? JSONDecoder().decode(PersistentIdentifier.self, from: data) {
            originalCardID = persistentIdentifier
        } else {
            originalCardID = nil
        }

        cardNumber = try container.decodeIfPresent(Int.self, forKey: .cardNumber) ?? 0

        if let decodedContent = try container.decodeIfPresent(DraftCardContent.self, forKey: .content) {
            content = decodedContent
        } else {
            let frontZone = try container.decodeIfPresent(ZoneModel.self, forKey: .frontZone) ?? .text()
            let backZone = try container.decodeIfPresent(ZoneModel.self, forKey: .backZone) ?? .text()
            let frontType = try container.decodeIfPresent(CardContentType.self, forKey: .frontType) ?? .text
            let backType = try container.decodeIfPresent(CardContentType.self, forKey: .backType) ?? .text
            content = .flashcard(
                FlashcardCardContent(
                    frontZone: frontZone,
                    backZone: backZone,
                    frontType: frontType,
                    backType: backType
                )
            )
        }

        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        creationSource = try container.decodeIfPresent(CardCreationSource.self, forKey: .creationSource) ?? .manual
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        editedAt = try container.decodeIfPresent(Date.self, forKey: .editedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)

        if let originalCardID,
           let data = try? JSONEncoder().encode(originalCardID),
           let stringValue = String(data: data, encoding: .utf8) {
            try container.encode(stringValue, forKey: .originalCardID)
        }

        try container.encode(cardNumber, forKey: .cardNumber)
        try container.encode(kind, forKey: .kind)
        try container.encode(content, forKey: .content)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encode(creationSource, forKey: .creationSource)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(editedAt, forKey: .editedAt)

        if case .flashcard(let flashcardContent) = content {
            try container.encode(flashcardContent.frontZone, forKey: .frontZone)
            try container.encode(flashcardContent.backZone, forKey: .backZone)
            try container.encode(flashcardContent.frontType, forKey: .frontType)
            try container.encode(flashcardContent.backType, forKey: .backType)
        }
    }

    // MARK: - Initializers

    /// Creates a new heterogeneous draft card.
    init(
        id: UUID = UUID(),
        originalCardID: PersistentIdentifier? = nil,
        cardNumber: Int = 0,
        content: DraftCardContent,
        isPinned: Bool = false,
        creationSource: CardCreationSource = .manual,
        createdAt: Date? = nil,
        editedAt: Date? = nil
    ) {
        self.id = id
        self.originalCardID = originalCardID
        self.cardNumber = cardNumber
        self.content = content
        self.isPinned = isPinned
        self.creationSource = creationSource
        self.createdAt = createdAt
        self.editedAt = editedAt
    }

    /// Creates a new flashcard draft, preserving the existing call sites during migration.
    init(
        originalCardID: PersistentIdentifier? = nil,
        cardNumber: Int = 0,
        frontZone: ZoneModel = .text(),
        backZone: ZoneModel = .text(),
        frontType: CardContentType = .text,
        backType: CardContentType = .text,
        isPinned: Bool = false,
        creationSource: CardCreationSource = .manual,
        createdAt: Date? = nil,
        editedAt: Date? = nil
    ) {
        self.init(
            originalCardID: originalCardID,
            cardNumber: cardNumber,
            content: .flashcard(
                FlashcardCardContent(
                    frontZone: frontZone,
                    backZone: backZone,
                    frontType: frontType,
                    backType: backType
                )
            ),
            isPinned: isPinned,
            creationSource: creationSource,
            createdAt: createdAt,
            editedAt: editedAt
        )
    }

    // MARK: - Factory

    /// Creates a `DraftCard` pre-populated from an existing `CardModel`.
    static func from(_ card: CardModel) -> DraftCard {
        DraftCard(
            originalCardID: card.persistentModelID,
            cardNumber: card.cardNumber,
            content: card.cardContent,
            isPinned: card.isPinned,
            creationSource: card.creationSource,
            createdAt: card.createdAt,
            editedAt: card.editedAt
        )
    }
}
