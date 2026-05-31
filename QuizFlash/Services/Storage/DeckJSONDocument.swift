//
//  DeckJSONDocument.swift
//  QuizFlash
//

import Foundation

// MARK: - Deck JSON Contract

/// Canonical external deck document used for JSON export/import and future API sync.
nonisolated struct DeckJSONDocument: Codable, Sendable {
    static let supportedSchemaVersion = 1

    var schemaVersion: Int
    var app: DeckJSONAppMetadata
    var deck: DeckJSONDeckMetadata
    var cards: [DeckJSONCardRecord]

    init(
        schemaVersion: Int = Self.supportedSchemaVersion,
        app: DeckJSONAppMetadata = .current,
        deck: DeckJSONDeckMetadata,
        cards: [DeckJSONCardRecord]
    ) {
        self.schemaVersion = schemaVersion
        self.app = app
        self.deck = deck
        self.cards = cards
    }
}

/// Lightweight app metadata for exported documents.
nonisolated struct DeckJSONAppMetadata: Codable, Sendable {
    var name: String
    var version: String

    static let current = DeckJSONAppMetadata(name: "QuizFlash", version: "1")
}

/// Deck-level metadata controlled by the app, not by AI generation.
nonisolated struct DeckJSONDeckMetadata: Codable, Sendable {
    var title: String
    var colorHex: String
    var createdAt: Date
    var editedAt: Date
}

/// One exported/imported card plus metadata that belongs to a persisted deck.
nonisolated struct DeckJSONCardRecord: Codable, Sendable {
    var id: UUID
    var creationSource: CardCreationSource
    var createdAt: Date
    var editedAt: Date
    var card: DeckJSONCardDTO
}

/// AI response envelope for generated cards. It intentionally excludes deck metadata.
nonisolated struct DeckJSONCardBatchDTO: Codable, Sendable {
    var schemaVersion: Int
    var cards: [DeckJSONCardDTO]

    init(
        schemaVersion: Int = DeckJSONDocument.supportedSchemaVersion,
        cards: [DeckJSONCardDTO]
    ) {
        self.schemaVersion = schemaVersion
        self.cards = cards
    }
}

/// Canonical card payload shared by export/import, AI generation, and future APIs.
nonisolated enum DeckJSONCardDTO: Codable, Sendable {
    case flashcard(DeckJSONFlashcardDTO)
    case quiz(DeckJSONQuizCardDTO)

    private enum CodingKeys: String, CodingKey {
        case type
        case front
        case back
        case frontType
        case backType
        case question
        case choices
        case explanation
        case allowsMultipleCorrect
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(DeckJSONCardType.self, forKey: .type)

        switch type {
        case .flashcard:
            self = .flashcard(
                DeckJSONFlashcardDTO(
                    front: try container.decode(DeckJSONCardFaceDTO.self, forKey: .front),
                    back: try container.decode(DeckJSONCardFaceDTO.self, forKey: .back),
                    frontType: try container.decodeIfPresent(CardContentType.self, forKey: .frontType) ?? .text,
                    backType: try container.decodeIfPresent(CardContentType.self, forKey: .backType) ?? .text
                )
            )
        case .quiz:
            self = .quiz(
                DeckJSONQuizCardDTO(
                    question: try container.decode(DeckJSONCardFaceDTO.self, forKey: .question),
                    choices: try container.decode([DeckJSONQuizChoiceDTO].self, forKey: .choices),
                    explanation: try container.decodeIfPresent(DeckJSONCardFaceDTO.self, forKey: .explanation),
                    allowsMultipleCorrect: try container.decodeIfPresent(Bool.self, forKey: .allowsMultipleCorrect)
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .flashcard(let payload):
            try container.encode(DeckJSONCardType.flashcard, forKey: .type)
            try container.encode(payload.front, forKey: .front)
            try container.encode(payload.back, forKey: .back)
            try container.encode(payload.frontType, forKey: .frontType)
            try container.encode(payload.backType, forKey: .backType)
        case .quiz(let payload):
            try container.encode(DeckJSONCardType.quiz, forKey: .type)
            try container.encode(payload.question, forKey: .question)
            try container.encode(payload.choices, forKey: .choices)
            try container.encodeIfPresent(payload.explanation, forKey: .explanation)
            try container.encode(payload.allowsMultipleCorrect, forKey: .allowsMultipleCorrect)
        }
    }
}

/// Supported card types in the external JSON contract.
nonisolated enum DeckJSONCardType: String, Codable, Sendable {
    case flashcard
    case quiz
}

/// External flashcard payload.
nonisolated struct DeckJSONFlashcardDTO: Codable, Sendable {
    var front: DeckJSONCardFaceDTO
    var back: DeckJSONCardFaceDTO
    var frontType: CardContentType
    var backType: CardContentType
}

/// External quiz payload.
nonisolated struct DeckJSONQuizCardDTO: Codable, Sendable {
    var question: DeckJSONCardFaceDTO
    var choices: [DeckJSONQuizChoiceDTO]
    var explanation: DeckJSONCardFaceDTO?
    var allowsMultipleCorrect: Bool

    init(
        question: DeckJSONCardFaceDTO,
        choices: [DeckJSONQuizChoiceDTO],
        explanation: DeckJSONCardFaceDTO?,
        allowsMultipleCorrect: Bool?
    ) {
        self.question = question
        self.choices = choices
        self.explanation = explanation
        self.allowsMultipleCorrect = allowsMultipleCorrect ?? (choices.filter(\.isCorrect).count > 1)
    }
}

/// One card face represented as a list of root zones.
nonisolated struct DeckJSONCardFaceDTO: Codable, Sendable {
    var zones: [DeckJSONZoneDTO]

    init(zones: [DeckJSONZoneDTO]) {
        self.zones = zones
    }
}

/// One quiz choice in the shared card JSON schema.
nonisolated struct DeckJSONQuizChoiceDTO: Codable, Sendable {
    var id: UUID
    var zones: [DeckJSONZoneDTO]
    var isCorrect: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case zones
        case isCorrect
    }

    init(
        id: UUID = UUID(),
        zones: [DeckJSONZoneDTO],
        isCorrect: Bool
    ) {
        self.id = id
        self.zones = zones
        self.isCorrect = isCorrect
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        zones = try container.decode([DeckJSONZoneDTO].self, forKey: .zones)
        isCorrect = try container.decode(Bool.self, forKey: .isCorrect)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(zones, forKey: .zones)
        try container.encode(isCorrect, forKey: .isCorrect)
    }
}

/// Zone tree node in the external JSON schema.
nonisolated struct DeckJSONZoneDTO: Codable, Sendable {
    var id: UUID
    var type: DeckJSONZoneType
    var text: String?
    var codeLanguage: String?
    var mediaBase64: Data?
    var textStyle: TextBlockStyle
    var textAlignment: TextBlockAlignment
    var sizeMode: ZoneSizeMode
    var blockAlignment: ZoneBlockAlignment
    var verticalAlignment: ZoneVerticalAlignment
    var fixedWidth: Double?
    var fixedHeight: Double?
    var textColor: TextBlockColor
    var isBold: Bool
    var isItalic: Bool
    var hasBullet: Bool
    var fontFamily: FontFamily
    var highlightColor: HighlightColor
    var imageScale: Double
    var direction: ZoneDirection?
    var children: [DeckJSONZoneDTO]?

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case text
        case codeLanguage
        case mediaBase64
        case textStyle
        case textAlignment
        case sizeMode
        case blockAlignment
        case verticalAlignment
        case fixedWidth
        case fixedHeight
        case textColor
        case isBold
        case isItalic
        case hasBullet
        case fontFamily
        case highlightColor
        case imageScale
        case direction
        case children
    }

    init(
        id: UUID = UUID(),
        type: DeckJSONZoneType,
        text: String? = nil,
        codeLanguage: String? = nil,
        mediaBase64: Data? = nil,
        textStyle: TextBlockStyle = .body,
        textAlignment: TextBlockAlignment = .leading,
        sizeMode: ZoneSizeMode = .auto,
        blockAlignment: ZoneBlockAlignment = .auto,
        verticalAlignment: ZoneVerticalAlignment = .auto,
        fixedWidth: Double? = nil,
        fixedHeight: Double? = nil,
        textColor: TextBlockColor = .primary,
        isBold: Bool = false,
        isItalic: Bool = false,
        hasBullet: Bool = false,
        fontFamily: FontFamily = .system,
        highlightColor: HighlightColor = .none,
        imageScale: Double = 1.0,
        direction: ZoneDirection? = nil,
        children: [DeckJSONZoneDTO]? = nil
    ) {
        self.id = id
        self.type = type
        self.text = text
        self.codeLanguage = codeLanguage
        self.mediaBase64 = mediaBase64
        self.textStyle = textStyle
        self.textAlignment = textAlignment
        self.sizeMode = sizeMode
        self.blockAlignment = blockAlignment
        self.verticalAlignment = verticalAlignment
        self.fixedWidth = fixedWidth
        self.fixedHeight = fixedHeight
        self.textColor = textColor
        self.isBold = isBold
        self.isItalic = isItalic
        self.hasBullet = hasBullet
        self.fontFamily = fontFamily
        self.highlightColor = highlightColor
        self.imageScale = imageScale
        self.direction = direction
        self.children = children
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        type = try container.decode(DeckJSONZoneType.self, forKey: .type)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        codeLanguage = try container.decodeIfPresent(String.self, forKey: .codeLanguage)
        mediaBase64 = try container.decodeIfPresent(Data.self, forKey: .mediaBase64)
        textStyle = try container.decodeIfPresent(TextBlockStyle.self, forKey: .textStyle) ?? .body
        textAlignment = try container.decodeIfPresent(TextBlockAlignment.self, forKey: .textAlignment) ?? .leading
        sizeMode = try container.decodeIfPresent(ZoneSizeMode.self, forKey: .sizeMode) ?? .auto
        blockAlignment = try container.decodeIfPresent(ZoneBlockAlignment.self, forKey: .blockAlignment) ?? .auto
        verticalAlignment = try container.decodeIfPresent(ZoneVerticalAlignment.self, forKey: .verticalAlignment) ?? .auto
        fixedWidth = try container.decodeIfPresent(Double.self, forKey: .fixedWidth)
        fixedHeight = try container.decodeIfPresent(Double.self, forKey: .fixedHeight)
        textColor = try container.decodeIfPresent(TextBlockColor.self, forKey: .textColor) ?? .primary
        isBold = try container.decodeIfPresent(Bool.self, forKey: .isBold) ?? false
        isItalic = try container.decodeIfPresent(Bool.self, forKey: .isItalic) ?? false
        hasBullet = try container.decodeIfPresent(Bool.self, forKey: .hasBullet) ?? false
        fontFamily = try container.decodeIfPresent(FontFamily.self, forKey: .fontFamily) ?? .system
        highlightColor = try container.decodeIfPresent(HighlightColor.self, forKey: .highlightColor) ?? .none
        imageScale = try container.decodeIfPresent(Double.self, forKey: .imageScale) ?? 1.0
        direction = try container.decodeIfPresent(ZoneDirection.self, forKey: .direction)
        children = try container.decodeIfPresent([DeckJSONZoneDTO].self, forKey: .children)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encodeIfPresent(codeLanguage, forKey: .codeLanguage)
        try container.encodeIfPresent(mediaBase64, forKey: .mediaBase64)
        try container.encode(textStyle, forKey: .textStyle)
        try container.encode(textAlignment, forKey: .textAlignment)
        try container.encode(sizeMode, forKey: .sizeMode)
        try container.encode(blockAlignment, forKey: .blockAlignment)
        try container.encode(verticalAlignment, forKey: .verticalAlignment)
        try container.encodeIfPresent(fixedWidth, forKey: .fixedWidth)
        try container.encodeIfPresent(fixedHeight, forKey: .fixedHeight)
        try container.encode(textColor, forKey: .textColor)
        try container.encode(isBold, forKey: .isBold)
        try container.encode(isItalic, forKey: .isItalic)
        try container.encode(hasBullet, forKey: .hasBullet)
        try container.encode(fontFamily, forKey: .fontFamily)
        try container.encode(highlightColor, forKey: .highlightColor)
        try container.encode(imageScale, forKey: .imageScale)
        try container.encodeIfPresent(direction, forKey: .direction)
        try container.encodeIfPresent(children, forKey: .children)
    }
}

/// Supported zone types in deck JSON. Containers are explicit in JSON.
nonisolated enum DeckJSONZoneType: String, Codable, Sendable {
    case empty
    case text
    case image
    case sketch
    case code
    case container
}

// MARK: - Domain Mapping

extension DeckJSONDocument {
    nonisolated static func from(deck: DeckModel, cards: [CardModel]) -> DeckJSONDocument {
        DeckJSONDocument(
            deck: DeckJSONDeckMetadata(
                title: deck.title,
                colorHex: deck.colorHex,
                createdAt: deck.createdAt,
                editedAt: deck.editedAt
            ),
            cards: cards.map { card in
                DeckJSONCardRecord(
                    id: UUID(),
                    creationSource: card.creationSource,
                    createdAt: card.createdAt,
                    editedAt: card.editedAt,
                    card: DeckJSONCardDTO.from(content: card.cardContent)
                )
            }
        )
    }
}

extension DeckJSONCardDTO {
    nonisolated static func from(content: DraftCardContent) -> DeckJSONCardDTO {
        switch content {
        case .flashcard(let content):
            return .flashcard(
                DeckJSONFlashcardDTO(
                    front: .from(rootZone: content.frontZone),
                    back: .from(rootZone: content.backZone),
                    frontType: content.frontType,
                    backType: content.backType
                )
            )
        case .quiz(let content):
            return .quiz(
                DeckJSONQuizCardDTO(
                    question: .from(rootZone: content.questionZone),
                    choices: content.choices.map { choice in
                        DeckJSONQuizChoiceDTO(
                            id: choice.id,
                            zones: DeckJSONCardFaceDTO.from(rootZone: choice.contentZone).zones,
                            isCorrect: choice.isCorrect
                        )
                    },
                    explanation: content.explanationZone.map { .from(rootZone: $0) },
                    allowsMultipleCorrect: content.allowsMultipleCorrect
                )
            )
        }
    }

    nonisolated func draftCardContent() throws -> DraftCardContent {
        switch self {
        case .flashcard(let payload):
            return .flashcard(
                FlashcardCardContent(
                    frontZone: try payload.front.rootZone(),
                    backZone: try payload.back.rootZone(),
                    frontType: payload.frontType,
                    backType: payload.backType
                )
            )
        case .quiz(let payload):
            let choices = try payload.choices.map { choice in
                QuizChoiceDraft(
                    id: choice.id,
                    contentZone: try DeckJSONCardFaceDTO(zones: choice.zones).rootZone(),
                    isCorrect: choice.isCorrect
                )
            }
            guard choices.count >= 2, choices.contains(where: \.isCorrect) else {
                throw DeckJSONValidationError.invalidQuizCard
            }

            return .quiz(
                QuizCardContent(
                    questionZone: try payload.question.rootZone(),
                    choices: choices,
                    explanationZone: try payload.explanation?.rootZone(),
                    allowsMultipleCorrect: payload.allowsMultipleCorrect
                )
            )
        }
    }
}

extension DeckJSONCardFaceDTO {
    nonisolated static func from(rootZone: ZoneModel) -> DeckJSONCardFaceDTO {
        DeckJSONCardFaceDTO(zones: [.from(zone: rootZone)])
    }

    nonisolated func rootZone() throws -> ZoneModel {
        let decodedZones = try zones.map { try $0.zoneModel() }
        switch decodedZones.count {
        case 0:
            return .text()
        case 1:
            return decodedZones[0]
        default:
            return .container(direction: .vertical, children: decodedZones)
        }
    }
}

extension DeckJSONZoneDTO {
    nonisolated static func from(zone: ZoneModel) -> DeckJSONZoneDTO {
        if let children = zone.children, !children.isEmpty {
            return DeckJSONZoneDTO(
                id: zone.id,
                type: .container,
                textStyle: zone.textStyle,
                textAlignment: zone.textAlignment,
                sizeMode: zone.sizeMode,
                blockAlignment: zone.blockAlignment,
                verticalAlignment: zone.verticalAlignment,
                fixedWidth: zone.fixedWidth.map(Double.init),
                fixedHeight: zone.fixedHeight.map(Double.init),
                textColor: zone.textColor,
                isBold: zone.isBold,
                isItalic: zone.isItalic,
                hasBullet: zone.hasBullet,
                fontFamily: zone.fontFamily,
                highlightColor: zone.highlightColor,
                imageScale: Double(zone.imageScale),
                direction: zone.direction,
                children: children.map { .from(zone: $0) }
            )
        }

        return DeckJSONZoneDTO(
            id: zone.id,
            type: DeckJSONZoneType(contentType: zone.contentType),
            text: zone.text.isEmpty ? nil : zone.text,
            codeLanguage: zone.codeLanguage,
            mediaBase64: zone.imageData,
            textStyle: zone.textStyle,
            textAlignment: zone.textAlignment,
            sizeMode: zone.sizeMode,
            blockAlignment: zone.blockAlignment,
            verticalAlignment: zone.verticalAlignment,
            fixedWidth: zone.fixedWidth.map(Double.init),
            fixedHeight: zone.fixedHeight.map(Double.init),
            textColor: zone.textColor,
            isBold: zone.isBold,
            isItalic: zone.isItalic,
            hasBullet: zone.hasBullet,
            fontFamily: zone.fontFamily,
            highlightColor: zone.highlightColor,
            imageScale: Double(zone.imageScale)
        )
    }

    nonisolated func zoneModel() throws -> ZoneModel {
        let contentType = try ZoneContentType(jsonType: type)
        let decodedChildren = try children?.map { try $0.zoneModel() }

        if type == .container {
            guard let decodedChildren, !decodedChildren.isEmpty else {
                throw DeckJSONValidationError.invalidZone
            }
        }

        return ZoneModel(
            id: id,
            contentType: contentType,
            codeLanguage: codeLanguage,
            text: text ?? "",
            imageData: mediaBase64,
            textStyle: textStyle,
            textAlignment: textAlignment,
            sizeMode: sizeMode,
            blockAlignment: blockAlignment,
            verticalAlignment: verticalAlignment,
            fixedWidth: fixedWidth.map { CGFloat($0) },
            fixedHeight: fixedHeight.map { CGFloat($0) },
            textColor: textColor,
            isBold: isBold,
            isItalic: isItalic,
            hasBullet: hasBullet,
            fontFamily: fontFamily,
            highlightColor: highlightColor,
            imageScale: CGFloat(imageScale),
            children: decodedChildren,
            direction: direction ?? .horizontal
        )
    }
}

private extension DeckJSONZoneType {
    nonisolated init(contentType: ZoneContentType) {
        switch contentType {
        case .empty:
            self = .empty
        case .text:
            self = .text
        case .image:
            self = .image
        case .sketch:
            self = .sketch
        case .code:
            self = .code
        }
    }
}

private extension ZoneContentType {
    nonisolated init(jsonType: DeckJSONZoneType) throws {
        switch jsonType {
        case .empty:
            self = .empty
        case .text:
            self = .text
        case .image:
            self = .image
        case .sketch:
            self = .sketch
        case .code:
            self = .code
        case .container:
            self = .empty
        }
    }
}

/// Validation failures in the canonical deck JSON contract.
nonisolated enum DeckJSONValidationError: LocalizedError {
    case unsupportedSchemaVersion(Int)
    case invalidQuizCard
    case invalidZone

    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "Unsupported deck JSON schema version: \(version)"
        case .invalidQuizCard:
            return "The deck JSON contains a quiz card without valid choices and correct answers."
        case .invalidZone:
            return "The deck JSON contains an invalid zone tree."
        }
    }
}
