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
    
    // NEW: Zone-based content (JSON encoded ZoneModel)
    // This preserves the hierarchical structure (horizontal/vertical containers)
    @Attribute(.externalStorage)
    var frontZoneData: Data?
    
    @Attribute(.externalStorage)
    var backZoneData: Data?
    
    // LEGACY: Linear content blocks (JSON encoded) - kept for migration
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

    // Learning stats (for study order and progress)
    var lastSeenAt: Date?
    var timesCorrect: Int = 0
    var timesWrong: Int = 0

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
    
    // MARK: - Zone Accessors (NEW - preserves layout structure)
    
    /// Get front zone model (preserves horizontal/vertical structure)
    var frontZone: ZoneModel {
        get {
            // Try new zone data first
            if let data = frontZoneData,
               let zone = ZoneModel.decode(from: data) {
                return zone
            }
            // Migrate from old blocks data
            if let data = frontBlocksData {
                let content = CardSideContent.fromData(data)
                return ZoneCardContent.from(oldContent: content).rootZone
            }
            // Migrate from legacy text/images
            if !frontText.isEmpty || !frontImages.isEmpty {
                let content = CardSideContent.fromLegacy(text: frontText, images: frontImages)
                return ZoneCardContent.from(oldContent: content).rootZone
            }
            return .text()
        }
        set {
            // Save zone structure
            frontZoneData = newValue.encode()
            // Also update legacy fields for search/preview
            let content = ZoneCardContent(rootZone: newValue)
            let oldContent = content.toOldContent()
            frontBlocksData = oldContent.toData()
            frontText = oldContent.combinedText
            frontImages = oldContent.allImages
        }
    }
    
    /// Get back zone model (preserves horizontal/vertical structure)
    var backZone: ZoneModel {
        get {
            // Try new zone data first
            if let data = backZoneData,
               let zone = ZoneModel.decode(from: data) {
                return zone
            }
            // Migrate from old blocks data
            if let data = backBlocksData {
                let content = CardSideContent.fromData(data)
                return ZoneCardContent.from(oldContent: content).rootZone
            }
            // Migrate from legacy text/images
            if !backText.isEmpty || !backImages.isEmpty {
                let content = CardSideContent.fromLegacy(text: backText, images: backImages)
                return ZoneCardContent.from(oldContent: content).rootZone
            }
            return .text()
        }
        set {
            // Save zone structure
            backZoneData = newValue.encode()
            // Also update legacy fields for search/preview
            let content = ZoneCardContent(rootZone: newValue)
            let oldContent = content.toOldContent()
            backBlocksData = oldContent.toData()
            backText = oldContent.combinedText
            backImages = oldContent.allImages
        }
    }
    
    // MARK: - Content Block Accessors (Legacy - for compatibility)
    
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
    
    /// Initialize with zone models directly (preserves layout structure)
    init(
        frontZone: ZoneModel,
        backZone: ZoneModel,
        frontType: CardContentType = .text,
        backType: CardContentType = .text
    ) {
        self.frontTypeRaw = frontType.rawValue
        self.backTypeRaw = backType.rawValue
        
        // Save zone structure directly using helper
        self.frontZoneData = frontZone.encode()
        self.backZoneData = backZone.encode()
        
        // Also save as blocks for legacy compatibility
        let frontContent = ZoneCardContent(rootZone: frontZone).toOldContent()
        let backContent = ZoneCardContent(rootZone: backZone).toOldContent()
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
    
    // Zone-based content (preserves layout)
    var frontZone: ZoneModel
    var backZone: ZoneModel
    
    // Type (text or canvas)
    var frontType: CardContentType
    var backType: CardContentType
    
    // Legacy canvas data (for sketch mode)
    var frontData: Data?
    var backData: Data?
    
    // MARK: - Computed (for compatibility)
    
    var front: String {
        ZoneCardContent(rootZone: frontZone).toOldContent().combinedText
    }
    
    var back: String {
        ZoneCardContent(rootZone: backZone).toOldContent().combinedText
    }
    
    var frontImages: [Data] {
        ZoneCardContent(rootZone: frontZone).toOldContent().allImages
    }
    
    var backImages: [Data] {
        ZoneCardContent(rootZone: backZone).toOldContent().allImages
    }
    
    var frontContent: CardSideContent {
        ZoneCardContent(rootZone: frontZone).toOldContent()
    }
    
    var backContent: CardSideContent {
        ZoneCardContent(rootZone: backZone).toOldContent()
    }
    
    // MARK: - Initializers
    
    init(
        frontZone: ZoneModel = .text(),
        backZone: ZoneModel = .text(),
        frontType: CardContentType = .text,
        backType: CardContentType = .text,
        frontData: Data? = nil,
        backData: Data? = nil
    ) {
        self.frontZone = frontZone
        self.backZone = backZone
        self.frontType = frontType
        self.backType = backType
        self.frontData = frontData
        self.backData = backData
    }
    
    /// Create from CardModel
    static func from(_ card: CardModel) -> DraftCard {
        DraftCard(
            frontZone: card.frontZone,
            backZone: card.backZone,
            frontType: card.frontType,
            backType: card.backType,
            frontData: card.frontData,
            backData: card.backData
        )
    }
}
