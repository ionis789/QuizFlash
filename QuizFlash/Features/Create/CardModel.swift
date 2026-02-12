//
//  CardModel.swift
//  QuizFlash
//
//  Created by Ion Socol on 12.02.2026.
//

import SwiftUI
import SwiftData

enum CardContentType: String, Codable {
    case text
    case canvas
}

// Modelul pentru un element de pe Canvas (Imagine cu poziție)
struct CanvasItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var imageData: Data
    var offset: CGSize = .zero
    var scale: CGFloat = 1.0
    var rotation: Double = 0.0 // Rotație în grade
    var zIndex: Double = 0.0
}

@Model
class CardModel {
    var frontTypeRaw: String = CardContentType.text.rawValue
    var backTypeRaw: String = CardContentType.text.rawValue
    
    var frontText: String
    var backText: String
    
    // Stocăm datele JSON ale layout-ului (Lista de CanvasItem)
    @Attribute(.externalStorage)
    var frontLayoutData: Data?
    
    @Attribute(.externalStorage)
    var backLayoutData: Data?
    
    // Păstrăm vechile câmpuri pentru compatibilitate (PencilKit)
    @Attribute(.externalStorage)
    var frontData: Data?
    @Attribute(.externalStorage)
    var backData: Data?
    
    var createdAt: Date
    var editedAt: Date
    
    var deck: DeckModel?
    
    var frontType: CardContentType {
        get { CardContentType(rawValue: frontTypeRaw) ?? .text }
        set { frontTypeRaw = newValue.rawValue }
    }
    
    var backType: CardContentType {
        get { CardContentType(rawValue: backTypeRaw) ?? .text }
        set { backTypeRaw = newValue.rawValue }
    }
    
    init(
        frontText: String = "",
        backText: String = "",
        frontType: CardContentType = .text,
        backType: CardContentType = .text,
        frontLayoutData: Data? = nil,
        backLayoutData: Data? = nil,
        frontData: Data? = nil, // PencilKit legacy
        backData: Data? = nil
    ) {
        self.frontText = frontText
        self.backText = backText
        self.frontTypeRaw = frontType.rawValue
        self.backTypeRaw = backType.rawValue
        self.frontLayoutData = frontLayoutData
        self.backLayoutData = backLayoutData
        self.frontData = frontData
        self.backData = backData
        self.createdAt = Date()
        self.editedAt = Date()
    }
}

// Structura Draft pentru Editor
struct DraftCard: Identifiable {
    let id = UUID()
    var front: String
    var back: String
    var frontLayout: [CanvasItem] = []
    var backLayout: [CanvasItem] = []
    var frontType: CardContentType
    var backType: CardContentType
}
