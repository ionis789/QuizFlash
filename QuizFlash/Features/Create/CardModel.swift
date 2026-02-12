//
//  CardModel.swift
//  QuizFlash
//
//  Created by Ion Socol on 30.12.2025.
//
//  Updated for Apple Notes-style linear content blocks.
//

import SwiftUI
import SwiftData

// MARK: - Card Content Type
enum CardContentType: String, Codable {
    case text   // Linear blocks (text + images)
    case canvas // PencilKit drawing (legacy)
}

// MARK: - Card Model (SwiftData)
@Model
class CardModel {
    // Content type (for backward compatibility)
    var frontTypeRaw: String = CardContentType.text.rawValue
    var backTypeRaw: String = CardContentType.text.rawValue
    
    // NEW: Linear content blocks (JSON encoded)
    @Attribute(.externalStorage)
    var frontBlocksData: Data?
    
    @Attribute(.externalStorage)
    var backBlocksData: Data?
    
    // LEGACY: Plain text (for migration & search)
    var frontText: String = ""
    var backText: String = ""
    
    // LEGACY: Image arrays (for migration)
    @Attribute(.externalStorage)
    var frontImages: [Data] = []
    
    @Attribute(.externalStorage)
    var backImages: [Data] = []
    
    // LEGACY: PencilKit canvas data
    @Attribute(.externalStorage)
    var frontData: Data?
    
    @Attribute(.externalStorage)
    var backData: Data?
    
    // Timestamps
    var createdAt: Date = Date()
    var editedAt: Date = Date()
    
    // Relationship
    var deck: DeckModel?
    
    // MARK: - Computed Properties
    
    var frontType: CardContentType {
        get { CardContentType(rawValue: frontTypeRaw) ?? .text }
        set { frontTypeRaw = newValue.rawValue }
    }
    
    var backType: CardContentType {
        get { CardContentType(rawValue: backTypeRaw) ?? .text }
        set { backTypeRaw = newValue.rawValue }
    }
    
    // MARK: - Content Block Accessors
    
    /// Get front content as CardSideContent
    var frontContent: CardSideContent {
        get {
            if let data = frontBlocksData {
                return CardSideContent.fromData(data)
            }
            // Migration from legacy format
            return CardSideContent.fromLegacy(text: frontText, images: frontImages)
        }
        set {
            frontBlocksData = newValue.toData()
            // Keep legacy fields in sync for search/preview
            frontText = newValue.combinedText
            frontImages = newValue.allImages
        }
    }
    
    /// Get back content as CardSideContent
    var backContent: CardSideContent {
        get {
            if let data = backBlocksData {
                return CardSideContent.fromData(data)
            }
            // Migration from legacy format
            return CardSideContent.fromLegacy(text: backText, images: backImages)
        }
        set {
            backBlocksData = newValue.toData()
            // Keep legacy fields in sync
            backText = newValue.combinedText
            backImages = newValue.allImages
        }
    }
    
    // MARK: - Initializers
    
    init(
        frontText: String = "",
        backText: String = "",
        frontType: CardContentType = .text,
        backType: CardContentType = .text,
        frontData: Data? = nil,
        backData: Data? = nil,
        frontImages: [Data] = [],
        backImages: [Data] = []
    ) {
        self.frontText = frontText
        self.backText = backText
        self.frontTypeRaw = frontType.rawValue
        self.backTypeRaw = backType.rawValue
        self.frontData = frontData
        self.backData = backData
        self.frontImages = frontImages
        self.backImages = backImages
        self.createdAt = Date()
        self.editedAt = Date()
        
        // Convert legacy data to blocks
        if frontType == .text {
            self.frontBlocksData = CardSideContent.fromLegacy(text: frontText, images: frontImages).toData()
        }
        if backType == .text {
            self.backBlocksData = CardSideContent.fromLegacy(text: backText, images: backImages).toData()
        }
    }
    
    /// Initialize with content blocks directly
    init(
        frontContent: CardSideContent,
        backContent: CardSideContent,
        frontType: CardContentType = .text,
        backType: CardContentType = .text
    ) {
        self.frontTypeRaw = frontType.rawValue
        self.backTypeRaw = backType.rawValue
        self.frontBlocksData = frontContent.toData()
        self.backBlocksData = backContent.toData()
        self.frontText = frontContent.combinedText
        self.backText = backContent.combinedText
        self.frontImages = frontContent.allImages
        self.backImages = backContent.allImages
        self.createdAt = Date()
        self.editedAt = Date()
    }
}

// MARK: - Draft Card (For CreateView)
struct DraftCard: Identifiable {
    let id = UUID()
    
    // Content blocks
    var frontContent: CardSideContent
    var backContent: CardSideContent
    
    // Type (text or canvas)
    var frontType: CardContentType
    var backType: CardContentType
    
    // Legacy canvas data (for sketch mode)
    var frontData: Data?
    var backData: Data?
    
    // MARK: - Computed
    
    var front: String {
        frontContent.combinedText
    }
    
    var back: String {
        backContent.combinedText
    }
    
    var frontImages: [Data] {
        frontContent.allImages
    }
    
    var backImages: [Data] {
        backContent.allImages
    }
    
    // MARK: - Initializers
    
    init(
        frontContent: CardSideContent = CardSideContent(blocks: [.text()]),
        backContent: CardSideContent = CardSideContent(blocks: [.text()]),
        frontType: CardContentType = .text,
        backType: CardContentType = .text,
        frontData: Data? = nil,
        backData: Data? = nil
    ) {
        self.frontContent = frontContent
        self.backContent = backContent
        self.frontType = frontType
        self.backType = backType
        self.frontData = frontData
        self.backData = backData
    }
    
    /// Create from CardModel
    static func from(_ card: CardModel) -> DraftCard {
        DraftCard(
            frontContent: card.frontContent,
            backContent: card.backContent,
            frontType: card.frontType,
            backType: card.backType,
            frontData: card.frontData,
            backData: card.backData
        )
    }
}
