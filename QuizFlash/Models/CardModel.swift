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
    var cardNumber: Int = 0

    // 🔴 ELIMINAT: lastSeenAt, timesCorrect, timesWrong, stats (CardStats)
    // Au fost înlocuite de reviewHistory și parametrii SRS

    var deck: DeckModel?

    // 🟢 NOU: Istoricul complet de review-uri (The Data Engine)
    @Relationship(deleteRule: .cascade, inverse: \ReviewEvent.card)
    var reviewHistory: [ReviewEvent] = []

    // 🟢 NOU: Spaced Repetition Parameters (SRS)
    var dueDate: Date = Date() // Când trebuie revizuit cardul?
    var easeFactor: Double = 2.5 // Multiplicatorul de dificultate (default 2.5)
    var interval: Int = 0 // Zile până la următoarea revizuire
    var consecutiveCorrectAnswers: Int = 0

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
        backType: CardContentType = .text,
        cardNumber: Int = 0
    ) {
        self.frontTypeRaw = frontType.rawValue
        self.backTypeRaw = backType.rawValue

        self.frontZoneData = frontZone.encode()
        self.backZoneData = backZone.encode()
        
        self.cardNumber = cardNumber

        self.frontText = frontZone.previewText(maxLength: 200)
        self.backText = backZone.previewText(maxLength: 200)

        self.createdAt = Date()
        self.editedAt = Date()

        // Initializare SRS
        self.dueDate = Date()
        self.easeFactor = 2.5
        self.interval = 0
        self.consecutiveCorrectAnswers = 0
    }
}

// 🔴 ȘTERGE complet clasa `CardStats` (dacă o ai în acest fișier). Nu mai avem nevoie de ea.

// MARK: - Draft Card (For CreateView)
// (Rămâne EXACT la fel cum îl ai tu acum, nu am modificat nimic la el, deoarece este perfect pentru UI-ul de creare).
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
