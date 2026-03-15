//
//  CardModel.swift
//  QuizFlash
//
//  A SwiftData model representing a single flashcard.
//  This file must remain free of SwiftUI and UIKit imports —
//  it is a pure data layer that the entire app depends on.
//

import Foundation
import SwiftData

// MARK: - Card Content Type

/// Describes the rendering mode for one side of a flashcard.
enum CardContentType: String, Codable {
    case text
    case canvas
}

// MARK: - Card Creation Source

/// Describes how a card entered the deck originally.
enum CardCreationSource: String, Codable {
    case manual
    case ai
}

// MARK: - Card Model

/// A SwiftData persistent model representing a single flashcard within a deck.
///
/// `CardModel` is a pure data entity. It must not import SwiftUI or UIKit,
/// and must not contain any presentation logic or UI state.
/// All UI-related behaviour (display formatting, colour, animations) belongs
/// in the ViewModel or View layers.
@Model
class CardModel {

    // MARK: - Raw Content Storage

    /// Raw string storing the `CardContentType` for the front face.
    var frontTypeRaw: String = CardContentType.text.rawValue

    /// Raw string storing the `CardContentType` for the back face.
    var backTypeRaw: String = CardContentType.text.rawValue

    /// Serialised `ZoneModel` tree for the front face, stored externally for performance.
    @Attribute(.externalStorage)
    var frontZoneData: Data?

    /// Serialised `ZoneModel` tree for the back face, stored externally for performance.
    @Attribute(.externalStorage)
    var backZoneData: Data?

    // MARK: - Text Preview Cache

    /// Denormalised plain-text preview of the front face (max 200 characters).
    /// Used for search indexing without decoding the full zone tree.
    var frontText: String = ""

    /// Denormalised plain-text preview of the back face (max 200 characters).
    /// Used for search indexing without decoding the full zone tree.
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

    // MARK: - Zone Cache

    /// In-memory cache for the decoded front `ZoneModel`.
    /// Avoids redundant JSON decoding on every access within the same session.
    @Transient private var cachedFrontZone: ZoneModel?

    /// In-memory cache for the decoded back `ZoneModel`.
    /// Avoids redundant JSON decoding on every access within the same session.
    @Transient private var cachedBackZone: ZoneModel?

    // MARK: - Computed Properties

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

    /// The decoded `ZoneModel` tree for the front face.
    ///
    /// Getting this property decodes `frontZoneData` from JSON on first access and
    /// caches the result. Setting it encodes the new zone to JSON and updates the
    /// `frontText` preview cache.
    var frontZone: ZoneModel {
        get {
            if let cached = cachedFrontZone { return cached }
            if let data = frontZoneData, let zone = ZoneModel.decode(from: data) {
                cachedFrontZone = zone
                return zone
            }
            return .text()
        }
        set {
            cachedFrontZone = newValue
            frontZoneData = newValue.encode()
            frontText = newValue.previewText(maxLength: 200)
        }
    }

    /// The decoded `ZoneModel` tree for the back face.
    ///
    /// Getting this property decodes `backZoneData` from JSON on first access and
    /// caches the result. Setting it encodes the new zone to JSON and updates the
    /// `backText` preview cache.
    var backZone: ZoneModel {
        get {
            if let cached = cachedBackZone { return cached }
            if let data = backZoneData, let zone = ZoneModel.decode(from: data) {
                cachedBackZone = zone
                return zone
            }
            return .text()
        }
        set {
            cachedBackZone = newValue
            backZoneData = newValue.encode()
            backText = newValue.previewText(maxLength: 200)
        }
    }

    // MARK: - Cache Management

    /// Releases the decoded `ZoneModel` caches, immediately reclaiming memory.
    ///
    /// `ZoneModel` can contain image data (megabytes). Without clearing,
    /// every card that has ever been displayed keeps its decoded zones
    /// alive for the entire app session via the `ModelContext` row cache.
    /// The zones will be re-decoded from `frontZoneData`/`backZoneData` on next access.
    func clearZoneCache() {
        cachedFrontZone = nil
        cachedBackZone = nil
    }

    // MARK: - Initializer

    /// Creates a new `CardModel` with the given zone content and metadata.
    ///
    /// - Parameters:
    ///   - frontZone: The zone tree for the front face of the card.
    ///   - backZone: The zone tree for the back face of the card.
    ///   - frontType: The rendering mode for the front face. Defaults to `.text`.
    ///   - backType: The rendering mode for the back face. Defaults to `.text`.
    ///   - cardNumber: The sequential display number. Defaults to `0`.
    init(
        frontZone: ZoneModel,
        backZone: ZoneModel,
        frontType: CardContentType = .text,
        backType: CardContentType = .text,
        cardNumber: Int = 0,
        isPinned: Bool = false,
        creationSource: CardCreationSource = .manual
    ) {
        self.frontTypeRaw = frontType.rawValue
        self.backTypeRaw = backType.rawValue

        self.frontZoneData = frontZone.encode()
        self.backZoneData = backZone.encode()

        self.cardNumber = cardNumber
        self.isPinned = isPinned
        self.creationSourceRaw = creationSource.rawValue

        self.frontText = frontZone.previewText(maxLength: 200)
        self.backText = backZone.previewText(maxLength: 200)

        self.createdAt = Date()
        self.editedAt = Date()

        // SRS defaults — matches SM-2 algorithm starting state.
        self.dueDate = Date()
        self.easeFactor = 2.5
        self.interval = 0
        self.consecutiveCorrectAnswers = 0
    }
}

// MARK: - Draft Card

/// A transient, non-persistent value type used to buffer edits in the card creation or
/// editing UI before they are committed to a `CardModel` in the SwiftData store.
///
/// `DraftCard` is intentionally a `struct` so it is cheap to copy and
/// can be held in `@State` without triggering SwiftData observation.
struct DraftCard: Identifiable, Codable, Equatable {

    // MARK: - Properties

    /// A stable unique identifier for this draft, used for SwiftUI list diffing.
    let id = UUID()

    /// The `PersistentIdentifier` of the `CardModel` being edited, or `nil` for new cards.
    /// Safely mapped to string for `Codable` via computed properties if needed, but for now we attempt default Codable on PersistentIdentifier since Swift 6.
    var originalCardID: PersistentIdentifier?

    /// The zone tree for the front face.
    var frontZone: ZoneModel

    /// The zone tree for the back face.
    var backZone: ZoneModel

    /// The rendering mode for the front face.
    var frontType: CardContentType

    /// The rendering mode for the back face.
    var backType: CardContentType

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
    
    // MARK: - Codable Conformance
    
    enum CodingKeys: String, CodingKey {
        case id, originalCardID, frontZone, backZone, frontType, backType, isPinned, creationSource, createdAt, editedAt
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // UUID id is usually a let, so we can't decode it conventionally, but let's try reading or skipping
        // since ID is a constant 'let id = UUID()', we can just decode the rest.
        if let originalCardIDString = try container.decodeIfPresent(String.self, forKey: .originalCardID),
           let data = originalCardIDString.data(using: .utf8),
           let pid = try? JSONDecoder().decode(PersistentIdentifier.self, from: data) {
            self.originalCardID = pid
        } else {
            self.originalCardID = nil
        }
        self.frontZone = try container.decode(ZoneModel.self, forKey: .frontZone)
        self.backZone = try container.decode(ZoneModel.self, forKey: .backZone)
        self.frontType = try container.decode(CardContentType.self, forKey: .frontType)
        self.backType = try container.decode(CardContentType.self, forKey: .backType)
        self.isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        self.creationSource = try container.decodeIfPresent(CardCreationSource.self, forKey: .creationSource) ?? .manual
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        self.editedAt = try container.decodeIfPresent(Date.self, forKey: .editedAt)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        if let originalCardID = originalCardID, let data = try? JSONEncoder().encode(originalCardID) {
            try container.encode(String(data: data, encoding: .utf8), forKey: .originalCardID)
        }
        try container.encode(frontZone, forKey: .frontZone)
        try container.encode(backZone, forKey: .backZone)
        try container.encode(frontType, forKey: .frontType)
        try container.encode(backType, forKey: .backType)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encode(creationSource, forKey: .creationSource)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(editedAt, forKey: .editedAt)
    }

    // MARK: - Initializer

    /// Creates a new `DraftCard`, optionally pre-populated with content from an existing card.
    ///
    /// - Parameters:
    ///   - originalCardID: The ID of the card being edited. Pass `nil` for a new card.
    ///   - frontZone: Initial zone tree for the front face. Defaults to an empty text zone.
    ///   - backZone: Initial zone tree for the back face. Defaults to an empty text zone.
    ///   - frontType: Rendering mode for the front face. Defaults to `.text`.
    ///   - backType: Rendering mode for the back face. Defaults to `.text`.
    ///   - isPinned: Whether the card should stay pinned. Defaults to `false`.
    ///   - creationSource: How the card originated. Defaults to `.manual`.
    ///   - createdAt: Original creation date. Defaults to `nil`.
    ///   - editedAt: Original edit date. Defaults to `nil`.
    init(
        originalCardID: PersistentIdentifier? = nil,
        frontZone: ZoneModel = .text(),
        backZone: ZoneModel = .text(),
        frontType: CardContentType = .text,
        backType: CardContentType = .text,
        isPinned: Bool = false,
        creationSource: CardCreationSource = .manual,
        createdAt: Date? = nil,
        editedAt: Date? = nil
    ) {
        self.originalCardID = originalCardID
        self.frontZone = frontZone
        self.backZone = backZone
        self.frontType = frontType
        self.backType = backType
        self.isPinned = isPinned
        self.creationSource = creationSource
        self.createdAt = createdAt
        self.editedAt = editedAt
    }

    // MARK: - Factory

    /// Creates a `DraftCard` pre-populated from an existing `CardModel`.
    ///
    /// Use this when opening the edit sheet for an existing card.
    /// - Parameter card: The source `CardModel` to mirror.
    /// - Returns: A `DraftCard` with all fields copied from `card`.
    static func from(_ card: CardModel) -> DraftCard {
        DraftCard(
            originalCardID: card.persistentModelID,
            frontZone: card.frontZone,
            backZone: card.backZone,
            frontType: card.frontType,
            backType: card.backType,
            isPinned: card.isPinned,
            creationSource: card.creationSource,
            createdAt: card.createdAt,
            editedAt: card.editedAt
        )
    }
}
