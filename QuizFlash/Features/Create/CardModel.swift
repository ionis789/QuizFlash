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

    // Structura ierarhică principală
    @Attribute(.externalStorage)
    var frontZoneData: Data?

    @Attribute(.externalStorage)
    var backZoneData: Data?

    // Plain text cached pentru căutare rapidă și preview în liste
    var frontText: String = ""
    var backText: String = ""

    // Timestamps
    var createdAt: Date = Date()
    var editedAt: Date = Date()

    // Learning stats
    var lastSeenAt: Date?
    var timesCorrect: Int = 0
    var timesWrong: Int = 0

    // Relatii
    var deck: DeckModel?

    @Relationship(deleteRule: .cascade)
    var stats: CardStats?

    // MARK: - Computed Properties

    // MARK: - Caching (Performanță)
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
            // 1. Verificăm dacă avem deja modelul decodat în memorie (Cache hit)
            if let cached = cachedFrontZone {
                return cached
            }
            // 2. Dacă nu e în cache, decodăm JSON-ul o singură dată (Cache miss)
            if let data = frontZoneData, let zone = ZoneModel.decode(from: data) {
                cachedFrontZone = zone // Salvăm în cache pentru viitor
                return zone
            }
            return .text()
        }
        set {
            // Când se modifică zona, actualizăm și cache-ul, și baza de date
            cachedFrontZone = newValue
            frontZoneData = newValue.encode()

            // Extragem primele caractere pentru preview rapid automat
            frontText = newValue.previewText(maxLength: 200)
        }
    }

    var backZone: ZoneModel {
        get {
            // Fix aceeași logică de caching și pentru spatele cardului
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

    var frontZone: ZoneModel
    var backZone: ZoneModel
    var frontType: CardContentType
    var backType: CardContentType

    var lastEditDate: Date? { Date() }

    init(
        frontZone: ZoneModel = .text(),
        backZone: ZoneModel = .text(),
        frontType: CardContentType = .text,
        backType: CardContentType = .text
    ) {
        self.frontZone = frontZone
        self.backZone = backZone
        self.frontType = frontType
        self.backType = backType
    }

    static func from(_ card: CardModel) -> DraftCard {
        DraftCard(
            frontZone: card.frontZone,
            backZone: card.backZone,
            frontType: card.frontType,
            backType: card.backType
        )
    }
}
