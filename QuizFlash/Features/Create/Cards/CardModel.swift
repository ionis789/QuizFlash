//
//  CardModel.swift
//  QuizFlash
//

import SwiftUI
import SwiftData

// MARK: - Card Content Type
enum CardContentType: String, Codable {
    case text
    case canvas
}

// MARK: - Card Model (SwiftData)
@Model
class CardModel {
    var frontTypeRaw: String = CardContentType.text.rawValue
    var backTypeRaw: String = CardContentType.text.rawValue

    @Attribute(.externalStorage)
    var frontZoneData: Data?

    @Attribute(.externalStorage)
    var backZoneData: Data?

    var frontText: String = ""
    var backText: String = ""

    var createdAt: Date = Date()
    var editedAt: Date = Date()

    var lastSeenAt: Date?
    var timesCorrect: Int = 0
    var timesWrong: Int = 0

    var deck: DeckModel?

    @Relationship(deleteRule: .cascade)
    var stats: CardStats?

    // MARK: - Caching
    @Transient private var cachedFrontZone: ZoneModel?
    @Transient private var cachedBackZone: ZoneModel?

    // MARK: - Computed Properties

    var frontType: CardContentType {
        get { CardContentType(rawValue: frontTypeRaw) ?? .text }
        set { frontTypeRaw = newValue.rawValue }
    }

    var backType: CardContentType {
        get { CardContentType(rawValue: backTypeRaw) ?? .text }
        set { backTypeRaw = newValue.rawValue }
    }

    var frontZone: ZoneModel {
        get {
            if let cached = cachedFrontZone {
                return cached
            }
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

    var backZone: ZoneModel {
        get {
            if let cached = cachedBackZone {
                return cached
            }
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

    // MARK: - Initializer
    init(
        frontZone: ZoneModel,
        backZone: ZoneModel,
        frontType: CardContentType = .text,
        backType: CardContentType = .text
    ) {
        self.frontTypeRaw = frontType.rawValue
        self.backTypeRaw = backType.rawValue

        self.frontZoneData = frontZone.encode()
        self.backZoneData = backZone.encode()

        self.frontText = frontZone.previewText(maxLength: 200)
        self.backText = backZone.previewText(maxLength: 200)

        self.createdAt = Date()
        self.editedAt = Date()
    }
}

// MARK: - Card Stats Model
@Model
class CardStats {
    var totalAttempts: Int = 0
    var correctCount: Int = 0
    var wrongCount: Int = 0
    var lastAttemptDate: Date?
    var streak: Int = 0
    var card: CardModel?

    init(totalAttempts: Int = 0, correctCount: Int = 0, wrongCount: Int = 0, lastAttemptDate: Date? = nil, streak: Int = 0, card: CardModel? = nil) {
        self.totalAttempts = totalAttempts
        self.correctCount = correctCount
        self.wrongCount = wrongCount
        self.lastAttemptDate = lastAttemptDate
        self.streak = streak
        self.card = card
    }
}

// MARK: - Draft Card (For CreateView)
struct DraftCard: Identifiable {
    let id = UUID()
    
    var originalCardID: PersistentIdentifier?

    var frontZone: ZoneModel
    var backZone: ZoneModel
    var frontType: CardContentType
    var backType: CardContentType

    var createdAt: Date?
    var editedAt: Date?

    var lastEditDate: Date? { editedAt }

    init(
        originalCardID: PersistentIdentifier? = nil,
        frontZone: ZoneModel = .text(),
        backZone: ZoneModel = .text(),
        frontType: CardContentType = .text,
        backType: CardContentType = .text,
        createdAt: Date? = nil,
        editedAt: Date? = nil
    ) {
        self.originalCardID = originalCardID
        self.frontZone = frontZone
        self.backZone = backZone
        self.frontType = frontType
        self.backType = backType
        self.createdAt = createdAt
        self.editedAt = editedAt
    }

    static func from(_ card: CardModel) -> DraftCard {
        DraftCard(
            originalCardID: card.id,
            frontZone: card.frontZone,
            backZone: card.backZone,
            frontType: card.frontType,
            backType: card.backType,
            createdAt: card.createdAt,
            editedAt: card.editedAt
        )
    }
}
